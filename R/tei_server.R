#' Start a local TEI server (background)
#'
#' Spawns a `text-embeddings-router` process in the background and waits until
#' the `/health` endpoint is reachable. The process PID is cached inside the
#' package and can be stopped with [tei_stop()]. If a server already appears to
#' be running at the same port, the function returns immediately.
#'
#' @param model Model id to load (passed to `--model-id`).
#'   Default `"sentence-transformers/all-MiniLM-L6-v2"`.
#' @param port TCP port to bind. Default `3000`.
#' @param bin Path to the `text-embeddings-router` binary. When `NULL`, common
#'   locations are checked (including `Sys.which("text-embeddings-router")`).
#' @param args Additional CLI flags to pass to the router (character vector).
#'   For example: `c("--normalize", "--pooling", "mean")`.
#' @param timeout Seconds to wait for the server to report healthy. Default `90`.
#' @param verbose Print progress messages. Default `TRUE`.
#'
#' @return A list with `pid`, `port`, `url`, and `cmd` (invisibly).
#'
#' @importFrom httr2 request req_perform
#' @export
tei_start <- function(
  model = "sentence-transformers/all-MiniLM-L6-v2",
  port = 3000L,
  bin = NULL,
  args = character(),
  timeout = 90,
  verbose = TRUE
) {
  state <- .tei_server_state()

  # If a server seems up already, reuse it
  if (
    !is.null(state$proc) &&
      inherits(state$proc, "processx_process") &&
      state$proc$is_alive()
  ) {
    if (.tei_is_healthy(port)) {
      if (isTRUE(verbose)) {
        message("TEI server already running on port ", port)
      }
      return(invisible(list(
        pid = state$proc$get_pid(),
        port = as.integer(port),
        url = paste0("http://localhost:", port, "/embed"),
        cmd = state$cmd
      )))
    } else {
      # Stale process, stop it first
      try(tei_stop(silent = TRUE), silent = TRUE)
    }
  }

  # Resolve binary location
  candidates <- c(
    bin,
    Sys.which("text-embeddings-router"),
    "~/.cargo/bin/text-embeddings-router",
    "/opt/homebrew/bin/text-embeddings-router",
    "/usr/local/bin/text-embeddings-router"
  )
  exe <- path.expand(candidates[nzchar(candidates)][1])
  if (is.na(exe) || !file.exists(exe)) {
    stop(
      "Cannot find 'text-embeddings-router'. Provide 'bin' or install the binary."
    )
  }

  # Launch with processx
  log_out <- tempfile("tei_out_")
  log_err <- tempfile("tei_err_")
  cli_args <- c("--model-id", model, "--port", as.character(as.integer(port)))
  if (length(args)) {
    cli_args <- c(cli_args, args)
  }

  proc <- processx::process$new(
    exe,
    cli_args,
    stdout = log_out,
    stderr = log_err,
    supervise = TRUE
  )
  pid <- proc$get_pid()
  if (is.na(pid) || pid <= 0) {
    stop("Failed to start text-embeddings-router (no PID captured).")
  }

  # Store state immediately so we can clean up on failure
  state$proc <- proc
  state$pid <- pid
  state$port <- as.integer(port)
  state$url <- paste0("http://localhost:", as.integer(port), "/embed")
  state$cmd <- paste(shQuote(exe), paste(shQuote(cli_args), collapse = " "))
  state$log_out <- log_out
  state$log_err <- log_err

  # Wait for health
  ok <- FALSE
  for (i in seq_len(as.integer(timeout))) {
    Sys.sleep(1)
    if (.tei_is_healthy(port)) {
      ok <- TRUE
      break
    }
    # Early exit if process died
    if (!state$proc$is_alive()) break
  }

  if (!ok) {
    out <- if (file.exists(log_out)) {
      paste(utils::tail(readLines(log_out, warn = FALSE), 50L), collapse = "\n")
    } else {
      ""
    }
    err <- if (file.exists(log_err)) {
      paste(utils::tail(readLines(log_err, warn = FALSE), 50L), collapse = "\n")
    } else {
      ""
    }
    try(tei_stop(silent = TRUE), silent = TRUE)
    stop(
      paste0(
        "TEI server did not become healthy on port ",
        port,
        " within ",
        timeout,
        "s.\n",
        if (nzchar(out)) "[stdout]\n" else "",
        out,
        if (nzchar(err)) "\n[stderr]\n" else "",
        err
      )
    )
  }

  if (isTRUE(verbose)) {
    message(
      "Started TEI server (pid ",
      pid,
      ") on port ",
      port,
      "; embed endpoint: ",
      state$url
    )
  }
  invisible(list(
    pid = pid,
    port = as.integer(port),
    url = state$url,
    cmd = state$cmd
  ))
}

