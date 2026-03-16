resolve_inst_file <- function(rel) {
  p <- system.file(rel, package = "openalexVectorComp")
  if (nzchar(p)) return(p)
  file.path("inst", rel)
}

testthat::test_that("run_demo_openalex_quarto prepares demo project with fixtures and template", {
  td <- tempfile("ovc_demo_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project")

  out <- run_demo_openalex_quarto(
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

  testthat::expect_identical(normalizePath(out$demo_dir), normalizePath(proj))
  testthat::expect_identical(normalizePath(out$project_dir), normalizePath(file.path(proj, "project")))
  testthat::expect_false(out$rendered)
})

testthat::test_that("run_demo_openalex_quarto enforces overwrite policy", {
  td <- tempfile("ovc_demo_overwrite_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project")

  run_demo_openalex_quarto(
    demo_dir = proj,
    render = FALSE,
    backend = ovc_hf_backend(max_batch_size = 4L),
    overwrite = FALSE,
    verbose = FALSE
  )

  testthat::expect_error(
    run_demo_openalex_quarto(
      demo_dir = proj,
      render = FALSE,
      backend = ovc_hf_backend(max_batch_size = 4L),
      overwrite = FALSE,
      verbose = FALSE
    ),
    "overwrite = TRUE"
  )

  testthat::expect_no_error(
    run_demo_openalex_quarto(
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

  out <- run_demo_openalex_quarto(
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
