make_tmp_corpus_project <- function() {
  td <- tempfile("ovc_embed_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  corpus_dir <- file.path(td, "corpus")
  dir.create(corpus_dir, recursive = TRUE, showWarnings = FALSE)
  corpus <- data.frame(
    id = c("W1", "W2"),
    title = c("Alpha", "Beta"),
    abstract = c("A abstract", "B abstract"),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(corpus, path = corpus_dir, format = "parquet")
  td
}

testthat::test_that("embed_texts forwards to embedding backend adapter", {
  seen <- NULL
  out <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_texts(
      texts = c("a", "b"),
      backend = list(provider = "hf")
    ),
    embedding_backend_embed_texts = function(texts, backend) {
      seen <<- list(texts = texts, backend = backend)
      matrix(c(1, 2, 3, 4), nrow = 2, byrow = TRUE)
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_equal(out, matrix(c(1, 2, 3, 4), nrow = 2, byrow = TRUE))
  testthat::expect_identical(seen$texts, c("a", "b"))
  testthat::expect_identical(seen$backend$provider, "hf")
})

testthat::test_that("HF/OpenAI/TEI adapter embedding functions handle batching", {
  hf_fun <- getFromNamespace(".embedding_embed_texts_hf", "openalexVectorComp")
  oa_fun <- getFromNamespace(".embedding_embed_texts_openai", "openalexVectorComp")
  tei_fun <- getFromNamespace(".embedding_embed_texts_tei", "openalexVectorComp")

  i <- 0L
  hf <- testthat::with_mocked_bindings(
    hf_fun(
      texts = c("a", "b", "c"),
      backend = list(
        provider = "hf",
        base_url = "https://router.huggingface.co/hf-inference",
        model = "BAAI/bge-small-en-v1.5",
        max_batch_size = 2L,
        retries = 0L
      )
    ),
    .embedding_with_retry = function(backend, fn) {
      i <<- i + 1L
      if (i == 1L) {
        list(c(1, 0), c(0, 1))
      } else {
        list(c(1, 1))
      }
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_equal(dim(hf), c(3L, 2L))
  testthat::expect_identical(colnames(hf), c("V1", "V2"))

  i <- 0L
  oa <- testthat::with_mocked_bindings(
    oa_fun(
      texts = c("a", "b", "c"),
      backend = list(
        provider = "openai",
        base_url = "https://api.openai.com/v1",
        model = "text-embedding-3-small",
        max_batch_size = 2L,
        retries = 0L
      )
    ),
    .embedding_with_retry = function(backend, fn) {
      i <<- i + 1L
      if (i == 1L) {
        list(data = list(
          list(embedding = c(1, 2)),
          list(embedding = c(3, 4))
        ))
      } else {
        list(data = list(list(embedding = c(5, 6))))
      }
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_equal(dim(oa), c(3L, 2L))
  testthat::expect_identical(colnames(oa), c("V1", "V2"))

  i <- 0L
  tei <- testthat::with_mocked_bindings(
    tei_fun(
      texts = c("a", "b", "c"),
      backend = list(
        provider = "tei",
        base_url = "http://localhost:3000",
        model = "dummy-model",
        max_batch_size = 2L,
        retries = 0L
      )
    ),
    .embedding_probe_tei = function(embed_url) {
      list(
        model = list(id = "dummy-model", requested_id = "dummy-model", embedding_dim = 2L),
        server = list(max_client_batch_size = 2L, embed_url = "http://localhost:3000/embed")
      )
    },
    .embedding_with_retry = function(backend, fn) {
      i <<- i + 1L
      if (i == 1L) {
        list(c(1, 1), c(2, 2))
      } else {
        list(c(3, 3))
      }
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_equal(dim(tei), c(3L, 2L))
  testthat::expect_identical(colnames(tei), c("V1", "V2"))
})

testthat::test_that("adapter functions error on malformed embedding payloads", {
  hf_fun <- getFromNamespace(".embedding_embed_texts_hf", "openalexVectorComp")
  oa_fun <- getFromNamespace(".embedding_embed_texts_openai", "openalexVectorComp")

  testthat::expect_error(
    testthat::with_mocked_bindings(
      hf_fun(
        texts = c("a", "b"),
        backend = list(
          provider = "hf",
          base_url = "https://router.huggingface.co/hf-inference",
          model = "BAAI/bge-small-en-v1.5",
          max_batch_size = 2L,
          retries = 0L
        )
      ),
      .embedding_with_retry = function(backend, fn) list(c(1, 2, 3)),
      .package = "openalexVectorComp"
    ),
    "Embedding count mismatch"
  )

  testthat::expect_error(
    testthat::with_mocked_bindings(
      oa_fun(
        texts = c("a"),
        backend = list(
          provider = "openai",
          base_url = "https://api.openai.com/v1",
          model = "text-embedding-3-small",
          max_batch_size = 2L,
          retries = 0L
        )
      ),
      .embedding_with_retry = function(backend, fn) list(data = NULL),
      .package = "openalexVectorComp"
    ),
    "did not contain `data`"
  )
})

testthat::test_that("embed_corpus respects delete_existing and skip unchanged rows", {
  proj <- make_tmp_corpus_project()
  backend <- openalexVectorComp::embedding_backend_config(provider = "hf")

  model_dir <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus(
      project_dir = proj,
      backend = backend,
      batch_size = 2,
      delete_existing = FALSE,
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      matrix(
        rep(seq_along(texts), each = 2L),
        nrow = length(texts),
        byrow = TRUE,
        dimnames = list(NULL, c("V1", "V2"))
      )
    },
    .package = "openalexVectorComp"
  )

  batch_files <- list.files(model_dir, pattern = "embeddings-.*[.]parquet$", recursive = TRUE, full.names = TRUE)
  testthat::expect_length(batch_files, 1L)

  marker <- file.path(model_dir, "to_be_deleted.txt")
  file.create(marker)
  testthat::expect_true(file.exists(marker))

  model_dir2 <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus(
      project_dir = proj,
      backend = backend,
      batch_size = 2,
      delete_existing = FALSE,
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      matrix(
        rep(seq_along(texts), each = 2L),
        nrow = length(texts),
        byrow = TRUE,
        dimnames = list(NULL, c("V1", "V2"))
      )
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_identical(model_dir2, model_dir)
  batch_files_2 <- list.files(model_dir, pattern = "embeddings-.*[.]parquet$", recursive = TRUE, full.names = TRUE)
  testthat::expect_length(batch_files_2, 1L)
  testthat::expect_true(file.exists(marker))

  model_dir3 <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus(
      project_dir = proj,
      backend = backend,
      batch_size = 2,
      delete_existing = TRUE,
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      matrix(
        rep(seq_along(texts), each = 2L),
        nrow = length(texts),
        byrow = TRUE,
        dimnames = list(NULL, c("V1", "V2"))
      )
    },
    .package = "openalexVectorComp"
  )
  testthat::expect_identical(model_dir3, model_dir)
  testthat::expect_false(file.exists(marker))
})

testthat::test_that("embed_corpus accepts custom text_preprocessor and cleaner_args", {
  proj <- make_tmp_corpus_project()
  backend <- openalexVectorComp::embedding_backend_config(provider = "hf")
  seen_suffix <- NULL

  my_preprocessor <- function(df, suffix = "X") {
    text <- paste0("Title: ", df$title, " ", suffix)
    data.frame(
      id = as.character(df$id),
      text = text,
      text_hash = vapply(text, digest::digest, character(1), algo = "xxhash64", serialize = FALSE),
      text_quality = "custom",
      stringsAsFactors = FALSE
    )
  }

  model_dir <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus(
      project_dir = proj,
      backend = backend,
      batch_size = 2,
      delete_existing = FALSE,
      text_preprocessor = function(df, suffix) {
        seen_suffix <<- suffix
        my_preprocessor(df, suffix = suffix)
      },
      cleaner_args = list(suffix = "YY"),
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      matrix(1, nrow = length(texts), ncol = 2, dimnames = list(NULL, c("V1", "V2")))
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_identical(seen_suffix, "YY")
  ds <- arrow::open_dataset(
    model_dir,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  testthat::expect_true("text" %in% names(ds))
  testthat::expect_true("text_quality" %in% names(ds))
  meta <- yaml::read_yaml(file.path(model_dir, "embed_model.yaml"))
  testthat::expect_true(is.list(meta$text_preprocessor))
  testthat::expect_identical(meta$text_preprocessor$name, "user_defined")

  model_dir_no_text <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus(
      project_dir = proj,
      backend = backend,
      batch_size = 2,
      delete_existing = TRUE,
      text_preprocessor = my_preprocessor,
      save_text = FALSE,
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      matrix(1, nrow = length(texts), ncol = 2, dimnames = list(NULL, c("V1", "V2")))
    },
    .package = "openalexVectorComp"
  )
  ds_no_text <- arrow::open_dataset(
    model_dir_no_text,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  testthat::expect_false("text" %in% names(ds_no_text))
})

testthat::test_that("embed_corpus validates text_preprocessor output contract", {
  proj <- make_tmp_corpus_project()
  backend <- openalexVectorComp::embedding_backend_config(provider = "hf")

  bad_missing <- function(df) data.frame(id = df$id, text = "x", stringsAsFactors = FALSE)
  testthat::expect_error(
    testthat::with_mocked_bindings(
      openalexVectorComp::embed_corpus(
        project_dir = proj,
        backend = backend,
        batch_size = 2,
        text_preprocessor = bad_missing,
        verbose = FALSE
      ),
      embed_texts = function(texts, backend) matrix(1, nrow = length(texts), ncol = 2),
      .package = "openalexVectorComp"
    ),
    "must contain columns: .*text_hash"
  )

  bad_extra_id <- function(df) data.frame(
    id = c(as.character(df$id), "NOT_IN_BATCH"),
    text = c(rep("Title: A", nrow(df)), "Title: B"),
    text_hash = c(rep("h", nrow(df)), "h2"),
    stringsAsFactors = FALSE
  )
  testthat::expect_error(
    testthat::with_mocked_bindings(
      openalexVectorComp::embed_corpus(
        project_dir = proj,
        backend = backend,
        batch_size = 2,
        text_preprocessor = bad_extra_id,
        verbose = FALSE
      ),
      embed_texts = function(texts, backend) matrix(1, nrow = length(texts), ncol = 2),
      .package = "openalexVectorComp"
    ),
    "returned ids not present"
  )
})

testthat::test_that("embed_corpus dry_run preprocesses but does not write embeddings", {
  proj <- make_tmp_corpus_project()
  backend <- openalexVectorComp::embedding_backend_config(provider = "hf")
  called <- FALSE

  model_dir <- testthat::with_mocked_bindings(
    openalexVectorComp::embed_corpus(
      project_dir = proj,
      backend = backend,
      batch_size = 2,
      dry_run = TRUE,
      verbose = FALSE
    ),
    embed_texts = function(texts, backend) {
      called <<- TRUE
      stop("embed_texts should not be called in dry_run")
    },
    .package = "openalexVectorComp"
  )

  testthat::expect_false(called)
  testthat::expect_false(dir.exists(model_dir))

  preview_file <- file.path(
    proj,
    sprintf("dry_run_cleaning_model_id=%s.parquet", gsub("/", "_", backend$model, fixed = TRUE))
  )
  testthat::expect_true(file.exists(preview_file))
  preview <- arrow::read_parquet(preview_file)
  testthat::expect_equal(nrow(preview), 2L)
  testthat::expect_true(all(c(
    "id",
    "title_original",
    "abstract_original",
    "cleaned_title",
    "cleaned_abstract",
    "text",
    "text_hash",
    "would_embed"
  ) %in% names(preview)))
  testthat::expect_equal(sort(preview$id), c("W1", "W2"))
  testthat::expect_true(all(preview$would_embed))

  emb_root <- file.path(proj, "embeddings")
  if (dir.exists(emb_root)) {
    batch_files <- list.files(
      emb_root,
      pattern = "embeddings-.*[.]parquet$",
      recursive = TRUE,
      full.names = TRUE
    )
    testthat::expect_length(batch_files, 0L)
  } else {
    testthat::expect_false(dir.exists(emb_root))
  }
})
