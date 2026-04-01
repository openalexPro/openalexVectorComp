#' Stream a corpus dataset, embed in batches, and write Parquets
#'
#' Processes a Parquet dataset without loading it fully in memory. Reads Arrow
#' record batches, builds canonical text from `title` + `abstract`, calls the
#' configured embedding backend, and writes Parquet batch files.
#'
#' @param project_dir Project root directory. Must contain
#'   `project_dir/<corpus_name>` with columns `id`, `title`, `abstract`.
#' @param backend Backend configuration created with
#'   [backend_config()].
#' @param corpus_name Folder name under `project_dir` containing the corpus
#'   parquet dataset. Defaults to `"corpus"`.
#' @param batch_size Number of corpus rows per Arrow scan batch.
#' @param delete_existing If `TRUE`, old embeddings for the target model are
#'   deleted before processing. If `FALSE`, unchanged rows are skipped using
#'   `id + text_hash`.
#' @param text_preprocessor Function that prepares embedding text from a batch
#'   data frame and returns at least columns `id`, `text`, `text_hash`.
#'   Defaults to [clean_abstract_for_embedding()].
#' @param cleaner_args Named list of additional arguments passed to
#'   `text_preprocessor`.
#' @param save_text Logical; if `TRUE` (default), store the cleaned embedding
#'   text in output Parquet files as column `text`. If `FALSE`, only `text_hash`
#'   is stored.
#' @param label Partition label written under
#'   `project_dir/embeddings/model_id=<...>/label=<label>/batch=<n>/`.
#'   Defaults to `corpus_name`.
#' @param dry_run Logical; if `TRUE`, run preprocessing and unchanged-row
#'   filtering without requesting embeddings or writing output files. In this
#'   mode, a Parquet preview file is written to
#'   `project_dir/<corpus_name>_dryrun.parquet`.
#' @param verbose Logical; print progress and summary messages.
#'
#' @return Invisibly the model-specific embeddings directory under
#'   `project_dir/embeddings/model_id=<...>/`.
#' @export
embed_corpus <- function(
  project_dir = NULL,
  backend = backend_config(),
  corpus_name = "corpus",
  batch_size = 5000,
  delete_existing = FALSE,
  text_preprocessor = clean_abstract_for_embedding,
  cleaner_args = list(),
  save_text = TRUE,
  label = corpus_name,
  dry_run = FALSE,
  verbose = TRUE
) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  if (is.null(project_dir) || !nzchar(project_dir)) {
    stop("Parameter `project_dir` must be a non-empty directory path.")
  }
  if (!is.numeric(batch_size) || length(batch_size) != 1 || batch_size <= 0) {
    stop("`batch_size` must be a positive number.")
  }
  if (!is.list(backend) || is.null(backend$provider)) {
    stop("`backend` must come from backend_config().")
  }
  if (!is.character(corpus_name) || length(corpus_name) != 1 || !nzchar(trimws(corpus_name))) {
    stop("`corpus_name` must be a non-empty character string.")
  }
  if (!is.function(text_preprocessor)) {
    stop("`text_preprocessor` must be a function.")
  }
  if (!is.list(cleaner_args)) {
    stop("`cleaner_args` must be a list.")
  }
  if (!is.logical(save_text) || length(save_text) != 1 || is.na(save_text)) {
    stop("`save_text` must be TRUE or FALSE.")
  }
  if (!is.character(label) || length(label) != 1 || !nzchar(trimws(label))) {
    stop("`label` must be a non-empty character string.")
  }
  if (!is.logical(dry_run) || length(dry_run) != 1 || is.na(dry_run)) {
    stop("`dry_run` must be TRUE or FALSE.")
  }
  batch_size <- as.integer(batch_size)
  corpus_name <- trimws(corpus_name)
  label <- trimws(label)

  corpus <- normalizePath(file.path(project_dir, corpus_name), mustWork = TRUE)
  ds <- arrow::open_dataset(corpus)
  req_cols <- c("id", "title", "abstract")
  missing <- setdiff(req_cols, names(ds))
  if (length(missing)) {
    stop("Dataset must contain columns: ", paste(missing, collapse = ", "))
  }
  ds <- ds |> dplyr::select(dplyr::all_of(req_cols))

  emb_root <- file.path(project_dir, "embeddings")
  if (!isTRUE(dry_run) && !dir.exists(emb_root)) {
    dir.create(emb_root, recursive = TRUE)
  }

  info <- backend_info(backend)
  model_id <- info$model_id %||% backend$model
  if (is.null(model_id) || !nzchar(model_id)) {
    stop("Could not determine model id from backend info.")
  }
  model_part <- gsub("/", "_", model_id, fixed = TRUE)
  model_dir <- file.path(emb_root, paste0("model_id=", model_part))
  label_part <- gsub("/", "_", label, fixed = TRUE)
  label_dir <- file.path(model_dir, paste0("label=", label_part))

  if (!isTRUE(dry_run)) {
    if (dir.exists(label_dir) && isTRUE(delete_existing)) {
      unlink(label_dir, recursive = TRUE)
    }
    if (!dir.exists(model_dir)) {
      dir.create(model_dir, recursive = TRUE)
      if (verbose) {
        message("Created model output directory: ", model_dir)
      }
    } else if (verbose) {
      message("Reusing existing model output directory: ", model_dir)
    }

    meta_path <- file.path(model_dir, "embed_model.yaml")
    backend_meta <- backend
    backend_meta$model <- model_id
    backend_meta$max_batch_size <- info$max_batch_size %||% backend$max_batch_size
    backend_save(backend = backend_meta, fn = meta_path)

    preproc_name <- if (identical(text_preprocessor, clean_abstract_for_embedding)) {
      "clean_abstract_for_embedding"
    } else {
      "user_defined"
    }
    meta <- yaml::read_yaml(meta_path)
    meta$text_preprocessor <- list(
      name = preproc_name,
      mode = cleaner_args$mode %||% NA_character_,
      no_abstract_policy = cleaner_args$no_abstract_policy %||% NA_character_
    )
    meta$embedding_label <- label
    yaml::write_yaml(meta, meta_path)

    if (verbose) {
      message("Wrote backend metadata to ", meta_path)
    }

    if (!dir.exists(label_dir)) {
      dir.create(label_dir, recursive = TRUE)
      if (verbose) {
        message("Created label output directory: ", label_dir)
      }
    } else if (verbose) {
      message("Reusing existing label output directory: ", label_dir)
    }
  } else if (verbose) {
    message("Dry run mode: no embeddings will be requested and no files will be written.")
  }

  reader <- arrow::Scanner$create(
    ds,
    columns = req_cols,
    batch_size = batch_size
  )$ToRecordBatchReader()

  total_rows <- nrow(ds)
  no_shards <- ceiling(total_rows / batch_size)
  shard_idx <- 0L
  embedded_rows <- 0L
  skipped_rows <- 0L

  start_time <- Sys.time()
  if (verbose) {
    message(
      "Embedding ",
      total_rows,
      " works in up to ",
      no_shards,
      " shards ..."
    )
  }

  existing_hash <- stats::setNames(character(), character())
  if (!delete_existing) {
    idx_ds <- try(
      arrow::open_dataset(
        model_dir,
        paste0("label=", label_part),
        factory_options = list(exclude_invalid_files = TRUE)
      ),
      silent = TRUE
    )
    if (!inherits(idx_ds, "try-error")) {
      idx_cols <- names(idx_ds)
      hash_col <- if ("text_hash" %in% idx_cols) "text_hash" else if ("hash" %in% idx_cols) "hash" else NULL
      if (!is.null(hash_col) && "id" %in% idx_cols) {
        idx_df <- idx_ds |>
          dplyr::select(id, dplyr::all_of(hash_col)) |>
          dplyr::collect()
        if (nrow(idx_df)) {
          names(idx_df)[2] <- "text_hash"
          idx_df <- idx_df[!is.na(idx_df$id) & !is.na(idx_df$text_hash), , drop = FALSE]
          if (nrow(idx_df)) {
            existing_hash <- stats::setNames(as.character(idx_df$text_hash), as.character(idx_df$id))
          }
        }
      }
    }
  }

  progress_id <- NULL
  if (verbose && is.finite(no_shards) && no_shards > 0) {
    progress_id <- cli::cli_progress_bar(
      "Embedding new/changed texts",
      total = no_shards
    )
  }

  validate_preprocessor_result <- function(prep, batch_ids) {
    req_cols <- c("id", "text", "text_hash")
    if (!is.data.frame(prep)) {
      stop("`text_preprocessor` must return a data frame.")
    }
    miss <- setdiff(req_cols, names(prep))
    if (length(miss)) {
      stop(
        "`text_preprocessor` output must contain columns: ",
        paste(miss, collapse = ", ")
      )
    }
    prep$id <- as.character(prep$id)
    prep$text <- as.character(prep$text)
    prep$text_hash <- as.character(prep$text_hash)
    bad_ids <- setdiff(unique(prep$id), unique(batch_ids))
    if (length(bad_ids)) {
      stop("`text_preprocessor` returned ids not present in the input batch.")
    }
    if (anyDuplicated(prep$id)) {
      stop("`text_preprocessor` output contains duplicated ids.")
    }
    prep <- prep[
      !is.na(prep$id) & !is.na(prep$text) & nzchar(prep$id) & nzchar(prep$text),
      ,
      drop = FALSE
    ]
    prep
  }

  parse_cleaned_text <- function(text) {
    n <- length(text)
    cleaned_title <- rep(NA_character_, n)
    cleaned_abstract <- rep(NA_character_, n)
    for (i in seq_len(n)) {
      ti <- text[[i]]
      if (is.na(ti) || !nzchar(ti)) {
        next
      }
      if (!startsWith(ti, "Title:")) {
        next
      }
      parts <- strsplit(ti, "\nAbstract:", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        cleaned_title[[i]] <- trimws(sub("^Title:\\s*", "", parts[[1]]))
        cleaned_abstract[[i]] <- trimws(paste(parts[-1], collapse = "\nAbstract:"))
      } else {
        cleaned_title[[i]] <- trimws(sub("^Title:\\s*", "", ti))
      }
    }
    list(cleaned_title = cleaned_title, cleaned_abstract = cleaned_abstract)
  }

  dry_run_file <- file.path(project_dir, paste0(corpus_name, "_dryrun.parquet"))
  dry_run_preview <- list()
  if (isTRUE(dry_run) && file.exists(dry_run_file)) {
    unlink(dry_run_file)
  }

  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) {
      break
    }

    batch_df <- dplyr::collect(batch) |>
      dplyr::mutate(
        id = ifelse(is.na(id), "", as.character(id)),
        title = ifelse(is.na(title), "", as.character(title)),
        abstract = ifelse(is.na(abstract), "", as.character(abstract))
      )
    prep <- do.call(
      text_preprocessor,
      c(list(df = batch_df), cleaner_args)
    )
    df <- validate_preprocessor_result(prep, batch_ids = batch_df$id)

    keep <- rep(FALSE, nrow(df))
    if (nrow(df)) {
      prev <- unname(existing_hash[df$id])
      keep <- is.na(prev) | prev != df$text_hash
      skipped_rows <- skipped_rows + sum(!keep)
    }

    if (isTRUE(dry_run) && nrow(df)) {
      idx <- match(df$id, batch_df$id)
      parsed <- parse_cleaned_text(df$text)
      cleaned_title <- if ("cleaned_title" %in% names(df)) {
        as.character(df$cleaned_title)
      } else {
        parsed$cleaned_title
      }
      cleaned_abstract <- if ("cleaned_abstract" %in% names(df)) {
        as.character(df$cleaned_abstract)
      } else {
        parsed$cleaned_abstract
      }
      preview <- data.frame(
        id = as.character(df$id),
        title_original = as.character(batch_df$title[idx]),
        abstract_original = as.character(batch_df$abstract[idx]),
        cleaned_title = cleaned_title,
        cleaned_abstract = cleaned_abstract,
        text = as.character(df$text),
        text_hash = as.character(df$text_hash),
        would_embed = as.logical(keep),
        stringsAsFactors = FALSE
      )
      dry_run_preview[[length(dry_run_preview) + 1L]] <- preview
    }

    if (nrow(df)) {
      df <- df[keep, , drop = FALSE]
    }

    if (!is.null(progress_id)) {
      cli::cli_progress_update(id = progress_id)
    }
    if (!nrow(df)) {
      next
    }

    if (isTRUE(dry_run)) {
      embedded_rows <- embedded_rows + nrow(df)
      next
    }

    emb <- embed_texts(texts = df$text, backend = backend)
    extra_cols <- setdiff(names(df), c("id", "text", "text_hash"))
    out_core <- data.frame(
      id = df$id,
      text_hash = df$text_hash,
      provider = backend$provider,
      model_id = model_id,
      created_at = as.character(Sys.time(), tz = "UTC"),
      check.names = FALSE
    )
    if (isTRUE(save_text)) {
      out_core$text <- df$text
    }
    out <- cbind(out_core, df[, extra_cols, drop = FALSE], emb)
    embedded_rows <- embedded_rows + nrow(out)
    existing_hash[df$id] <- df$text_hash

    shard_idx <- shard_idx + 1L
    shard_dir <- file.path(label_dir, sprintf("batch=%d", shard_idx))
    if (!dir.exists(shard_dir)) {
      dir.create(shard_dir, recursive = TRUE)
    }
    arrow::write_parquet(
      out,
      file.path(shard_dir, sprintf("embeddings-%05d.parquet", shard_idx))
    )
  }

  if (!is.null(progress_id)) {
    cli::cli_progress_done(id = progress_id)
  }
  if (isTRUE(dry_run) && length(dry_run_preview)) {
    preview_all <- do.call(rbind, dry_run_preview)
    arrow::write_parquet(preview_all, dry_run_file)
  }
  elapsed <- Sys.time() - start_time
  if (isTRUE(dry_run)) {
    cli::cli_alert_info(sprintf(
      "Dry run complete: would embed %d new/changed works, skipped %d unchanged rows in %s. Preview: %s",
      embedded_rows,
      skipped_rows,
      format(elapsed, digits = 2),
      dry_run_file
    ))
  } else {
    cli::cli_alert_success(sprintf(
      "Done! Embedded %d new/changed works, skipped %d unchanged rows, wrote %d batches in %s.",
      embedded_rows,
      skipped_rows,
      shard_idx,
      format(elapsed, digits = 2)
    ))
  }

  invisible(model_dir)
}
