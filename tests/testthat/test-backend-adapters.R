# Offline tests for backend adapters: HTTP is mocked with httr2.

testthat::test_that("backend_specter2_tei builds a TEI backend and validates inputs", {
  b <- backend_specter2_tei()
  testthat::expect_identical(b$provider, "tei")
  testthat::expect_identical(b$embed_url, "http://localhost:8080/embed")
  testthat::expect_identical(b$base_url, "http://localhost:8080/embed")
  testthat::expect_identical(b$model, "allenai/specter2_proximity_merged")

  b2 <- backend_specter2_tei(port = 9001, host = "gpu-box", model = "m")
  testthat::expect_identical(b2$embed_url, "http://gpu-box:9001/embed")
  testthat::expect_identical(b2$model, "m")

  testthat::expect_error(backend_specter2_tei(port = 0), "`port` must be a positive integer")
  testthat::expect_error(
    suppressWarnings(backend_specter2_tei(port = "x")),
    "`port` must be a positive integer"
  )
  testthat::expect_error(backend_specter2_tei(host = ""), "`host` must be a non-empty string")
  testthat::expect_error(backend_specter2_tei(host = c("a", "b")), "`host` must be a non-empty string")
})

testthat::test_that("backend_read handles flat embed_url, invalid and unknown YAML", {
  fn <- tempfile(fileext = ".yaml")
  yaml::write_yaml(
    list(
      provider = "tei",
      base_url = "http://localhost:3000",
      model = "m",
      embed_url = "http://tei.local:8080/embed/"
    ),
    fn
  )
  cfg <- backend_read(fn)
  testthat::expect_identical(cfg$embed_url, "http://tei.local:8080/embed")
  testthat::expect_identical(cfg$base_url, "http://tei.local:8080/embed")

  fn_hf <- tempfile(fileext = ".yaml")
  yaml::write_yaml(
    list(provider = "hf", embed_url = "https://example.test/custom/"),
    fn_hf
  )
  cfg_hf <- backend_read(fn_hf)
  testthat::expect_identical(cfg_hf$embed_url, "https://example.test/custom")
  # Non-TEI providers keep their base_url.
  testthat::expect_identical(cfg_hf$base_url, "https://router.huggingface.co/hf-inference")

  fn_scalar <- tempfile(fileext = ".yaml")
  writeLines("just a string", fn_scalar)
  testthat::expect_error(backend_read(fn_scalar), "does not contain a valid YAML object")

  fn_unknown <- tempfile(fileext = ".yaml")
  yaml::write_yaml(list(something = "else"), fn_unknown)
  testthat::expect_error(backend_read(fn_unknown), "recognized backend configuration format")
})

testthat::test_that("backend_save and backend_embed_texts validate backend objects", {
  testthat::expect_error(
    backend_save(backend = list(), fn = tempfile()),
    "`backend` must be a configuration object"
  )
  testthat::expect_error(
    backend_embed_texts(texts = "a", backend = list()),
    "`backend` must be a configuration object"
  )
})

testthat::test_that(".embedding_request_base adds bearer token only when set", {
  req_base <- ovc_ns(".embedding_request_base")

  ovc_local_token(NA)
  req <- req_base("https://example.test/embed", list())
  testthat::expect_identical(httr2::req_get_method(req), "POST")
  testthat::expect_null(httr2::req_get_headers(req, "reveal")$Authorization)

  ovc_local_token("tok-1")
  req2 <- req_base("https://example.test/embed", list())
  testthat::expect_identical(
    httr2::req_get_headers(req2, "reveal")$Authorization,
    "Bearer tok-1"
  )
})

testthat::test_that(".embedding_as_matrix passes matrices and converts data frames", {
  as_matrix <- ovc_ns(".embedding_as_matrix")
  m <- matrix(1:4, nrow = 2)
  testthat::expect_identical(as_matrix(m), m)
  df <- data.frame(a = c(1, 2), b = c(3, 4))
  testthat::expect_equal(unname(as_matrix(df)), matrix(c(1, 2, 3, 4), nrow = 2))
})

testthat::test_that("HF backend posts batched inputs and builds the embedding matrix", {
  ovc_local_token("hf-tok")
  calls <- list()
  httr2::local_mocked_responses(function(req) {
    body <- httr2::req_get_body(req)
    calls[[length(calls) + 1L]] <<- list(
      url = httr2::req_get_url(req),
      auth = httr2::req_get_headers(req, "reveal")$Authorization,
      inputs = unlist(body$inputs)
    )
    n <- length(body$inputs)
    httr2::response_json(body = lapply(seq_len(n), function(i) c(i, 10 * i)))
  })

  backend <- backend_config(provider = "hf", max_batch_size = 2, retries = 0)
  out <- backend_embed_texts(c("a", "b", "c"), backend)

  testthat::expect_equal(dim(out), c(3L, 2L))
  testthat::expect_identical(colnames(out), c("V1", "V2"))
  testthat::expect_equal(unname(out[, 1]), c(1, 2, 1))
  testthat::expect_length(calls, 2L)
  testthat::expect_identical(
    calls[[1]]$url,
    "https://router.huggingface.co/hf-inference/models/BAAI/bge-small-en-v1.5"
  )
  testthat::expect_identical(calls[[1]]$auth, "Bearer hf-tok")
  testthat::expect_identical(calls[[1]]$inputs, c("a", "b"))
  testthat::expect_identical(calls[[2]]$inputs, "c")
})

