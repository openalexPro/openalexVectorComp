#' Create and optionally run a self-contained demo project via Quarto
#'
#' Sets up a demo workspace under `demo_dir`, creates a pipeline project under
#' `demo_dir/project`, copies small corpus and
#' reference fixtures and Quarto template from `inst/ovc_demo`, and optionally
#' renders the analysis.
#'
#' The workspace keeps all generated directories and output artifacts. The
#' Quarto file is created in `demo_dir`, while embedding pipeline data is stored
#' in `demo_dir/project`.
#'
#' @param demo_dir Demo workspace directory. Defaults to
#'   `file.path(getwd(), "demos", "openalex")`.
#' @param render Logical; if `TRUE` (default), run `quarto render` on the
#'   copied template.
#' @param backend Optional backend config from [embedding_backend_config()]. If
#'   `NULL`, defaults to Hugging Face (`provider = "hf"`,
#'   model `"BAAI/bge-small-en-v1.5"`).
#' @param max_corpus Maximum number of corpus fixture rows to copy.
#' @param max_reference Maximum number of reference fixture rows to copy.
#' @param overwrite Logical; if `FALSE` (default), stop when demo-managed files
#'   already exist. If `TRUE`, refresh demo-managed files.
#' @param quarto_file Name of the analysis file created in `demo_dir`.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns a list with project paths and render status.
#' @export
run_demo_openalex_quarto <- function(
  demo_dir = file.path(getwd(), "demos", "openalex"),
  render = TRUE,
  backend = NULL,
  max_corpus = 100,
  max_reference = 10,
  overwrite = FALSE,
  quarto_file = "openalex_demo_analysis.qmd",
  verbose = TRUE
) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  if (
    !is.character(demo_dir) ||
      length(demo_dir) != 1 ||
      !nzchar(trimws(demo_dir))
  ) {
    stop("`demo_dir` must be a non-empty character string.")
  }
  if (!is.logical(render) || length(render) != 1 || is.na(render)) {
    stop("`render` must be TRUE or FALSE.")
  }
  if (
    !is.numeric(max_corpus) ||
      length(max_corpus) != 1 ||
      !is.finite(max_corpus) ||
      max_corpus <= 0
  ) {
    stop("`max_corpus` must be a positive number.")
  }
  if (
    !is.numeric(max_reference) ||
      length(max_reference) != 1 ||
      !is.finite(max_reference) ||
      max_reference <= 0
  ) {
    stop("`max_reference` must be a positive number.")
  }
  if (!is.logical(overwrite) || length(overwrite) != 1 || is.na(overwrite)) {
    stop("`overwrite` must be TRUE or FALSE.")
  }
  if (
    !is.character(quarto_file) ||
      length(quarto_file) != 1 ||
      !nzchar(trimws(quarto_file))
  ) {
    stop("`quarto_file` must be a non-empty character string.")
  }

  max_corpus <- as.integer(max_corpus)
  max_reference <- as.integer(max_reference)
  demo_dir <- normalizePath(demo_dir, mustWork = FALSE)
  project_dir <- file.path(demo_dir, "project")

  if (is.null(backend)) {
    backend <- embedding_backend_config(
      provider = "hf",
      model = "BAAI/bge-small-en-v1.5"
    )
  }
  if (!is.list(backend) || is.null(backend$provider)) {
    stop(
      "`backend` must be NULL or a backend config from `embedding_backend_config()`."
    )
  }

  qmd_path <- file.path(demo_dir, quarto_file)
  backend_yaml <- file.path(demo_dir, "demo_backend.yaml")

  managed_paths <- c(project_dir, qmd_path, backend_yaml)
  if (
    !isTRUE(overwrite) &&
      any(file.exists(managed_paths) | dir.exists(managed_paths))
  ) {
    stop(
      "Demo files already exist in `demo_dir`. Set `overwrite = TRUE` to refresh demo-managed files."
    )
  }

  if (!dir.exists(demo_dir)) {
    dir.create(demo_dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(project_dir)) {
    dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)
  }

  corpus_dir <- file.path(project_dir, "corpus")
  reference_dir <- file.path(project_dir, "reference_corpus")

  .ovc_copy_demo_fixture(
    src = .ovc_demo_path("ovc_demo/project/corpus/corpus_small.parquet"),
    dst_dir = corpus_dir,
    dst_file = "corpus_small.parquet",
    max_rows = max_corpus
  )
  .ovc_copy_demo_fixture(
    src = .ovc_demo_path("ovc_demo/project/reference_corpus/reference_small.parquet"),
    dst_dir = reference_dir,
    dst_file = "reference_small.parquet",
    max_rows = max_reference
  )

  template_rel <- if (identical(quarto_file, "openai_demo_analysis.qmd")) {
    "ovc_demo/openai_demo_analysis.qmd"
  } else {
    "ovc_demo/openalex_demo_analysis.qmd"
  }
  template_src <- .ovc_demo_path(template_rel)
  dir.create(dirname(qmd_path), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(template_src, qmd_path, overwrite = TRUE)) {
    stop("Failed to copy Quarto template to `", qmd_path, "`.")
  }

  embedding_backend_save(backend = backend, fn = backend_yaml)

  if (verbose) {
    message("Demo workspace prepared at ", demo_dir)
  }

  rendered <- FALSE
  if (isTRUE(render)) {
    provider <- tolower(as.character(backend$provider %||% ""))
    if (provider %in% c("hf", "openai")) {
      token <- Sys.getenv("OVC_API_TOKEN", unset = "")
      if (!nzchar(token)) {
        stop(
          "`OVC_API_TOKEN` is required for provider `",
          provider,
          "` when `render = TRUE`."
        )
      }
    }

    if (verbose) {
      message("Rendering Quarto analysis: ", quarto_file)
    }
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(demo_dir)
    quarto::quarto_render(input = quarto_file)

    rendered <- TRUE
  }

  invisible(list(
    demo_dir = demo_dir,
    project_dir = project_dir,
    corpus_dir = corpus_dir,
    reference_corpus_dir = reference_dir,
    quarto_file = qmd_path,
    backend_yaml = backend_yaml,
    rendered = rendered
  ))
}

