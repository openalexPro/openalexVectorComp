.ovc_or <- function(x, y) if (is.null(x)) y else x
.ovc_validate_openai_batch_inputs <- function(
  project_dir,
  backend,
  corpus_name,
  label,
  batch_size,
  text_preprocessor,
  cleaner_args,
  save_text,
  max_requests_per_job,
  max_job_bytes,
  completion_window
) {
  if (!is.character(project_dir) || length(project_dir) != 1 || !nzchar(trimws(project_dir))) {
    stop("`project_dir` must be a non-empty character string.")
  }
  if (!is.list(backend) || is.null(backend$provider) || backend$provider != "openai") {
    stop("`backend` must be an OpenAI backend configuration.")
  }
  if (!is.character(corpus_name) || length(corpus_name) != 1 || !nzchar(trimws(corpus_name))) {
    stop("`corpus_name` must be a non-empty character string.")
  }
  if (!is.character(label) || length(label) != 1 || !nzchar(trimws(label))) {
    stop("`label` must be a non-empty character string.")
  }
  if (!is.numeric(batch_size) || length(batch_size) != 1 || !is.finite(batch_size) || batch_size <= 0) {
    stop("`batch_size` must be a positive number.")
  }
  if (!is.function(text_preprocessor)) {
    stop("`text_preprocessor` must be a function.")
  }
  if (!is.list(cleaner_args)) {
    stop("`cleaner_args` must be a list.")
  }
  if (!is.logical(save_text) || length(save_text) != 1 || is.na(save_text)) {
    stop("`save_text` must be TRUE or FALSE.")
  }
  if (!is.numeric(max_requests_per_job) || length(max_requests_per_job) != 1 || !is.finite(max_requests_per_job)) {
    stop("`max_requests_per_job` must be numeric scalar.")
  }
  if (!is.numeric(max_job_bytes) || length(max_job_bytes) != 1 || !is.finite(max_job_bytes)) {
    stop("`max_job_bytes` must be numeric scalar.")
  }
  if (max_requests_per_job <= 0 || max_requests_per_job > 50000) {
    stop("`max_requests_per_job` must be > 0 and <= 50000.")
  }
  if (max_job_bytes <= 0 || max_job_bytes > (200 * 1024^2)) {
    stop("`max_job_bytes` must be > 0 and <= 200 MB.")
  }
  if (!identical(completion_window, "24h")) {
    stop("`completion_window` must currently be '24h'.")
  }
}

.ovc_openai_state_file <- function(project_dir, label) {
  label_part <- gsub("/", "_", trimws(as.character(label)), fixed = TRUE)
  file.path(project_dir, paste0("openai_batch_state_label=", label_part, ".json"))
}

.ovc_openai_state_read <- function(state_file, model_id = NULL, backend = NULL, label = NULL, corpus_name = NULL) {
  if (!file.exists(state_file)) {
    return(list(
      version = 1L,
      provider = "openai",
      model_id = model_id,
      label = label,
      corpus_name = corpus_name,
      created_at = as.character(Sys.time(), tz = "UTC"),
      updated_at = as.character(Sys.time(), tz = "UTC"),
      backend = list(
        base_url = .ovc_or(backend$base_url, "https://api.openai.com/v1"),
        timeout = .ovc_or(backend$timeout, 60),
        retries = .ovc_or(backend$retries, 3)
      ),
      jobs = list()
    ))
  }
  txt <- paste(readLines(state_file, warn = FALSE), collapse = "\n")
  if (!nzchar(txt)) {
    stop("State file is empty: ", state_file)
  }
  state <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if (is.null(state$jobs)) state$jobs <- list()
  state
}

.ovc_openai_state_write <- function(state_file, state) {
  state$updated_at <- as.character(Sys.time(), tz = "UTC")
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, null = "null", pretty = TRUE)
  writeLines(json, state_file, useBytes = TRUE)
  invisible(state_file)
}

