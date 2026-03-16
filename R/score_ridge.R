#' Convert ridge distances to ridge scores
#'
#' Reads a distance dataset with columns `id` and `area_distance`, computes
#' `relevance_score = exp(-alpha * area_distance)`, and writes a scored Parquet
#' dataset.
#'
#' @param distance_parquet Path to a Parquet dataset (file or directory) with
#'   at least columns `id` and `area_distance`.
#' @param output_dir Optional output directory. If `NULL`, defaults to replacing
#'   `"distance_ridge"` with `"score_ridge"` in `distance_parquet`.
#' @param alpha Positive numeric scaling factor in
#'   `exp(-alpha * area_distance)`. Default `0.5` reproduces previous behavior.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns output directory.
#' @export
score_ridge <- function(
  distance_parquet,
  output_dir = NULL,
  alpha = 0.5,
  verbose = TRUE
) {
  if (!is.character(distance_parquet) || length(distance_parquet) != 1 || !nzchar(trimws(distance_parquet))) {
    stop("`distance_parquet` must be a non-empty character string.")
  }
  if (!is.numeric(alpha) || length(alpha) != 1 || !is.finite(alpha) || alpha <= 0) {
    stop("`alpha` must be a positive number.")
  }

  distance_parquet <- normalizePath(distance_parquet, mustWork = TRUE)

  if (is.null(output_dir)) {
    if (grepl("distance_ridge", distance_parquet, fixed = TRUE)) {
      output_dir <- sub("distance_ridge", "score_ridge", distance_parquet, fixed = TRUE)
    } else {
      output_dir <- file.path(dirname(distance_parquet), "score_ridge")
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
  if (!all(c("id", "area_distance") %in% names(ds))) {
    stop("`distance_parquet` must contain columns `id` and `area_distance`.")
  }

  cols <- c("id", "area_distance")
  if ("batch" %in% names(ds)) {
    cols <- c(cols, "batch")
  }
  reader <- arrow::Scanner$create(
    ds,
    columns = cols,
    batch_size = 100000L
  )$ToRecordBatchReader()

  idx <- 0L
  n_scored <- 0L
  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) break

    df <- as.data.frame(batch, stringsAsFactors = FALSE)
    if (!nrow(df)) next
    if (any(!is.finite(df$area_distance))) {
      stop("`area_distance` contains non-finite values.")
    }

    out_df <- data.frame(
      id = as.character(df$id),
      relevance_score = exp(-alpha * as.numeric(df$area_distance)),
      area_distance = as.numeric(df$area_distance),
      check.names = FALSE
    )

    idx <- idx + 1L
    batch_id <- if ("batch" %in% names(df)) as.character(df$batch[[1]]) else as.character(idx)
    shard_dir <- file.path(output_dir, sprintf("batch=%s", batch_id))
    if (!dir.exists(shard_dir)) dir.create(shard_dir, recursive = TRUE)
    arrow::write_parquet(out_df, file.path(shard_dir, sprintf("ridge-score-%05d.parquet", idx)))
    n_scored <- n_scored + nrow(out_df)
  }

  if (n_scored == 0L) {
    stop("No rows found in distance dataset.")
  }
  if (verbose) {
    cli::cli_alert_success(sprintf(
      "Done! Wrote ridge scores for %d rows to %s.",
      n_scored,
      output_dir
    ))
  }
  invisible(output_dir)
}
