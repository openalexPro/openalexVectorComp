resolve_inst_file <- function(rel) {
  p <- system.file(rel, package = "openalexVectorComp")
  if (nzchar(p)) return(p)
  file.path("inst", rel)
}

testthat::test_that("run_demo_openalex prepares demo project with fixtures and template", {
  td <- tempfile("ovc_demo_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project")

  out <- run_demo_openalex(
    demo_dir = proj,
    render = FALSE,
    backend = ovc_hf_backend(max_batch_size = 4L),
    max_corpus = 25,
    max_reference = 7,
    overwrite = FALSE,
    verbose = FALSE
  )

  testthat::expect_true(dir.exists(proj))
  testthat::expect_true(dir.exists(file.path(proj, "project")))
  testthat::expect_true(dir.exists(file.path(proj, "project", "corpus")))
  testthat::expect_true(dir.exists(file.path(proj, "project", "reference_corpus")))
  testthat::expect_true(file.exists(file.path(proj, "openalex_demo_analysis.qmd")))
  testthat::expect_true(file.exists(file.path(proj, "demo_backend.yaml")))

  corpus_df <- arrow::read_parquet(file.path(proj, "project", "corpus", "corpus_small.parquet"))
  ref_df <- arrow::read_parquet(file.path(proj, "project", "reference_corpus", "reference_small.parquet"))

  testthat::expect_lte(nrow(corpus_df), 25)
  testthat::expect_lte(nrow(ref_df), 7)
  testthat::expect_true(all(c("id", "title", "abstract") %in% names(corpus_df)))
  testthat::expect_true(all(c("id", "title", "abstract") %in% names(ref_df)))

  qmd <- readLines(file.path(proj, "openalex_demo_analysis.qmd"), warn = FALSE)
  qmd_text <- paste(qmd, collapse = "\n")
  testthat::expect_match(qmd_text, "embed_corpus\\(")
  testthat::expect_match(qmd_text, "distance_reference_cosine\\(")
  testthat::expect_match(qmd_text, "score_reference_cosine\\(")
  testthat::expect_match(qmd_text, "distance_ridge\\(")
  testthat::expect_match(qmd_text, "score_ridge\\(")
  testthat::expect_match(qmd_text, "demo_finalize_openai_batch\\(")
  testthat::expect_match(qmd_text, "Run later: openalexVectorComp::demo_finalize_openai_batch")

  testthat::expect_identical(normalizePath(out$demo_dir), normalizePath(proj))
  testthat::expect_identical(normalizePath(out$project_dir), normalizePath(file.path(proj, "project")))
  testthat::expect_false(out$rendered)
})

testthat::test_that("run_demo_openalex enforces overwrite policy", {
  td <- tempfile("ovc_demo_overwrite_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project")

  run_demo_openalex(
    demo_dir = proj,
    render = FALSE,
    backend = ovc_hf_backend(max_batch_size = 4L),
    overwrite = FALSE,
    verbose = FALSE
  )

  testthat::expect_error(
    run_demo_openalex(
      demo_dir = proj,
      render = FALSE,
      backend = ovc_hf_backend(max_batch_size = 4L),
      overwrite = FALSE,
      verbose = FALSE
    ),
    "overwrite = TRUE"
  )

  testthat::expect_no_error(
    run_demo_openalex(
      demo_dir = proj,
      render = FALSE,
      backend = ovc_hf_backend(max_batch_size = 4L),
      overwrite = TRUE,
      max_corpus = 15,
      max_reference = 5,
      verbose = FALSE
    )
  )

  corpus_df <- arrow::read_parquet(file.path(proj, "project", "corpus", "corpus_small.parquet"))
  ref_df <- arrow::read_parquet(file.path(proj, "project", "reference_corpus", "reference_small.parquet"))
  testthat::expect_lte(nrow(corpus_df), 15)
  testthat::expect_lte(nrow(ref_df), 5)
})

