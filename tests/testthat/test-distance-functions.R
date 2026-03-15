make_distance_test_project <- function() {
  project_dir <- tempfile("ovc_distance_")
  dir.create(project_dir, recursive = TRUE, showWarnings = FALSE)

  model_part <- "model_id=BAAI_bge-small-en-v1.5"
  model_dir <- file.path(project_dir, "embeddings", model_part)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  n_each <- 40L
  v1_pos <- seq(0.85, 1.15, length.out = n_each)
  v1_neg <- -v1_pos
  v2_pattern <- c(-0.08, -0.04, 0.00, 0.04, 0.08)
  v2_pos <- rep(v2_pattern, length.out = n_each)
  v2_neg <- rep(rev(v2_pattern), length.out = n_each)

  emb <- data.frame(
    id = paste0("W", seq_len(2L * n_each)),
    V1 = c(v1_pos, v1_neg),
    V2 = c(v2_pos, v2_neg),
    label = c(rep("reference", n_each), rep("corpus", n_each)),
    batch = rep(seq_len(8L), each = 10L),
    stringsAsFactors = FALSE
  )

  arrow::write_dataset(
    emb,
    path = model_dir,
    format = "parquet",
    partitioning = c("label", "batch")
  )

  openalexVectorComp::embedding_backend_save(
    backend = openalexVectorComp::embedding_backend_config(
      provider = "hf",
      model = "BAAI/bge-small-en-v1.5"
    ),
    fn = file.path(model_dir, "embed_model.yaml")
  )

  reference_ids <- paste0("W", seq_len(n_each))
  corpus_ids <- paste0("W", n_each + seq_len(n_each))
  reference_csv <- file.path(project_dir, "reference.csv")
  corpus_csv <- file.path(project_dir, "corpus.csv")
  utils::write.csv(
    data.frame(id = reference_ids, stringsAsFactors = FALSE),
    reference_csv,
    row.names = FALSE
  )
  utils::write.csv(
    data.frame(id = corpus_ids, stringsAsFactors = FALSE),
    corpus_csv,
    row.names = FALSE
  )

  list(
    project_dir = project_dir,
    model_dir = model_dir,
    model_part = model_part,
    reference_ids = reference_ids,
    corpus_ids = corpus_ids,
    reference_csv = reference_csv,
    corpus_csv = corpus_csv
  )
}

testthat::test_that("similarity_cosine and distance_cosine handle vectors and matrices", {
  a <- c(1, 0)
  b <- c(1, 0)
  cvec <- c(-1, 0)
  m <- rbind(c(1, 0), c(0, 1), c(-1, 0))

  testthat::expect_equal(openalexVectorComp::similarity_cosine(a, b), 1)
  testthat::expect_equal(openalexVectorComp::distance_cosine(a, b), 0)
  testthat::expect_equal(openalexVectorComp::similarity_cosine(a, cvec), -1)

  sims <- openalexVectorComp::similarity_cosine(a, m)
  dists <- openalexVectorComp::distance_cosine(a, m)
  testthat::expect_equal(unname(sims), c(1, 0, -1))
  testthat::expect_equal(unname(dists), c(0, 1, 2))

  testthat::expect_true(is.na(openalexVectorComp::similarity_cosine(c(0, 0), c(1, 1))))
})

testthat::test_that("fit_ridge returns persisted reference-area fit", {
  p <- make_distance_test_project()
  out <- file.path(p$project_dir, "ridge_fit_unit.rds")

  returned <- openalexVectorComp::fit_ridge(
    embeddings = p$model_dir,
    reference_label = "reference",
    output = out,
    verbose = FALSE
  )

  testthat::expect_identical(returned, out)
  testthat::expect_true(file.exists(out))

  fit <- readRDS(out)
  testthat::expect_s3_class(fit, "ovc_reference_area_fit")
  testthat::expect_true(is.numeric(fit$mu))
  testthat::expect_true(is.matrix(fit$Sigma_inv))
})

testthat::test_that("distance_prototype writes pairwise cosine matrix", {
  p <- make_distance_test_project()

  out_dir <- openalexVectorComp::distance_prototype(
    project_dir = p$project_dir,
    embeddings_dir = p$model_part,
    corpus_label = "corpus",
    reference_label = "reference",
    verbose = FALSE
  )

  testthat::expect_true(dir.exists(out_dir))
  out_file <- file.path(out_dir, "pairwise-cosine.parquet")
  testthat::expect_true(file.exists(out_file))
  mat <- arrow::read_parquet(out_file)

  testthat::expect_true("reference_id" %in% names(mat))
  testthat::expect_equal(nrow(mat), 40L)
  testthat::expect_equal(ncol(mat), 41L)
  testthat::expect_equal(sort(mat$reference_id), sort(p$reference_ids))

  corpus_cols <- setdiff(names(mat), "reference_id")
  testthat::expect_equal(sort(corpus_cols), sort(p$corpus_ids))
  testthat::expect_true(all(is.finite(as.matrix(mat[, corpus_cols, drop = FALSE]))))
})

