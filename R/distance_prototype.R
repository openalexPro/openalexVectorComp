#' Score prototype margin for a Parquet embeddings dataset
#'
#' Streams an embeddings Parquet dataset in batches, computes the cosine-sim
#' margin of distance to positive minus negative prototypes, and writes Parquet
#' outputs mirroring the embeddings layout: `model_id=<...>/batch=<n>/
#' prototype-margin-*.parquet` with columns `id` and `distance`.
#'
#' @param project_dir Project root directory.
#'   Must contain a folder `embeddings` containing the embeddings.
#'   Outputs are written under
#'   `project_dir/distance_prototype/model_id=<...>/batch=<n>/` with columns
#'   `id` and `distance`.
#' @param embeddings_dir Subfolder under `project_dir/embeddings` that contains
#'   the embeddings dataset.
#' @param included Name of a csv file containing a column named `id` containing the `id` values that define the positive prototype.
#' @param excluded Name of a csv file containing a column named `id` containing the `id` values that define the negative prototype.
#' @param workers Number of parallel workers to use. Passed to
#'   `future::plan()` as `workers`.
#' @param future_plan Future plan to use. Defaults to `"multisession"`.
#'
#' @return Invisibly the model-specific output directory under
#'   `project_dir/distance_prototype/model_id=<...>/`.
#'
#' @examples
#' \dontrun{
#' scores <- distance_prototype(
#'   embeddings = "project/embeddings/",
#'   included = "included.csv",
#'   excluded = "excluded.csv",
#'   project_dir = "project/"
#' )
#' }
#'
#' @importFrom dplyr filter select collect bind_rows all_of
#' @importFrom arrow open_dataset Scanner write_parquet
#' @importFrom cli cli_alert_success
#' @importFrom future.apply future_lapply
#' @importFrom future plan
#' @importFrom progressr with_progress progressor
#'
#' @export
distance_prototype <- function(
  project_dir,
  embeddings_dir = "model_id=BAAI_bge-small-en-v1.5",
  included,
  excluded,
  workers = 2,
  future_plan = "multisession",
  verbose = TRUE
) {
  embeddings_path <- normalizePath(
    file.path(project_dir, "embeddings", embeddings_dir),
    mustWork = TRUE
  )

  out_model_dir <- normalizePath(
    file.path(project_dir, "distance_prototype", embeddings_dir),
    mustWork = FALSE
  )

  if (dir.exists(out_model_dir)) {
    unlink(out_model_dir, recursive = TRUE)
  }
  dir.create(out_model_dir, recursive = TRUE, showWarnings = FALSE)

  ds <- arrow::open_dataset(
    embeddings_path,
    factory_options = list(exclude_invalid_files = TRUE)
  )

  # Identify embedding columns (V1..Vd)
  vcols <- names(ds)
  vcols <- vcols[grepl("^V[0-9]+$", vcols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  if (verbose) {
    message("Calculating and L2-normalizing prototype vectors...")
  }

  # Compute column means lazily in Arrow and collect only the single-row summary
  pos <- centroid_prototype(
    project_dir = project_dir,
    embeddings_dir = embeddings_dir,
    selected = included
  )

  neg <- centroid_prototype(
    project_dir = project_dir,
    embeddings_dir = embeddings_dir,
    selected = excluded
  )

  # L2-normalize the prototype vectors for cosine similarity
  pos_u <- pos / sqrt(sum(pos^2) + 1e-12)
  neg_u <- neg / sqrt(sum(neg^2) + 1e-12)

  # Stream all rows to score margins
  cols <- c("id", vcols)
  if ("batch" %in% names(ds)) {
    cols <- c(cols, "batch")
  }

  batches <- list.dirs(
    embeddings_path,
    recursive = FALSE
  )

  # Create matching model_id directory under output and copy metadata
  `%||%` <- function(x, y) if (is.null(x)) y else x

  start_time <- Sys.time()

  future::plan(future_plan, workers = workers)

  if (verbose) {
    message("Streaming individual batches to calculate distance...")
  }

  progressr::with_progress({
    p <- progressr::progressor(along = batches)

    future.apply::future_lapply(
      seq_along(batches),
      function(i) {
        batch_path <- batches[[i]]
        batch <- arrow::open_dataset(batch_path) |>
          dplyr::collect()

        X <- as.matrix(batch[, vcols, drop = FALSE])
        Xn <- X / sqrt(rowSums(X^2) + 1e-12)
        m <- as.numeric(Xn %*% pos_u) - as.numeric(Xn %*% neg_u)

        batch_dir <- file.path(
          out_model_dir,
          basename(batch_path)
        )

        if (!dir.exists(batch_dir)) {
          dir.create(batch_dir, recursive = TRUE, showWarnings = FALSE)
        }

        batch |>
          dplyr::select(
            id
          ) |>
          dplyr::mutate(
            distance = m
          ) |>
          arrow::write_parquet(
            file.path(batch_dir, sprintf("prototype-margin-%05d.parquet", i))
          )

        p()
      }
    )
  })

  elapsed <- Sys.time() - start_time

  cli::cli_alert_success(sprintf(
    "Done! Processed %d chunks in %d batches in %s.",
    nrow(ds),
    length(batches),
    format(elapsed, digits = 2)
  ))

  invisible(out_model_dir)
}

# Internal helper: compute centroid for a selected id set.
centroid_prototype <- function(
  project_dir,
  embeddings_dir = "model_id=BAAI_bge-small-en-v1.5",
  selected = "included.csv",
  verbose = TRUE
) {
  embeddings <- normalizePath(
    file.path(project_dir, "embeddings", embeddings_dir),
    mustWork = TRUE
  )

  selected <- read.csv(file.path(project_dir, selected))$id
  stopifnot(length(selected) > 0)

  ds <- arrow::open_dataset(
    embeddings,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  vcols <- names(ds)
  vcols <- vcols[grepl("^V[0-9]+$", vcols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  sel_ids <- ds |>
    dplyr::select(id) |>
    dplyr::filter(id %in% selected) |>
    dplyr::distinct() |>
    dplyr::collect()

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

  ds |>
    dplyr::filter(id %in% selected) |>
    dplyr::collect() |>
    dplyr::select(dplyr::all_of(vcols)) |>
    colMeans()
}
