#' Perform batched nearest-neighbour search in Qdrant
#'
#' Submits a list of query vectors to Qdrant's `/points/search/batch` endpoint
#' and returns the raw results. Handy when you already have an embedding matrix
#' in memory and want to minimize HTTP overhead.
#'
#' @param collection Qdrant collection name.
#' @param vectors Numeric matrix of query vectors (rows = queries).
#' @param limit Number of neighbours to return per query (default `25`).
#' @param filter Optional Qdrant filter list applied to every query.
#' @param qdrant Base URL of Qdrant (default `"http://localhost:6333"`).
#'
#' @return A list of length `nrow(vectors)` containing the hits for each query
#'   (as returned by Qdrant).
#'
#' @examples
#' \dontrun{
#' Q <- matrix(runif(3 * 384), nrow = 3)
#' hits <- qdrant_search_batch("demo", Q, limit = 10)
#' length(hits)  # three result sets
#' }
#'
#' @importFrom httr2 request req_method req_body_json req_perform resp_body_json
#' @export
qdrant_search_batch <- function(
  collection,
  vectors,
  limit = 25,
  filter = NULL,
  qdrant = "http://localhost:6333"
) {
  searches <- lapply(
    seq_len(nrow(vectors)),
    function(i) list(vector = as.numeric(vectors[i, ]), limit = as.integer(limit), filter = filter)
  )
  res <- httr2::request(paste0(qdrant, "/collections/", collection, "/points/search/batch")) |>
    httr2::req_method("POST") |>
    httr2::req_body_json(list(searches = searches)) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
  res$result
}

