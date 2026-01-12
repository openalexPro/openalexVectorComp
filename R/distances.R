##' Join prototype and ridge distances lazily via Arrow
##'
##' Opens two Parquet datasets (prototype margins and ridge scores) as Arrow
##' datasets and performs a lazy inner join on the common key (typically `id`).
##' The result is an Arrow-dplyr query that is not materialized until you call
##' `dplyr::collect()` or write it with `arrow::write_dataset()`.
##'
##' @param prototype_distances Path to a Parquet dataset (file or directory)
##'   containing prototype distances, e.g., columns `id` and `margin`.
##' @param ridge_distance Path to a Parquet dataset (file or directory)
##'   containing ridge-based scores, e.g., columns `id` and `relevance_score`.
##'
##' @return A lazy Arrow dplyr query representing the joined datasets.
##'
##' @examples
##' \dontrun{
##' joined <- distances(
##'   prototype_distances = "path/to/prototype_distances/",
##'   ridge_distance      = "path/to/ridge_scores/"
##' )
##'
##' # Continue piping lazily and write without loading into memory
##' joined |>
##'   dplyr::mutate(ensemble = (margin + relevance_score) / 2) |>
##'   arrow::write_dataset(path = "path/to/output_scores/", format = "parquet")
##'
##' # Or collect a small sample for inspection
##' head(dplyr::collect(joined))
##' }
##'
##' @importFrom arrow open_dataset
##' @importFrom dplyr inner_join
distances <- function(
  prototype_distances,
  ridge_distance
) {
  dplyr::inner_join(
    open_dataset(prototype_distances),
    open_dataset(ridge_distance)
  )
}
