#' Submit OpenAI Batch jobs for corpus embeddings (asynchronous)
#'
#' Preprocesses corpus text, performs preflight request-size checks, splits work
#' into compliant OpenAI batch jobs, submits them, and returns immediately.
#'
#' @param project_dir Project root directory.
#' @param backend Backend configuration from [backend_config()]. Must
#'   use `provider = "openai"`.
#' @param corpus_name Folder name under `project_dir` containing the corpus
#'   dataset. Defaults to `"corpus"`.
#' @param label Embedding label partition. Defaults to `corpus_name`.
#' @param batch_size Number of corpus rows per Arrow scan batch while preparing
#'   requests.
#' @param delete_existing If `TRUE`, remove existing embeddings for `label` and
#'   existing OpenAI batch state before submitting new jobs.
#' @param text_preprocessor Text-preparation function returning `id`, `text`,
#'   `text_hash`.
#' @param cleaner_args Additional named arguments passed to `text_preprocessor`.
#' @param save_text Logical; whether to keep cleaned text for downstream parquet
#'   output.
#' @param max_requests_per_job Max requests per submitted OpenAI job. Must be
#'   <= 50000.
#' @param max_job_bytes Max JSONL bytes per submitted OpenAI job. Must be
#'   <= 200 MB.
#' @param completion_window OpenAI batch completion window. Defaults to `"24h"`.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns a list with state path and submission summary.
#' @export
batch_submit_openai <- function(
  project_dir,
  backend = backend_config(provider = "openai"),
  corpus_name = "corpus",
  label = corpus_name,
  batch_size = 5000,
  delete_existing = FALSE,
  text_preprocessor = clean_abstract_for_embedding,
  cleaner_args = list(),
  save_text = TRUE,
  max_requests_per_job = 20000L,
  max_job_bytes = 150 * 1024^2,
  completion_window = "24h",
  verbose = TRUE
) {
  .ovc_validate_openai_batch_inputs(
    project_dir = project_dir,
    backend = backend,
    corpus_name = corpus_name,
    label = label,
    batch_size = batch_size,
    text_preprocessor = text_preprocessor,
    cleaner_args = cleaner_args,
    save_text = save_text,
    max_requests_per_job = max_requests_per_job,
    max_job_bytes = max_job_bytes,
    completion_window = completion_window
  )

  batch_size <- as.integer(batch_size)
  corpus_name <- trimws(corpus_name)
  label <- trimws(label)
  max_requests_per_job <- as.integer(max_requests_per_job)
  max_job_bytes <- as.numeric(max_job_bytes)

  info <- backend_info(backend)
  model_id <- .ovc_or(info$model_id, backend$model)
  model_part <- gsub("/", "_", model_id, fixed = TRUE)
  label_part <- gsub("/", "_", label, fixed = TRUE)

  emb_root <- file.path(project_dir, "embeddings")
  model_dir <- file.path(emb_root, paste0("model_id=", model_part))
  label_dir <- file.path(model_dir, paste0("label=", label_part))

  state_file <- .ovc_openai_state_file(project_dir, label)
  state_lock <- paste0(state_file, ".lock")
  work_root <- file.path(project_dir, "openai_batch", paste0("model_id=", model_part), paste0("label=", label_part))

  if (!dir.exists(project_dir)) {
    stop("`project_dir` does not exist: ", project_dir)
  }

  if (isTRUE(delete_existing)) {
    if (dir.exists(label_dir)) unlink(label_dir, recursive = TRUE)
    if (dir.exists(work_root)) unlink(work_root, recursive = TRUE)
    if (file.exists(state_file)) unlink(state_file)
  }

  if (!dir.exists(emb_root)) dir.create(emb_root, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(model_dir)) dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  backend_meta <- backend
  backend_meta$model <- model_id
  backend_meta$max_batch_size <- .ovc_or(info$max_batch_size, backend$max_batch_size)
  meta_path <- file.path(model_dir, "embed_model.yaml")
  backend_save(backend = backend_meta, fn = meta_path)
  meta <- yaml::read_yaml(meta_path)
  meta$embedding_label <- label
  meta$submission_mode <- "openai_batch"
  meta$openai_batch_max_requests_per_job <- max_requests_per_job
  meta$openai_batch_max_job_bytes <- as.numeric(max_job_bytes)
  yaml::write_yaml(meta, meta_path)

  corpus <- normalizePath(file.path(project_dir, corpus_name), mustWork = TRUE)
  ds <- arrow::open_dataset(corpus)
  req_cols <- c("id", "title", "abstract")
  missing <- setdiff(req_cols, names(ds))
  if (length(missing)) {
    stop("Dataset must contain columns: ", paste(missing, collapse = ", "))
  }
  ds <- ds |> dplyr::select(dplyr::all_of(req_cols))

  state <- .ovc_openai_state_read(state_file, model_id = model_id, backend = backend, label = label, corpus_name = corpus_name)

  existing_hash <- .ovc_load_existing_hash(model_dir = model_dir, label_part = label_part)
  queued_ids <- .ovc_openai_state_active_custom_ids(state)

  prepared <- .ovc_prepare_corpus_rows(
    ds = ds,
    batch_size = batch_size,
    text_preprocessor = text_preprocessor,
    cleaner_args = cleaner_args,
    existing_hash = existing_hash,
    queued_custom_ids = queued_ids,
    save_text = save_text
  )

  if (!nrow(prepared)) {
    if (verbose) cli::cli_alert_info("No new/changed rows to submit.")
    return(invisible(list(
      state_file = state_file,
      model_dir = model_dir,
      label = label,
      submitted_jobs = 0L,
      submitted_rows = 0L,
      skipped_rows = 0L
    )))
  }

  split <- .ovc_openai_plan_jobs(
    prepared = prepared,
    model = model_id,
    max_requests_per_job = max_requests_per_job,
    max_job_bytes = max_job_bytes
  )
  prepared <- split$prepared

  if (isTRUE(split$split_by_size) && verbose) {
    cli::cli_alert_warning("Preflight split jobs by byte-size limits; submitting {length(split$jobs)} jobs.")
  }

  dir.create(work_root, recursive = TRUE, showWarnings = FALSE)

  lock_created <- .ovc_openai_lock_acquire(state_lock)
  if (!lock_created) {
    stop("State lock exists. Another submit/collect may be running: ", state_lock)
  }
  on.exit(unlink(state_lock), add = TRUE)

  state <- .ovc_openai_state_read(state_file, model_id = model_id, backend = backend, label = label, corpus_name = corpus_name)

  submitted_jobs <- 0L
  submitted_rows <- 0L
  next_batch_index <- .ovc_openai_state_next_batch_index(state)

  for (job_idx in seq_along(split$jobs)) {
    idx <- split$jobs[[job_idx]]
    job_df <- prepared[idx, , drop = FALSE]
    batch_index <- next_batch_index
    next_batch_index <- next_batch_index + 1L

    batch_dir <- file.path(work_root, paste0("batch=", batch_index))
    dir.create(batch_dir, recursive = TRUE, showWarnings = FALSE)
    req_path <- file.path(batch_dir, "requests.jsonl")
    manifest_path <- file.path(batch_dir, "manifest.parquet")

    writeLines(as.character(job_df$request_line), req_path, useBytes = TRUE)

    manifest_cols <- c("custom_id", "id", "text_hash")
    if (isTRUE(save_text) && "text" %in% names(job_df)) {
      manifest_cols <- c(manifest_cols, "text")
    }
    extra_cols <- setdiff(names(job_df), c("request_line", "request_bytes", "custom_id", "id", "text_hash", "text"))
    manifest_cols <- c(manifest_cols, extra_cols)
    manifest <- job_df[, manifest_cols, drop = FALSE]
    arrow::write_parquet(manifest, manifest_path)
    req_path_abs <- normalizePath(req_path, mustWork = FALSE)
    manifest_path_abs <- normalizePath(manifest_path, mustWork = FALSE)

    file_id <- .openai_batch_upload_file(backend, req_path)
    batch <- .openai_batch_create(backend, input_file_id = file_id, completion_window = completion_window)

    state$jobs[[length(state$jobs) + 1L]] <- list(
      job_id = as.character(batch$id),
      batch_index = as.integer(batch_index),
      submitted_at = as.character(Sys.time(), tz = "UTC"),
      status = as.character(.ovc_or(batch$status, "submitted")),
      input_file_id = as.character(file_id),
      output_file_id = as.character(.ovc_or(batch$output_file_id, "")),
      error_file_id = as.character(.ovc_or(batch$error_file_id, "")),
      local_input_jsonl = req_path_abs,
      local_output_jsonl = "",
      manifest_parquet = manifest_path_abs,
      row_count_submitted = as.integer(nrow(job_df)),
      row_count_downloaded = 0L,
      downloaded_at = "",
      ingested_at = "",
      error_message = ""
    )

    submitted_jobs <- submitted_jobs + 1L
    submitted_rows <- submitted_rows + nrow(job_df)
  }

  .ovc_openai_state_write(state_file, state)

  if (verbose) {
    cli::cli_alert_success("Submitted {submitted_jobs} OpenAI batch job(s) with {submitted_rows} row(s).")
  }

  invisible(list(
    state_file = state_file,
    model_dir = model_dir,
    label = label,
    submitted_jobs = submitted_jobs,
    submitted_rows = submitted_rows,
    skipped_rows = as.integer(.ovc_or(attr(prepared, "skipped_rows"), 0L))
  ))
}

#' Inspect OpenAI batch state for a label
#'
#' @param project_dir Project root directory.
#' @param label Embedding label.
#' @param refresh_remote Logical; if `TRUE`, refresh non-terminal job statuses
#'   from OpenAI before returning.
#'
#' @return A data frame with one row per tracked job.
