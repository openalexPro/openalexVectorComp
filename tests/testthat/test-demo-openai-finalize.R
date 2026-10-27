make_demo_openai_workspace <- function() {
  td <- tempfile("ovc_demo_finalize_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  proj <- file.path(td, "demo_project_openai")
  dir.create(file.path(proj, "project"), recursive = TRUE, showWarnings = FALSE)
  openalexVectorComp::backend_save(
    openalexVectorComp::backend_config(
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

testthat::test_that("demo_finalize_openai_batch returns pending without state", {
  demo_dir <- make_demo_openai_workspace()

  out <- openalexVectorComp::demo_finalize_openai_batch(
    demo_dir = demo_dir,
    label = "corpus_batch",
    refresh_remote = TRUE,
    verbose = FALSE
  )

  testthat::expect_false(isTRUE(out$comparison_ready))
  testthat::expect_match(out$message, "No batch submission state found")
})

testthat::test_that("demo_finalize_openai_batch errors for non-openai backend yaml", {
  td <- tempfile("ovc_demo_finalize_hf_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  demo_dir <- file.path(td, "demo_project_hf")
  dir.create(file.path(demo_dir, "project"), recursive = TRUE, showWarnings = FALSE)
  openalexVectorComp::backend_save(
    openalexVectorComp::backend_config(
      provider = "hf",
      model = "BAAI/bge-small-en-v1.5"
    ),
    fn = file.path(demo_dir, "demo_backend.yaml")
  )

  testthat::expect_error(
    openalexVectorComp::demo_finalize_openai_batch(demo_dir = demo_dir, verbose = FALSE),
    "provider = 'openai'"
  )
})

testthat::test_that("demo_finalize_openai_batch writes comparison outputs when batch embeddings are present", {
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
    openalexVectorComp::demo_finalize_openai_batch(
      demo_dir = demo_dir,
      label = "corpus_batch",
      refresh_remote = TRUE,
      verbose = FALSE
    ),
    batch_status_openai = function(project_dir, label, refresh_remote) {
      data.frame(batch_index = integer(), job_id = character(), status = character(), stringsAsFactors = FALSE)
    },
    batch_collect_openai = function(project_dir, backend, label, verbose) {
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
    batch_submit_openai = function(...) {
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

testthat::test_that("demo_finalize_openai_batch accepts api_key argument for token-scoped call", {
  demo_dir <- make_demo_openai_workspace()

  old <- Sys.getenv("OVC_API_TOKEN", unset = "")
  on.exit(
    if (nzchar(old)) Sys.setenv(OVC_API_TOKEN = old) else Sys.unsetenv("OVC_API_TOKEN"),
    add = TRUE
  )
  Sys.unsetenv("OVC_API_TOKEN")

  out <- testthat::with_mocked_bindings(
    openalexVectorComp::demo_finalize_openai_batch(
      demo_dir = demo_dir,
      api_key = "temp-test-key",
      label = "corpus_batch",
      refresh_remote = TRUE,
      verbose = FALSE
    ),
    batch_status_openai = function(project_dir, label, refresh_remote) {
      testthat::expect_identical(Sys.getenv("OVC_API_TOKEN"), "temp-test-key")
      data.frame()
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_false(isTRUE(out$comparison_ready))
  testthat::expect_match(out$message, "No batch submission state found")
  testthat::expect_identical(Sys.getenv("OVC_API_TOKEN", unset = ""), "")
})

testthat::test_that("demo_finalize_openai_batch validates arguments and workspace", {
  testthat::expect_error(demo_finalize_openai_batch(demo_dir = ""), "`demo_dir` must be a non-empty")
  testthat::expect_error(demo_finalize_openai_batch(demo_dir = "x", label = ""), "`label` must be a non-empty")
  testthat::expect_error(demo_finalize_openai_batch(demo_dir = "x", api_key = ""), "`api_key` must be NULL or")
  testthat::expect_error(demo_finalize_openai_batch(demo_dir = "x", refresh_remote = NA), "`refresh_remote` must be")
  testthat::expect_error(demo_finalize_openai_batch(demo_dir = "x", verbose = "no"), "`verbose` must be")

  td <- tempfile("ovc_finalize_missing_")
  dir.create(td)
  testthat::expect_error(demo_finalize_openai_batch(td, verbose = FALSE), "Missing backend config")
  backend_save(backend_config(provider = "openai"), fn = file.path(td, "demo_backend.yaml"))
  testthat::expect_error(demo_finalize_openai_batch(td, verbose = FALSE), "Missing demo project directory")

  demo_dir <- make_demo_openai_workspace()
  emb <- file.path(demo_dir, "project", "embeddings")
  dir.create(file.path(emb, "model_id=a"), recursive = TRUE)
  dir.create(file.path(emb, "model_id=b"), recursive = TRUE)
  testthat::expect_error(
    demo_finalize_openai_batch(demo_dir, verbose = FALSE),
    "Expected exactly one model_id directory"
  )
})

testthat::test_that("demo_finalize_openai_batch reports pending batches and restores the token", {
  demo_dir <- make_demo_openai_workspace()
  project_dir <- file.path(demo_dir, "project")
  jsonlite::write_json(
    list(
      version = 1L,
      provider = "openai",
      model_id = "text-embedding-3-small",
      label = "corpus_batch",
      backend = list(base_url = "https://api.openai.test/v1", timeout = 60, retries = 0),
      jobs = list()
    ),
    path = file.path(project_dir, "openai_batch_state_label=corpus_batch.json"),
    auto_unbox = TRUE
  )

  ovc_local_token("outer-token")
  testthat::expect_message(
    out <- demo_finalize_openai_batch(demo_dir, api_key = "inner", verbose = TRUE),
    "Batch still pending"
  )
  testthat::expect_false(out$comparison_ready)
  testthat::expect_identical(out$collect$checked_jobs, 0L)
  testthat::expect_identical(Sys.getenv("OVC_API_TOKEN"), "outer-token")
})

testthat::test_that("demo_finalize_openai_batch announces a written comparison when verbose", {
  demo_dir <- make_demo_openai_workspace()
  project_dir <- file.path(demo_dir, "project")
  df <- data.frame(id = c("A", "B"), V1 = c(1, 0), V2 = c(0, 1))
  write_demo_label_embeddings(project_dir, "corpus", df)
  write_demo_label_embeddings(project_dir, "corpus_batch", df)
  file.create(file.path(project_dir, "openai_batch_state_label=corpus_batch.json"))

  testthat::expect_message(
    out <- testthat::with_mocked_bindings(
      demo_finalize_openai_batch(demo_dir, verbose = TRUE),
      batch_status_openai = function(...) data.frame(),
      batch_collect_openai = function(...) list(downloaded_jobs = 0L),
      .package = "openalexVectorComp"
    ),
    "Batch comparison written successfully"
  )
  testthat::expect_true(out$comparison_ready)
  testthat::expect_equal(out$summary_df$mean_cosine_similarity, 1)
  summary <- yaml::read_yaml(out$summary_yaml)
  testthat::expect_identical(summary$matched_ids, 2L)
})

testthat::test_that(".ovc_compare_direct_vs_batch validates inputs and handles zero vectors", {
  compare <- ovc_ns(".ovc_compare_direct_vs_batch")
  mk <- function(direct, batch) {
    demo_dir <- make_demo_openai_workspace()
    project_dir <- file.path(demo_dir, "project")
    write_demo_label_embeddings(project_dir, "corpus", direct)
    write_demo_label_embeddings(project_dir, "corpus_batch", batch)
    function() compare(project_dir, "model_id=text-embedding-3-small", batch_label = "corpus_batch")
  }
  ok <- data.frame(id = c("A", "B"), V1 = c(1, 0), V2 = c(0, 1))
  empty <- ok[0, ]

  testthat::expect_error(mk(empty, ok)(), "Direct embeddings are empty")
  testthat::expect_error(mk(ok, empty)(), "Batch embeddings are empty")
  testthat::expect_error(
    mk(ok, data.frame(id = c("A", "B"), W1 = 1))(),
    "Could not find common embedding columns"
  )
  testthat::expect_error(
    mk(ok, data.frame(id = c("X", "Y"), V1 = 1, V2 = 1))(),
    "No overlapping ids"
  )

  res <- mk(
    data.frame(id = c("A", "B"), V1 = c(0, 3), V2 = c(0, 4)),
    data.frame(id = c("A", "B"), V1 = c(1, 3), V2 = c(0, 4.5))
  )()
  cmp <- res$comparison_df[order(res$comparison_df$id), ]
  testthat::expect_true(is.na(cmp$cosine_similarity[1]))
  testthat::expect_equal(cmp$max_abs_diff, c(1, 0.5))
  testthat::expect_identical(res$matched_ids, 2L)
  testthat::expect_identical(res$vcols, c("V1", "V2"))
})
