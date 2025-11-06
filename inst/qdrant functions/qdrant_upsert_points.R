#' Upsert points into a Qdrant collection
#'
#' Sends vectors to Qdrant's `/points` endpoint in a single request. When
#' `payloads` is omitted, an empty list is attached to each point. The function
#' assumes `vectors` is an `n x d` matrix aligned with `ids`.
#'
#' @param collection Qdrant collection name.
#' @param ids Vector of point identifiers (character or integer).
#' @param vectors Numeric matrix with one row per point.
#' @param payloads Optional list of metadata lists matching `ids`.
#' @param qdrant Base URL of Qdrant (default `"http://localhost:6333"`).
#' @param wait Logical; if `TRUE`, adds `?wait=true` to the request.
#'
#' @return Invisibly returns `NULL` once the HTTP request completes.
#'
#' @examples
#' \dontrun{
#' emb <- matrix(runif(6), nrow = 2)
#' qdrant_upsert_points("demo", ids = c("a", "b"), vectors = emb)
#' }
#'
#' @importFrom httr2 request req_method req_body_json req_perform
#' @export
qdrant_upsert_points <- function(
  collection,
  ids,
  vectors,
  payloads = NULL,
  qdrant = "http://localhost:6333",
  wait = TRUE
) {
  if (is.null(payloads)) {
    payloads <- replicate(nrow(vectors), list(), simplify = FALSE)
  }
  stopifnot(nrow(vectors) == length(ids), length(payloads) == length(ids))
  points <- lapply(seq_along(ids), function(i) {
    list(id = ids[[i]], vector = as.numeric(vectors[i, ]), payload = payloads[[i]])
  })
  url <- paste0(qdrant, "/collections/", collection, "/points", if (wait) "?wait=true" else "")
  httr2::request(url) |>
    httr2::req_method("PUT") |>
    httr2::req_body_json(list(points = points)) |>
    httr2::req_perform() |>
    invisible()
}

