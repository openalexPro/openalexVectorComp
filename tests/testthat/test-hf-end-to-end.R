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

  backend <- ovc_hf_backend(max_batch_size = 4L)
  model_dir <- embed_corpus(
    project_dir = project_dir,
    backend = backend,
    batch_size = 3,
    delete_existing = TRUE,
    label = "corpus",
    verbose = FALSE
  )
  embed_corpus(
    project_dir = project_dir,
    backend = backend,
    batch_size = 3,
    delete_existing = FALSE,
    label = "reference",
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
  testthat::expect_equal(sort(unique(emb_ids$id)), sort(corpus$id))

  out_proto <- distance_prototype(
    project_dir = project_dir,
    embeddings_dir = basename(model_dir),
    corpus_label = "corpus",
    reference_label = "reference",
    verbose = FALSE
  )
  testthat::expect_true(dir.exists(out_proto))
  proto_file <- file.path(out_proto, "pairwise-cosine.parquet")
  testthat::expect_true(file.exists(proto_file))
  proto <- arrow::read_parquet(proto_file)
  testthat::expect_true("reference_id" %in% names(proto))
  testthat::expect_equal(nrow(proto), nrow(corpus))

  out_ridge <- distance_ridge(
    project_dir = project_dir,
    reference_label = "reference",
    corpus_label = "corpus",
    batch_size = 3,
    verbose = FALSE
  )
  testthat::expect_true(dir.exists(out_ridge))
  ridge_ds <- arrow::open_dataset(
    out_ridge,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  testthat::expect_true("relevance_score" %in% names(ridge_ds))
  testthat::expect_true("area_distance" %in% names(ridge_ds))

  labels_dir <- file.path(project_dir, "labels_parquet")
  dir.create(labels_dir, recursive = TRUE, showWarnings = FALSE)
  labels_df <- data.frame(
    id = c("W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"),
    label = c(1L, 1L, 1L, 1L, 0L, 0L, 0L, 0L),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(labels_df, path = labels_dir, format = "parquet")

  best <- calibrate_threshold(
    scores_parquet = out_ridge,
    score_col = "relevance_score",
    labels_parquet = labels_dir,
    n_thresholds = 25,
    batch_size = 20,
    verbose = FALSE
  )
  testthat::expect_true(is.list(best))
  testthat::expect_true(is.finite(best$th))
  testthat::expect_gte(best$precision, 0)
  testthat::expect_lte(best$precision, 1)
})
