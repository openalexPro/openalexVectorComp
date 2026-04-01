#' Collect completed OpenAI batch embedding jobs
#'
#' @param project_dir Project root directory.
#' @param backend Backend configuration from [backend_config()]. Must
#'   use `provider = "openai"`.
#' @param label Embedding label partition to collect into.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns a list with collection summary.
#' @export
batch_collect_openai <- function(
  project_dir,
  backend = backend_config(provider = "openai"),
  label = "corpus",
  verbose = TRUE
) {
  if (!is.list(backend) || is.null(backend$provider) || backend$provider != "openai") {
    stop("`backend` must be an OpenAI backend configuration.")
  }
  label <- trimws(as.character(label))
  if (!nzchar(label)) stop("`label` must be non-empty.")

  state_file <- .ovc_openai_state_file(project_dir, label)
  if (!file.exists(state_file)) {
    stop("No OpenAI batch state found for label `", label, "`: ", state_file)
  }

  state_lock <- paste0(state_file, ".lock")
  lock_created <- .ovc_openai_lock_acquire(state_lock)
  if (!lock_created) {
    stop("State lock exists. Another submit/collect may be running: ", state_lock)
  }
  on.exit(unlink(state_lock), add = TRUE)

  state <- .ovc_openai_state_read(state_file)
  model_id <- .ovc_or(state$model_id, backend$model)
  if (is.null(model_id) || !nzchar(model_id)) {
    stop("Could not determine model id from state/backend.")
  }
  model_part <- gsub("/", "_", model_id, fixed = TRUE)
  label_part <- gsub("/", "_", label, fixed = TRUE)

  emb_root <- file.path(project_dir, "embeddings")
  model_dir <- file.path(emb_root, paste0("model_id=", model_part))
  label_dir <- file.path(model_dir, paste0("label=", label_part))
  if (!dir.exists(label_dir)) dir.create(label_dir, recursive = TRUE, showWarnings = FALSE)

  checked_jobs <- 0L
  completed_jobs <- 0L
  downloaded_jobs <- 0L
  written_rows <- 0L
  failed_jobs <- 0L
  pending_jobs <- 0L

  for (i in seq_along(state$jobs)) {
    job <- state$jobs[[i]]
    if (nzchar(.ovc_or(job$ingested_at, ""))) {
      next
    }

    checked_jobs <- checked_jobs + 1L
    remote <- .openai_batch_get(backend, job$job_id)
    job <- .ovc_openai_job_update_from_remote(job, remote)

    status <- tolower(.ovc_or(job$status, ""))
    if (.ovc_openai_is_terminal(status) && status != "completed") {
      failed_jobs <- failed_jobs + 1L
      state$jobs[[i]] <- job
      next
    }
    if (status != "completed") {
      pending_jobs <- pending_jobs + 1L
      state$jobs[[i]] <- job
      next
    }

    completed_jobs <- completed_jobs + 1L

    output_file_id <- .ovc_or(job$output_file_id, "")
    if (!nzchar(output_file_id)) {
      job$error_message <- "Completed job has no output_file_id."
      state$jobs[[i]] <- job
      next
    }

    batch_dir <- dirname(job$manifest_parquet)
    out_path <- file.path(batch_dir, "output.jsonl")
    .openai_batch_download_file(backend, output_file_id, out_path)
    job$local_output_jsonl <- out_path
    job$downloaded_at <- as.character(Sys.time(), tz = "UTC")

    parsed <- .ovc_openai_parse_output_jsonl(out_path)
    manifest <- arrow::read_parquet(job$manifest_parquet)

    out <- .ovc_openai_build_embeddings_output(
      parsed = parsed,
      manifest = manifest,
      provider = "openai",
      model_id = model_id
    )

    batch_idx <- .ovc_next_embed_batch_index(label_dir)
    shard_dir <- file.path(label_dir, sprintf("batch=%d", batch_idx))
    dir.create(shard_dir, recursive = TRUE, showWarnings = FALSE)
    shard_fn <- file.path(shard_dir, sprintf("embeddings-%05d.parquet", batch_idx))
    arrow::write_parquet(out, shard_fn)

    downloaded_jobs <- downloaded_jobs + 1L
    written_rows <- written_rows + nrow(out)
    job$row_count_downloaded <- as.integer(nrow(out))
    job$ingested_at <- as.character(Sys.time(), tz = "UTC")
    state$jobs[[i]] <- job
  }

  .ovc_openai_state_write(state_file, state)

  if (verbose) {
    if (downloaded_jobs == 0L) {
      cli::cli_alert_info("No completed OpenAI batch jobs ready for ingestion.")
    } else {
      cli::cli_alert_success(
        "Collected {downloaded_jobs} completed job(s), wrote {written_rows} embedding row(s)."
      )
    }
  }

  invisible(list(
    state_file = state_file,
    checked_jobs = checked_jobs,
    completed_jobs = completed_jobs,
    downloaded_jobs = downloaded_jobs,
    written_rows = written_rows,
    pending_jobs = pending_jobs,
    failed_jobs = failed_jobs
  ))
}
