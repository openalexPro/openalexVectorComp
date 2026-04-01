make_openai_batch_project <- function(n = 6) {
  td <- tempfile("ovc_openai_batch_")
  dir.create(td, recursive = TRUE)
  corpus_dir <- file.path(td, "corpus")
  dir.create(corpus_dir, recursive = TRUE)
  df <- data.frame(
    id = paste0("W", seq_len(n)),
    title = paste("Title", seq_len(n)),
    abstract = paste("Abstract", seq_len(n)),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(df, file.path(corpus_dir, "corpus.parquet"))
  td
}

fake_openai_backend <- function() {
  openalexVectorComp::embedding_backend_config(
    provider = "openai",
    base_url = "https://api.openai.com/v1",
    model = "text-embedding-3-small",
    retries = 0
  )
}

testthat::test_that("submit splits jobs by request count", {
  proj <- make_openai_batch_project(5)
  backend <- fake_openai_backend()
  uploads <- 0L
  creates <- 0L
  uploaded_lines <- integer()

  out <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus_submit_openai_batch(
      project_dir = proj,
      backend = backend,
      max_requests_per_job = 2,
      max_job_bytes = 150 * 1024^2,
      verbose = FALSE
    ),
    .openai_batch_upload_file = function(backend, file_path) {
      uploads <<- uploads + 1L
      uploaded_lines <<- c(uploaded_lines, length(readLines(file_path, warn = FALSE)))
      paste0("file_", uploads)
    },
    .openai_batch_create = function(backend, input_file_id, completion_window = "24h") {
      creates <<- creates + 1L
      list(id = paste0("job_", creates), status = "validating")
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_equal(out$submitted_jobs, 3L)
  testthat::expect_equal(out$submitted_rows, 5L)
  testthat::expect_equal(uploads, 3L)
  testthat::expect_equal(creates, 3L)
  testthat::expect_true(all(uploaded_lines > 0L))

  state <- jsonlite::fromJSON(out$state_file, simplifyVector = FALSE)
  testthat::expect_length(state$jobs, 3L)
})

testthat::test_that("submit splits jobs by byte size", {
  proj <- make_openai_batch_project(3)
  backend <- fake_openai_backend()

  # Inflate one field enough that two records do not fit in tiny byte budget.
  df <- data.frame(
    id = c("A", "B", "C"),
    title = c("t", "t", "t"),
    abstract = c(strrep("x", 400), strrep("y", 400), strrep("z", 400)),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(df, file.path(proj, "corpus", "corpus.parquet"))

  uploads <- 0L
  out <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus_submit_openai_batch(
      project_dir = proj,
      backend = backend,
      max_requests_per_job = 50000,
      max_job_bytes = 1200,
      verbose = FALSE
    ),
    .openai_batch_upload_file = function(backend, file_path) {
      uploads <<- uploads + 1L
      paste0("file_", uploads)
    },
    .openai_batch_create = function(backend, input_file_id, completion_window = "24h") {
      list(id = paste0("job_", input_file_id), status = "validating")
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_gt(out$submitted_jobs, 1L)
})

testthat::test_that("single oversized request line errors before submission", {
  proj <- make_openai_batch_project(1)
  backend <- fake_openai_backend()

  df <- data.frame(
    id = "A",
    title = "t",
    abstract = strrep("x", 10000),
    stringsAsFactors = FALSE
  )
  arrow::write_parquet(df, file.path(proj, "corpus", "corpus.parquet"))

  uploads <- 0L
  testthat::expect_error(
    testthat::with_mocked_bindings(
      openalexVectorComp::embed_corpus_submit_openai_batch(
        project_dir = proj,
        backend = backend,
        max_job_bytes = 500,
        verbose = FALSE
      ),
      .openai_batch_upload_file = function(backend, file_path) {
        uploads <<- uploads + 1L
        "file_1"
      },
      .openai_batch_create = function(backend, input_file_id, completion_window = "24h") {
        list(id = "job_1", status = "validating")
      },
      .package = "openalexVectorComp"
    ),
    "Single request exceeds"
  )
  testthat::expect_equal(uploads, 0L)
})

testthat::test_that("limit validation rejects invalid caps", {
  proj <- make_openai_batch_project(1)
  backend <- fake_openai_backend()

  testthat::expect_error(
    openalexVectorComp::embed_corpus_submit_openai_batch(
      project_dir = proj,
      backend = backend,
      max_requests_per_job = 50001,
      verbose = FALSE
    ),
    "<= 50000"
  )
  testthat::expect_error(
    openalexVectorComp::embed_corpus_submit_openai_batch(
      project_dir = proj,
      backend = backend,
      max_job_bytes = 210 * 1024^2,
      verbose = FALSE
    ),
    "<= 200 MB"
  )
})

testthat::test_that("collect ingests completed jobs and is idempotent", {
  proj <- make_openai_batch_project(2)
  backend <- fake_openai_backend()

  submit <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus_submit_openai_batch(
      project_dir = proj,
      backend = backend,
      max_requests_per_job = 50000,
      verbose = FALSE
    ),
    .openai_batch_upload_file = function(backend, file_path) "file_1",
    .openai_batch_create = function(backend, input_file_id, completion_window = "24h") {
      list(id = "job_1", status = "in_progress")
    },
    .package = "openalexVectorComp"
  )

  fake_output <- tempfile("ovc_openai_output_", fileext = ".jsonl")
  state <- jsonlite::fromJSON(submit$state_file, simplifyVector = FALSE)
  manifest <- arrow::read_parquet(state$jobs[[1]]$manifest_parquet)

  lines <- vapply(seq_len(nrow(manifest)), function(i) {
    jsonlite::toJSON(list(
      custom_id = as.character(manifest$custom_id[[i]]),
      response = list(
        body = list(
          data = list(
            list(embedding = c(i * 0.1, i * 0.2, i * 0.3))
          )
        )
      )
    ), auto_unbox = TRUE)
  }, character(1))
  writeLines(lines, fake_output)

  downloaded <- 0L
  out1 <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus_collect_openai_batch(
      project_dir = proj,
      backend = backend,
      label = "corpus",
      verbose = FALSE
    ),
    .openai_batch_get = function(backend, job_id) {
      list(id = job_id, status = "completed", output_file_id = "of_1")
    },
    .openai_batch_download_file = function(backend, file_id, dest) {
      downloaded <<- downloaded + 1L
      file.copy(fake_output, dest, overwrite = TRUE)
      invisible(dest)
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_equal(out1$downloaded_jobs, 1L)
  testthat::expect_equal(downloaded, 1L)

  model_dir <- file.path(proj, "embeddings", "model_id=text-embedding-3-small", "label=corpus")
  files <- list.files(model_dir, pattern = "embeddings-.*[.]parquet$", recursive = TRUE, full.names = TRUE)
  testthat::expect_length(files, 1L)

  out2 <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus_collect_openai_batch(
      project_dir = proj,
      backend = backend,
      label = "corpus",
      verbose = FALSE
    ),
    .openai_batch_get = function(backend, job_id) {
      list(id = job_id, status = "completed", output_file_id = "of_1")
    },
    .openai_batch_download_file = function(backend, file_id, dest) {
      downloaded <<- downloaded + 1L
      file.copy(fake_output, dest, overwrite = TRUE)
      invisible(dest)
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_equal(out2$downloaded_jobs, 0L)
  files2 <- list.files(model_dir, pattern = "embeddings-.*[.]parquet$", recursive = TRUE, full.names = TRUE)
  testthat::expect_length(files2, 1L)
})
