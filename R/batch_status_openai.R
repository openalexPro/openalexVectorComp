#' Inspect OpenAI batch state for a label
#'
#' @param project_dir Project root directory.
#' @param label Embedding label.
#' @param refresh_remote Logical; if `TRUE`, refresh non-terminal job statuses
#'   from OpenAI before returning.
#'
#' @return A data frame with one row per tracked job.
#' @export
batch_status_openai <- function(
  project_dir,
  label = "corpus",
  refresh_remote = TRUE
) {
  label <- trimws(as.character(label))
  if (!nzchar(label)) stop("`label` must be non-empty.")
  if (!is.logical(refresh_remote) || length(refresh_remote) != 1 || is.na(refresh_remote)) {
    stop("`refresh_remote` must be TRUE or FALSE.")
  }

  state_file <- .ovc_openai_state_file(project_dir, label)
  if (!file.exists(state_file)) {
    return(data.frame())
  }

  state <- .ovc_openai_state_read(state_file)

  if (isTRUE(refresh_remote) && length(state$jobs)) {
    backend <- backend_config(
      provider = "openai",
      base_url = .ovc_or(state$backend$base_url, NULL),
      model = .ovc_or(state$model_id, NULL),
      timeout = .ovc_or(state$backend$timeout, 60),
      retries = .ovc_or(state$backend$retries, 3)
    )

    for (i in seq_along(state$jobs)) {
      job <- state$jobs[[i]]
      if (!nzchar(.ovc_or(job$ingested_at, "")) && !.ovc_openai_is_terminal(.ovc_or(job$status, ""))) {
        remote <- .openai_batch_get(backend, job$job_id)
        state$jobs[[i]] <- .ovc_openai_job_update_from_remote(job, remote)
      }
    }
    .ovc_openai_state_write(state_file, state)
  }

  .ovc_openai_state_to_df(state)
}

#' Collect completed OpenAI batch embedding jobs
#'
#' @param project_dir Project root directory.
#' @param backend Backend configuration from [backend_config()]. Must
#'   use `provider = "openai"`.
#' @param label Embedding label partition to collect into.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns a list with collection summary.
