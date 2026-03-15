testthat::test_that("HF embed_texts returns a numeric matrix", {
  ovc_skip_if_no_hf()

  backend <- ovc_hf_backend(max_batch_size = 4L)
  texts <- c(
    "Title: Biodiversity and ecosystem services\nAbstract: Impacts on policy and conservation.",
    "Title: High-energy physics\nAbstract: Collider detector calibration methods."
  )
  emb <- embed_texts(texts = texts, backend = backend)

  testthat::expect_true(is.matrix(emb))
  testthat::expect_equal(nrow(emb), length(texts))
  testthat::expect_gt(ncol(emb), 10)
  testthat::expect_true(is.numeric(emb))
})

testthat::test_that("HF pipeline covers corpus embed, distance scoring, and calibration", {
  ovc_skip_if_no_hf()

  project_dir <- tempfile("ovc_hf_pipeline_")
  dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)
  corpus_dir <- file.path(project_dir, "corpus")
  dir.create(corpus_dir, recursive = TRUE, showWarnings = FALSE)

  corpus <- data.frame(
    id = paste0("W", 1:8),
    title = c(
      "Biodiversity conservation",
      "Ecosystem services valuation",
      "Nature-based climate adaptation",
      "Protected area governance",
      "Quantum field approximation",
      "Collider detector alignment",
      "Particle beam optimization",
      "High-energy scattering"
    ),
    abstract = c(
      "Conservation strategies for species and habitats.",
      "Economic and ecological valuation across regions.",
      "Adaptation planning with ecosystem restoration.",
      "Institutional pathways for biodiversity policy.",
      "Methods for approximation in lattice field models.",
      "Calibration methods for large collider detectors.",
      "Beamline tuning and optimization approaches.",
      "Scattering signatures in accelerator experiments."
    ),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(corpus, path = corpus_dir, format = "parquet")

  included_rel <- "included.csv"
  excluded_rel <- "excluded.csv"
  included_abs <- file.path(project_dir, included_rel)
  excluded_abs <- file.path(project_dir, excluded_rel)

  utils::write.csv(
    data.frame(id = c("W1", "W2", "W3", "W4"), stringsAsFactors = FALSE),
    included_abs,
    row.names = FALSE
  )
  utils::write.csv(
    data.frame(id = c("W5", "W6", "W7", "W8"), stringsAsFactors = FALSE),
    excluded_abs,
    row.names = FALSE
  )

  backend <- ovc_hf_backend(max_batch_size = 4L)
  model_dir <- embed_corpus(
    project_dir = project_dir,
    backend = backend,
    batch_size = 3,
    delete_existing = TRUE,
    verbose = FALSE
  )
  testthat::expect_true(dir.exists(model_dir))

  emb_ds <- arrow::open_dataset(
    model_dir,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  emb_ids <- emb_ds |>
    dplyr::select(id) |>
    dplyr::collect()
  testthat::expect_equal(sort(emb_ids$id), sort(corpus$id))

  out_proto <- distance_prototype(
    project_dir = project_dir,
    embeddings_dir = basename(model_dir),
    included = included_rel,
    excluded = excluded_rel,
    workers = 1,
    future_plan = "sequential",
    verbose = FALSE
  )
  testthat::expect_true(dir.exists(out_proto))
  proto_ds <- arrow::open_dataset(
    out_proto,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  testthat::expect_true("distance" %in% names(proto_ds))

  out_ridge <- distance_ridge(
    project_dir = project_dir,
    included = included_abs,
    excluded = excluded_abs,
    batch_size = 3,
    verbose = FALSE
  )
  testthat::expect_true(dir.exists(out_ridge))
  ridge_ds <- arrow::open_dataset(
    out_ridge,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  testthat::expect_true("relevance_score" %in% names(ridge_ds))

  best <- calibrate_threshold(
    scores_parquet = out_ridge,
    score_col = "relevance_score",
    included = included_abs,
    excluded = excluded_abs,
    n_thresholds = 25,
    batch_size = 20,
    verbose = FALSE
  )
  testthat::expect_true(is.list(best))
  testthat::expect_true(is.finite(best$th))
  testthat::expect_gte(best$precision, 0)
  testthat::expect_lte(best$precision, 1)
})
