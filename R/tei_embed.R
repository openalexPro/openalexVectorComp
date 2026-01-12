#' Stream a Parquet dataset, embed in batches, and write shard Parquets
#'
#' Processes a Parquet *dataset* without loading it fully in memory.
#' Reads Arrow record batches, builds `text` from `title` + `abstract`,
#' calls TEI in sub-batches, and writes out embeddings as many Parquet
#' shard files under `output`.
#'
#' @param tei_url TEI `/embed` endpoint. Defaults to the URL saved by
#'   [tei_start()] for the current session (if available), otherwise
#'   `"http://localhost:3000/embed"`.
#' @param batch_size Number of texts per TEI HTTP request.
#' @param project_dir Project root directory. **Must contain a parquet database with the
#'    corpus to be analyses.**
#'    Embeddings are written under
#'   `project_dir/embeddings/model_id=<...>/shard=<n>/` as Parquet files with
#'   columns: `id`, `text_hash`, `V1..Vd`. Model metadata is also saved to
#'   `project_dir/_tei_info.yaml`.
#' @return Invisibly the model-specific embeddings directory under
#'   `project_dir/embeddings/model_id=<...>/`.
#'
#' @details
#' Requires that the dataset has columns `id`, `title`, `abstract`.
#' Vector dimension `d` is inferred from the first TEI response.
#'
#' Deduplication and resume safety:
#' - Before embedding, we pre-scan the corpus once to compute a stable
#'   `text_hash` (xxhash64 of `title + "\n\n" + abstract`).
#' - We compare `(id, text_hash)` against existing embeddings and only embed
#'   new or changed rows. If none are new/changed, the function aborts early.
#' - We also persist TEI server/model metadata in `_tei_info.yaml` and abort if
#'   the model configuration differs between runs in the same model folder.
#'
#' @examples
#' \dontrun{
#' embeddings_dir <- tei_embed(
#'   project_dir = "project/",
#'   batch_size = 5000,
#' )
#' # Later:
#' ds <- arrow::open_dataset(embeddings_dir)
#' }
#'
#' @importFrom arrow open_dataset
#' @importFrom httr2 request req_method req_body_json req_perform resp_body_json
#' @importFrom digest digest
#' @importFrom fastmatch fmatch
#' @importFrom utils head
#' @importFrom stats setNames
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done cli_alert_success
#' @export
tei_embed <- function(
  project_dir = NULL,
  tei_url = tei_default_embed_url(),
  batch_size = 5000,
  verbose = TRUE
) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  corpus <- normalizePath(file.path(project_dir, "corpus"), mustWork = TRUE)

  if (is.null(project_dir) || !nzchar(project_dir)) {
    stop("Parameter 'project_dir' must be a non-empty directory path.")
  }

  ds <- arrow::open_dataset(corpus)

  # Validate required columns lazily (names(ds) is available without materializing)
  req_cols <- c("id", "title", "abstract")
  missing <- setdiff(req_cols, names(ds))
  if (length(missing)) {
    stop("Dataset must contain columns: ", paste(missing, collapse = ", "))
  }

  ds <- ds |>
    dplyr::select(
      dplyr::all_of(req_cols)
    )

  # Output preparation: ensure project and embeddings folders exist
  if (!dir.exists(project_dir)) {
    dir.create(project_dir, recursive = TRUE)
  }
  emb_root <- file.path(project_dir, "embeddings")
  if (!dir.exists(emb_root)) {
    dir.create(emb_root, recursive = TRUE)
  }

  info <- tei_info(tei_url)
  model_id <- info$model$id %||% info$model$requested_id
  if (is.null(model_id) || !nzchar(model_id)) {
    stop("Could not determine model id from tei_info(); aborting.")
  }
  model_part <- gsub("/", "_", model_id, fixed = TRUE)
  model_dir <- file.path(emb_root, paste0("model_id=", model_part))
  if (!dir.exists(model_dir)) {
    dir.create(model_dir, recursive = TRUE)
    if (verbose) message("Created model output directory: ", model_dir)
  }
  if (verbose) {
    message(
      "Using TEI model_id=",
      model_id,
      " (folder: ",
      basename(model_dir),
      ")"
    )
  }

  meta_path <- file.path(model_dir, "_tei_info.yaml")
  current_meta <- list(
    model = list(
      id = model_id,
      revision = info$model$revision %||%
        info$model$model_sha %||%
        NA_character_,
      embedding_dim = info$model$embedding_dim %||% NA_integer_,
      pooling = info$model$pooling %||% NA_character_,
      normalize = isTRUE(info$model$normalize),
      model_dtype = info$model$model_dtype %||% NA_character_
    ),
    server = list(
      version = info$server$version %||% NA_character_
    )
  )
  if (file.exists(meta_path)) {
    prev <- try(yaml::read_yaml(meta_path), silent = TRUE)
    if (!inherits(prev, "try-error")) {
      # Compare key fields
      mism <- c(
        identical(prev$model$id, current_meta$model$id) == FALSE,
        identical(prev$model$revision, current_meta$model$revision) == FALSE,
        identical(prev$model$embedding_dim, current_meta$model$embedding_dim) ==
          FALSE,
        identical(prev$model$pooling, current_meta$model$pooling) == FALSE,
        identical(isTRUE(prev$model$normalize), current_meta$model$normalize) ==
          FALSE,
        identical(prev$model$model_dtype, current_meta$model$model_dtype) ==
          FALSE
      )
      if (any(mism, na.rm = TRUE)) {
        stop(
          "Existing embeddings in ",
          model_dir,
          " were produced with a different model configuration. ",
          "Please choose a different output directory for this run."
        )
      } else {
        if (verbose) message("Model metadata matches existing _tei_info.yaml")
      }
    }
  } else {
    yaml::write_yaml(current_meta, meta_path)
    if (verbose) message("Wrote TEI metadata to ", meta_path)
  }

  # Also copy/write model YAML to project root
  project_root <- normalizePath(project_dir, mustWork = FALSE)
  proj_yaml <- file.path(project_root, "_tei_info.yaml")
  # Prefer writing only if not identical, to reduce churn
  ok_copy <- TRUE
  if (file.exists(proj_yaml)) {
    prev <- try(yaml::read_yaml(proj_yaml), silent = TRUE)
    if (!inherits(prev, "try-error")) {
      ok_copy <- !identical(prev, current_meta)
    }
  }
  if (ok_copy) {
    dir.create(dirname(proj_yaml), recursive = TRUE, showWarnings = FALSE)
    yaml::write_yaml(current_meta, proj_yaml)
    if (verbose) message("Wrote TEI metadata to project root: ", proj_yaml)
  }

  # Load existing embeddings index (id + text_hash) once
  seen_key <- character(0)
  emb_ds <- NULL
  try(
    {
      if (
        length(
          list.files(
            model_dir,
            recursive = TRUE,
            pattern = "\\.parquet$"
          )
        )
      ) {
        emb_ds <- arrow::open_dataset(model_dir)
        existing <- emb_ds |>
          dplyr::select(id, text_hash) |>
          dplyr::collect()
        if (nrow(existing)) {
          seen_key <- unique(paste0(
            as.character(existing$id),
            "\u00A6",
            as.character(existing$text_hash)
          ))
          if (verbose) {
            message(
              "Loaded ",
              length(seen_key),
              " existing (id,text_hash) pairs"
            )
          }
        } else {
          if (verbose) message("No existing embeddings found in ", model_dir)
        }
      }
    },
    silent = TRUE
  )

  # Pre-scan corpus to compute todo keys and collect corpus ids
  if (verbose) {
    message(
      "Pre-scanning corpus to compute text hashes and detect new/changed works ..."
    )
  }
  todo_key <- character(0)
  corpus_ids <- character(0)
  pre_reader <- arrow::Scanner$create(
    ds,
    columns = req_cols,
    batch_size = as.integer(batch_size)
  )$ToRecordBatchReader()
  repeat {
    batch <- pre_reader$read_next_batch()
    if (is.null(batch)) {
      break
    }

    df <- dplyr::collect(batch)
    title <- ifelse(is.na(df$title), "", df$title)
    abstr <- ifelse(is.na(df$abstract), "", df$abstract)
    text <- paste(title, abstr, sep = "\n\n")
    keep <- (!is.na(df$id)) & nzchar(text)
    if (!any(keep)) {
      next
    }
    ids <- df$id[keep]
    text <- text[keep]

    # Compute xxhash64 for current batch
    text_hash <- vapply(
      text,
      function(x) digest::digest(x, algo = "xxhash64", serialize = FALSE),
      character(1)
    )
    key <- paste0(as.character(ids), "\u00A6", text_hash)
    if (length(seen_key)) {
      need <- fastmatch::fmatch(key, seen_key, nomatch = 0L) == 0L
    } else {
      need <- rep(TRUE, length(key))
    }
    if (any(need)) {
      todo_key <- c(todo_key, key[need])
    }
    corpus_ids <- c(corpus_ids, as.character(ids))
  }
  todo_key <- unique(todo_key)
  corpus_ids <- unique(corpus_ids)
  if (verbose) {
    message(
      "Pre-scan complete: ",
      length(corpus_ids),
      " works in corpus; ",
      length(todo_key),
      " to embed."
    )
  }

  if (!length(todo_key)) {
    message("No new or changed texts to embed. Corpus is up to date.")
  }

  # Create a Scanner for the embedding pass
  reader <- arrow::Scanner$create(
    ds, # Dataset/Table/query
    columns = req_cols, # do projection earlier if you like
    batch_size = as.integer(batch_size)
  )$ToRecordBatchReader()

  # Prepare embedding progress
  total_to_embed <- length(todo_key)
  no_shards <- ceiling(total_to_embed / batch_size)
  shard_idx <- 0L

  start_time <- Sys.time()
  if (verbose) {
    message(
      "Embedding ",
      total_to_embed,
      " works in up to ",
      no_shards,
      " shards ..."
    )
  }
  cli::cli_progress_bar("Embedding new/changed texts", total = no_shards)
  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) {
      break
    } # end of stream

    # Convert this record batch to a data.frame (bounded size)
    df <- dplyr::collect(batch)

    # Build text safely (handle NA)
    title <- ifelse(is.na(df$title), "", df$title)
    abstr <- ifelse(is.na(df$abstract), "", df$abstract)
    text <- paste(title, abstr, sep = "\n\n")

    # Drop rows with missing id or empty text
    keep <- (!is.na(df$id)) & nzchar(text)
    if (!any(keep)) {
      next
    }
    ids <- df$id[keep]
    text <- text[keep]

    # Compute hashes and filter to only todo keys
    text_hash <- vapply(
      text,
      function(x) digest::digest(x, algo = "xxhash64", serialize = FALSE),
      character(1)
    )
    key <- paste0(as.character(ids), "\u00A6", text_hash)
    need <- fastmatch::fmatch(key, todo_key, nomatch = 0L) != 0L
    if (!any(need)) {
      next
    }
    ids <- ids[need]
    text <- text[need]
    text_hash <- text_hash[need]

    if (verbose) {
      message(
        "Embedding shard #",
        shard_idx + 1L,
        " of ",
        no_shards,
        " (",
        length(ids),
        " items)..."
      )
    }
    cli::cli_progress_update()

    # Call TEI in sub-requests
    emb <- tei_embed_text(
      text,
      tei_url
    ) # matrix n x d

    # Build a shard data.frame: id + text_hash + V1..Vd
    shard <- data.frame(
      id = ids,
      text_hash = text_hash,
      emb,
      check.names = FALSE
    )

    shard_idx <- shard_idx + 1L
    shard_dir <- file.path(model_dir, sprintf("shard=%d", shard_idx))
    if (!dir.exists(shard_dir)) {
      dir.create(shard_dir, recursive = TRUE)
    }
    path <- file.path(shard_dir, sprintf("part-%09d.parquet", shard_idx))
    # Write one shard per batch under Hive partition
    arrow::write_parquet(shard, path)
    if (verbose) {
      message(
        "Wrote shard #",
        shard_idx,
        " (",
        nrow(shard),
        " rows) to ",
        shard_dir
      )
    }
  }
  cli::cli_progress_done()
  elapsed <- Sys.time() - start_time
  cli::cli_alert_success(sprintf(
    "Done! Embedded %d new/changed works in %d shards in %s.",
    total_to_embed,
    no_shards,
    format(elapsed, digits = 2)
  ))

  # Prune embeddings for works no longer present in the corpus (rewrite dataset)
  pruned <- 0L
  if (verbose) {
    message("Checking for embeddings to prune (ids no longer in corpus) ...")
  }
  try(
    {
      emb_ds2 <- arrow::open_dataset(model_dir)
      emb_ids <- emb_ds2 |>
        dplyr::select(id) |>
        dplyr::collect() |>
        dplyr::pull(id) |>
        as.character() |>
        unique()
      dangling <- setdiff(emb_ids, corpus_ids)
      if (length(dangling)) {
        if (verbose) {
          message("Pruning ", length(dangling), " ids from embeddings ...")
        }
        tmp_dir <- file.path(
          dirname(model_dir),
          paste0(
            basename(model_dir),
            "_tmp_pruned_",
            format(Sys.time(), "%Y%m%d%H%M%S")
          )
        )
        filtered <- emb_ds2 |>
          dplyr::filter(!(id %in% dangling))
        arrow::write_dataset(
          filtered,
          tmp_dir,
          format = "parquet",
          partitioning = "shard"
        )
        # preserve metadata
        if (file.exists(meta_path)) {
          file.copy(
            meta_path,
            file.path(tmp_dir, "_tei_info.yaml"),
            overwrite = TRUE
          )
        }
        unlink(model_dir, recursive = TRUE, force = TRUE)
        file.rename(tmp_dir, model_dir)
        pruned <- length(dangling)
      } else {
        if (verbose) message("No pruning required.")
      }
    },
    silent = TRUE
  )
  if (pruned > 0L) {
    cli::cli_alert_success(sprintf(
      "Pruned %d works no longer in corpus.",
      pruned
    ))
  }

  invisible(model_dir)
}
