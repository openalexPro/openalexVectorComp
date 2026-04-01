#' Embed texts through a configured backend
#'
#' Sends a character vector to the configured backend and returns embeddings as
#' a numeric matrix.
#'
#' @param texts Character vector of texts to embed. Empty inputs return a
#'   0-row matrix; missing values are not supported.
#' @param backend Backend configuration created with
#'   [backend_config()].
#'
#' @return A numeric matrix with one row per input text and one column per
#'   embedding dimension.
#' @export
embed_texts <- function(
  texts,
  backend = backend_config()
) {
  backend_embed_texts(
    texts = texts,
    backend = backend
  )
}

