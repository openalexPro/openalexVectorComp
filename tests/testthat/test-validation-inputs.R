make_tmp_scores_fixture <- function() {
  td <- tempfile("ovc_scores_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)

  scores_dir <- file.path(td, "scores")
  dir.create(scores_dir, recursive = TRUE, showWarnings = FALSE)
  scores <- data.frame(
    id = c("A", "B", "C", "D"),
    relevance_score = c(0.9, 0.7, 0.2, 0.1),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(scores, path = scores_dir, format = "parquet")

  labels_dir <- file.path(td, "labels")
  dir.create(labels_dir, recursive = TRUE, showWarnings = FALSE)
  labels <- data.frame(
    id = c("A", "B", "C", "D"),
    label = c(1L, 1L, 0L, 0L),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(labels, path = labels_dir, format = "parquet")

  list(
    root = td,
    scores_dir = scores_dir,
    labels_dir = labels_dir
  )
}

make_tmp_embeddings_no_vcols <- function() {
  td <- tempfile("ovc_emb_nov_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  emb_dir <- file.path(td, "emb")
  dir.create(emb_dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(
    data.frame(id = c("X1", "X2"), stringsAsFactors = FALSE),
    path = emb_dir,
    format = "parquet"
  )
  emb_dir
}

testthat::test_that("embedding_backend_config validates numeric inputs", {
  testthat::expect_error(
    embedding_backend_config(timeout = 0),
    "`timeout` must be a positive number."
  )
  testthat::expect_error(
    embedding_backend_config(timeout = -5),
    "`timeout` must be a positive number."
  )
  testthat::expect_error(
    embedding_backend_config(retries = -1),
    "`retries` must be >= 0."
  )
  testthat::expect_error(
    embedding_backend_config(max_batch_size = 0),
    "`max_batch_size` must be a positive integer."
  )
})

testthat::test_that("embedding_backend_save/read round-trip and legacy compatibility", {
  cfg <- embedding_backend_config(
    provider = "hf",
    base_url = "https://router.huggingface.co/hf-inference",
    model = "BAAI/bge-small-en-v1.5",
    max_batch_size = 32,
    timeout = 12,
    retries = 4
  )
  fn <- tempfile(fileext = ".yaml")
  saved <- embedding_backend_save(backend = cfg, fn = fn)
  testthat::expect_identical(saved, fn)

  back <- embedding_backend_read(fn)
  testthat::expect_identical(back$provider, cfg$provider)
  testthat::expect_identical(back$base_url, cfg$base_url)
  testthat::expect_identical(back$model, cfg$model)
  testthat::expect_identical(back$max_batch_size, cfg$max_batch_size)
  testthat::expect_identical(back$timeout, cfg$timeout)
  testthat::expect_identical(back$retries, cfg$retries)

  legacy_fn <- tempfile(fileext = ".yaml")
  yaml::write_yaml(
    list(
      model = list(id = "legacy-model"),
      backend = list(
        provider = "tei",
        base_url = "http://localhost:3000",
        embed_url = "http://localhost:3000/embed",
        max_batch_size = 64L,
        timeout = 30,
        retries = 2L
      )
    ),
    legacy_fn
  )
  legacy <- embedding_backend_read(legacy_fn)
  testthat::expect_identical(legacy$provider, "tei")
  testthat::expect_identical(legacy$model, "legacy-model")
  testthat::expect_identical(legacy$embed_url, "http://localhost:3000/embed")
})

testthat::test_that("embedding backend config applies tei_url override", {
  cfg <- embedding_backend_config(
    provider = "tei",
    base_url = "http://localhost:9999/",
    tei_url = "http://localhost:3000/embed///"
  )
  testthat::expect_identical(cfg$embed_url, "http://localhost:3000/embed")
  testthat::expect_identical(cfg$base_url, "http://localhost:3000/embed")
})

testthat::test_that("embedding_backend_info and embed_texts validate backend/texts", {
  testthat::expect_error(
    embedding_backend_info(backend = list()),
    "`backend` must be a configuration object"
  )
  testthat::expect_error(
    embedding_backend_info(backend = list(provider = "nope")),
    "Unsupported backend provider"
  )
  testthat::expect_error(
    embedding_backend_embed_texts(texts = 123),
    "`texts` must be a character vector."
  )
  testthat::expect_error(
    embedding_backend_embed_texts(texts = "a", backend = list(provider = "nope")),
    "Unsupported backend provider"
  )
  out <- embedding_backend_embed_texts(texts = character())
  testthat::expect_true(is.matrix(out))
  testthat::expect_equal(nrow(out), 0)
})

testthat::test_that("internal backend helpers handle edge cases", {
  as_matrix <- getFromNamespace(".embedding_as_matrix", "openalexVectorComp")
  batch_starts <- getFromNamespace(".embedding_batch_starts", "openalexVectorComp")
  with_retry <- getFromNamespace(".embedding_with_retry", "openalexVectorComp")
  info_hf <- getFromNamespace(".embedding_info_hf", "openalexVectorComp")

  testthat::expect_equal(as_matrix(c(1, 2, 3)), matrix(c(1, 2, 3), nrow = 1))
  testthat::expect_error(
    as_matrix(list(c(1, 2), c(1))),
    "inconsistent length"
  )
  testthat::expect_error(
    as_matrix("bad"),
    "Unsupported embedding response format."
  )

  testthat::expect_equal(batch_starts(300, 0), c(1L, 129L, 257L))

  n <- 0L
  val <- with_retry(
    backend = list(retries = 3L),
    fn = function() {
      n <<- n + 1L
      if (n < 3L) {
        stop("transient")
      }
      42L
    }
  )
  testthat::expect_identical(val, 42L)

  testthat::expect_error(
    with_retry(
      backend = list(retries = 1L),
      fn = function() stop("always")
    ),
    "Embedding request failed after retries"
  )

  hf_router <- info_hf(list(
    base_url = "https://router.huggingface.co/hf-inference/",
    model = "BAAI/bge-small-en-v1.5",
    embed_url = NULL,
    max_batch_size = NULL
  ))
  testthat::expect_match(hf_router$raw$embed_url, "/models/BAAI/bge-small-en-v1.5$")

  hf_legacy <- info_hf(list(
    base_url = "https://api-inference.huggingface.co/",
    model = "BAAI/bge-small-en-v1.5",
    embed_url = NULL,
    max_batch_size = NULL
  ))
  testthat::expect_match(hf_legacy$raw$embed_url, "/pipeline/feature-extraction/BAAI/bge-small-en-v1.5$")
})

testthat::test_that("embed_corpus validates key inputs", {
  testthat::expect_error(
    embed_corpus(project_dir = "", verbose = FALSE),
    "Parameter `project_dir` must be a non-empty directory path."
  )
  testthat::expect_error(
    embed_corpus(project_dir = tempdir(), batch_size = 0, verbose = FALSE),
    "`batch_size` must be a positive number."
  )
  testthat::expect_error(
    embed_corpus(project_dir = tempdir(), backend = list(), verbose = FALSE),
    "`backend` must come from embedding_backend_config"
  )
  testthat::expect_error(
    embed_corpus(project_dir = tempdir(), corpus_name = "", verbose = FALSE),
    "`corpus_name` must be a non-empty character string."
  )
  testthat::expect_error(
    embed_corpus(project_dir = tempdir(), save_text = NA, verbose = FALSE),
    "`save_text` must be TRUE or FALSE."
  )
  testthat::expect_error(
    embed_corpus(project_dir = tempdir(), dry_run = NA, verbose = FALSE),
    "`dry_run` must be TRUE or FALSE."
  )
  testthat::expect_error(
    embed_corpus(project_dir = tempdir(), label = "", verbose = FALSE),
    "`label` must be a non-empty character string."
  )

  td <- tempfile("ovc_corpus_bad_")
  dir.create(file.path(td, "corpus"), recursive = TRUE, showWarnings = FALSE)
  bad <- data.frame(id = "W1", title = "Only title", stringsAsFactors = FALSE)
  arrow::write_dataset(bad, path = file.path(td, "corpus"), format = "parquet")

  testthat::expect_error(
    embed_corpus(project_dir = td, verbose = FALSE),
    "Dataset must contain columns: abstract"
  )

  td2 <- tempfile("ovc_corpus_custom_")
  dir.create(file.path(td2, "papers"), recursive = TRUE, showWarnings = FALSE)
  ok <- data.frame(
    id = c("W1", "W2"),
    title = c("A", "B"),
    abstract = c("Alpha", "Beta"),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(ok, path = file.path(td2, "papers"), format = "parquet")

  backend <- embedding_backend_config(provider = "hf", model = "BAAI/bge-small-en-v1.5")
  model_dir <- testthat::with_mocked_bindings(
    embed_corpus(
      project_dir = td2,
      corpus_name = "papers",
      backend = backend,
      batch_size = 10,
      delete_existing = TRUE,
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      matrix(
        rep(c(1, 2), times = length(texts)),
        nrow = length(texts),
        byrow = TRUE,
        dimnames = list(NULL, c("V1", "V2"))
      )
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_true(dir.exists(file.path(model_dir, "label=papers")))
})

testthat::test_that("fit_ridge and distance_ridge fail cleanly on invalid embeddings", {
  emb_dir <- make_tmp_embeddings_no_vcols()
  out_rds <- file.path(tempfile("ovc_fit_"), "ridge.rds")

  testthat::expect_error(
    fit_ridge(
      embeddings = emb_dir,
      reference_label = "reference",
      output = out_rds,
      verbose = FALSE
    ),
    "has no `label` partition"
  )

  proj <- tempfile("ovc_ridge_bad_")
  dir.create(file.path(proj, "embeddings"), recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(
    data.frame(id = c("A", "B"), V1 = c(1, -1), stringsAsFactors = FALSE),
    path = file.path(proj, "embeddings"),
    format = "parquet"
  )
  testthat::expect_error(
    distance_ridge(project_dir = proj, reference_label = "reference", corpus_label = "corpus", verbose = FALSE),
    "has no `label` partition"
  )
})

testthat::test_that("calibrate_threshold validates missing columns and labels", {
  fx <- make_tmp_scores_fixture()

  testthat::expect_error(
    calibrate_threshold(
      scores_parquet = fx$scores_dir,
      score_col = "not_here",
      labels_parquet = fx$labels_dir,
      verbose = FALSE
    ),
    "`scores_parquet` must contain columns `id` and `not_here`."
  )

  labels_bad <- file.path(fx$root, "labels_bad")
  dir.create(labels_bad, recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(
    data.frame(id = c("A", "B"), bad = c(1, 0), stringsAsFactors = FALSE),
    path = labels_bad,
    format = "parquet"
  )
  testthat::expect_error(
    calibrate_threshold(
      scores_parquet = fx$scores_dir,
      score_col = "relevance_score",
      labels_parquet = labels_bad,
      verbose = FALSE
    ),
    "`labels_parquet` must have columns: id, label"
  )
  labels_none <- file.path(fx$root, "labels_none")
  dir.create(labels_none, recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(
    data.frame(id = c("ZZ1", "ZZ2"), label = c(1L, 0L), stringsAsFactors = FALSE),
    path = labels_none,
    format = "parquet"
  )
  testthat::expect_error(
    calibrate_threshold(
      scores_parquet = fx$scores_dir,
      score_col = "relevance_score",
      labels_parquet = labels_none,
      verbose = FALSE
    ),
    "No labeled rows found in scores dataset."
  )
})

testthat::test_that("calibrate_threshold succeeds with labels_parquet and explicit thresholds", {
  fx <- make_tmp_scores_fixture()
  labels_dir <- file.path(fx$root, "labels_ok")
  dir.create(labels_dir, recursive = TRUE, showWarnings = FALSE)
  labels <- data.frame(
    id = c("A", "B", "C", "D"),
    label = c(1L, 1L, 0L, 0L),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(labels, path = labels_dir, format = "parquet")

  out <- calibrate_threshold(
    scores_parquet = fx$scores_dir,
    score_col = "relevance_score",
    labels_parquet = labels_dir,
    metric = "precision_at_recall",
    recall_min = 0.5,
    thresholds = c(0.2, 0.5, 0.8),
    verbose = FALSE
  )

  testthat::expect_true(is.list(out))
  testthat::expect_true(is.finite(out$th))
  testthat::expect_equal(length(out$thresholds), 3L)
})
