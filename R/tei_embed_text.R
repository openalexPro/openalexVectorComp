#' Embed texts through a TEI `/embed` endpoint
#'
#' Sends character vector to a TEI service and returns the embeddings as matrix.
#' This helper chunks inputs to respect the TEI per-request limit.
#'
#' @param texts Character vector of texts to embed. Empty inputs return a
#'   0-row matrix; missing values are not supported.
#' @param tei_url Base URL to the TEI `/embed` endpoint. Defaults to the URL
#'   saved by [tei_start()] for the current session (if available), otherwise
#'   `"http://localhost:3000/embed"`.
#' @param max_batch_size Maximum number of texts to send per request. Defaults
#'   to 128 to match the TEI limit.
#'
#' @return A numeric matrix with one row per input text and one column per
#'   embedding dimension.
#'
#' @details
#' The function submits `texts` as JSON via [`httr2::request()`].
#' Responses are assumed to be lists a numeric matrix;
#' When the TEI service returns vectors of inconsistent length the
#' call will.
#'
#' @examples
#' \dontrun{
#' sentences <- c(
#'   "Open science accelerates discovery.",
#'   "Controlled vocabularies improve recall."
#' )
#' emb <- tei_embed_text(sentences)
#' dim(emb)
#' }
#'
#' @importFrom httr2 request req_method req_body_json req_perform resp_body_json
#' @export
tei_embed_text <- function(
  texts,
  tei_url = tei_default_embed_url(),
  max_batch_size = tei_info()$server$max_client_batch_size
) {
  stopifnot(is.character(texts))
  if (!length(texts)) {
    return(matrix(numeric(0), nrow = 0))
  }
  if (!is.numeric(max_batch_size) || length(max_batch_size) != 1) {
    stop("max_batch_size must be a single numeric value.")
  }
  max_batch_size <- as.integer(max_batch_size)
  if (max_batch_size <= 0L) {
    stop("max_batch_size must be >= 1.")
  }

  batch_starts <- seq.int(1L, length(texts), by = max_batch_size)
  emb_list <- vector("list", length(batch_starts))

  for (i in seq_along(batch_starts)) {
    start <- batch_starts[[i]]
    end <- min(length(texts), start + max_batch_size - 1L)
    batch <- texts[start:end]
    body <- list(inputs = as.list(batch))
    emb <- httr2::request(tei_url) |>
      httr2::req_method("POST") |>
      httr2::req_body_json(body) |>
      httr2::req_perform() |>
      httr2::resp_body_json(simplifyVector = TRUE)

    # emb should be a numeric matrix with nrow(emb) == length(batch)
    if (nrow(emb) != length(batch)) {
      stop(
        "Embedding count mismatch: got ",
        nrow(emb),
        " vectors for ",
        length(batch),
        " submitted texts."
      )
    }
    emb_list[[i]] <- emb
  }

  emb_all <- do.call(rbind, emb_list)
  colnames(emb_all) <- paste0("V", seq_len(ncol(emb_all)))
  emb_all
}