.ovc_openai_lock_acquire <- function(lock_file) {
  if (file.exists(lock_file)) return(FALSE)
  ok <- file.create(lock_file)
  isTRUE(ok)
}

.ovc_openai_state_next_batch_index <- function(state) {
  if (!length(state$jobs)) return(1L)
  idx <- vapply(state$jobs, function(j) as.integer(.ovc_or(j$batch_index, NA_integer_)), integer(1))
  idx <- idx[is.finite(idx)]
  if (!length(idx)) return(1L)
  as.integer(max(idx) + 1L)
}

.ovc_openai_state_active_custom_ids <- function(state) {
  ids <- character()
  if (!length(state$jobs)) return(ids)
  for (job in state$jobs) {
    if (nzchar(.ovc_or(job$ingested_at, ""))) next
    mf <- .ovc_or(job$manifest_parquet, "")
    if (!nzchar(mf) || !file.exists(mf)) next
    m <- arrow::read_parquet(mf)
    if ("custom_id" %in% names(m)) ids <- c(ids, as.character(m$custom_id))
  }
  unique(ids)
}

.ovc_openai_is_terminal <- function(status) {
  tolower(as.character(status)) %in% c("completed", "failed", "expired", "cancelled")
}

.ovc_openai_job_update_from_remote <- function(job, remote) {
  job$status <- as.character(.ovc_or(remote$status, job$status))
  job$output_file_id <- as.character(.ovc_or(remote$output_file_id, .ovc_or(job$output_file_id, "")))
  job$error_file_id <- as.character(.ovc_or(remote$error_file_id, .ovc_or(job$error_file_id, "")))
  if (!is.null(remote$errors) && length(remote$errors)) {
    job$error_message <- as.character(jsonlite::toJSON(remote$errors, auto_unbox = TRUE))
  }
  job
}

.ovc_load_existing_hash <- function(model_dir, label_part) {
  existing_hash <- stats::setNames(character(), character())
  idx_ds <- try(
    arrow::open_dataset(
      model_dir,
      paste0("label=", label_part),
      factory_options = list(exclude_invalid_files = TRUE)
    ),
    silent = TRUE
  )
  if (inherits(idx_ds, "try-error")) return(existing_hash)

  idx_cols <- names(idx_ds)
  hash_col <- if ("text_hash" %in% idx_cols) "text_hash" else if ("hash" %in% idx_cols) "hash" else NULL
  if (is.null(hash_col) || !"id" %in% idx_cols) return(existing_hash)

  idx_df <- idx_ds |>
    dplyr::select(id, dplyr::all_of(hash_col)) |>
    dplyr::collect()
  if (!nrow(idx_df)) return(existing_hash)

  names(idx_df)[2] <- "text_hash"
  idx_df <- idx_df[!is.na(idx_df$id) & !is.na(idx_df$text_hash), , drop = FALSE]
  if (!nrow(idx_df)) return(existing_hash)
  stats::setNames(as.character(idx_df$text_hash), as.character(idx_df$id))
}

