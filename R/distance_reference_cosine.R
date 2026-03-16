#' Pairwise cosine distances with centroid axis between label partitions
#'
#' Reads embeddings from a model-specific dataset and computes cosine distances
#' between all vectors in `corpus_label` and all vectors in `reference_label`.
#' A centroid row/column is added to the matrix:
#' - rows are corpus ids plus `"centroid"` (corpus centroid),
#' - columns are reference ids plus `"centroid"` (reference centroid).
#'
#' Embeddings are expected under:
#' `project_dir/embeddings/model_id=<...>/label=<label>/batch=<n>/...`
#'
#' Output file:
#' - `pairwise-cosine.parquet`: wide table with first column `id` (corpus id or
#'   `"centroid"`), reference-id columns, and a final `centroid` column.
#'
#' @param project_dir Project root directory containing `embeddings/`.
#' @param embeddings_dir Model subfolder under `project_dir/embeddings`, e.g.
#'   `"model_id=BAAI_bge-small-en-v1.5"`.
#' @param corpus_label Label partition used as corpus side. Defaults to
#'   `"corpus"`.
#' @param reference_label Label partition used as reference side. Defaults to
#'   `"reference"`.
#' @param batch_size Unused placeholder for compatibility with planned streaming
#'   extension.
#' @param max_cells Maximum allowed matrix size
#'   (`(n_corpus + 1) * (n_reference + 1)`) to guard memory use.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly the output directory
#'   `project_dir/distance_reference_cosine/model_id=<...>/corpus_label=<...>/reference_label=<...>/`.
#' @export
distance_reference_cosine <- function(
  project_dir,
  embeddings_dir = "model_id=BAAI_bge-small-en-v1.5",
  corpus_label = "corpus",
  reference_label = "reference",
  batch_size = 100000,
  max_cells = 5e7,
  verbose = TRUE
) {
  if (!is.character(corpus_label) || length(corpus_label) != 1 || !nzchar(trimws(corpus_label))) {
    stop("`corpus_label` must be a non-empty character string.")
  }
  if (!is.character(reference_label) || length(reference_label) != 1 || !nzchar(trimws(reference_label))) {
    stop("`reference_label` must be a non-empty character string.")
  }
  if (!is.numeric(max_cells) || length(max_cells) != 1 || !is.finite(max_cells) || max_cells <= 0) {
    stop("`max_cells` must be a positive number.")
  }

  embeddings_path <- normalizePath(
    file.path(project_dir, "embeddings", embeddings_dir),
    mustWork = TRUE
  )

  corpus_label <- trimws(corpus_label)
  reference_label <- trimws(reference_label)
  corpus_label_part <- gsub("/", "_", corpus_label, fixed = TRUE)
  reference_label_part <- gsub("/", "_", reference_label, fixed = TRUE)

  out_model_dir <- normalizePath(
    file.path(
      project_dir,
      "distance_reference_cosine",
      embeddings_dir,
      paste0("corpus_label=", corpus_label_part),
      paste0("reference_label=", reference_label_part)
    ),
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

  if (!("label" %in% names(ds))) {
    stop("Embeddings dataset has no `label` partition. Re-embed with `embed_corpus(label = ...)`.")
  }

  vcols <- names(ds)
  vcols <- vcols[grepl("^V[0-9]+$", vcols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  if (verbose) {
    message("Loading reference and corpus label partitions...")
  }

  ref_df <- ds |>
    dplyr::filter(label == reference_label) |>
    dplyr::select(dplyr::all_of(c("id", vcols))) |>
    dplyr::collect()

  corpus_df <- ds |>
    dplyr::filter(label == corpus_label) |>
    dplyr::select(dplyr::all_of(c("id", vcols))) |>
    dplyr::collect()

  if (!nrow(ref_df)) {
    stop("No embeddings found for `reference_label = ", reference_label, "`.")
  }
  if (!nrow(corpus_df)) {
    stop("No embeddings found for `corpus_label = ", corpus_label, "`.")
  }

  if (anyDuplicated(ref_df$id)) {
    stop("Duplicate ids found in reference label partition.")
  }
  if (anyDuplicated(corpus_df$id)) {
    stop("Duplicate ids found in corpus label partition.")
  }

  n_ref <- nrow(ref_df)
  n_corpus <- nrow(corpus_df)
  n_cells <- as.double(n_corpus + 1L) * as.double(n_ref + 1L)
  if (n_cells > max_cells) {
    stop(
      "Distance matrix would contain ",
      format(n_cells, scientific = FALSE, trim = TRUE),
      " cells (", n_corpus + 1L, " x ", n_ref + 1L, "), exceeding `max_cells = ",
      format(max_cells, scientific = FALSE, trim = TRUE),
      "`. Reduce label sizes or increase `max_cells`."
    )
  }

  R <- as.matrix(ref_df[, vcols, drop = FALSE])
  C <- as.matrix(corpus_df[, vcols, drop = FALSE])

  r_norms <- sqrt(rowSums(R^2))
  if (any(!is.finite(r_norms)) || any(r_norms <= 0)) {
    stop("Reference partition contains zero-norm or non-finite vectors; cannot compute cosine values.")
  }
  c_norms <- sqrt(rowSums(C^2))
  if (any(!is.finite(c_norms)) || any(c_norms <= 0)) {
    stop("Corpus partition contains zero-norm or non-finite vectors; cannot compute cosine values.")
  }

  Rn <- R / r_norms
  Cn <- C / c_norms

  reference_centroid <- colMeans(Rn)
  reference_centroid_norm <- sqrt(sum(reference_centroid^2))
  if (!is.finite(reference_centroid_norm) || reference_centroid_norm <= 0) {
    stop("Reference centroid has zero norm; cannot compute distances.")
  }
  reference_centroid <- reference_centroid / reference_centroid_norm

  corpus_centroid <- colMeans(Cn)
  corpus_centroid_norm <- sqrt(sum(corpus_centroid^2))
  if (!is.finite(corpus_centroid_norm) || corpus_centroid_norm <= 0) {
    stop("Corpus centroid has zero norm; cannot compute distances.")
  }
  corpus_centroid <- corpus_centroid / corpus_centroid_norm

  if (verbose) {
    message("Computing cosine distance matrix for ", n_corpus, " corpus x ", n_ref, " reference vectors plus centroids...")
  }

  # Core block: rows corpus, columns reference
  D_cr <- 1 - (Cn %*% t(Rn))
  # Extra centroid axis
  d_c_to_ref_centroid <- 1 - drop(Cn %*% reference_centroid)
  d_corpus_centroid_to_r <- 1 - drop(Rn %*% corpus_centroid)
  d_centroid_centroid <- 1 - sum(corpus_centroid * reference_centroid)

  out <- as.data.frame(D_cr, stringsAsFactors = FALSE, check.names = FALSE)
  colnames(out) <- as.character(ref_df$id)
  out$centroid <- as.numeric(d_c_to_ref_centroid)
  out <- cbind(
    data.frame(id = as.character(corpus_df$id), stringsAsFactors = FALSE, check.names = FALSE),
    out
  )

  centroid_row <- as.data.frame(
    as.list(c(as.numeric(d_corpus_centroid_to_r), as.numeric(d_centroid_centroid))),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(centroid_row) <- c(as.character(ref_df$id), "centroid")
  centroid_row <- cbind(
    data.frame(id = "centroid", stringsAsFactors = FALSE, check.names = FALSE),
    centroid_row
  )
  out <- rbind(out, centroid_row)

  numeric_cols <- setdiff(names(out), "id")
  out[numeric_cols] <- lapply(out[numeric_cols], as.numeric)

  out_file <- file.path(out_model_dir, "pairwise-cosine.parquet")
  arrow::write_parquet(out, out_file)

  if (verbose) {
    cli::cli_alert_success(sprintf(
      "Done! Wrote cosine distance matrix (%d x %d) with centroid axis to %s.",
      n_corpus + 1L,
      n_ref + 1L,
      out_file
    ))
  }

  invisible(out_model_dir)
}
