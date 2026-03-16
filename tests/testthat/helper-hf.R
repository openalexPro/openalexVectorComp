ovc_set_hf_token_from_keyring <- function() {
  token <- trimws(Sys.getenv("OVC_API_TOKEN", unset = ""))
  if (!nzchar(token)) {
    try(
      Sys.setenv(OVC_API_TOKEN = keyring::key_get("API_huggingface")),
      silent = TRUE
    )
    token <- trimws(Sys.getenv("OVC_API_TOKEN", unset = ""))
  }
  if (!nzchar(token)) {
    token <- trimws(Sys.getenv("API_huggingface", unset = ""))
  }
  if (!nzchar(token)) {
    token <- trimws(Sys.getenv("HF_TOKEN", unset = ""))
  }
  if (nzchar(token)) {
    Sys.setenv(OVC_API_TOKEN = token)
  }
  invisible(token)
}

ovc_enable_demo_render_test <- function() {
  token <- ovc_set_hf_token_from_keyring()
  if (nzchar(token)) {
    Sys.setenv(OVC_RUN_DEMO_RENDER_TEST = "true")
    return(TRUE)
  }
  Sys.setenv(OVC_RUN_DEMO_RENDER_TEST = "false")
  FALSE
}

ovc_skip_if_no_hf <- function() {
  token <- ovc_set_hf_token_from_keyring()
  testthat::skip_if(
    !nzchar(token),
    "`OVC_API_TOKEN` is required for HF integration tests."
  )

  probe <- try(
    httr2::request(
      "https://router.huggingface.co/hf-inference/models/BAAI/bge-small-en-v1.5"
    ) |>
      httr2::req_method("POST") |>
      httr2::req_headers(
        Authorization = paste("Bearer", token),
        `Content-Type` = "application/json"
      ) |>
      httr2::req_body_json(list(inputs = "ping")) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    silent = TRUE
  )
  if (inherits(probe, "try-error")) {
    testthat::skip("Hugging Face embedding endpoint is not reachable.")
  }
  status <- httr2::resp_status(probe)
  testthat::skip_if(
    status %in% c(401L, 403L),
    "Hugging Face token was rejected for integration tests."
  )
  testthat::skip_if(
    status >= 500L,
    "Hugging Face embedding endpoint is temporarily unavailable."
  )
}

ovc_hf_backend <- function(max_batch_size = 8L) {
  embedding_backend_config(
    provider = "hf",
    model = "BAAI/bge-small-en-v1.5",
    max_batch_size = as.integer(max_batch_size),
    retries = 1
  )
}
