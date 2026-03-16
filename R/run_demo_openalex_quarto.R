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
#'   `file.path(getwd(), "demo_project")`.
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
  demo_dir = file.path(getwd(), "demo_project"),
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

  template_src <- .ovc_demo_path("ovc_demo/openalex_demo_analysis.qmd")
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