#' Create and optionally run an OpenAI-based demo project via Quarto
#'
#' Uses the same demo structure as [run_demo_openalex_quarto()], but configures
#' an OpenAI backend and requires an explicit API key argument. The key is set
#' in `OVC_API_TOKEN` for the duration of the call.
#'
#' @param api_key OpenAI API key. Must be a non-empty string.
#' @param demo_dir Demo workspace directory. Defaults to
#'   `file.path(getwd(), "demos", "openai")`.
#' @param render Logical; if `TRUE` (default), run `quarto render` on the
#'   copied template.
#' @param model OpenAI embedding model id. Defaults to
#'   `"text-embedding-3-small"`.
#' @param max_corpus Maximum number of corpus fixture rows to copy.
#' @param max_reference Maximum number of reference fixture rows to copy.
#' @param overwrite Logical; if `FALSE` (default), stop when demo-managed files
#'   already exist. If `TRUE`, refresh demo-managed files.
#' @param quarto_file Name of the analysis file created in `demo_dir`.
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns a list with project paths and render status.
#' @export
run_demo_openai_quarto <- function(
  api_key,
  demo_dir = file.path(getwd(), "demos", "openai"),
  render = TRUE,
  model = "text-embedding-3-small",
  max_corpus = 100,
  max_reference = 10,
  overwrite = FALSE,
  quarto_file = "openai_demo_analysis.qmd",
  verbose = TRUE
) {
  if (!is.character(api_key) || length(api_key) != 1 || !nzchar(trimws(api_key))) {
    stop("`api_key` must be a non-empty character string.")
  }
  if (!is.character(model) || length(model) != 1 || !nzchar(trimws(model))) {
    stop("`model` must be a non-empty character string.")
  }

  old_token <- Sys.getenv("OVC_API_TOKEN", unset = "")
  on.exit(
    if (nzchar(old_token)) {
      Sys.setenv(OVC_API_TOKEN = old_token)
    } else {
      Sys.unsetenv("OVC_API_TOKEN")
    },
    add = TRUE
  )
  Sys.setenv(OVC_API_TOKEN = trimws(api_key))

  backend <- embedding_backend_config(
    provider = "openai",
    model = trimws(model)
  )

  out <- run_demo_openalex_quarto(
    demo_dir = demo_dir,
    render = render,
    backend = backend,
    max_corpus = max_corpus,
    max_reference = max_reference,
    overwrite = overwrite,
    quarto_file = quarto_file,
    verbose = verbose
  )

  status_cmd <- paste0(
    "openalexVectorComp::embed_corpus_status_openai_batch(\n",
    "  project_dir = \"", out$project_dir, "\",\n",
    "  label = \"corpus_batch\",\n",
    "  refresh_remote = TRUE\n",
    ")"
  )
  finalize_cmd <- paste0(
    "openalexVectorComp::finalize_demo_openai_batch(\n",
    "  demo_dir = \"", out$demo_dir, "\",\n",
    "  api_key = keyring::key_get(\"API_openai_ipbes\"),\n",
    "  label = \"corpus_batch\"\n",
    ")"
  )

  out$openai_batch_status_command <- status_cmd
  out$openai_batch_finalize_command <- finalize_cmd

  if (isTRUE(verbose)) {
    message("OpenAI batch status command:\n", status_cmd)
    message("OpenAI batch finalize command:\n", finalize_cmd)
  }

  invisible(out)
}

