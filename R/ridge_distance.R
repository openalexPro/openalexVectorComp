#' Predict probabilities from a ridge logistic `cv.glmnet` fit
#'
#' Streams an embeddings Parquet dataset in batches, applies a trained ridge
#' logistic model, and writes Parquet outputs mirroring the embeddings layout:
#' `model_id=<...>/shard=<n>/ridge-logistic-*.parquet` with columns `id` and
#' `relevance_score`. Also writes the fitted model as `ridge_fit.rds` into the
#' corresponding `model_id=<...>` directory and copies `_tei_info.yaml` there.
#'
#' @param project_dir Project root.
#'   Must contain a folder `embeddings` containing the embeddings.
#'   Scores are written under
#'   `project_dir/ridge_distance/model_id=<...>/shard=<n>/` and the fitted model
#'   RDS is saved to `project_dir/ridge_fit.rds`. The `_tei_info.yaml` is copied
#'   to both the model folder and the project root.
#' @param ridge_fit Path to an `.rds` file produced by [fit_ridge()] containing
#'   the `cv.glmnet` object.
#' @param s Lambda to use; one of `"lambda.min"` or `"lambda.1se"` (default
#'   `"lambda.min"`).
#' @param batch_size Approximate number of rows per Arrow scan batch.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly the model output directory under
#'   `project_dir/ridge_distance/model_id=<...>/`.
#'
#' @export
ridge_distance <- function(
  project_dir,
  included = included,
  excluded = excluded,
  s = c("lambda.min", "lambda.1se"),
  batch_size = 100000,
  verbose = TRUE
) {
  s <- match.arg(s)

  embeddings <- normalizePath(
    file.path(project_dir, "embeddings"),
    mustWork = TRUE
  )

  # Resolve the embeddings model directory (expects model_id=... level)
  emb_path <- embeddings
  model_dir_emb <- if (file.exists(file.path(emb_path, "_tei_info.yaml"))) {
    emb_path
  } else {
    subs <- list.dirs(emb_path, full.names = TRUE, recursive = FALSE)
    subs <- subs[grepl("^model_id=", basename(subs))]
    if (length(subs) == 1) subs[[1]] else emb_path
  }
  if (verbose) {
    message("Using embeddings from ", model_dir_emb)
  }

  ds <- arrow::open_dataset(model_dir_emb)

  vcols <- names(ds)
  vcols <- vcols[grepl("^V[0-9]+$", vcols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  if (verbose) {
    message("Streaming batches to score ridge probabilities ...")
  }

  # Stream all rows to score margins
  cols <- c("id", vcols)
  if ("shard" %in% names(ds)) {
    cols <- c(cols, "shard")
  }
  reader <- arrow::Scanner$create(
    ds, # Dataset/Table/query
    columns = cols,
    batch_size = as.integer(batch_size)
  )$ToRecordBatchReader()

  # Output Preparation ----------------------------------------------------
  if (!dir.exists(project_dir)) {
    dir.create(project_dir, recursive = TRUE)
  }
  task_root <- file.path(project_dir, "ridge_distance")
  if (!dir.exists(task_root)) {
    dir.create(task_root, recursive = TRUE)
  }

  # Create matching model_id directory under output
  `%||%` <- function(x, y) if (is.null(x)) y else x
  model_part <- basename(model_dir_emb) # try to use existing partition name
  if (!grepl("^model_id=", model_part)) {
    meta_path <- file.path(model_dir_emb, "_tei_info.yaml")
    if (file.exists(meta_path)) {
      meta <- try(yaml::read_yaml(meta_path), silent = TRUE)
      if (!inherits(meta, "try-error")) {
        mid <- `%||%`(meta$model$id, meta$model$requested_id)
        if (!is.null(mid) && nzchar(mid)) {
          model_part <- paste0("model_id=", gsub("/", "_", mid, fixed = TRUE))
        }
      }
    }
  }
  out_model_dir <- file.path(task_root, model_part)
  if (!dir.exists(out_model_dir)) {
    dir.create(out_model_dir, recursive = TRUE)
    if (verbose) message("Created output model directory: ", out_model_dir)
  }
  # Copy TEI metadata if present
  meta_src <- file.path(model_dir_emb, "_tei_info.yaml")
  meta_dst <- file.path(out_model_dir, "_tei_info.yaml")
  if (file.exists(meta_src)) {
    file.copy(meta_src, meta_dst, overwrite = TRUE)
    if (verbose) message("Copied _tei_info.yaml to ", meta_dst)
  }
  # Also ensure a copy in the project root
  project_root <- normalizePath(project_dir, mustWork = FALSE)
  if (file.exists(meta_src)) {
    file.copy(
      meta_src,
      file.path(project_root, "_tei_info.yaml"),
      overwrite = TRUE
    )
    if (verbose) {
      message(
        "Copied _tei_info.yaml to project root: ",
        file.path(project_root, "_tei_info.yaml")
      )
    }
  }

  idx <- 0L
  no_shards <- nrow(ds) %/% batch_size + 1L
  start_time <- Sys.time()

  # Load model once (fit if needed) and store fit RDS at project root
  ridge_fit_path <- file.path(project_root, "ridge_fit.rds")
  fit <- fit_ridge(
    embeddings = model_dir_emb,
    included = read.csv(included)$id,
    excluded = read.csv(excluded)$id,
    output = ridge_fit_path,
    verbose = verbose
  ) |>
    readRDS()
  if (verbose) {
    message("Loaded ridge fit from ", ridge_fit_path)
  }

  # pb_id <- cli::cli_progress_bar("Processing batches", total = no_shards)

  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) {
      break
    }

    if (verbose) {
      message("   Batch #", idx + 1L, " of at at least ", no_shards, " ...")
    }

    # if (no_shards > 1) {
    #   cli::cli_progress_update(id = pb_id)
    # }

    df <- as.data.frame(batch, stringsAsFactors = FALSE)
    # Include shard if present as partition column
    shard_col_present <- "shard" %in% names(df)
    X <- as.matrix(df[, vcols, drop = FALSE])
    preds <- as.numeric(predict(
      object = fit,
      newx = X,
      s = s,
      type = "response"
    ))

    # Simple per-batch constancy check (helps debug unexpected flat outputs)
    if (verbose && length(preds) > 1 && sd(preds) == 0) {
      message("Warning: predictions are constant within batch #", idx + 1L)
    }

    if (shard_col_present) {
      # Write under corresponding shard partitions to mirror embeddings
      split_idx <- split(seq_len(nrow(df)), df$shard)
      for (sh_name in names(split_idx)) {
        rows <- split_idx[[sh_name]]
        shard_df <- data.frame(
          id = df$id[rows],
          relevance_score = preds[rows],
          check.names = FALSE
        )
        shard_dir <- file.path(out_model_dir, sprintf("shard=%s", sh_name))
        if (!dir.exists(shard_dir)) {
          dir.create(shard_dir, recursive = TRUE)
        }
        idx <- idx + 1L
        path <- file.path(
          shard_dir,
          sprintf("ridge-logistic-%05d.parquet", idx)
        )
        arrow::write_parquet(shard_df, path)
      }
    } else {
      # Fallback: write sequential shards under incrementing shard index
      idx <- idx + 1L
      shard_dir <- file.path(out_model_dir, sprintf("shard=%d", idx))
      if (!dir.exists(shard_dir)) {
        dir.create(shard_dir, recursive = TRUE)
      }
      path <- file.path(shard_dir, sprintf("ridge-logistic-%05d.parquet", idx))
      shard_df <- data.frame(
        id = df$id,
        relevance_score = preds,
        check.names = FALSE
      )
      arrow::write_parquet(shard_df, path)
    }
  }

  # cli::cli_progress_done(id = pb_id)

  elapsed <- Sys.time() - start_time
  cli::cli_alert_success(sprintf(
    "Done! Processed %d works in %d batches in %s.",
    nrow(ds),
    no_shards,
    format(elapsed, digits = 2)
  ))

  invisible(out_model_dir)
}