testthat::test_that("demo fixtures in inst/ovc_demo satisfy required schema and caps", {
  corpus_fixture <- resolve_inst_file("ovc_demo/project/corpus/corpus_small.parquet")
  reference_fixture <- resolve_inst_file("ovc_demo/project/reference_corpus/reference_small.parquet")

  testthat::expect_true(file.exists(corpus_fixture))
  testthat::expect_true(file.exists(reference_fixture))

  corpus_df <- arrow::read_parquet(corpus_fixture)
  reference_df <- arrow::read_parquet(reference_fixture)

  testthat::expect_lte(nrow(corpus_df), 100)
  testthat::expect_lte(nrow(reference_df), 10)
  testthat::expect_true(all(c("id", "title", "abstract") %in% names(corpus_df)))
  testthat::expect_true(all(c("id", "title", "abstract") %in% names(reference_df)))
})

testthat::test_that("optional demo render works when quarto and token are available", {
  ovc_skip_if_no_hf()
  quarto_bin <- Sys.which("quarto")
  testthat::skip_if_not(nzchar(quarto_bin), "Quarto is not available")
  qv <- try(system2(quarto_bin, "--version", stdout = TRUE, stderr = TRUE), silent = TRUE)
  testthat::skip_if(inherits(qv, "try-error"), "Quarto executable is not runnable in this environment.")

  td <- tempfile("ovc_demo_render_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project")

  out <- run_demo_openalex(
    demo_dir = proj,
    render = TRUE,
    backend = ovc_hf_backend(max_batch_size = 4L),
    max_corpus = 5,
    max_reference = 3,
    overwrite = FALSE,
    verbose = FALSE
  )

  testthat::expect_true(isTRUE(out$rendered))
  testthat::expect_true(file.exists(file.path(proj, "openalex_demo_analysis.html")))
})

testthat::test_that("run_demo_openai requires api_key and configures OpenAI backend", {
  td <- tempfile("ovc_demo_openai_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project_openai")

  testthat::expect_error(
    run_demo_openai(
      api_key = "",
      demo_dir = proj,
      render = FALSE,
      verbose = FALSE
    ),
    "api_key"
  )

  out <- run_demo_openai(
    api_key = "test-key",
    demo_dir = proj,
    render = FALSE,
    max_corpus = 12,
    max_reference = 4,
    overwrite = FALSE,
    verbose = FALSE
  )

  testthat::expect_true(file.exists(file.path(proj, "openai_demo_analysis.qmd")))
  testthat::expect_true(file.exists(file.path(proj, "demo_backend.yaml")))

  backend <- openalexVectorComp::backend_read(
    file.path(proj, "demo_backend.yaml")
  )
  testthat::expect_identical(tolower(as.character(backend$provider)), "openai")
  testthat::expect_identical(as.character(backend$model), "text-embedding-3-small")
  testthat::expect_false(out$rendered)
})

testthat::test_that("run_demo_openalex validates its arguments", {
  d <- tempfile("ovc_demo_val_")
  testthat::expect_error(run_demo_openalex(demo_dir = ""), "`demo_dir` must be a non-empty")
  testthat::expect_error(run_demo_openalex(demo_dir = d, render = NA), "`render` must be TRUE or FALSE")
  testthat::expect_error(run_demo_openalex(demo_dir = d, max_corpus = 0), "`max_corpus` must be a positive")
  testthat::expect_error(run_demo_openalex(demo_dir = d, max_reference = Inf), "`max_reference` must be a positive")
  testthat::expect_error(run_demo_openalex(demo_dir = d, overwrite = "yes"), "`overwrite` must be TRUE or FALSE")
  testthat::expect_error(run_demo_openalex(demo_dir = d, quarto_file = ""), "`quarto_file` must be a non-empty")
  testthat::expect_error(
    run_demo_openalex(demo_dir = d, render = FALSE, backend = "hf"),
    "`backend` must be NULL or a backend config"
  )
  testthat::expect_false(dir.exists(d))
})

testthat::test_that("run_demo_openalex defaults to the HF backend and reports when verbose", {
  d <- file.path(tempfile("ovc_demo_default_"), "demo")
  testthat::expect_message(
    out <- run_demo_openalex(demo_dir = d, render = FALSE, max_corpus = 3, max_reference = 2, verbose = TRUE),
    "Demo workspace prepared at"
  )
  b <- backend_read(out$backend_yaml)
  testthat::expect_identical(b$provider, "hf")
  testthat::expect_identical(b$model, "BAAI/bge-small-en-v1.5")
  testthat::expect_equal(nrow(arrow::read_parquet(file.path(out$corpus_dir, "corpus_small.parquet"))), 3L)
})