#' Finalize OpenAI demo batch jobs and compare direct vs batch embeddings
#'
#' Runs OpenAI batch status/collect for a prepared demo workspace and, when
#' batch embeddings are available, computes direct-vs-batch vector comparison.
#' Comparison artifacts are written to:
#' `project/openai_batch_comparison/label=<label>/`.
#'
#' @param demo_dir Demo workspace directory created by
#'   [run_demo_openai_quarto()] or [run_demo_openalex_quarto()].
#' @param api_key Optional OpenAI API key. If provided, it is set in
#'   `OVC_API_TOKEN` for the duration of this call.
#' @param label Batch embedding label to finalize. Defaults to `"corpus_batch"`.
#' @param refresh_remote Logical; forwarded to
#'   [embed_corpus_status_openai_batch()].
#' @param verbose Logical; print progress messages.
#'
#' @return Invisibly returns a list containing status/collect summaries,
#'   comparison readiness, and output paths.
#' @export
finalize_demo_openai_batch <- function(
  demo_dir,
  api_key = NULL,
  label = "corpus_batch",
  refresh_remote = TRUE,
  verbose = TRUE
) {
  if (!is.character(demo_dir) || length(demo_dir) != 1 || !nzchar(trimws(demo_dir))) {
    stop("`demo_dir` must be a non-empty character string.")
  }
  if (!is.character(label) || length(label) != 1 || !nzchar(trimws(label))) {
    stop("`label` must be a non-empty character string.")
  }
  if (!is.null(api_key) && (!is.character(api_key) || length(api_key) != 1 || !nzchar(trimws(api_key)))) {
    stop("`api_key` must be NULL or a non-empty character string.")
  }
  if (!is.logical(refresh_remote) || length(refresh_remote) != 1 || is.na(refresh_remote)) {
    stop("`refresh_remote` must be TRUE or FALSE.")
  }
  if (!is.logical(verbose) || length(verbose) != 1 || is.na(verbose)) {
    stop("`verbose` must be TRUE or FALSE.")
  }

  old_token <- Sys.getenv("OVC_API_TOKEN", unset = "")
  on.exit(
    if (nzchar(old_token)) {
      Sys.setenv(OVC_API_TOKEN = old_token)
    } else {
      Sys.unsetenv("OVC_API_TOKEN")
    },
    add = TRUE
  )
  if (!is.null(api_key)) {
    Sys.setenv(OVC_API_TOKEN = trimws(api_key))
  }

  demo_dir <- normalizePath(demo_dir, mustWork = FALSE)
  project_dir <- file.path(demo_dir, "project")
  backend_yaml <- file.path(demo_dir, "demo_backend.yaml")

  if (!file.exists(backend_yaml)) {
    stop("Missing backend config: ", backend_yaml)
  }
  if (!dir.exists(project_dir)) {
    stop("Missing demo project directory: ", project_dir)
  }

  backend <- embedding_backend_read(backend_yaml)
  provider <- tolower(as.character(if (is.null(backend$provider)) "" else backend$provider))
  if (!identical(provider, "openai")) {
    stop("`demo_backend.yaml` must configure provider = 'openai'.")
  }

  emb_root <- file.path(project_dir, "embeddings")
  model_dirs <- character()
  if (dir.exists(emb_root)) {
    model_dirs <- list.dirs(emb_root, recursive = FALSE, full.names = FALSE)
    model_dirs <- model_dirs[grepl("^model_id=", model_dirs)]
  }
  if (length(model_dirs) > 1L) {
    stop("Expected exactly one model_id directory in demo, found: ", paste(model_dirs, collapse = ", "))
  }
  model_id_dir <- if (length(model_dirs) == 1L) model_dirs[[1]] else ""

  status_df <- embed_corpus_status_openai_batch(
    project_dir = project_dir,
    label = label,
    refresh_remote = refresh_remote
  )
  state_file <- .ovc_openai_state_file(project_dir, label)
  collect_info <- list(
    state_file = state_file,
    checked_jobs = 0L,
    completed_jobs = 0L,
    downloaded_jobs = 0L,
    written_rows = 0L,
    pending_jobs = 0L,
    failed_jobs = 0L
  )
  if (file.exists(state_file)) {
    collect_info <- embed_corpus_collect_openai_batch(
      project_dir = project_dir,
      backend = backend,
      label = label,
      verbose = verbose
    )
  }

  cmp_dir <- file.path(project_dir, "openai_batch_comparison", paste0("label=", gsub("/", "_", label, fixed = TRUE)))
  comparison_parquet <- file.path(cmp_dir, "comparison.parquet")
  summary_yaml <- file.path(cmp_dir, "summary.yaml")

  ready <- FALSE
  message_txt <- ""
  comparison_df <- data.frame()
  summary_df <- data.frame()

  batch_path <- file.path(emb_root, model_id_dir, paste0("label=", gsub("/", "_", label, fixed = TRUE)))
  batch_df <- tryCatch(
    arrow::open_dataset(
      batch_path,
      factory_options = list(exclude_invalid_files = TRUE)
    ) |>
      dplyr::collect(),
    error = function(e) data.frame()
  )

  if (!file.exists(state_file)) {
    message_txt <- paste0(
      "No batch submission state found for label `", label,
      "`. Submit the batch first, then rerun finalize."
    )
  } else if (!nzchar(model_id_dir) || !nrow(batch_df)) {
    message_txt <- "Batch still pending; rerun finalize later."
  } else {
    cmp <- .ovc_compare_direct_vs_batch(
      project_dir = project_dir,
      model_id_dir = model_id_dir,
      direct_label = "corpus",
      batch_label = label
    )

    dir.create(cmp_dir, recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(cmp$comparison_df, comparison_parquet)
    yaml::write_yaml(as.list(cmp$summary_df[1, , drop = FALSE]), summary_yaml)

    ready <- TRUE
    comparison_df <- cmp$comparison_df
    summary_df <- cmp$summary_df
    message_txt <- "Batch comparison written successfully."
  }

  if (isTRUE(verbose)) {
    if (isTRUE(ready)) {
      cli::cli_alert_success("{message_txt}")
    } else {
      cli::cli_alert_info("{message_txt}")
    }
  }

  invisible(list(
    demo_dir = demo_dir,
    project_dir = project_dir,
    label = label,
    model_id_dir = model_id_dir,
    status = status_df,
    collect = collect_info,
    comparison_ready = ready,
    message = message_txt,
    comparison_parquet = comparison_parquet,
    summary_yaml = summary_yaml,
    comparison_df = comparison_df,
    summary_df = summary_df
  ))
}

.ovc_copy_demo_fixture <- function(src, dst_dir, dst_file, max_rows) {
  if (!file.exists(src)) {
    stop("Demo fixture does not exist: ", src)
  }
  if (dir.exists(dst_dir)) {
    unlink(dst_dir, recursive = TRUE)
  }
  dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)

  df <- arrow::read_parquet(src)
  req <- c("id", "title", "abstract")
  miss <- setdiff(req, names(df))
  if (length(miss)) {
    stop(
      "Demo fixture is missing required columns: ",
      paste(miss, collapse = ", ")
    )
  }
  n_keep <- min(nrow(df), as.integer(max_rows))
  df <- df[seq_len(n_keep), req, drop = FALSE]

  arrow::write_parquet(df, file.path(dst_dir, dst_file))
}

