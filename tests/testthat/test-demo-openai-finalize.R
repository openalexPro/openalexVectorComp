make_demo_openai_workspace <- function() {
  td <- tempfile("ovc_demo_finalize_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project_openai")
  dir.create(file.path(proj, "project"), recursive = TRUE, showWarnings = FALSE)
  openalexVectorComp::embedding_backend_save(
    openalexVectorComp::embedding_backend_config(
      provider = "openai",
      model = "text-embedding-3-small"
    ),
    fn = file.path(proj, "demo_backend.yaml")
  )
  proj
}

write_demo_label_embeddings <- function(project_dir, label, df) {
  model_dir <- file.path(project_dir, "embeddings", "model_id=text-embedding-3-small")
  label_dir <- file.path(model_dir, paste0("label=", label), "batch=1")
  dir.create(label_dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(df, file.path(label_dir, "embeddings-00001.parquet"))
}

testthat::test_that("finalize_demo_openai_batch returns pending without state", {
  demo_dir <- make_demo_openai_workspace()

  out <- openalexVectorComp::finalize_demo_openai_batch(
    demo_dir = demo_dir,
    label = "corpus_batch",
    refresh_remote = TRUE,
    verbose = FALSE
  )

  testthat::expect_false(isTRUE(out$comparison_ready))
  testthat::expect_match(out$message, "No batch submission state found")
})

testthat::test_that("finalize_demo_openai_batch errors for non-openai backend yaml", {
  td <- tempfile("ovc_demo_finalize_hf_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  demo_dir <- file.path(td, "demo_project_hf")
  dir.create(file.path(demo_dir, "project"), recursive = TRUE, showWarnings = FALSE)
  openalexVectorComp::embedding_backend_save(
    openalexVectorComp::embedding_backend_config(
      provider = "hf",
      model = "BAAI/bge-small-en-v1.5"
    ),
    fn = file.path(demo_dir, "demo_backend.yaml")
  )

  testthat::expect_error(
    openalexVectorComp::finalize_demo_openai_batch(demo_dir = demo_dir, verbose = FALSE),
    "provider = 'openai'"
  )
})

testthat::test_that("finalize_demo_openai_batch writes comparison outputs when batch embeddings are present", {
  demo_dir <- make_demo_openai_workspace()
  project_dir <- file.path(demo_dir, "project")

  direct_df <- data.frame(
    id = c("A", "B"),
    text_hash = c("h1", "h2"),
    provider = "openai",
    model_id = "text-embedding-3-small",
    created_at = as.character(Sys.time()),
    V1 = c(0.1, 0.3),
    V2 = c(0.2, 0.4),
    stringsAsFactors = FALSE
  )
  batch_df <- data.frame(
    id = c("A", "B"),
    text_hash = c("h1", "h2"),
    provider = "openai",
    model_id = "text-embedding-3-small",
    created_at = as.character(Sys.time()),
    V1 = c(0.1, 0.31),
    V2 = c(0.2, 0.39),
    stringsAsFactors = FALSE
  )
  write_demo_label_embeddings(project_dir, "corpus", direct_df)
  write_demo_label_embeddings(project_dir, "corpus_batch", batch_df)

  state_file <- file.path(project_dir, "openai_batch_state_label=corpus_batch.json")
  jsonlite::write_json(
    list(
      version = 1L,
      provider = "openai",
      model_id = "text-embedding-3-small",
      label = "corpus_batch",
      corpus_name = "corpus",
      backend = list(base_url = "https://api.openai.com/v1", timeout = 60, retries = 3),
      jobs = list()
    ),
    path = state_file,
    auto_unbox = TRUE,
    pretty = TRUE
  )

  out <- testthat::with_mocked_bindings(
    openalexVectorComp::finalize_demo_openai_batch(
      demo_dir = demo_dir,
      label = "corpus_batch",
      refresh_remote = TRUE,
      verbose = FALSE
    ),
    embed_corpus_status_openai_batch = function(project_dir, label, refresh_remote) {
      data.frame(batch_index = integer(), job_id = character(), status = character(), stringsAsFactors = FALSE)
    },
    embed_corpus_collect_openai_batch = function(project_dir, backend, label, verbose) {
      list(
        state_file = state_file,
        checked_jobs = 0L,
        completed_jobs = 0L,
        downloaded_jobs = 0L,
        written_rows = 0L,
        pending_jobs = 0L,
        failed_jobs = 0L
      )
    },
    embed_corpus_submit_openai_batch = function(...) {
      stop("submit should not be called by finalize")
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_true(isTRUE(out$comparison_ready))
  testthat::expect_true(file.exists(out$comparison_parquet))
  testthat::expect_true(file.exists(out$summary_yaml))
  cmp <- arrow::read_parquet(out$comparison_parquet)
  testthat::expect_equal(nrow(cmp), 2L)
})

testthat::test_that("finalize_demo_openai_batch accepts api_key argument for token-scoped call", {
  demo_dir <- make_demo_openai_workspace()

  old <- Sys.getenv("OVC_API_TOKEN", unset = "")
  on.exit(
    if (nzchar(old)) Sys.setenv(OVC_API_TOKEN = old) else Sys.unsetenv("OVC_API_TOKEN"),
    add = TRUE
  )
  Sys.unsetenv("OVC_API_TOKEN")

  out <- testthat::with_mocked_bindings(
    openalexVectorComp::finalize_demo_openai_batch(
      demo_dir = demo_dir,
      api_key = "temp-test-key",
      label = "corpus_batch",
      refresh_remote = TRUE,
      verbose = FALSE
    ),
    embed_corpus_status_openai_batch = function(project_dir, label, refresh_remote) {
      testthat::expect_identical(Sys.getenv("OVC_API_TOKEN"), "temp-test-key")
      data.frame()
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_false(isTRUE(out$comparison_ready))
  testthat::expect_match(out$message, "No batch submission state found")
  testthat::expect_identical(Sys.getenv("OVC_API_TOKEN", unset = ""), "")
})