.ovc_prepare_corpus_rows <- function(
  ds,
  batch_size,
  text_preprocessor,
  cleaner_args,
  existing_hash,
  queued_custom_ids,
  save_text
) {
  validate_preprocessor_result <- function(prep, batch_ids) {
    req_cols <- c("id", "text", "text_hash")
    if (!is.data.frame(prep)) {
      stop("`text_preprocessor` must return a data frame.")
    }
    miss <- setdiff(req_cols, names(prep))
    if (length(miss)) {
      stop("`text_preprocessor` output must contain columns: ", paste(miss, collapse = ", "))
    }
    prep$id <- as.character(prep$id)
    prep$text <- as.character(prep$text)
    prep$text_hash <- as.character(prep$text_hash)
    bad_ids <- setdiff(unique(prep$id), unique(batch_ids))
    if (length(bad_ids)) {
      stop("`text_preprocessor` returned ids not present in the input batch.")
    }
    if (anyDuplicated(prep$id)) {
      stop("`text_preprocessor` output contains duplicated ids.")
    }
    prep <- prep[
      !is.na(prep$id) & !is.na(prep$text) & nzchar(prep$id) & nzchar(prep$text),
      ,
      drop = FALSE
    ]
    prep
  }

  reader <- arrow::Scanner$create(
    ds,
    columns = c("id", "title", "abstract"),
    batch_size = as.integer(batch_size)
  )$ToRecordBatchReader()

  out <- list()
  skipped <- 0L

  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) break

    batch_df <- dplyr::collect(batch) |>
      dplyr::mutate(
        id = ifelse(is.na(id), "", as.character(id)),
        title = ifelse(is.na(title), "", as.character(title)),
        abstract = ifelse(is.na(abstract), "", as.character(abstract))
      )

    prep <- do.call(text_preprocessor, c(list(df = batch_df), cleaner_args))
    df <- validate_preprocessor_result(prep, batch_ids = batch_df$id)
    if (!nrow(df)) next

    prev <- unname(existing_hash[df$id])
    keep <- is.na(prev) | prev != df$text_hash

    custom_id <- paste0(df$id, "::", df$text_hash)
    keep <- keep & !(custom_id %in% queued_custom_ids)
    skipped <- skipped + sum(!keep)

    df <- df[keep, , drop = FALSE]
    if (!nrow(df)) next

    if (!isTRUE(save_text) && "text" %in% names(df)) {
      # Keep text temporarily for request building; drop only before manifest writing.
    }

    df$custom_id <- paste0(df$id, "::", df$text_hash)
    out[[length(out) + 1L]] <- df
  }

  if (!length(out)) {
    res <- data.frame()
    attr(res, "skipped_rows") <- skipped
    return(res)
  }

  res <- do.call(rbind, out)
  attr(res, "skipped_rows") <- skipped
  res
}

.ovc_openai_plan_jobs <- function(prepared, model, max_requests_per_job, max_job_bytes) {
  make_line <- function(custom_id, text) {
    obj <- list(
      custom_id = custom_id,
      method = "POST",
      url = "/v1/embeddings",
      body = list(
        model = model,
        input = text
      )
    )
    jsonlite::toJSON(obj, auto_unbox = TRUE, null = "null")
  }

  n <- nrow(prepared)
  request_line <- character(n)
  request_bytes <- numeric(n)
  for (i in seq_len(n)) {
    line <- make_line(prepared$custom_id[[i]], prepared$text[[i]])
    line_bytes <- nchar(enc2utf8(line), type = "bytes") + 1L
    if (line_bytes > max_job_bytes) {
      stop(
        "Single request exceeds `max_job_bytes` (id=", prepared$id[[i]], ", bytes=", line_bytes, ")."
      )
    }
    request_line[[i]] <- line
    request_bytes[[i]] <- line_bytes
  }

  prepared$request_line <- as.character(request_line)
  prepared$request_bytes <- request_bytes

  jobs <- list()
  split_by_size <- FALSE
  cur <- integer()
  cur_bytes <- 0
  for (i in seq_len(n)) {
    next_count <- length(cur) + 1L
    next_bytes <- cur_bytes + request_bytes[[i]]
    if (length(cur) > 0L && (next_count > max_requests_per_job || next_bytes > max_job_bytes)) {
      if (next_bytes > max_job_bytes) split_by_size <- TRUE
      jobs[[length(jobs) + 1L]] <- cur
      cur <- integer()
      cur_bytes <- 0
    }
    cur <- c(cur, i)
    cur_bytes <- cur_bytes + request_bytes[[i]]
  }
  if (length(cur)) jobs[[length(jobs) + 1L]] <- cur

  list(prepared = prepared, jobs = jobs, split_by_size = split_by_size)
}