#' Stop the background TEI server
#'
#' Sends SIGTERM then SIGKILL (if needed) to the cached router PID. Safe to call
#' if no server is running.
#'
#' @param silent Suppress messages. Default `FALSE`.
#'
#' @return Logical indicating whether a process was stopped (invisibly).
#' @export
tei_stop <- function(silent = FALSE) {
  state <- .tei_server_state()
  # Prefer processx handle if available
  if (!is.null(state$proc) && inherits(state$proc, "processx_process")) {
    proc <- state$proc
    pid <- tryCatch(proc$get_pid(), error = function(e) NA_integer_)
    # Graceful terminate where supported, then kill if needed
    try(proc$signal(15L), silent = TRUE)
    proc$wait(1000)
    if (proc$is_alive()) {
      try(proc$kill(), silent = TRUE)
    }
  } else if (!is.null(state$pid) && !is.na(state$pid)) {
    pid <- state$pid
    try(tools::pskill(pid, 15L), silent = TRUE)
    Sys.sleep(0.4)
    alive <- try(tools::pskill(pid, 0L), silent = TRUE)
    if (!identical(alive, FALSE)) try(tools::pskill(pid, 9L), silent = TRUE)
  } else {
    if (!isTRUE(silent)) {
      message("No TEI server to stop.")
    }
    return(invisible(FALSE))
  }

  # Cleanup logs
  if (!is.null(state$log_out)) {
    try(unlink(state$log_out), silent = TRUE)
  }
  if (!is.null(state$log_err)) {
    try(unlink(state$log_err), silent = TRUE)
  }

  # Reset state
  state$proc <- NULL
  state$pid <- NA_integer_
  state$port <- NA_integer_
  state$url <- NULL
  state$cmd <- NULL
  state$log_out <- NULL
  state$log_err <- NULL

  if (!isTRUE(silent)) {
    message(
      "Stopped TEI server",
      if (!is.na(pid)) paste0(" (pid ", pid, ")") else "",
      "."
    )
  }
  invisible(TRUE)
}


