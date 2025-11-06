#' Create (or update) a Qdrant collection
#'
#' Issues an idempotent `PUT` request to ensure a collection exists with the
#' desired vector size and distance metric. Safe to call multiple times.
#'
#' @param collection Name of the Qdrant collection to create.
#' @param size Integer dimensionality of the stored vectors.
#' @param distance Distance metric (`"Cosine"`, `"Euclid"`, or `"Dot"`).
#' @param qdrant Base URL of the Qdrant instance (default `"http://localhost:6333"`).
#'
#' @return Invisibly returns `NULL`. The primary effect is the HTTP side-effect.
#'
#' @examples
#' \dontrun{
#' qdrant_create_collection("demo", size = 384)
#' }
#'
#' @importFrom httr2 request req_method req_body_json req_perform
#' @export
qdrant_create_collection <- function(
  collection,
  size,
  distance = "Cosine",
  qdrant = "http://localhost:6333"
) {
  body <- list(vectors = list(size = as.integer(size), distance = distance))
  httr2::request(paste0(qdrant, "/collections/", collection)) |>
    httr2::req_method("PUT") |>
    httr2::req_body_json(body) |>
    httr2::req_perform() |>
    invisible()
}

