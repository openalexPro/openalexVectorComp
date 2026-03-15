#' Pairwise cosine distances between reference and corpus label partitions
#'
#' Reads embeddings from a model-specific dataset and computes pairwise cosine
#' distances between all vectors in `reference_label` and all vectors in
#' `corpus_label`.
#'
#' Embeddings are expected under:
#' `project_dir/embeddings/model_id=<...>/label=<label>/batch=<n>/...`
#'
#' Output is a wide Parquet table with one row per reference id and one column
#' per corpus id.
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
#' @param max_cells Maximum allowed matrix size (`n_reference * n_corpus`) to
#'   guard memory use.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly the output directory
#'   `project_dir/distance_prototype/model_id=<...>/corpus_label=<...>/reference_label=<...>/`.
#' @export
distance_prototype <- function(
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
      "distance_prototype",
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
  n_cells <- as.double(n_ref) * as.double(n_corpus)
  if (n_cells > max_cells) {
    stop(
      "Pairwise distance matrix would contain ",
      format(n_cells, scientific = FALSE, trim = TRUE),
      " cells (", n_ref, " x ", n_corpus, "), exceeding `max_cells = ",
      format(max_cells, scientific = FALSE, trim = TRUE),
      "`. Reduce label sizes or increase `max_cells`."
    )
  }

  if (verbose) {
    message("Computing pairwise cosine distances for ", n_ref, " reference x ", n_corpus, " corpus vectors...")
  }

  R <- as.matrix(ref_df[, vcols, drop = FALSE])
  C <- as.matrix(corpus_df[, vcols, drop = FALSE])

  Rn <- R / sqrt(rowSums(R^2) + 1e-12)
  Cn <- C / sqrt(rowSums(C^2) + 1e-12)

  S <- Rn %*% t(Cn)
  D <- 1 - S

  out <- as.data.frame(D, stringsAsFactors = FALSE, check.names = FALSE)
  colnames(out) <- as.character(corpus_df$id)
  out <- cbind(
    data.frame(reference_id = as.character(ref_df$id), stringsAsFactors = FALSE, check.names = FALSE),
    out
  )

  out_file <- file.path(out_model_dir, "pairwise-cosine.parquet")
  arrow::write_parquet(out, out_file)

  if (verbose) {
    cli::cli_alert_success(sprintf(
      "Done! Wrote pairwise cosine distance matrix (%d x %d) to %s.",
      n_ref,
      n_corpus,
      out_file
    ))
  }

  invisible(out_model_dir)
}
