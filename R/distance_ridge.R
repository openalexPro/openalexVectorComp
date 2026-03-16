#' Compute corpus distance to a reference embedding area
#'
#' Fits (or loads) a reference-area model from `reference_label` embeddings and
#' computes squared Mahalanobis distance for rows in `corpus_label`.
#'
#' @param project_dir Project root containing `embeddings/`.
#' @param reference_label Label partition used to fit the reference area.
#'   Defaults to `"reference"`.
#' @param corpus_label Label partition to score. Defaults to `"corpus"`.
#' @param fit_path Optional path to an existing reference-area fit (`.rds`). If
#'   `NULL`, a new fit is created at `project_dir/ridge_fit.rds`.
#' @param batch_size Approximate number of rows per Arrow scan batch.
#' @param regularization Diagonal covariance regularization added before
#'   inversion.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly the model output directory under
#'   `project_dir/distance_ridge/model_id=<...>/corpus_label=<...>/reference_label=<...>/`.
#' @export
distance_ridge <- function(
  project_dir,
  reference_label = "reference",
  corpus_label = "corpus",
  fit_path = NULL,
  batch_size = 100000,
  regularization = 1e-6,
  verbose = TRUE
) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  if (!is.character(reference_label) || length(reference_label) != 1 || !nzchar(trimws(reference_label))) {
    stop("`reference_label` must be a non-empty character string.")
  }
  if (!is.character(corpus_label) || length(corpus_label) != 1 || !nzchar(trimws(corpus_label))) {
    stop("`corpus_label` must be a non-empty character string.")
  }
  if (!is.numeric(regularization) || length(regularization) != 1 || !is.finite(regularization) || regularization <= 0) {
    stop("`regularization` must be a positive number.")
  }

  reference_label <- trimws(reference_label)
  corpus_label <- trimws(corpus_label)

  embeddings <- normalizePath(file.path(project_dir, "embeddings"), mustWork = TRUE)

  # Resolve embeddings model directory (model_id=...)
  emb_path <- embeddings
  meta_name <- "embed_model.yaml"
  legacy_meta_name <- "_tei_info.yaml"
  model_dir_emb <- if (
    file.exists(file.path(emb_path, meta_name)) ||
      file.exists(file.path(emb_path, legacy_meta_name))
  ) {
    emb_path
  } else {
    subs <- list.dirs(emb_path, full.names = TRUE, recursive = FALSE)
    subs <- subs[grepl("^model_id=", basename(subs))]
    if (length(subs) == 1) subs[[1]] else emb_path
  }
  if (verbose) {
    message("Using embeddings from ", model_dir_emb)
  }

  ds <- arrow::open_dataset(
    model_dir_emb,
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

  # Output preparation -----------------------------------------------------
  task_root <- file.path(project_dir, "distance_ridge")
  if (!dir.exists(task_root)) {
    dir.create(task_root, recursive = TRUE)
  }

  model_part <- basename(model_dir_emb)
  if (!grepl("^model_id=", model_part)) {
    meta_path <- file.path(model_dir_emb, meta_name)
    if (!file.exists(meta_path)) {
      meta_path <- file.path(model_dir_emb, legacy_meta_name)
    }
    if (file.exists(meta_path)) {
      meta <- try(embedding_backend_read(meta_path), silent = TRUE)
      if (!inherits(meta, "try-error")) {
        mid <- meta$model %||% NULL
        if (!is.null(mid) && nzchar(mid)) {
          model_part <- paste0("model_id=", gsub("/", "_", mid, fixed = TRUE))
        }
      }
    }
  }

  corpus_label_part <- gsub("/", "_", corpus_label, fixed = TRUE)
  reference_label_part <- gsub("/", "_", reference_label, fixed = TRUE)
  out_model_dir <- file.path(
    task_root,
    model_part,
    paste0("corpus_label=", corpus_label_part),
    paste0("reference_label=", reference_label_part)
  )
  if (dir.exists(out_model_dir)) {
    unlink(out_model_dir, recursive = TRUE)
  }
  dir.create(out_model_dir, recursive = TRUE, showWarnings = FALSE)

  meta_src <- file.path(model_dir_emb, meta_name)
  if (!file.exists(meta_src)) {
    meta_src <- file.path(model_dir_emb, legacy_meta_name)
  }
  meta_dst <- file.path(out_model_dir, meta_name)
  if (file.exists(meta_src)) {
    file.copy(meta_src, meta_dst, overwrite = TRUE)
    meta <- try(yaml::read_yaml(meta_dst), silent = TRUE)
    if (!inherits(meta, "try-error") && is.list(meta)) {
      meta$ridge_mode <- "reference_area"
      meta$reference_label <- reference_label
      meta$corpus_label <- corpus_label
      meta$regularization <- regularization
      yaml::write_yaml(meta, meta_dst)
    }
  }

  project_root <- normalizePath(project_dir, mustWork = FALSE)
  ridge_fit_path <- fit_path %||% file.path(project_root, "ridge_fit.rds")

  fit <- if (is.null(fit_path)) {
    fit_ridge(
      embeddings = model_dir_emb,
      reference_label = reference_label,
      output = ridge_fit_path,
      regularization = regularization,
      verbose = verbose
    )
    readRDS(ridge_fit_path)
  } else {
    if (!file.exists(fit_path)) {
      stop("`fit_path` does not exist: ", fit_path)
    }
    readRDS(fit_path)
  }

  if (!inherits(fit, "ovc_reference_area_fit")) {
    stop("Fit object is not an `ovc_reference_area_fit` model.")
  }

  if (verbose) {
    message("Computing area distances for corpus label '", corpus_label, "'...")
  }

  cols <- c("id", "label", vcols)
  if ("batch" %in% names(ds)) {
    cols <- c(cols, "batch")
  }
  reader <- arrow::Scanner$create(
    ds,
    columns = cols,
    batch_size = as.integer(batch_size)
  )$ToRecordBatchReader()

  idx <- 0L
  scored_rows <- 0L
  seen_ids <- new.env(parent = emptyenv())
  start_time <- Sys.time()

  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) break

    df <- as.data.frame(batch, stringsAsFactors = FALSE)
    df <- df[df$label == corpus_label, c("id", vcols, intersect("batch", names(df))), drop = FALSE]
    if (!nrow(df)) next

    if (anyDuplicated(df$id)) {
      stop("Duplicate ids found in corpus label partition.")
    }
    dup_global <- vapply(df$id, exists, logical(1), envir = seen_ids, inherits = FALSE)
    if (any(dup_global)) {
      stop("Duplicate ids found in corpus label partition across batches.")
    }
    for (idv in df$id) assign(idv, TRUE, envir = seen_ids)

    X <- as.matrix(df[, vcols, drop = FALSE])
    if (any(!is.finite(X))) {
      stop("Non-finite embedding values found in corpus label partition.")
    }

    area_distance <- .reference_area_md2(X, fit$mu, fit$Sigma_inv)

    out_df <- data.frame(
      id = df$id,
      area_distance = area_distance,
      check.names = FALSE
    )

    idx <- idx + 1L
    batch_id <- if ("batch" %in% names(df)) as.character(df$batch[[1]]) else as.character(idx)
    shard_dir <- file.path(out_model_dir, sprintf("batch=%s", batch_id))
    if (!dir.exists(shard_dir)) dir.create(shard_dir, recursive = TRUE)
    arrow::write_parquet(out_df, file.path(shard_dir, sprintf("ridge-area-%05d.parquet", idx)))

    scored_rows <- scored_rows + nrow(out_df)
  }

  if (scored_rows == 0L) {
    stop("No embeddings found for `corpus_label = ", corpus_label, "`.")
  }

  elapsed <- Sys.time() - start_time
  cli::cli_alert_success(sprintf(
    "Done! Computed area distances for %d corpus rows in %d batches in %s.",
    scored_rows,
    idx,
    format(elapsed, digits = 2)
  ))

  invisible(out_model_dir)
}