#' Ridge logistic regression from embeddings parquet
#'
#' Fits a cross-validated ridge-penalised logistic regression (`alpha = 0`)
#' using embeddings stored in a Parquet dataset. Positives are given by
#' `included` ids (label `1`) and negatives by `excluded` ids (label `0`).
#'
#' @param embeddings Path to a Parquet dataset (file or directory opened by
#'   Arrow) with columns `id` and `V1..Vd` (embedding dimensions).
#' @param included Vector of `id` values to use as positive examples (label `1`).
#' @param excluded Vector of `id` values to use as negative examples (label `0`).
#' @param output Name of the frds file into which to save the result.
#' @param verbose Logical; print basic progress (not used at the moment).
#'
#' @return A `cv.glmnet` fit object.
#'
#' @details
#' The function locates embedding columns `V1..Vd`, collects the rows for
#' `included` and `excluded` ids from the dataset, constructs a response vector
#' (`1` for included, `0` for excluded), and runs `glmnet::cv.glmnet()` with
#' `family = "binomial"` and ridge penalty (`alpha = 0`).
#'
#' @examples
#' \dontrun{
#' fit <- fit_ridge(
#'   embeddings = "path/to/embeddings_dataset/",
#'   included   = c("work1", "work2"),  # positives (y = 1)
#'   excluded   = c("work3", "work4"),  # negatives (y = 0)
#'   verbose    = TRUE
#' )
#' fit$lambda.min
#' }
#'
#' @seealso [ridge_distance()]
#' @importFrom dplyr if_else
#' @importFrom glmnet cv.glmnet
#' @export
fit_ridge <- function(
  embeddings,
  included,
  excluded,
  output,
  verbose = TRUE
) {
  ds <- arrow::open_dataset(embeddings)

  vcols <- names(ds)
  vcols <- vcols[grepl("^V[0-9]+$", vcols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  # Check presence of requested ids (collect only ids)
  pos_ids <- ds |>
    dplyr::filter(id %in% included) |>
    dplyr::select(id) |>
    dplyr::collect()

  if (nrow(pos_ids) == 0) {
    stop("None of the `included` ids were found in embeddings dataset.")
  }

  miss_inc <- setdiff(included, pos_ids$id)
  if (length(miss_inc)) {
    warning(
      "Some included ids not found: ",
      paste(head(miss_inc, 10), collapse = ", "),
      if (length(miss_inc) > 10) " …"
    )
  }

  df <- ds |>
    dplyr::filter(id %in% c(included, excluded)) |>
    dplyr::select(
      id,
      dplyr::all_of(vcols)
    ) |>
    dplyr::mutate(
      label = if_else(id %in% included, 1L, 0L)
    ) |>
    dplyr::collect()

  result <- glmnet::cv.glmnet(
    x = as.matrix(df[, vcols]),
    y = unlist(df$label),
    family = "binomial",
    alpha = 0, # L2 penalty (ridge)
    nfolds = 5
  )
  saveRDS(result, file = output)
  return(output)
}
