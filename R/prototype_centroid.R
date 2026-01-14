#' Compute a prototype centroid from an embeddings dataset
#'
#' Loads the embeddings for a selected set of `id` values and returns the
#' column-wise mean vector (centroid).
#'
#' @param project_dir Project root directory.
#'   Must contain a folder `embeddings` containing the embeddings.
#' @param embeddings_dir Subfolder under `project_dir/embeddings` that contains
#'   the embeddings dataset.
#' @param selected Name of a csv file containing a column named `id` with the
#'   values that define the prototype.
#'
#' @return A numeric vector representing the centroid embedding.
#'
#' @examples
#' \dontrun{
#' centroid <- prototype_centroid(
#'   project_dir = "project/",
#'   embeddings_dir = "model_id=sentence-transformers_all-MiniLM-L6-v2",
#'   selected = "selected.csv"
#' )
#' }
#'
#' @importFrom dplyr filter select collect distinct all_of
#' @importFrom arrow open_dataset
#'
#' @export
prototype_centroid <- function(
  project_dir,
  embeddings_dir = "model_id=sentence-transformers_all-MiniLM-L6-v2",
  selected = "included.csv",
  verbose = TRUE
) {
  embeddings <- normalizePath(
    file.path(project_dir, "embeddings", embeddings_dir),
    mustWork = TRUE
  )

  selected <- read.csv(file.path(project_dir, selected))$id

  stopifnot(length(selected) > 0)

  ds <- arrow::open_dataset(embeddings)
  # Identify embedding columns (V1..Vd)
  vcols <- names(ds)
  vcols <- vcols[grepl("^V[0-9]+$", vcols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  # Check presence of requested ids (collect only ids)
  sel_ids <- ds |>
    dplyr::select(id) |>
    dplyr::filter(id %in% selected) |>
    dplyr::distinct() |>
    collect()

  if (nrow(sel_ids) == 0) {
    stop("None of the `selected` ids were found in embeddings dataset.")
  }

  miss_sel <- setdiff(selected, sel_ids$id)
  if (length(miss_sel)) {
    warning(
      "Some selected ids not found: ",
      paste(head(miss_sel, 10), collapse = ", "),
      if (length(miss_sel) > 10) " …"
    )
  }

  if (verbose) {
    message("Calculating prototype centroid...")
  }

  # Compute column means lazily in Arrow and collect only the single-row summary
  sel_centroid <- ds |>
    dplyr::filter(id %in% selected) |>
    collect() |>
    dplyr::select(
      dplyr::all_of(vcols)
    ) |>
    colMeans()

  return(sel_centroid)
}
