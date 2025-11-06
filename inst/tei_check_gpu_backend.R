#' Check GPU (Metal) support of text-embeddings-router (robust)
#' @param model Model ID (default: small & fast).
#' @param bin Path to router binary or auto-detect.
#' @param port Port to use (random if NULL).
#' @param timeout Seconds to wait for startup & logs.
#' @return list(backend = "Metal (Candle)" | "Metal (Torch)" | "CPU (Torch)" | "CPU (Candle)" | "Unknown",
#'              log = full_startup_log)
#' @importFrom httr2 request req_perform
#' @export
tei_check_gpu_backend <- function(
  model = "sentence-transformers/all-MiniLM-L6-v2",
  bin = NULL,
  port = NULL,
  timeout = 90
) {
  # Resolve binary
  candidates <- c(
    bin,
    Sys.which("text-embeddings-router"),
    "~/.cargo/bin/text-embeddings-router",
    "/opt/homebrew/bin/text-embeddings-router",
    "/usr/local/bin/text-embeddings-router"
  )
  exe <- path.expand(candidates[nzchar(candidates)][1])
  if (is.na(exe) || !file.exists(exe)) {
    stop("Cannot find 'text-embeddings-router'; supply 'bin'.")
  }

  if (is.null(port)) {
    port <- sample(8000:9000, 1)
  }
  log_out <- tempfile("tei_out_")
  log_err <- tempfile("tei_err_")

  # Start router in background, capture PID
  cmd <- sprintf(
    "%s --model-id %s --port %d > %s 2> %s & echo $!",
    shQuote(exe),
    shQuote(model),
    port,
    shQuote(log_out),
    shQuote(log_err)
  )
  pid <- suppressWarnings(as.integer(system(cmd, intern = TRUE)))
  on.exit(
    {
      if (!is.na(pid)) {
        tools::pskill(pid, 15L)
      }
      Sys.sleep(0.4)
      if (!is.na(pid)) {
        tools::pskill(pid, 9L)
      }
      unlink(c(log_out, log_err))
    },
    add = TRUE
  )

  # Helper: read both logs
  read_logs <- function() {
    out <- if (file.exists(log_out)) {
      paste(readLines(log_out, warn = FALSE), collapse = "\n")
    } else {
      ""
    }
    err <- if (file.exists(log_err)) {
      paste(readLines(log_err, warn = FALSE), collapse = "\n")
    } else {
      ""
    }
    paste(out, err, sep = "\n")
  }

  # Wait until /health responds OR "Ready" appears in logs (handles buffering)
  started <- FALSE
  for (i in seq_len(timeout)) {
    Sys.sleep(1)
    # Try health
    ok <- try(
      httr2::request(paste0("http://localhost:", port, "/health")) |>
        httr2::req_perform(),
      silent = TRUE
    )
    logs <- read_logs()
    if (!inherits(ok, "try-error") || grepl("\\bReady\\b", logs)) {
      started <- TRUE
      break
    }
  }

  # Gather full log text
  full_log <- read_logs()

  # Backend detection (covers your case)
  detect_backend_from_log <- function(txt) {
    # Candle + Metal (your log shows: "Starting Bert model on Metal(MetalDevice(DeviceId(1)))")
    if (grepl("Metal\\(MetalDevice\\(DeviceId\\(", txt)) {
      return("Metal (Candle)")
    }
    # Torch + Metal
    if (
      grepl("Inference backend:\\s*Torch \\(Metal\\)", txt, ignore.case = TRUE)
    ) {
      return("Metal (Torch)")
    }
    # Torch + CPU
    if (
      grepl("Inference backend:\\s*Torch \\(CPU\\)", txt, ignore.case = TRUE)
    ) {
      return("CPU (Torch)")
    }
    # Candle + CPU (some builds log Candle on CPU explicitly)
    if (grepl("Candle", txt, ignore.case = TRUE) && grepl("\\bCPU\\b", txt)) {
      return("CPU (Candle)")
    }
    "Unknown"
  }

  backend <- detect_backend_from_log(full_log)
  message(sprintf("Backend detected: %s", backend))
  invisible(list(
    backend = backend,
    log = full_log,
    started = started,
    pid = pid,
    port = port
  ))
}
