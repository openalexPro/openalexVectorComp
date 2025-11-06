#' Embed texts through a TEI `/embed` endpoint
#'
#' Streams character vectors to a TEI service in fixed-size batches and binds
#' the returned embeddings row-wise. This helper keeps requests small enough for
#' typical TEI deployments while preserving the order of `texts` in the output.
#'
#' @param texts Character vector of texts to embed. Empty inputs return a
#'   0-row matrix; missing values are not supported.
#' @param tei_url Base URL to the TEI `/embed` endpoint
#'   (default `"http://localhost:8080/embed"`).
#' @param batch_size Maximum number of texts to send per HTTP request.
#'
#' @return A numeric matrix with one row per input text and one column per
#'   embedding dimension.
#'
#' @details
#' The function splits `texts` into consecutive groups of size `batch_size` and
#' submits each chunk as JSON via [`httr2::request()`]. Responses are assumed to
#' be lists of numeric vectors; each vector is cast to `numeric` and combined
#' with `rbind`. When the TEI service returns vectors of inconsistent length the
#' call will fail when `rbind` attempts to bind the results.
#'
#' @examples
#' \dontrun{
#' sentences <- c(
#'   "Open science accelerates discovery.",
#'   "Controlled vocabularies improve recall."
#' )
#' emb <- tei_embed(sentences)
#' dim(emb)
#' }
#'
#' @importFrom httr2 request req_method req_body_json req_perform resp_body_json
#' @export
tei_embed <- function(texts, tei_url = "http://localhost:8080/embed", batch_size = 128) {
  stopifnot(is.character(texts))
  if (!length(texts)) return(matrix(numeric(0), nrow = 0))
  batches <- split(seq_along(texts), ceiling(seq_along(texts)/batch_size))
  out <- vector("list", length(batches))
  i <- 1L
  for (idx in batches) {
    body <- list(inputs = as.list(texts[idx]))
    res <- httr2::request(tei_url) |>
      httr2::req_method("POST") |>
      httr2::req_body_json(body) |>
      httr2::req_perform() |>
      httr2::resp_body_json(simplifyVector = TRUE)
    # res should be a list of numeric vectors
    M <- do.call(rbind, lapply(res, function(x) as.numeric(x)))
    out[[i]] <- M
    i <- i + 1L
  }
  # rbind all
  do.call(rbind, out)
}

