#' Convert reference-cosine distances to scores
#'
#' Reads a wide reference-cosine distance matrix (as written by
#' [distance_reference_cosine()]) and converts all numeric distance columns to
#' scores.
#'
#' @param distance_parquet Path to a Parquet dataset (file or directory) with
#'   first column `id` and one or more numeric distance columns.
#' @param output_dir Optional output directory. If `NULL`, defaults to replacing
#'   `"distance_reference_cosine"` with `"score_reference_cosine"` in
#'   `distance_parquet`.
#' @param method Scoring transform: `"linear"` (default, `1 - distance`) or
#'   `"exponential"` (`exp(-alpha * distance)`).
#' @param alpha Positive numeric scaling factor used when
#'   `method = "exponential"`.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns output directory.
#' @export
score_reference_cosine <- function(
  distance_parquet,
  output_dir = NULL,
  method = c("linear", "exponential"),
  alpha = 1,
  verbose = TRUE
) {
  if (!is.character(distance_parquet) || length(distance_parquet) != 1 || !nzchar(trimws(distance_parquet))) {
    stop("`distance_parquet` must be a non-empty character string.")
  }
  method <- match.arg(method)
  if (method == "exponential") {
    if (!is.numeric(alpha) || length(alpha) != 1 || !is.finite(alpha) || alpha <= 0) {
      stop("`alpha` must be a positive number when `method = \"exponential\"`.")
    }
  }

  distance_parquet <- normalizePath(distance_parquet, mustWork = TRUE)

  if (is.null(output_dir)) {
    if (grepl("distance_reference_cosine", distance_parquet, fixed = TRUE)) {
      output_dir <- sub("distance_reference_cosine", "score_reference_cosine", distance_parquet, fixed = TRUE)
    } else {
      output_dir <- file.path(dirname(distance_parquet), "score_reference_cosine")
    }
  }
  output_dir <- normalizePath(output_dir, mustWork = FALSE)

  if (dir.exists(output_dir)) {
    unlink(output_dir, recursive = TRUE)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  ds <- arrow::open_dataset(
    distance_parquet,
    factory_options = list(exclude_invalid_files = TRUE)
  )

  if (!("id" %in% names(ds))) {
    stop("`distance_parquet` must contain an `id` column.")
  }
  value_cols <- setdiff(names(ds), "id")
  if (!length(value_cols)) {
    stop("`distance_parquet` must contain at least one distance column besides `id`.")
  }

  query <- ds |>
    dplyr::select(dplyr::all_of(c("id", value_cols)))

  query <- switch(
    method,
    linear = query |>
      dplyr::mutate(dplyr::across(dplyr::all_of(value_cols), ~ 1 - .x)),
    exponential = query |>
      dplyr::mutate(dplyr::across(dplyr::all_of(value_cols), ~ exp(-alpha * .x)))
  )

  arrow::write_dataset(query, path = output_dir, format = "parquet")

  if (verbose) {
    cli::cli_alert_success(sprintf(
      "Done! Wrote reference cosine scores to %s.",
      output_dir
    ))
  }
  invisible(output_dir)
}