testthat::test_that("distance_prototype validates labels and max_cells guard", {
  p <- make_distance_test_project()

  testthat::expect_error(
    openalexVectorComp::distance_prototype(
      project_dir = p$project_dir,
      embeddings_dir = p$model_part,
      corpus_label = "missing",
      reference_label = "reference",
      verbose = FALSE
    ),
    "No embeddings found for `corpus_label"
  )

  testthat::expect_error(
    openalexVectorComp::distance_prototype(
      project_dir = p$project_dir,
      embeddings_dir = p$model_part,
      corpus_label = "corpus",
      reference_label = "reference",
      max_cells = 10,
      verbose = FALSE
    ),
    "exceeding `max_cells"
  )
})

testthat::test_that("distance_prototype errors on duplicate ids within a label partition", {
  td <- tempfile("ovc_distance_dup_")
  model_part <- "model_id=BAAI_bge-small-en-v1.5"
  model_dir <- file.path(td, "embeddings", model_part)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  emb <- data.frame(
    id = c("R1", "R1", "C1"),
    V1 = c(1, 1, 0),
    V2 = c(0, 0, 1),
    label = c("reference", "reference", "corpus"),
    batch = c(1, 1, 1),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(emb, path = model_dir, format = "parquet", partitioning = c("label", "batch"))

  testthat::expect_error(
    openalexVectorComp::distance_prototype(
      project_dir = td,
      embeddings_dir = model_part,
      corpus_label = "corpus",
      reference_label = "reference",
      verbose = FALSE
    ),
    "Duplicate ids found in reference label partition"
  )
})

testthat::test_that("distance_ridge creates relevance scores in [0, 1]", {
  p <- make_distance_test_project()

  out_dir <- openalexVectorComp::distance_ridge(
    project_dir = p$project_dir,
    reference_label = "reference",
    corpus_label = "corpus",
    batch_size = 4,
    verbose = FALSE
  )

  testthat::expect_true(dir.exists(out_dir))
  ds <- arrow::open_dataset(
    out_dir,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  scores <- ds |>
    dplyr::select(id, relevance_score, area_distance) |>
    dplyr::collect() |>
    dplyr::group_by(id) |>
    dplyr::summarise(
      relevance_score = mean(relevance_score),
      area_distance = mean(area_distance),
      .groups = "drop"
    )

  testthat::expect_equal(
    sort(scores$id),
    sort(p$corpus_ids)
  )
  testthat::expect_true(all(is.finite(scores$relevance_score)))
  testthat::expect_true(all(is.finite(scores$area_distance)))
  testthat::expect_true(all(scores$relevance_score >= 0 & scores$relevance_score <= 1))

  testthat::expect_true(all(scores$area_distance >= 0))
})

testthat::test_that("distances joins prototype and ridge datasets by id", {
  td <- tempfile("ovc_join_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)

  prototype_dir <- file.path(td, "prototype")
  ridge_dir <- file.path(td, "ridge")
  dir.create(prototype_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(ridge_dir, recursive = TRUE, showWarnings = FALSE)

  proto <- data.frame(
    id = c("W1", "W2", "W3"),
    distance = c(0.9, 0.4, -0.2),
    stringsAsFactors = FALSE
  )
  ridge <- data.frame(
    id = c("W2", "W3", "W4"),
    relevance_score = c(0.8, 0.1, 0.7),
    stringsAsFactors = FALSE
  )

  arrow::write_dataset(proto, path = prototype_dir, format = "parquet")
  arrow::write_dataset(ridge, path = ridge_dir, format = "parquet")

  joined <- openalexVectorComp:::distances(
    prototype_distances = prototype_dir,
    ridge_distance = ridge_dir
  ) |>
    dplyr::collect() |>
    dplyr::arrange(id)

  testthat::expect_equal(joined$id, c("W2", "W3"))
  testthat::expect_true(all(c("distance", "relevance_score") %in% names(joined)))
  testthat::expect_equal(joined$distance, c(0.4, -0.2))
  testthat::expect_equal(joined$relevance_score, c(0.8, 0.1))
})