#' Fit a reference-area model from embeddings parquet
#'
#' Fits a reference-area model (centroid + regularized covariance inverse)
#' using rows from `reference_label`.
#'
#' @param embeddings Path to a Parquet dataset (file or directory opened by
#'   Arrow) with columns `id`, `label`, and `V1..Vd`.
#' @param reference_label Label partition used to define the reference area.
#' @param output Name of the `.rds` file to save the fit object.
#' @param regularization Positive numeric diagonal regularization added to
#'   covariance.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns `output`.
#' @export
fit_ridge <- function(
  embeddings,
  reference_label = "reference",
  output,
  regularization = 1e-6,
  verbose = TRUE
) {
  if (!is.character(reference_label) || length(reference_label) != 1 || !nzchar(trimws(reference_label))) {
    stop("`reference_label` must be a non-empty character string.")
  }
  if (!is.numeric(regularization) || length(regularization) != 1 || !is.finite(regularization) || regularization <= 0) {
    stop("`regularization` must be a positive number.")
  }

  reference_label <- trimws(reference_label)

  ds <- arrow::open_dataset(
    embeddings,
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

  df <- ds |>
    dplyr::filter(label == reference_label) |>
    dplyr::select(dplyr::all_of(vcols)) |>
    dplyr::collect()

  if (!nrow(df)) {
    stop("No embeddings found for `reference_label = ", reference_label, "`.")
  }

  X <- as.matrix(df[, vcols, drop = FALSE])
  if (any(!is.finite(X))) {
    stop("Non-finite embedding values found in reference label partition.")
  }

  mu <- colMeans(X)

  d <- ncol(X)
  if (nrow(X) < 2L) {
    warning("Reference set has < 2 rows; using diagonal covariance fallback.")
    Sigma <- diag(rep(1, d))
  } else {
    Sigma <- stats::cov(X)
    if (!all(is.finite(Sigma))) {
      stop("Covariance computation failed due to non-finite values.")
    }
  }

  Sigma_reg <- Sigma + diag(regularization, nrow = d, ncol = d)
  Sigma_inv <- try(solve(Sigma_reg), silent = TRUE)
  if (inherits(Sigma_inv, "try-error") || any(!is.finite(Sigma_inv))) {
    stop("Could not invert regularized covariance matrix; increase `regularization`.")
  }

  fit <- list(
    mode = "reference_area",
    reference_label = reference_label,
    regularization = regularization,
    vcols = vcols,
    mu = as.numeric(mu),
    Sigma_inv = unname(Sigma_inv)
  )
  class(fit) <- c("ovc_reference_area_fit", "list")

  saveRDS(fit, file = output)
  if (verbose) {
    message("Saved reference-area fit to ", output)
  }
  invisible(output)
}

.reference_area_md2 <- function(X, mu, Sigma_inv) {
  delta <- sweep(X, 2, mu, FUN = "-")
  rowSums((delta %*% Sigma_inv) * delta)
}