.ovc_openai_parse_output_jsonl <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  if (!length(lines)) {
    stop("Downloaded OpenAI batch output is empty: ", path)
  }

  custom_id <- character()
  emb <- list()
  for (ln in lines) {
    obj <- jsonlite::fromJSON(ln, simplifyVector = FALSE)
    cid <- as.character(.ovc_or(obj$custom_id, ""))
    if (!nzchar(cid)) next

    vec <- NULL
    if (!is.null(obj$response$body$data) && length(obj$response$body$data) && !is.null(obj$response$body$data[[1]]$embedding)) {
      vec <- as.numeric(obj$response$body$data[[1]]$embedding)
    } else if (!is.null(obj$embedding)) {
      vec <- as.numeric(obj$embedding)
    }

    if (!is.null(vec) && length(vec)) {
      custom_id <- c(custom_id, cid)
      emb[[length(emb) + 1L]] <- vec
    }
  }

  if (!length(custom_id)) {
    stop("No embeddings could be parsed from OpenAI batch output: ", path)
  }
  if (anyDuplicated(custom_id)) {
    stop("Duplicate `custom_id` values in batch output.")
  }

  list(custom_id = custom_id, embeddings = emb)
}

.ovc_openai_build_embeddings_output <- function(parsed, manifest, provider, model_id) {
  if (!("custom_id" %in% names(manifest)) || !("id" %in% names(manifest)) || !("text_hash" %in% names(manifest))) {
    stop("Manifest must include `custom_id`, `id`, and `text_hash`.")
  }

  idx <- match(parsed$custom_id, as.character(manifest$custom_id))
  if (anyNA(idx)) {
    stop("Output contains `custom_id` values missing in manifest.")
  }

  m <- manifest[idx, , drop = FALSE]
  emb <- .embedding_as_matrix(parsed$embeddings)
  if (nrow(emb) != nrow(m)) {
    stop("Embedding count mismatch after manifest join.")
  }

  extra_cols <- setdiff(names(m), c("custom_id", "id", "text_hash"))
  out_core <- data.frame(
    id = as.character(m$id),
    text_hash = as.character(m$text_hash),
    provider = as.character(provider),
    model_id = as.character(model_id),
    created_at = as.character(Sys.time(), tz = "UTC"),
    check.names = FALSE
  )
  out <- cbind(out_core, m[, extra_cols, drop = FALSE], emb)
  colnames(out)[(ncol(out) - ncol(emb) + 1L):ncol(out)] <- paste0("V", seq_len(ncol(emb)))
  out
}

.ovc_openai_state_to_df <- function(state) {
  if (!length(state$jobs)) return(data.frame())
  rows <- lapply(state$jobs, function(j) {
    data.frame(
      batch_index = as.integer(.ovc_or(j$batch_index, NA_integer_)),
      job_id = as.character(.ovc_or(j$job_id, "")),
      status = as.character(.ovc_or(j$status, "")),
      submitted_at = as.character(.ovc_or(j$submitted_at, "")),
      downloaded_at = as.character(.ovc_or(j$downloaded_at, "")),
      ingested_at = as.character(.ovc_or(j$ingested_at, "")),
      row_count_submitted = as.integer(.ovc_or(j$row_count_submitted, 0L)),
      row_count_downloaded = as.integer(.ovc_or(j$row_count_downloaded, 0L)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

.ovc_next_embed_batch_index <- function(label_dir) {
  if (!dir.exists(label_dir)) return(1L)
  b <- list.dirs(label_dir, full.names = FALSE, recursive = FALSE)
  b <- b[grepl("^batch=[0-9]+$", b)]
  if (!length(b)) return(1L)
  nums <- suppressWarnings(as.integer(sub("^batch=", "", b)))
  nums <- nums[is.finite(nums)]
  if (!length(nums)) return(1L)
  as.integer(max(nums) + 1L)
}
