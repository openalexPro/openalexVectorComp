#' Build embedding backend configuration
#'
#' Creates a configuration object used by the embedding backend adapter.
#'
#' @param provider Backend provider: `"hf"`, `"openai"`, or `"tei"`.
#' @param base_url Provider base URL. If `NULL`, provider defaults are used.
#' @param model Optional model id. If `NULL`, provider defaults are used.
#' @param max_batch_size Optional max texts per HTTP request.
#' @param timeout Request timeout (seconds) used by backends that support it.
#' @param retries Number of retry attempts for transient failures.
#' @param tei_url Optional TEI compatibility argument. If provided, it is treated
#'   as the full embedding endpoint URL and overrides `base_url`.
#'
#' @return A named list with backend configuration.
#' @export
backend_config <- function(
  provider = c("hf", "openai", "tei"),
  base_url = NULL,
  model = NULL,
  max_batch_size = NULL,
  timeout = 60,
  retries = 3,
  tei_url = NULL
) {
  provider <- match.arg(provider)
  timeout <- as.numeric(timeout)
  retries <- as.integer(retries)
  if (!is.finite(timeout) || timeout <= 0) {
    stop("`timeout` must be a positive number.")
  }
  if (!is.finite(retries) || retries < 0L) {
    stop("`retries` must be >= 0.")
  }
  if (!is.null(max_batch_size)) {
    max_batch_size <- as.integer(max_batch_size)
    if (!is.finite(max_batch_size) || max_batch_size <= 0L) {
      stop("`max_batch_size` must be a positive integer.")
    }
  }

  cfg <- switch(provider,
    hf = list(
      provider = "hf",
      base_url = if (is.null(base_url)) "https://router.huggingface.co/hf-inference" else base_url,
      model = if (is.null(model)) "BAAI/bge-small-en-v1.5" else model,
      embed_url = NULL
    ),
    openai = list(
      provider = "openai",
      base_url = if (is.null(base_url)) "https://api.openai.com/v1" else base_url,
      model = if (is.null(model)) "text-embedding-3-small" else model,
      embed_url = NULL
    ),
    tei = list(
      provider = "tei",
      base_url = if (is.null(base_url)) "http://localhost:3000" else base_url,
      model = model,
      embed_url = NULL
    )
  )

  if (!is.null(tei_url) && nzchar(tei_url)) {
    cfg$embed_url <- sub("/+$", "", tei_url)
    cfg$base_url <- cfg$embed_url
  }
  cfg$base_url <- sub("/+$", "", cfg$base_url)
  cfg$max_batch_size <- max_batch_size
  cfg$timeout <- timeout
  cfg$retries <- retries
  cfg
}

#' Get embedding backend model/service information
#'
#' Returns normalized backend metadata used by the pipeline.
#'
#' @param backend Backend configuration from [backend_config()].
#'
#' @return A list with fields `provider`, `model_id`, `dim`, `max_batch_size`,
#'   and `raw`.
#' @export
backend_info <- function(backend = backend_config()) {
  if (!is.list(backend) || is.null(backend$provider)) {
    stop("`backend` must be a configuration object from backend_config().")
  }
  switch(backend$provider,
    hf = .embedding_info_hf(backend),
    openai = .embedding_info_openai(backend),
    tei = .embedding_info_tei(backend),
    stop("Unsupported backend provider: ", backend$provider)
  )
}

#' Embed texts via configured backend
#'
#' Uses the configured backend adapter to embed a character vector of texts.
#' For authenticated providers, set `OVC_API_TOKEN` in the environment. The
#' adapter sends it as a bearer token.
#'
#' @param texts Character vector of input texts.
#' @param backend Backend configuration from [backend_config()].
#'
#' @return Numeric matrix with one row per text and columns `V1..Vd`.
#' @export
backend_embed_texts <- function(
  texts,
  backend = backend_config()
) {
  if (!is.character(texts)) {
    stop("`texts` must be a character vector.")
  }
  if (!length(texts)) {
    return(matrix(numeric(0), nrow = 0))
  }
  if (!is.list(backend) || is.null(backend$provider)) {
    stop("`backend` must be a configuration object from backend_config().")
  }
  switch(backend$provider,
    hf = .embedding_embed_texts_hf(texts, backend),
    openai = .embedding_embed_texts_openai(texts, backend),
    tei = .embedding_embed_texts_tei(texts, backend),
    stop("Unsupported backend provider: ", backend$provider)
  )
}

