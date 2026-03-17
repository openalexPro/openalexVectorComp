.openai_batch_request <- function(backend, path, method = "GET") {
  if (!is.list(backend) || is.null(backend$base_url)) {
    stop("`backend` must include `base_url`.")
  }
  token <- trimws(Sys.getenv("OVC_API_TOKEN", unset = ""))
  if (!nzchar(token)) {
    stop("`OVC_API_TOKEN` is required for OpenAI Batch API calls.")
  }

  url <- paste0(sub("/+$", "", as.character(backend$base_url)), path)
  req <- httr2::request(url) |>
    httr2::req_method(method) |>
    httr2::req_headers(
      Authorization = paste("Bearer", token)
    )

  timeout <- suppressWarnings(as.numeric(backend$timeout))
  if (is.finite(timeout) && timeout > 0) {
    req <- httr2::req_timeout(req, timeout)
  }
  req
}

.openai_batch_upload_file <- function(backend, file_path) {
  req <- .openai_batch_request(backend, "/files", method = "POST") |>
    httr2::req_body_multipart(
      purpose = "batch",
      file = httr2::req_body_file(file_path)
    )

  res <- .embedding_with_retry(backend, function() {
    httr2::req_perform(req) |> httr2::resp_body_json(simplifyVector = TRUE)
  })

  if (is.null(res$id) || !nzchar(as.character(res$id))) {
    stop("OpenAI file upload did not return a file id.")
  }
  as.character(res$id)
}

.openai_batch_create <- function(backend, input_file_id, completion_window = "24h") {
  req <- .openai_batch_request(backend, "/batches", method = "POST") |>
    httr2::req_body_json(list(
      input_file_id = input_file_id,
      endpoint = "/v1/embeddings",
      completion_window = completion_window
    ))

  res <- .embedding_with_retry(backend, function() {
    httr2::req_perform(req) |> httr2::resp_body_json(simplifyVector = TRUE)
  })

  if (is.null(res$id) || !nzchar(as.character(res$id))) {
    stop("OpenAI batch create did not return a batch id.")
  }
  res
}

.openai_batch_get <- function(backend, job_id) {
  req <- .openai_batch_request(backend, paste0("/batches/", job_id), method = "GET")
  .embedding_with_retry(backend, function() {
    httr2::req_perform(req) |> httr2::resp_body_json(simplifyVector = TRUE)
  })
}

.openai_batch_download_file <- function(backend, file_id, dest) {
  req <- .openai_batch_request(backend, paste0("/files/", file_id, "/content"), method = "GET")
  .embedding_with_retry(backend, function() {
    httr2::req_perform(req) |> httr2::resp_body_raw()
  }) -> raw

  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  con <- file(dest, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(raw, con)
  invisible(dest)
}
