#' Embed texts through a TEI `/embed` endpoint
#'
#' Sends character vector to a TEI service and returns the embeddings as matrix.
#' This helper accepts a maximum of 128 text elements for processing.
#'
#' @param texts Character vector of texts to embed. Empty inputs return a
#'   0-row matrix; missing values are not supported.
#' @param tei_url Base URL to the TEI `/embed` endpoint. Defaults to the URL
#'   saved by [tei_start()] for the current session (if available), otherwise
#'   `"http://localhost:3000/embed"`.
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
  tei_url = tei_default_embed_url()
) {
  stopifnot(is.character(texts))
  if (!length(texts)) {
    return(matrix(numeric(0), nrow = 0))
  } else {
    if (length(texts) > 128) {
      stop("Input length exceeds 128. Please spit the text vector!")
    }
  }
  body <- list(inputs = as.list(texts))
  emb <- httr2::request(tei_url) |>
    httr2::req_method("POST") |>
    httr2::req_body_json(body) |>
    httr2::req_perform() |>
    httr2::resp_body_json(simplifyVector = TRUE)

  # emb should be a numeric matrix with nrow(emb) == length(texts)
  if (nrow(emb) != length(texts)) {
    stop(
      "Embedding count mismatch: got ",
      nrow(emb),
      " vectors for ",
      length(texts),
      " submitted texts."
    )
  }
  d <- ncol(emb)
  colnames(emb) <- paste0("V", seq_len(ncol(emb)))
  return(emb)
}