#' Read backend configuration from YAML
#'
#' Reads backend configuration from a YAML file and returns a normalized object
#' in the same format as [backend_config()].
#'
#' Supports both the current flat format and legacy nested metadata format.
#'
#' @param fn Path to YAML file. Defaults to `"embed_model.yaml"`.
#'
#' @return A backend configuration list compatible with
#'   [backend_config()].
#' @export
backend_read <- function(fn = "embed_model.yaml") {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  meta <- yaml::read_yaml(fn)
  if (!is.list(meta)) {
    stop("`fn` does not contain a valid YAML object.")
  }

  # Current flat format (same shape as backend_config()).
  if (!is.null(meta$provider)) {
    cfg <- backend_config(
      provider = meta$provider,
      base_url = meta$base_url %||% NULL,
      model = meta$model %||% NULL,
      max_batch_size = meta$max_batch_size %||% NULL,
      timeout = meta$timeout %||% 60,
      retries = meta$retries %||% 3
    )
    if (!is.null(meta$embed_url) && nzchar(meta$embed_url)) {
      cfg$embed_url <- sub("/+$", "", meta$embed_url)
      if (identical(cfg$provider, "tei")) {
        cfg$base_url <- cfg$embed_url
      }
    }
    return(cfg)
  }

  # Legacy nested format created earlier in this alpha cycle.
  if (!is.null(meta$backend) && !is.null(meta$backend$provider)) {
    model <- meta$model$requested_id %||% meta$model$id %||% NULL
    cfg <- backend_config(
      provider = meta$backend$provider,
      base_url = meta$backend$base_url %||% NULL,
      model = model,
      max_batch_size = meta$backend$max_batch_size %||% NULL,
      timeout = meta$backend$timeout %||% 60,
      retries = meta$backend$retries %||% 3
    )
    if (!is.null(meta$backend$embed_url) && nzchar(meta$backend$embed_url)) {
      cfg$embed_url <- sub("/+$", "", meta$backend$embed_url)
      if (identical(cfg$provider, "tei")) {
        cfg$base_url <- cfg$embed_url
      }
    }
    return(cfg)
  }

  stop("YAML file does not contain a recognized backend configuration format.")
}

#' Save backend configuration to YAML
#'
#' Writes a backend configuration (same shape as returned by
#' [backend_config()]) to YAML.
#'
#' @param backend Backend configuration from [backend_config()].
#' @param fn Output YAML file path. Defaults to `"embed_model.yaml"`.
#'
#' @return Invisibly returns `fn`.
#' @export
backend_save <- function(
  backend = backend_config(),
  fn = "embed_model.yaml"
) {
  if (!is.list(backend) || is.null(backend$provider)) {
    stop("`backend` must be a configuration object from backend_config().")
  }
  data <- list(
    provider = backend$provider,
    base_url = backend$base_url,
    model = backend$model,
    embed_url = backend$embed_url,
    max_batch_size = backend$max_batch_size,
    timeout = backend$timeout,
    retries = backend$retries
  )
  yaml::write_yaml(data, fn)
  invisible(fn)
}

.embedding_with_retry <- function(backend, fn) {
  attempts <- seq_len(backend$retries + 1L)
  last_err <- NULL
  for (attempt in attempts) {
    out <- try(fn(), silent = TRUE)
    if (!inherits(out, "try-error")) {
      return(out)
    }
    last_err <- out
    if (attempt < length(attempts)) {
      Sys.sleep(min(2^(attempt - 1L), 8))
    }
  }
  stop("Embedding request failed after retries: ", as.character(last_err))
}

.embedding_request_base <- function(url, backend) {
  req <- httr2::request(url) |>
    httr2::req_method("POST")
  token <- Sys.getenv("OVC_API_TOKEN", unset = "")
  if (nzchar(token)) {
    req <- httr2::req_headers(req, Authorization = paste("Bearer", token))
  }
  req
}

.embedding_as_matrix <- function(x) {
  if (is.matrix(x)) {
    return(x)
  }
  if (is.data.frame(x)) {
    return(as.matrix(x))
  }
  if (is.list(x) && length(x) && is.numeric(x[[1]])) {
    lens <- vapply(x, length, integer(1))
    if (length(unique(lens)) != 1L) {
      stop("Backend returned vectors of inconsistent length.")
    }
    return(as.matrix(do.call(rbind, x)))
  }
  if (is.numeric(x)) {
    return(matrix(x, nrow = 1L))
  }
  stop("Unsupported embedding response format.")
}

.embedding_batch_starts <- function(n, by) {
  by <- as.integer(by)
  if (!is.finite(by) || by <= 0L) {
    by <- 128L
  }
  seq.int(1L, n, by = by)
}

.embedding_or <- function(x, y) if (is.null(x)) y else x