#' Inspect TEI backend, model, and limits of a running server
#'
#' Queries an already running TEI service via `/health`, `/info`, and performs
#' a tiny `/embed` probe to infer embedding dimension and latency. No processes
#' are launched by this function.
#'
#' @param tei_url URL to the running server's `/embed` endpoint. Defaults to the
#'   URL remembered by [tei_start()] for this session (if available).
#' @param timeout Seconds to wait for HTTP requests (per call). Default `10`.
#' @param yaml_path Optional path to write a YAML report; if `NULL`, only returns
#'   the list.
#'
#' @return A named list with fields `started` (reachability), `backend`,
#'   `device`, `dtype`, `model` (nested), `server` (nested), and `probe` (nested).
#'
#' @importFrom httr2 request req_perform resp_body_json
#' @importFrom yaml write_yaml
#' @export
tei_info <- function(
  tei_url = tei_default_embed_url(),
  timeout = 10,
  yaml_path = NULL
) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  # Derive base URL and endpoints
  base <- sub("/embed/?$", "", tei_url)
  base <- sub("/+$", "", base)
  health_url <- paste0(base, "/health")
  info_url <- paste0(base, "/info")
  embed_url <- paste0(base, "/embed")

  # Health and info
  health_ok <- !inherits(
    try(httr2::request(health_url) |> httr2::req_perform(), silent = TRUE),
    "try-error"
  )
  info <- try(
    {
      httr2::request(info_url) |>
        httr2::req_perform() |>
        httr2::resp_body_json(simplifyVector = TRUE)
    },
    silent = TRUE
  )

  # Probe /embed once for dim + latency (optional)
  probe_dim <- NA_integer_
  probe_ms <- NA_real_
  invisible(try(
    {
      t0 <- Sys.time()
      emb <- tei_embed_text(c("hello"), tei_url = embed_url, max_batch_size = 3)
      probe_dim <- ncol(emb)
      probe_ms <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000
    },
    silent = TRUE
  ))

  # Extract what we can from /info
  backend <- if (!inherits(info, "try-error")) {
    info$backend %||% NA_character_
  } else {
    NA_character_
  }
  device <- if (!inherits(info, "try-error")) {
    info$device %||% NA_character_
  } else {
    NA_character_
  }
  dtype <- if (!inherits(info, "try-error")) {
    (info$model_dtype %||% info$dtype) %||% NA_character_
  } else {
    NA_character_
  }

  res <- list(
    started = isTRUE(health_ok),
    backend = backend,
    device = device,
    dtype = dtype,
    model = list(
      requested_id = if (!inherits(info, "try-error")) {
        info$model_id %||% NA_character_
      } else {
        NA_character_
      },
      id = if (!inherits(info, "try-error")) {
        info$model_id %||% NA_character_
      } else {
        NA_character_
      },
      revision = if (!inherits(info, "try-error")) {
        info$revision %||% NA_character_
      } else {
        NA_character_
      },
      model_sha = if (!inherits(info, "try-error")) {
        info$model_sha %||% NA_character_
      } else {
        NA_character_
      },
      model_dtype = dtype,
      embedding_dim = if (!inherits(info, "try-error")) {
        info$embedding_size %||% probe_dim
      } else {
        probe_dim
      },
      max_input_length = if (!inherits(info, "try-error")) {
        info$max_input_length %||% NA_integer_
      } else {
        NA_integer_
      },
      pooling = if (!inherits(info, "try-error")) {
        if (!is.null(info$model_type) && !is.null(info$model_type$embedding)) {
          info$model_type$embedding$pooling %||% NA_character_
        } else {
          info$pooling %||% NA_character_
        }
      } else {
        NA_character_
      },
      normalize = if (!inherits(info, "try-error")) {
        info$normalize %||% NA
      } else {
        NA
      }
    ),
    server = list(
      base_url = base,
      embed_url = embed_url,
      version = if (!inherits(info, "try-error")) {
        info$version %||% NA_character_
      } else {
        NA_character_
      },
      max_client_batch_size = if (!inherits(info, "try-error")) {
        info$max_client_batch_size %||% NA_integer_
      } else {
        NA_integer_
      },
      max_batch_tokens = if (!inherits(info, "try-error")) {
        info$max_batch_tokens %||% NA_integer_
      } else {
        NA_integer_
      },
      workers = if (!inherits(info, "try-error")) {
        (info$workers %||% info$tokenization_workers) %||% NA_integer_
      } else {
        NA_integer_
      },
      max_concurrent_requests = if (!inherits(info, "try-error")) {
        info$max_concurrent_requests %||% NA_integer_
      } else {
        NA_integer_
      },
      max_batch_requests = if (!inherits(info, "try-error")) {
        info$max_batch_requests %||% NA_integer_
      } else {
        NA_integer_
      },
      auto_truncate = if (!inherits(info, "try-error")) {
        info$auto_truncate %||% NA
      } else {
        NA
      },
      sha = if (!inherits(info, "try-error")) {
        info$sha %||% NA_character_
      } else {
        NA_character_
      },
      docker_label = if (!inherits(info, "try-error")) {
        info$docker_label %||% NA_character_
      } else {
        NA_character_
      }
    ),
    probe = list(
      latency_ms = probe_ms,
      embedding_dim = probe_dim
    )
  )

  if (!is.null(yaml_path)) {
    dir.create(dirname(yaml_path), recursive = TRUE, showWarnings = FALSE)
    yaml::write_yaml(res, yaml_path)
    return(invisible(res))
  }
  res
}


# State env is created in zzz.R (.tei_server_state())

# Internal: check health endpoint for the given port
.tei_is_healthy <- function(port) {
  base <- paste0("http://localhost:", as.integer(port), "/health")
  ok <- try(httr2::request(base) |> httr2::req_perform(), silent = TRUE)
  !inherits(ok, "try-error")
}

#' Default TEI embed URL from saved server state
#'
#' Returns the embed endpoint URL remembered by [tei_start()] for the current
#' session. If none is set, constructs from a saved port if available, otherwise
#' falls back to `http://localhost:3000/embed`.
#'
#' @return A length-1 character string with the embed URL.
#' @export
tei_default_embed_url <- function() {
  state <- .tei_server_state()
  if (!is.null(state$url) && is.character(state$url) && nzchar(state$url)) {
    return(state$url)
  }
  if (!is.null(state$port) && is.finite(state$port)) {
    return(paste0("http://localhost:", as.integer(state$port), "/embed"))
  }
  "http://localhost:3000/embed"
}