.ovc_demo_path <- function(rel) {
  p <- system.file(rel, package = "openalexVectorComp")
  if (nzchar(p)) {
    return(p)
  }
  local <- file.path("inst", rel)
  if (file.exists(local)) {
    return(local)
  }
  stop("Could not resolve installed or local inst path for `", rel, "`.")
}

.ovc_compare_direct_vs_batch <- function(
  project_dir,
  model_id_dir,
  direct_label = "corpus",
  batch_label
) {
  direct_part <- gsub("/", "_", as.character(direct_label), fixed = TRUE)
  batch_part <- gsub("/", "_", as.character(batch_label), fixed = TRUE)
  emb_root <- file.path(project_dir, "embeddings", model_id_dir)

  direct_path <- file.path(emb_root, paste0("label=", direct_part))
  batch_path <- file.path(emb_root, paste0("label=", batch_part))

  direct_df <- arrow::open_dataset(
    direct_path,
    factory_options = list(exclude_invalid_files = TRUE)
  ) |>
    dplyr::collect()
  batch_df <- arrow::open_dataset(
    batch_path,
    factory_options = list(exclude_invalid_files = TRUE)
  ) |>
    dplyr::collect()

  if (!nrow(direct_df)) {
    stop("Direct embeddings are empty for label `", direct_label, "`.")
  }
  if (!nrow(batch_df)) {
    stop("Batch embeddings are empty for label `", batch_label, "`.")
  }

  vcols <- grep("^V[0-9]+$", names(direct_df), value = TRUE)
  vcols <- vcols[vcols %in% names(batch_df)]
  if (!length(vcols)) {
    stop("Could not find common embedding columns (V1..Vd) for comparison.")
  }

  direct_small <- direct_df[, c("id", vcols), drop = FALSE]
  batch_small <- batch_df[, c("id", vcols), drop = FALSE]
  joined <- merge(
    direct_small,
    batch_small,
    by = "id",
    suffixes = c("_direct", "_batch"),
    all = FALSE
  )
  if (!nrow(joined)) {
    stop("No overlapping ids between direct and batch embeddings.")
  }

  row_cosine <- function(a, b) {
    denom <- sqrt(sum(a * a)) * sqrt(sum(b * b))
    if (!is.finite(denom) || denom == 0) return(NA_real_)
    sum(a * b) / denom
  }

  direct_cols <- paste0(vcols, "_direct")
  batch_cols <- paste0(vcols, "_batch")
  cosine <- numeric(nrow(joined))
  max_abs_diff <- numeric(nrow(joined))
  for (r in seq_len(nrow(joined))) {
    vd <- as.numeric(joined[r, direct_cols, drop = TRUE])
    vb <- as.numeric(joined[r, batch_cols, drop = TRUE])
    cosine[r] <- row_cosine(vd, vb)
    max_abs_diff[r] <- max(abs(vd - vb))
  }

  comparison_df <- data.frame(
    id = as.character(joined$id),
    cosine_similarity = cosine,
    max_abs_diff = max_abs_diff,
    stringsAsFactors = FALSE
  )
  summary_df <- data.frame(
    matched_ids = nrow(comparison_df),
    mean_cosine_similarity = mean(comparison_df$cosine_similarity, na.rm = TRUE),
    min_cosine_similarity = min(comparison_df$cosine_similarity, na.rm = TRUE),
    max_abs_diff = max(comparison_df$max_abs_diff, na.rm = TRUE),
    stringsAsFactors = FALSE
  )

  list(
    summary_df = summary_df,
    comparison_df = comparison_df,
    matched_ids = nrow(comparison_df),
    vcols = vcols
  )
}
