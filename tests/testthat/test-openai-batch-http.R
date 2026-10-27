oa_http_backend <- function(base_url = "https://api.openai.test/v1/", timeout = 7) {
  list(
    provider = "openai",
    base_url = base_url,
    model = "text-embedding-3-small",
    timeout = timeout,
    retries = 0L
  )
}

testthat::test_that(".openai_batch_request validates backend and token", {
  req_fun <- ovc_ns(".openai_batch_request")

  testthat::expect_error(req_fun(list(), "/files"), "must include `base_url`")
  testthat::expect_error(req_fun("x", "/files"), "must include `base_url`")

  ovc_local_token(NA)
  testthat::expect_error(
    req_fun(oa_http_backend(), "/files"),
    "`OVC_API_TOKEN` is required"
  )
})

testthat::test_that(".openai_batch_request builds url, method, auth and timeout", {
  req_fun <- ovc_ns(".openai_batch_request")
  ovc_local_token("  sk-test  ")

  req <- req_fun(oa_http_backend(), "/batches/abc", method = "GET")
  testthat::expect_identical(httr2::req_get_url(req), "https://api.openai.test/v1/batches/abc")
  testthat::expect_identical(httr2::req_get_method(req), "GET")
  testthat::expect_identical(
    httr2::req_get_headers(req, "reveal")$Authorization,
    "Bearer sk-test"
  )
  testthat::expect_equal(req$options$timeout_ms, 7000)

  req_no_timeout <- req_fun(oa_http_backend(timeout = NA), "/files", method = "POST")
  testthat::expect_identical(httr2::req_get_method(req_no_timeout), "POST")
  testthat::expect_null(req_no_timeout$options$timeout_ms)
})

testthat::test_that(".openai_batch_upload_file posts multipart and returns the file id", {
  upload <- ovc_ns(".openai_batch_upload_file")
  ovc_local_token()
  f <- tempfile(fileext = ".jsonl")
  writeLines('{"custom_id":"a"}', f)

  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- list(
      url = httr2::req_get_url(req),
      method = httr2::req_get_method(req),
      body_type = httr2::req_get_body_type(req)
    )
    httr2::response_json(body = list(id = "file-123", purpose = "batch"))
  })

  testthat::expect_identical(upload(oa_http_backend(), f), "file-123")
  testthat::expect_identical(seen$url, "https://api.openai.test/v1/files")
  testthat::expect_identical(seen$method, "POST")
  testthat::expect_identical(seen$body_type, "multipart")
})

testthat::test_that(".openai_batch_upload_file reports HTTP errors with API message or body", {
  upload <- ovc_ns(".openai_batch_upload_file")
  ovc_local_token()
  f <- tempfile(fileext = ".jsonl")
  writeLines("{}", f)

  httr2::local_mocked_responses(function(req) {
    httr2::response_json(
      status_code = 400L,
      body = list(error = list(message = "Invalid purpose"))
    )
  })
  testthat::expect_error(
    upload(oa_http_backend(), f),
    "OpenAI file upload failed \\(HTTP 400\\)\\. Invalid purpose"
  )

  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 502L,
      headers = list(`Content-Type` = "text/plain"),
      body = charToRaw("Bad gateway")
    )
  })
  testthat::expect_error(
    upload(oa_http_backend(), f),
    "HTTP 502\\)\\. Bad gateway"
  )

  httr2::local_mocked_responses(function(req) {
    httr2::response(status_code = 500L)
  })
  testthat::expect_error(
    upload(oa_http_backend(), f),
    "HTTP 500\\)\\. No error body returned"
  )
})

testthat::test_that(".openai_batch_upload_file rejects non-JSON or id-less success responses", {
  upload <- ovc_ns(".openai_batch_upload_file")
  ovc_local_token()
  f <- tempfile(fileext = ".jsonl")
  writeLines("{}", f)

  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 200L,
      headers = list(`Content-Type` = "text/html"),
      body = charToRaw("<html>ok</html>")
    )
  })
  testthat::expect_error(upload(oa_http_backend(), f), "non-JSON response")

  httr2::local_mocked_responses(function(req) {
    httr2::response_json(body = list(object = "file"))
  })
  testthat::expect_error(upload(oa_http_backend(), f), "did not return a file id")
})

testthat::test_that(".openai_batch_create sends embeddings batch request", {
  create <- ovc_ns(".openai_batch_create")
  ovc_local_token()

  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- list(
      url = httr2::req_get_url(req),
      method = httr2::req_get_method(req),
      body = httr2::req_get_body(req)
    )
    httr2::response_json(body = list(id = "batch_1", status = "validating"))
  })

  res <- create(oa_http_backend(), input_file_id = "file-9")
  testthat::expect_identical(res$id, "batch_1")
  testthat::expect_identical(res$status, "validating")
  testthat::expect_identical(seen$url, "https://api.openai.test/v1/batches")
  testthat::expect_identical(seen$method, "POST")
  testthat::expect_identical(seen$body$input_file_id, "file-9")
  testthat::expect_identical(seen$body$endpoint, "/v1/embeddings")
  testthat::expect_identical(seen$body$completion_window, "24h")

  httr2::local_mocked_responses(function(req) {
    httr2::response_json(body = list(status = "validating"))
  })
  testthat::expect_error(
    create(oa_http_backend(), input_file_id = "file-9"),
    "did not return a batch id"
  )
})

testthat::test_that(".openai_batch_get fetches the batch by id", {
  get_batch <- ovc_ns(".openai_batch_get")
  ovc_local_token()

  seen_url <- NULL
  httr2::local_mocked_responses(function(req) {
    seen_url <<- httr2::req_get_url(req)
    httr2::response_json(body = list(id = "batch_7", status = "completed", output_file_id = "of_7"))
  })

  res <- get_batch(oa_http_backend(), "batch_7")
  testthat::expect_identical(seen_url, "https://api.openai.test/v1/batches/batch_7")
  testthat::expect_identical(res$status, "completed")
  testthat::expect_identical(res$output_file_id, "of_7")

  httr2::local_mocked_responses(function(req) httr2::response(status_code = 404L))
  testthat::expect_error(
    get_batch(oa_http_backend(), "missing"),
    "Embedding request failed after retries"
  )
})

testthat::test_that(".openai_batch_download_file writes raw content to dest", {
  download <- ovc_ns(".openai_batch_download_file")
  ovc_local_token()

  payload <- '{"custom_id":"cid_1","embedding":[1,2]}\n'
  seen_url <- NULL
  httr2::local_mocked_responses(function(req) {
    seen_url <<- httr2::req_get_url(req)
    httr2::response(status_code = 200L, body = charToRaw(payload))
  })

  dest <- file.path(tempfile("ovc_dl_"), "nested", "output.jsonl")
  out <- download(oa_http_backend(), "of_1", dest)
  testthat::expect_identical(out, dest)
  testthat::expect_identical(seen_url, "https://api.openai.test/v1/files/of_1/content")
  testthat::expect_true(file.exists(dest))
  testthat::expect_identical(
    readChar(dest, file.size(dest), useBytes = TRUE),
    payload
  )
})