testthat::test_that("OpenAI backend posts model and input and parses data", {
  ovc_local_token("oa-tok")
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- list(url = httr2::req_get_url(req), body = httr2::req_get_body(req))
    httr2::response_json(body = list(
      object = "list",
      data = list(
        list(index = 0L, embedding = c(0.1, 0.2, 0.3)),
        list(index = 1L, embedding = c(0.4, 0.5, 0.6))
      )
    ))
  })

  backend <- backend_config(provider = "openai", model = "text-embedding-3-large", retries = 0)
  out <- backend_embed_texts(c("x", "y"), backend)

  testthat::expect_equal(dim(out), c(2L, 3L))
  testthat::expect_equal(unname(out[2, ]), c(0.4, 0.5, 0.6))
  testthat::expect_identical(seen$url, "https://api.openai.com/v1/embeddings")
  testthat::expect_identical(seen$body$model, "text-embedding-3-large")
  testthat::expect_identical(unlist(seen$body$input), c("x", "y"))
})

testthat::test_that("OpenAI adapter handles alternative and malformed `data` shapes", {
  oa_fun <- ovc_ns(".embedding_embed_texts_openai")
  backend <- list(
    provider = "openai",
    base_url = "https://api.openai.com/v1",
    model = "text-embedding-3-small",
    max_batch_size = 4L,
    retries = 0L
  )
  run_with <- function(res, texts = c("a", "b")) {
    testthat::with_mocked_bindings(
      oa_fun(texts, backend),
      .embedding_with_retry = function(backend, fn) res,
      .package = "openalexVectorComp"
    )
  }

  # Already-extracted vectors are accepted as-is.
  out <- run_with(list(data = list(c(1, 2), c(3, 4))))
  testthat::expect_equal(unname(out), matrix(c(1, 2, 3, 4), nrow = 2, byrow = TRUE))

  testthat::expect_error(
    run_with(list(data = data.frame(index = 0:1, object = "embedding"))),
    "did not include `embedding`"
  )
  testthat::expect_error(
    run_with(list(data = c("not", "numeric"))),
    "unsupported shape"
  )
  testthat::expect_error(
    run_with(list(data = list(list(embedding = c(1, 2)))), texts = c("a", "b")),
    "Embedding count mismatch: got 1 vectors for 2 submitted texts"
  )
})

testthat::test_that("TEI backend probes /info and embeds via the server embed url", {
  calls <- character()
  httr2::local_mocked_responses(function(req) {
    url <- httr2::req_get_url(req)
    calls <<- c(calls, url)
    if (grepl("/info$", url)) {
      return(httr2::response_json(body = list(
        model_id = "BAAI/bge-base",
        served_model_name = "bge-served",
        embedding_size = 2L,
        max_client_batch_size = 2L
      )))
    }
    n <- length(httr2::req_get_body(req)$inputs)
    httr2::response_json(body = lapply(seq_len(n), function(i) c(i, -i)))
  })

  backend <- backend_config(provider = "tei", base_url = "http://tei.test:3000", retries = 0)
  info <- backend_info(backend)
  testthat::expect_identical(info$provider, "tei")
  testthat::expect_identical(info$model_id, "bge-served")
  testthat::expect_identical(info$dim, 2L)
  testthat::expect_identical(info$max_batch_size, 2L)
  testthat::expect_identical(info$raw$model$requested_id, "BAAI/bge-base")
  testthat::expect_identical(info$raw$server$embed_url, "http://tei.test:3000/embed")

  calls <- character()
  out <- backend_embed_texts(c("a", "b", "c"), backend)
  testthat::expect_equal(dim(out), c(3L, 2L))
  testthat::expect_equal(unname(out[, 2]), c(-1, -2, -1))
  testthat::expect_identical(
    calls,
    c(
      "http://tei.test:3000/info",
      "http://tei.test:3000/embed",
      "http://tei.test:3000/embed"
    )
  )
})

testthat::test_that("TEI info falls back to backend metadata when /info is unreachable", {
  httr2::local_mocked_responses(function(req) httr2::response(status_code = 503L))

  with_model <- backend_info(
    backend_config(provider = "tei", base_url = "http://tei.test", model = "my-model")
  )
  testthat::expect_identical(with_model$model_id, "my-model")
  testthat::expect_true(is.na(with_model$dim))
  testthat::expect_identical(with_model$max_batch_size, 128L)
  testthat::expect_identical(with_model$raw$embed_url, "http://tei.test/embed")

  no_model <- backend_info(list(
    provider = "tei",
    base_url = "http://tei.test",
    embed_url = "http://tei.test/pipeline/feature-extraction/org/model-x",
    model = NULL,
    max_batch_size = 16L
  ))
  testthat::expect_identical(no_model$model_id, "org/model-x")
  testthat::expect_identical(no_model$max_batch_size, 16L)
})

testthat::test_that("TEI adapter errors on embedding count mismatch", {
  tei_fun <- ovc_ns(".embedding_embed_texts_tei")
  testthat::expect_error(
    testthat::with_mocked_bindings(
      tei_fun(
        texts = c("a", "b"),
        backend = list(
          provider = "tei",
          base_url = "http://tei.test",
          model = "m",
          max_batch_size = 4L,
          retries = 0L
        )
      ),
      .embedding_probe_tei = function(embed_url) NULL,
      .embedding_with_retry = function(backend, fn) list(c(1, 2)),
      .package = "openalexVectorComp"
    ),
    "Embedding count mismatch: got 1 vectors for 2 submitted texts"
  )
})
