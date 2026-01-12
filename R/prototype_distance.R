#' Score prototype margin for a Parquet embeddings dataset
#'
#' Streams an embeddings Parquet dataset in batches, computes the cosine-sim
#' margin of distance to positive minus negative prototypes, and writes Parquet
#' outputs mirroring the embeddings layout: `model_id=<...>/shard=<n>/
#' prototype-margin-*.parquet` with columns `id` and `margin`. Copies the
#' embeddings model specification `_tei_info.yaml` into the corresponding
#' `model_id=<...>` directory under `output`.
#'
#' @param project_dir Project root directory.
#'   Must contain a folder `embeddings` containing the embeddings.
#'   Outputs are written under
#'   `project_dir/prototype_distance/model_id=<...>/shard=<n>/` with columns
#'   `id` and `margin`. The embeddings model metadata `_tei_info.yaml` is also
#'   copied to `project_dir/`.
#' @param included Name of a csv file containing a column named `id` containing the `id` values that define the positive prototype.
#' @param excluded Name of a csv file containing a column named `id` containing the `id` values that define the negative prototype.
#' @param batch_size Approximate number of rows per Arrow scan batch when scoring
#'   the dataset (default `100000`).
#'
#' @return Invisibly the model-specific output directory under
#'   `project_dir/prototype_distance/model_id=<...>/`.
#'
#' @examples
#' \dontrun{
#' scores <- prototype_distance(
#'   embeddings = "project/embeddings/",
#'   included = "included.csv",
#'   excluded = "excluded.csv",
#'   project_dir = "project/"
#' )
#' }
#'
#' @importFrom dplyr filter select collect bind_rows all_of
#' @importFrom arrow open_dataset Scanner write_parquet
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done cli_alert_success
#'
#' @export
prototype_distance <- function(
  project_dir,
  included,
  excluded,
  batch_size = 10000,
  verbose = TRUE
) {
  embeddings <- normalizePath(
    file.path(project_dir, "embeddings"),
    mustWork = TRUE
  )

  included <- read.csv(included)$id
  excluded <- read.csv(excluded)$id

  stopifnot(length(included) > 0, length(excluded) > 0)

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
  # Identify embedding columns (V1..Vd)
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
  neg_ids <- ds |>
    dplyr::filter(id %in% excluded) |>
    dplyr::select(id) |>
    dplyr::collect()

  if (nrow(pos_ids) == 0) {
    stop("None of the `included` ids were found in embeddings dataset.")
  }
  if (nrow(neg_ids) == 0) {
    stop("None of the `excluded` ids were found in embeddings dataset.")
  }

  miss_inc <- setdiff(included, pos_ids$id)
  miss_exc <- setdiff(excluded, neg_ids$id)
  if (length(miss_inc)) {
    warning(
      "Some included ids not found: ",
      paste(head(miss_inc, 10), collapse = ", "),
      if (length(miss_inc) > 10) " …"
    )
  }
  if (length(miss_exc)) {
    warning(
      "Some excluded ids not found: ",
      paste(head(miss_exc, 10), collapse = ", "),
      if (length(miss_exc) > 10) " …"
    )
  }

  if (verbose) {
    message("Calculating and L2-normalizing prototype vectors...")
  }

  # Compute column means lazily in Arrow and collect only the single-row summary
  pos <- ds |>
    dplyr::filter(id %in% included) |>
    collect() |>
    dplyr::select(
      dplyr::all_of(vcols)
    ) |>
    colMeans()

  neg <- ds |>
    dplyr::filter(id %in% excluded) |>
    collect() |>
    dplyr::select(
      dplyr::all_of(vcols)
    ) |>
    colMeans()

  # L2-normalize the prototype vectors for cosine similarity
  pos_u <- pos / sqrt(sum(pos^2) + 1e-12)
  neg_u <- neg / sqrt(sum(neg^2) + 1e-12)

  if (verbose) {
    message("Streaming individual batches to calculate distance...")
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
  task_root <- file.path(project_dir, "prototype_distance")
  if (!dir.exists(task_root)) {
    dir.create(task_root, recursive = TRUE)
  }

  # Create matching model_id directory under output and copy metadata
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
  # Also copy to project root
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
    shard_col_present <- "shard" %in% names(df)
    X <- as.matrix(df[, vcols, drop = FALSE])
    Xn <- X / sqrt(rowSums(X^2) + 1e-12)
    m <- as.numeric(Xn %*% pos_u) - as.numeric(Xn %*% neg_u)

    if (shard_col_present) {
      # Write under corresponding shard partitions to mirror embeddings
      split_idx <- split(seq_len(nrow(df)), df$shard)
      for (sh_name in names(split_idx)) {
        rows <- split_idx[[sh_name]]
        shard_df <- data.frame(
          id = df$id[rows],
          margin = m[rows],
          check.names = FALSE
        )
        shard_dir <- file.path(out_model_dir, sprintf("shard=%s", sh_name))
        if (!dir.exists(shard_dir)) {
          dir.create(shard_dir, recursive = TRUE)
        }
        idx <- idx + 1L
        path <- file.path(
          shard_dir,
          sprintf("prototype-margin-%05d.parquet", idx)
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
      path <- file.path(
        shard_dir,
        sprintf("prototype-margin-%05d.parquet", idx)
      )
      shard_df <- data.frame(
        id = df$id,
        margin = m,
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