testthat::test_that("run_demo_openalex render requires a token for hosted providers", {
  ovc_local_token(NA)
  d <- tempfile("ovc_demo_notoken_")
  testthat::expect_error(
    run_demo_openalex(demo_dir = d, render = TRUE, backend = ovc_hf_backend(), verbose = FALSE),
    "`OVC_API_TOKEN` is required for provider `hf`"
  )
})

testthat::test_that("run_demo_openalex render calls quarto in the demo dir", {
  testthat::skip_if_not_installed("quarto")
  d <- tempfile("ovc_demo_render_mock_")
  wd_before <- getwd()
  seen <- NULL
  testthat::local_mocked_bindings(
    quarto_render = function(input, ...) {
      seen <<- list(input = input, wd = getwd())
      invisible(NULL)
    },
    .package = "quarto"
  )

  msgs <- testthat::capture_messages(
    out <- run_demo_openalex(
      demo_dir = d,
      render = TRUE,
      backend = backend_config(provider = "tei", model = "m"),
      max_corpus = 2,
      max_reference = 2,
      verbose = TRUE
    )
  )
  testthat::expect_match(paste(msgs, collapse = ""), "Rendering Quarto analysis: openalex_demo_analysis.qmd")
  testthat::expect_true(out$rendered)
  testthat::expect_identical(seen$input, "openalex_demo_analysis.qmd")
  testthat::expect_identical(normalizePath(seen$wd), normalizePath(d))
  testthat::expect_identical(getwd(), wd_before)
})

testthat::test_that("run_demo_openai validates model, restores token and prints commands", {
  d <- tempfile("ovc_demo_openai_cmd_")
  testthat::expect_error(
    run_demo_openai(api_key = "k", demo_dir = d, model = " ", render = FALSE),
    "`model` must be a non-empty"
  )

  ovc_local_token("previous-token")
  msgs <- testthat::capture_messages(
    out <- run_demo_openai(api_key = " k2 ", demo_dir = d, render = FALSE, max_corpus = 2, max_reference = 1, verbose = TRUE)
  )
  txt <- paste(msgs, collapse = "")
  testthat::expect_match(txt, "OpenAI batch status command:")
  testthat::expect_match(txt, "batch_status_openai\\(")
  testthat::expect_match(txt, "OpenAI batch finalize command:")
  testthat::expect_match(out$openai_batch_finalize_command, "demo_finalize_openai_batch\\(")
  testthat::expect_match(out$openai_batch_status_command, "label = \"corpus_batch\"")
  testthat::expect_identical(Sys.getenv("OVC_API_TOKEN"), "previous-token")
})

testthat::test_that("demo fixture helpers report missing files and columns", {
  copy_fixture <- ovc_ns(".ovc_copy_demo_fixture")
  demo_path <- ovc_ns(".ovc_demo_path")
  td <- tempfile("ovc_fixture_")
  dir.create(td)

  testthat::expect_error(
    copy_fixture(file.path(td, "missing.parquet"), file.path(td, "out"), "x.parquet", 5),
    "Demo fixture does not exist"
  )
  src <- file.path(td, "bad.parquet")
  arrow::write_parquet(data.frame(id = "a", title = "t"), src)
  testthat::expect_error(
    copy_fixture(src, file.path(td, "out"), "x.parquet", 5),
    "missing required columns: abstract"
  )

  testthat::expect_error(
    demo_path("ovc_demo/does-not-exist.txt"),
    "Could not resolve installed or local inst path"
  )

  dir.create(file.path(td, "inst", "local_only"), recursive = TRUE)
  file.create(file.path(td, "inst", "local_only", "f.txt"))
  old <- setwd(td)
  on.exit(setwd(old), add = TRUE)
  testthat::expect_identical(demo_path("local_only/f.txt"), file.path("inst", "local_only", "f.txt"))
})
