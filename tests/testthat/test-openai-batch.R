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
  openalexVectorComp::backend_config(
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
    openalexVectorComp::batch_submit_openai(
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
    openalexVectorComp::batch_submit_openai(
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
      openalexVectorComp::batch_submit_openai(
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
    openalexVectorComp::batch_submit_openai(
      project_dir = proj,
      backend = backend,
      max_requests_per_job = 50001,
      verbose = FALSE
    ),
    "<= 50000"
  )
  testthat::expect_error(
    openalexVectorComp::batch_submit_openai(
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
    openalexVectorComp::batch_submit_openai(
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
    openalexVectorComp::batch_collect_openai(
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
    openalexVectorComp::batch_collect_openai(
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

# Helpers for state/collect tests ------------------------------------------

write_openai_state <- function(project_dir, label = "corpus", jobs = list(), model_id = "text-embedding-3-small") {
  state_file <- file.path(project_dir, paste0("openai_batch_state_label=", label, ".json"))
  jsonlite::write_json(
    list(
      version = 1L,
      provider = "openai",
      model_id = model_id,
      label = label,
      backend = list(base_url = "https://api.openai.test/v1", timeout = 30, retries = 0),
      jobs = jobs
    ),
    path = state_file,
    auto_unbox = TRUE,
    null = "null",
    pretty = TRUE
  )
  state_file
}

testthat::test_that("batch input validation rejects each invalid argument", {
  validate <- ovc_ns(".ovc_validate_openai_batch_inputs")
  args <- list(
    project_dir = tempdir(),
    backend = fake_openai_backend(),
    corpus_name = "corpus",
    label = "corpus",
    batch_size = 10,
    text_preprocessor = identity,
    cleaner_args = list(),
    save_text = TRUE,
    max_requests_per_job = 10,
    max_job_bytes = 1000,
    completion_window = "24h"
  )
  call_with <- function(...) {
    a <- args
    a[names(list(...))] <- list(...)
    do.call(validate, a)
  }

  testthat::expect_null(call_with())
  testthat::expect_error(call_with(project_dir = ""), "`project_dir` must be a non-empty")
  testthat::expect_error(
    call_with(backend = backend_config(provider = "hf")),
    "must be an OpenAI backend"
  )
  testthat::expect_error(call_with(corpus_name = " "), "`corpus_name` must be a non-empty")
  testthat::expect_error(call_with(label = ""), "`label` must be a non-empty")
  testthat::expect_error(call_with(batch_size = 0), "`batch_size` must be a positive number")
  testthat::expect_error(call_with(text_preprocessor = "x"), "`text_preprocessor` must be a function")
  testthat::expect_error(call_with(cleaner_args = "x"), "`cleaner_args` must be a list")
  testthat::expect_error(call_with(save_text = NA), "`save_text` must be TRUE or FALSE")
  testthat::expect_error(call_with(max_requests_per_job = "a"), "`max_requests_per_job` must be numeric scalar")
  testthat::expect_error(call_with(max_job_bytes = Inf), "`max_job_bytes` must be numeric scalar")
  testthat::expect_error(call_with(completion_window = "1h"), "must currently be '24h'")
})

testthat::test_that("state helpers read, default, lock and index consistently", {
  state_read <- ovc_ns(".ovc_openai_state_read")
  state_file_fun <- ovc_ns(".ovc_openai_state_file")
  lock_acquire <- ovc_ns(".ovc_openai_lock_acquire")
  next_index <- ovc_ns(".ovc_openai_state_next_batch_index")
  active_ids <- ovc_ns(".ovc_openai_state_active_custom_ids")
  is_terminal <- ovc_ns(".ovc_openai_is_terminal")
  to_df <- ovc_ns(".ovc_openai_state_to_df")

  td <- tempfile("ovc_state_")
  dir.create(td)

  testthat::expect_identical(
    basename(state_file_fun(td, " a/b ")),
    "openai_batch_state_label=a_b.json"
  )

  fresh <- state_read(file.path(td, "nope.json"), model_id = "m", backend = list(base_url = "u"))
  testthat::expect_identical(fresh$model_id, "m")
  testthat::expect_identical(fresh$backend$base_url, "u")
  testthat::expect_equal(fresh$backend$timeout, 60)
  testthat::expect_length(fresh$jobs, 0L)

  empty <- file.path(td, "empty.json")
  file.create(empty)
  testthat::expect_error(state_read(empty), "State file is empty")

  no_jobs <- file.path(td, "nojobs.json")
  writeLines('{"version": 1}', no_jobs)
  testthat::expect_identical(state_read(no_jobs)$jobs, list())

  lock <- file.path(td, "x.lock")
  testthat::expect_true(lock_acquire(lock))
  testthat::expect_false(lock_acquire(lock))

  testthat::expect_identical(next_index(list(jobs = list())), 1L)
  testthat::expect_identical(next_index(list(jobs = list(list(job_id = "a")))), 1L)
  testthat::expect_identical(
    next_index(list(jobs = list(list(batch_index = 2L), list(batch_index = 5L)))),
    6L
  )

  mf <- file.path(td, "manifest.parquet")
  arrow::write_parquet(data.frame(custom_id = c("c1", "c2", "c1")), mf)
  jobs <- list(
    list(ingested_at = "2026-01-01", manifest_parquet = mf),
    list(ingested_at = "", manifest_parquet = file.path(td, "missing.parquet")),
    list(ingested_at = "", manifest_parquet = ""),
    list(ingested_at = "", manifest_parquet = mf)
  )
  testthat::expect_identical(active_ids(list(jobs = list())), character())
  testthat::expect_identical(active_ids(list(jobs = jobs)), c("c1", "c2"))

  testthat::expect_identical(
    is_terminal(c("completed", "FAILED", "expired", "cancelled", "in_progress")),
    c(TRUE, TRUE, TRUE, TRUE, FALSE)
  )

  testthat::expect_identical(to_df(list(jobs = list())), data.frame())
  df <- to_df(list(jobs = list(
    list(batch_index = 1L, job_id = "j1", status = "completed", row_count_submitted = 3L),
    list(job_id = "j2")
  )))
  testthat::expect_identical(df$job_id, c("j1", "j2"))
  testthat::expect_identical(df$batch_index, c(1L, NA_integer_))
  testthat::expect_identical(df$row_count_submitted, c(3L, 0L))
})

testthat::test_that("job update from remote keeps old ids and records errors", {
  update <- ovc_ns(".ovc_openai_job_update_from_remote")
  job <- list(status = "validating", output_file_id = "of_old", error_file_id = "")

  same <- update(job, list())
  testthat::expect_identical(same$status, "validating")
  testthat::expect_identical(same$output_file_id, "of_old")
  testthat::expect_null(same$error_message)

  upd <- update(job, list(
    status = "failed",
    error_file_id = "ef_1",
    errors = list(data = list(list(code = "invalid_request")))
  ))
  testthat::expect_identical(upd$status, "failed")
  testthat::expect_identical(upd$output_file_id, "of_old")
  testthat::expect_identical(upd$error_file_id, "ef_1")
  testthat::expect_match(upd$error_message, "invalid_request")
})

testthat::test_that("output JSONL parsing handles both shapes and rejects bad files", {
  parse <- ovc_ns(".ovc_openai_parse_output_jsonl")
  td <- tempfile("ovc_parse_")
  dir.create(td)
  write_lines <- function(x) {
    f <- tempfile(tmpdir = td, fileext = ".jsonl")
    writeLines(x, f)
    f
  }

  testthat::expect_error(parse(write_lines(c("", "  "))), "output is empty")

  ok <- parse(write_lines(c(
    '{"custom_id":"a","response":{"body":{"data":[{"embedding":[1,2]}]}}}',
    '{"custom_id":"","embedding":[9,9]}',
    '{"custom_id":"b","embedding":[3,4]}',
    '{"custom_id":"c","response":{"status_code":500}}'
  )))
  testthat::expect_identical(ok$custom_id, c("a", "b"))
  testthat::expect_identical(ok$embeddings, list(c(1, 2), c(3, 4)))

  testthat::expect_error(
    parse(write_lines('{"custom_id":"a","error":{"message":"x"}}')),
    "No embeddings could be parsed"
  )
  testthat::expect_error(
    parse(write_lines(c('{"custom_id":"a","embedding":[1]}', '{"custom_id":"a","embedding":[2]}'))),
    "Duplicate `custom_id`"
  )
})

testthat::test_that("embedding output builder joins manifest and validates it", {
  build <- ovc_ns(".ovc_openai_build_embeddings_output")
  manifest <- data.frame(
    custom_id = c("c1", "c2"),
    id = c("W1", "W2"),
    text_hash = c("h1", "h2"),
    text = c("t1", "t2"),
    stringsAsFactors = FALSE
  )
  parsed <- list(custom_id = c("c2", "c1"), embeddings = list(c(3, 4), c(1, 2)))

  out <- build(parsed, manifest, provider = "openai", model_id = "m")
  testthat::expect_identical(out$id, c("W2", "W1"))
  testthat::expect_identical(out$text, c("t2", "t1"))
  testthat::expect_identical(out$model_id, c("m", "m"))
  testthat::expect_equal(out$V1, c(3, 1))
  testthat::expect_equal(out$V2, c(4, 2))

  testthat::expect_error(
    build(parsed, manifest[, c("custom_id", "id")], "openai", "m"),
    "Manifest must include"
  )
  testthat::expect_error(
    build(list(custom_id = "zz", embeddings = list(1)), manifest, "openai", "m"),
    "missing in manifest"
  )
})

testthat::test_that("next embed batch index scans batch=<n> directories", {
  next_idx <- ovc_ns(".ovc_next_embed_batch_index")
  td <- tempfile("ovc_bidx_")
  testthat::expect_identical(next_idx(td), 1L)
  dir.create(td)
  testthat::expect_identical(next_idx(td), 1L)
  dir.create(file.path(td, "other"))
  testthat::expect_identical(next_idx(td), 1L)
  dir.create(file.path(td, "batch=2"))
  dir.create(file.path(td, "batch=10"))
  testthat::expect_identical(next_idx(td), 11L)
})

testthat::test_that("submit validates preprocessor output contract", {
  proj <- make_openai_batch_project(2)
  backend <- fake_openai_backend()
  submit <- function(pp) {
    testthat::with_mocked_bindings(
      openalexVectorComp::batch_submit_openai(
        project_dir = proj,
        backend = backend,
        text_preprocessor = pp,
        verbose = FALSE
      ),
      .openai_batch_upload_file = function(backend, file_path) stop("no upload expected"),
      .openai_batch_create = function(...) stop("no create expected"),
      .package = "openalexVectorComp"
    )
  }

  testthat::expect_error(submit(function(df) "x"), "must return a data frame")
  testthat::expect_error(
    submit(function(df) data.frame(id = df$id, text = "t")),
    "must contain columns: text_hash"
  )
  testthat::expect_error(
    submit(function(df) data.frame(id = "ZZ", text = "t", text_hash = "h")),
    "ids not present"
  )
  testthat::expect_error(
    submit(function(df) data.frame(id = rep(df$id[1], 2), text = "t", text_hash = c("a", "b"))),
    "duplicated ids"
  )

  # Rows with empty text are dropped; nothing left to submit.
  out <- submit(function(df) data.frame(id = df$id, text = "", text_hash = "h"))
  testthat::expect_identical(out$submitted_jobs, 0L)
  testthat::expect_identical(out$submitted_rows, 0L)
})

testthat::test_that("submit skips queued rows, honours delete_existing and reports progress", {
  proj <- make_openai_batch_project(3)
  backend <- fake_openai_backend()
  n_create <- 0L
  do_submit <- function(...) {
    testthat::with_mocked_bindings(
      openalexVectorComp::batch_submit_openai(project_dir = proj, backend = backend, ...),
      .openai_batch_upload_file = function(backend, file_path) "file_x",
      .openai_batch_create = function(backend, input_file_id, completion_window = "24h") {
        n_create <<- n_create + 1L
        list(id = paste0("job_", n_create), status = "validating")
      },
      .package = "openalexVectorComp"
    )
  }

  testthat::expect_message(
    first <- do_submit(verbose = TRUE),
    "Submitted 1 OpenAI batch job"
  )
  testthat::expect_identical(first$submitted_rows, 3L)

  # Same rows are already queued in an un-ingested job: nothing new.
  testthat::expect_message(
    second <- do_submit(verbose = TRUE),
    "No new/changed rows to submit"
  )
  testthat::expect_identical(second$submitted_jobs, 0L)
  state <- jsonlite::fromJSON(first$state_file, simplifyVector = FALSE)
  testthat::expect_length(state$jobs, 1L)

  # delete_existing wipes state and label embeddings and resubmits everything.
  stale <- file.path(first$model_dir, "label=corpus", "batch=1", "embeddings-00001.parquet")
  dir.create(dirname(stale), recursive = TRUE)
  file.create(stale)
  third <- do_submit(delete_existing = TRUE, verbose = FALSE)
  testthat::expect_false(file.exists(stale))
  testthat::expect_identical(third$submitted_rows, 3L)
  state3 <- jsonlite::fromJSON(third$state_file, simplifyVector = FALSE)
  testthat::expect_length(state3$jobs, 1L)
  testthat::expect_identical(state3$jobs[[1]]$job_id, "job_2")
  testthat::expect_identical(state3$jobs[[1]]$batch_index, 1L)

  meta <- yaml::read_yaml(file.path(first$model_dir, "embed_model.yaml"))
  testthat::expect_identical(meta$submission_mode, "openai_batch")
  testthat::expect_identical(meta$embedding_label, "corpus")
})

testthat::test_that("submit warns on byte split, and errors on missing dir, columns or lock", {
  proj <- make_openai_batch_project(3)
  backend <- fake_openai_backend()
  mocks <- function(code) {
    testthat::with_mocked_bindings(
      code,
      .openai_batch_upload_file = function(backend, file_path) "file_x",
      .openai_batch_create = function(backend, input_file_id, completion_window = "24h") {
        list(id = "job", status = "validating")
      },
      .package = "openalexVectorComp"
    )
  }

  testthat::expect_message(
    mocks(openalexVectorComp::batch_submit_openai(
      project_dir = proj, backend = backend, max_job_bytes = 300, verbose = TRUE
    )),
    "split jobs by byte-size limits"
  )

  testthat::expect_error(
    openalexVectorComp::batch_submit_openai(
      project_dir = file.path(tempdir(), "does-not-exist-ovc"),
      backend = backend,
      verbose = FALSE
    ),
    "`project_dir` does not exist"
  )

  proj2 <- make_openai_batch_project(1)
  arrow::write_parquet(
    data.frame(id = "A", title = "t"),
    file.path(proj2, "corpus", "corpus.parquet")
  )
  testthat::expect_error(
    openalexVectorComp::batch_submit_openai(project_dir = proj2, backend = backend, verbose = FALSE),
    "Dataset must contain columns: abstract"
  )

  proj3 <- make_openai_batch_project(1)
  file.create(file.path(proj3, "openai_batch_state_label=corpus.json.lock"))
  testthat::expect_error(
    mocks(openalexVectorComp::batch_submit_openai(project_dir = proj3, backend = backend, verbose = FALSE)),
    "State lock exists"
  )
})

testthat::test_that("batch_status_openai validates input and refreshes non-terminal jobs", {
  proj <- make_openai_batch_project(1)

  testthat::expect_error(batch_status_openai(proj, label = " "), "`label` must be non-empty")
  testthat::expect_error(batch_status_openai(proj, refresh_remote = NA), "TRUE or FALSE")
  testthat::expect_identical(batch_status_openai(proj), data.frame())

  state_file <- write_openai_state(proj, jobs = list(
    list(job_id = "j_pending", batch_index = 1L, status = "in_progress", ingested_at = ""),
    list(job_id = "j_done", batch_index = 2L, status = "completed", ingested_at = ""),
    list(job_id = "j_ingested", batch_index = 3L, status = "in_progress", ingested_at = "2026-01-01")
  ))

  asked <- character()
  seen_backend <- NULL
  df <- testthat::with_mocked_bindings(
    batch_status_openai(proj, label = "corpus", refresh_remote = TRUE),
    .openai_batch_get = function(backend, job_id) {
      asked <<- c(asked, job_id)
      seen_backend <<- backend
      list(id = job_id, status = "completed", output_file_id = "of_1")
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_identical(asked, "j_pending")
  testthat::expect_identical(seen_backend$base_url, "https://api.openai.test/v1")
  testthat::expect_identical(seen_backend$timeout, 30)
  testthat::expect_identical(df$status, c("completed", "completed", "in_progress"))
  saved <- jsonlite::fromJSON(state_file, simplifyVector = FALSE)
  testthat::expect_identical(saved$jobs[[1]]$output_file_id, "of_1")

  df2 <- testthat::with_mocked_bindings(
    batch_status_openai(proj, refresh_remote = FALSE),
    .openai_batch_get = function(...) stop("should not refresh"),
    .package = "openalexVectorComp"
  )
  testthat::expect_identical(nrow(df2), 3L)
})

testthat::test_that("batch_collect_openai validates inputs, state and lock", {
  proj <- make_openai_batch_project(1)
  backend <- fake_openai_backend()

  testthat::expect_error(
    batch_collect_openai(proj, backend = backend_config(provider = "hf"), verbose = FALSE),
    "must be an OpenAI backend"
  )
  testthat::expect_error(
    batch_collect_openai(proj, backend = backend, label = "", verbose = FALSE),
    "`label` must be non-empty"
  )
  testthat::expect_error(
    batch_collect_openai(proj, backend = backend, verbose = FALSE),
    "No OpenAI batch state found"
  )

  state_file <- write_openai_state(proj)
  file.create(paste0(state_file, ".lock"))
  testthat::expect_error(
    batch_collect_openai(proj, backend = backend, verbose = FALSE),
    "State lock exists"
  )
  unlink(paste0(state_file, ".lock"))

  write_openai_state(proj, model_id = NULL)
  no_model <- backend
  no_model["model"] <- list(NULL)
  testthat::expect_error(
    batch_collect_openai(proj, backend = no_model, verbose = FALSE),
    "Could not determine model id"
  )
  testthat::expect_false(file.exists(paste0(state_file, ".lock")))
})

testthat::test_that("batch_collect_openai counts failed, pending and output-less jobs", {
  proj <- make_openai_batch_project(1)
  backend <- fake_openai_backend()
  state_file <- write_openai_state(proj, jobs = list(
    list(job_id = "j_fail", status = "in_progress", ingested_at = ""),
    list(job_id = "j_wait", status = "validating", ingested_at = ""),
    list(job_id = "j_nofile", status = "in_progress", ingested_at = "")
  ))
  remote <- list(
    j_fail = list(status = "failed", errors = list(message = "boom")),
    j_wait = list(status = "in_progress"),
    j_nofile = list(status = "completed")
  )

  testthat::expect_message(
    out <- testthat::with_mocked_bindings(
      batch_collect_openai(proj, backend = backend, verbose = TRUE),
      .openai_batch_get = function(backend, job_id) remote[[job_id]],
      .openai_batch_download_file = function(...) stop("nothing to download"),
      .package = "openalexVectorComp"
    ),
    "No completed OpenAI batch jobs ready"
  )
  testthat::expect_identical(out$checked_jobs, 3L)
  testthat::expect_identical(out$failed_jobs, 1L)
  testthat::expect_identical(out$pending_jobs, 1L)
  testthat::expect_identical(out$completed_jobs, 1L)
  testthat::expect_identical(out$downloaded_jobs, 0L)

  saved <- jsonlite::fromJSON(state_file, simplifyVector = FALSE)
  testthat::expect_identical(saved$jobs[[1]]$status, "failed")
  testthat::expect_match(saved$jobs[[1]]$error_message, "boom")
  testthat::expect_identical(saved$jobs[[2]]$status, "in_progress")
  testthat::expect_identical(saved$jobs[[3]]$error_message, "Completed job has no output_file_id.")
})

testthat::test_that("batch_collect_openai reports collected rows when verbose", {
  proj <- make_openai_batch_project(2)
  backend <- fake_openai_backend()
  submit <- testthat::with_mocked_bindings(
    openalexVectorComp::batch_submit_openai(project_dir = proj, backend = backend, verbose = FALSE),
    .openai_batch_upload_file = function(backend, file_path) "file_1",
    .openai_batch_create = function(...) list(id = "job_1", status = "in_progress"),
    .package = "openalexVectorComp"
  )
  state <- jsonlite::fromJSON(submit$state_file, simplifyVector = FALSE)
  manifest <- arrow::read_parquet(state$jobs[[1]]$manifest_parquet)
  lines <- vapply(manifest$custom_id, function(cid) {
    jsonlite::toJSON(list(custom_id = cid, embedding = c(1, 0)), auto_unbox = TRUE)
  }, character(1))

  testthat::expect_message(
    out <- testthat::with_mocked_bindings(
      batch_collect_openai(proj, backend = backend, verbose = TRUE),
      .openai_batch_get = function(backend, job_id) list(status = "completed", output_file_id = "of"),
      .openai_batch_download_file = function(backend, file_id, dest) {
        writeLines(lines, dest)
        invisible(dest)
      },
      .package = "openalexVectorComp"
    ),
    "Collected 1 completed job\\(s\\), wrote 2 embedding row\\(s\\)"
  )
  testthat::expect_identical(out$written_rows, 2L)
})

testthat::test_that("submit skips rows already embedded with the same text hash", {
  proj <- make_openai_batch_project(2)
  backend <- fake_openai_backend()
  prep <- clean_abstract_for_embedding(arrow::read_parquet(file.path(proj, "corpus", "corpus.parquet")))
  label_dir <- file.path(proj, "embeddings", "model_id=text-embedding-3-small", "label=corpus", "batch=1")
  dir.create(label_dir, recursive = TRUE)
  arrow::write_parquet(
    data.frame(id = prep$id, text_hash = prep$text_hash, V1 = 1),
    file.path(label_dir, "embeddings-00001.parquet")
  )
  out <- testthat::with_mocked_bindings(
    openalexVectorComp::batch_submit_openai(project_dir = proj, backend = backend, verbose = FALSE),
    .openai_batch_upload_file = function(...) stop("no upload expected"),
    .openai_batch_create = function(...) stop("no create expected"),
    .package = "openalexVectorComp"
  )
  testthat::expect_identical(out$submitted_rows, 0L)
})

testthat::test_that("collect removes superseded rows from older shards", {
  proj <- make_openai_batch_project(2)
  backend <- fake_openai_backend()
  label_dir <- file.path(proj, "embeddings", "model_id=text-embedding-3-small", "label=corpus")
  # Older shard: stale W1/W2 (hash differs, so both get resubmitted) plus W9.
  dir.create(file.path(label_dir, "batch=1"), recursive = TRUE)
  arrow::write_parquet(
    data.frame(id = c("W1", "W2", "W9"), text_hash = "old", V1 = 0, V2 = 0),
    file.path(label_dir, "batch=1", "embeddings-00001.parquet")
  )
  submit <- testthat::with_mocked_bindings(
    openalexVectorComp::batch_submit_openai(project_dir = proj, backend = backend, verbose = FALSE),
    .openai_batch_upload_file = function(backend, file_path) "file_1",
    .openai_batch_create = function(...) list(id = "job_1", status = "in_progress"),
    .package = "openalexVectorComp"
  )
  testthat::expect_identical(submit$submitted_rows, 2L)
  state <- jsonlite::fromJSON(submit$state_file, simplifyVector = FALSE)
  manifest <- arrow::read_parquet(state$jobs[[1]]$manifest_parquet)
  lines <- vapply(manifest$custom_id, function(cid) {
    jsonlite::toJSON(list(custom_id = cid, embedding = c(1, 1)), auto_unbox = TRUE)
  }, character(1))
  testthat::with_mocked_bindings(
    batch_collect_openai(proj, backend = backend, verbose = FALSE),
    .openai_batch_get = function(backend, job_id) list(status = "completed", output_file_id = "of"),
    .openai_batch_download_file = function(backend, file_id, dest) {
      writeLines(lines, dest)
      invisible(dest)
    },
    .package = "openalexVectorComp"
  )
  d <- as.data.frame(arrow::open_dataset(label_dir))
  testthat::expect_identical(sort(d$id), c("W1", "W2", "W9"))
  testthat::expect_identical(d$batch[d$id == "W9"], 1L)
  testthat::expect_true(all(d$batch[d$id != "W9"] == 2L))
  testthat::expect_true(all(d$V1[d$id != "W9"] == 1))
  testthat::expect_false(any(d$text_hash[d$id != "W9"] == "old"))
})
