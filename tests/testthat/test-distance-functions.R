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

  openalexVectorComp::backend_save(
    backend = openalexVectorComp::backend_config(
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

testthat::test_that("distance_reference_cosine writes one distance matrix with centroid axis", {
  p <- make_distance_test_project()

  out_dir <- openalexVectorComp::distance_reference_cosine(
    project_dir = p$project_dir,
    embeddings_dir = p$model_part,
    corpus_label = "corpus",
    reference_label = "reference",
    verbose = FALSE
  )

  testthat::expect_true(dir.exists(out_dir))
  out_file <- file.path(out_dir, "pairwise-cosine.parquet")
  testthat::expect_true(file.exists(out_file))
  testthat::expect_false(file.exists(file.path(out_dir, "centroid-cosine.parquet")))
  mat <- arrow::read_parquet(out_file)

  testthat::expect_true("id" %in% names(mat))
  testthat::expect_true("centroid" %in% names(mat))
  testthat::expect_equal(nrow(mat), 41L) # 40 corpus + centroid row
  testthat::expect_equal(ncol(mat), 42L) # id + 40 reference + centroid col
  testthat::expect_equal(sort(mat$id), sort(c(p$corpus_ids, "centroid")))

  ref_cols <- setdiff(names(mat), c("id", "centroid"))
  testthat::expect_equal(sort(ref_cols), sort(p$reference_ids))
  testthat::expect_true(all(is.finite(as.matrix(mat[, c(ref_cols, "centroid"), drop = FALSE]))))
})

testthat::test_that("distance_reference_cosine validates labels and max_cells guard", {
  p <- make_distance_test_project()

  testthat::expect_error(
    openalexVectorComp::distance_reference_cosine(
      project_dir = p$project_dir,
      embeddings_dir = p$model_part,
      corpus_label = "missing",
      reference_label = "reference",
      verbose = FALSE
    ),
    "No embeddings found for `corpus_label"
  )

  testthat::expect_error(
    openalexVectorComp::distance_reference_cosine(
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

testthat::test_that("distance_reference_cosine errors on duplicate ids within a label partition", {
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
    openalexVectorComp::distance_reference_cosine(
      project_dir = td,
      embeddings_dir = model_part,
      corpus_label = "corpus",
      reference_label = "reference",
      verbose = FALSE
    ),
    "Duplicate ids found in reference label partition"
  )
})

testthat::test_that("distance_reference_cosine validates zero-norm and centroid edge cases", {
  td_zero <- tempfile("ovc_distance_zero_")
  model_part <- "model_id=BAAI_bge-small-en-v1.5"
  model_dir <- file.path(td_zero, "embeddings", model_part)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  emb_zero <- data.frame(
    id = c("R1", "C1"),
    V1 = c(1, 0),
    V2 = c(0, 0),
    label = c("reference", "corpus"),
    batch = c(1, 1),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(emb_zero, path = model_dir, format = "parquet", partitioning = c("label", "batch"))
  testthat::expect_error(
    openalexVectorComp::distance_reference_cosine(
      project_dir = td_zero,
      embeddings_dir = model_part,
      corpus_label = "corpus",
      reference_label = "reference",
      verbose = FALSE
    ),
    "Corpus partition contains zero-norm or non-finite vectors"
  )

  td_deg <- tempfile("ovc_distance_deg_")
  model_dir2 <- file.path(td_deg, "embeddings", model_part)
  dir.create(model_dir2, recursive = TRUE, showWarnings = FALSE)
  emb_deg <- data.frame(
    id = c("R1", "R2", "C1"),
    V1 = c(1, -1, 1),
    V2 = c(0, 0, 0),
    label = c("reference", "reference", "corpus"),
    batch = c(1, 1, 1),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(emb_deg, path = model_dir2, format = "parquet", partitioning = c("label", "batch"))
  testthat::expect_error(
    openalexVectorComp::distance_reference_cosine(
      project_dir = td_deg,
      embeddings_dir = model_part,
      corpus_label = "corpus",
      reference_label = "reference",
      verbose = FALSE
    ),
    "Reference centroid has zero norm"
  )
})

testthat::test_that("distance_reference_cosine centroid axis matches manual values", {
  p <- make_distance_test_project()

  out_dir <- openalexVectorComp::distance_reference_cosine(
    project_dir = p$project_dir,
    embeddings_dir = p$model_part,
    corpus_label = "corpus",
    reference_label = "reference",
    verbose = FALSE
  )
  mat <- arrow::read_parquet(file.path(out_dir, "pairwise-cosine.parquet"))

  ds <- arrow::open_dataset(p$model_dir, factory_options = list(exclude_invalid_files = TRUE))
  ref_df <- ds |>
    dplyr::filter(label == "reference") |>
    dplyr::select(id, V1, V2) |>
    dplyr::collect()
  corpus_df <- ds |>
    dplyr::filter(label == "corpus") |>
    dplyr::select(id, V1, V2) |>
    dplyr::collect()

  R <- as.matrix(ref_df[, c("V1", "V2")])
  C <- as.matrix(corpus_df[, c("V1", "V2")])
  Rn <- R / sqrt(rowSums(R^2))
  Cn <- C / sqrt(rowSums(C^2))
  rc <- colMeans(Rn); rc <- rc / sqrt(sum(rc^2))
  cc <- colMeans(Cn); cc <- cc / sqrt(sum(cc^2))

  # One regular cell
  c_id <- corpus_df$id[[1]]
  r_id <- ref_df$id[[1]]
  expected_cell <- 1 - sum(Cn[1, ] * Rn[1, ])
  got_cell <- mat[mat$id == c_id, r_id, drop = TRUE]
  testthat::expect_equal(as.numeric(got_cell), as.numeric(expected_cell), tolerance = 1e-10)

  # Centroid column for first corpus row
  expected_col <- 1 - sum(Cn[1, ] * rc)
  got_col <- mat[mat$id == c_id, "centroid", drop = TRUE]
  testthat::expect_equal(as.numeric(got_col), as.numeric(expected_col), tolerance = 1e-10)

  # Centroid row for first reference column
  expected_row <- 1 - sum(cc * Rn[1, ])
  got_row <- mat[mat$id == "centroid", r_id, drop = TRUE]
  testthat::expect_equal(as.numeric(got_row), as.numeric(expected_row), tolerance = 1e-10)

  # Centroid-corner cell
  expected_corner <- 1 - sum(cc * rc)
  got_corner <- mat[mat$id == "centroid", "centroid", drop = TRUE]
  testthat::expect_equal(as.numeric(got_corner), as.numeric(expected_corner), tolerance = 1e-10)
})

testthat::test_that("score_reference_cosine preserves shape and applies linear/exponential transforms", {
  p <- make_distance_test_project()

  dist_dir <- openalexVectorComp::distance_reference_cosine(
    project_dir = p$project_dir,
    embeddings_dir = p$model_part,
    corpus_label = "corpus",
    reference_label = "reference",
    verbose = FALSE
  )
  dist_df <- arrow::open_dataset(dist_dir, factory_options = list(exclude_invalid_files = TRUE)) |>
    dplyr::collect()

  score_lin <- openalexVectorComp::score_reference_cosine(
    distance_parquet = dist_dir,
    method = "linear",
    verbose = FALSE
  )
  lin_df <- arrow::open_dataset(score_lin, factory_options = list(exclude_invalid_files = TRUE)) |>
    dplyr::collect()

  testthat::expect_identical(names(lin_df), names(dist_df))
  testthat::expect_equal(dim(lin_df), dim(dist_df))
  value_cols <- setdiff(names(dist_df), "id")
  testthat::expect_equal(
    as.numeric(lin_df[1, value_cols, drop = TRUE]),
    1 - as.numeric(dist_df[1, value_cols, drop = TRUE]),
    tolerance = 1e-10
  )

  alpha <- 2
  score_exp <- openalexVectorComp::score_reference_cosine(
    distance_parquet = dist_dir,
    method = "exponential",
    alpha = alpha,
    verbose = FALSE
  )
  exp_df <- arrow::open_dataset(score_exp, factory_options = list(exclude_invalid_files = TRUE)) |>
    dplyr::collect()
  testthat::expect_equal(
    as.numeric(exp_df[1, value_cols, drop = TRUE]),
    exp(-alpha * as.numeric(dist_df[1, value_cols, drop = TRUE])),
    tolerance = 1e-10
  )
})

testthat::test_that("score_reference_cosine validates schema and parameters", {
  td <- tempfile("ovc_score_ref_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)

  bad_no_id <- file.path(td, "bad_no_id")
  dir.create(bad_no_id, recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(data.frame(a = 1:2), path = bad_no_id, format = "parquet")
  testthat::expect_error(
    openalexVectorComp::score_reference_cosine(bad_no_id, verbose = FALSE),
    "must contain an `id` column"
  )

  bad_no_vals <- file.path(td, "bad_no_vals")
  dir.create(bad_no_vals, recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(data.frame(id = c("A", "B")), path = bad_no_vals, format = "parquet")
  testthat::expect_error(
    openalexVectorComp::score_reference_cosine(bad_no_vals, verbose = FALSE),
    "must contain at least one distance column"
  )

  p <- make_distance_test_project()
  dist_dir <- openalexVectorComp::distance_reference_cosine(
    project_dir = p$project_dir,
    embeddings_dir = p$model_part,
    verbose = FALSE
  )
  testthat::expect_error(
    openalexVectorComp::score_reference_cosine(
      distance_parquet = dist_dir,
      method = "exponential",
      alpha = -1,
      verbose = FALSE
    ),
    "`alpha` must be a positive number"
  )
})

testthat::test_that("distance_ridge creates area_distance and score_ridge creates relevance scores", {
  p <- make_distance_test_project()

  out_dist <- openalexVectorComp::distance_ridge(
    project_dir = p$project_dir,
    reference_label = "reference",
    corpus_label = "corpus",
    batch_size = 4,
    verbose = FALSE
  )

  testthat::expect_true(dir.exists(out_dist))
  ds_dist <- arrow::open_dataset(
    out_dist,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  dist_df <- ds_dist |>
    dplyr::select(id, area_distance) |>
    dplyr::collect() |>
    dplyr::group_by(id) |>
    dplyr::summarise(
      area_distance = mean(area_distance),
      .groups = "drop"
    )

  testthat::expect_equal(
    sort(dist_df$id),
    sort(p$corpus_ids)
  )
  testthat::expect_true(all(is.finite(dist_df$area_distance)))
  testthat::expect_true(all(dist_df$area_distance >= 0))

  out_score <- openalexVectorComp::score_ridge(
    distance_parquet = out_dist,
    verbose = FALSE
  )
  testthat::expect_true(dir.exists(out_score))
  ds_score <- arrow::open_dataset(
    out_score,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  scores <- ds_score |>
    dplyr::select(id, relevance_score, area_distance) |>
    dplyr::collect() |>
    dplyr::group_by(id) |>
    dplyr::summarise(
      relevance_score = mean(relevance_score),
      area_distance = mean(area_distance),
      .groups = "drop"
    )

  testthat::expect_equal(sort(scores$id), sort(p$corpus_ids))
  testthat::expect_true(all(is.finite(scores$relevance_score)))
  testthat::expect_true(all(scores$relevance_score >= 0 & scores$relevance_score <= 1))
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

# Small fixture writer: `emb` must contain id, label, V* (and optionally batch).
write_label_embeddings <- function(dir, emb, partitioning = c("label", "batch")) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (!"batch" %in% names(emb)) emb$batch <- 1L
  arrow::write_dataset(emb, path = dir, format = "parquet", partitioning = partitioning)
  dir
}

small_ridge_emb <- function() {
  data.frame(
    id = c("R1", "R2", "R3", "R4", "C1", "C2"),
    V1 = c(1, 1.2, 0.8, 1.1, 1, -1),
    V2 = c(0.1, -0.1, 0.05, 0, 0, 0.2),
    label = c(rep("reference", 4), "corpus", "corpus"),
    stringsAsFactors = FALSE
  )
}

testthat::test_that("distance_ridge and fit_ridge validate labels and regularization", {
  testthat::expect_error(distance_ridge(tempdir(), reference_label = ""), "`reference_label` must be")
  testthat::expect_error(distance_ridge(tempdir(), corpus_label = c("a", "b")), "`corpus_label` must be")
  testthat::expect_error(distance_ridge(tempdir(), regularization = 0), "`regularization` must be")
  testthat::expect_error(fit_ridge(tempdir(), reference_label = " ", output = tempfile()), "`reference_label` must be")
  testthat::expect_error(fit_ridge(tempdir(), output = tempfile(), regularization = -1), "`regularization` must be")
})

testthat::test_that("distance_ridge reads a flat embeddings dir, names output from metadata and reuses a fit", {
  proj <- tempfile("ovc_ridge_flat_")
  emb_dir <- write_label_embeddings(file.path(proj, "embeddings"), small_ridge_emb())
  backend_save(
    backend_config(provider = "hf", model = "org/flat-model"),
    fn = file.path(emb_dir, "embed_model.yaml")
  )

  msgs <- testthat::capture_messages(
    out <- distance_ridge(proj, batch_size = 10, verbose = TRUE)
  )
  txt <- paste(msgs, collapse = "")
  testthat::expect_match(txt, "Using embeddings from")
  testthat::expect_match(txt, "Saved reference-area fit to")
  testthat::expect_match(txt, "Computing area distances for corpus label 'corpus'")
  testthat::expect_match(
    out,
    "distance_ridge/model_id=org_flat-model/corpus_label=corpus/reference_label=reference$"
  )
  meta <- yaml::read_yaml(file.path(out, "embed_model.yaml"))
  testthat::expect_identical(meta$ridge_mode, "reference_area")
  testthat::expect_identical(meta$reference_label, "reference")

  fit_path <- file.path(proj, "ridge_fit.rds")
  testthat::expect_true(file.exists(fit_path))
  first <- dplyr::collect(arrow::open_dataset(out, factory_options = list(exclude_invalid_files = TRUE)))
  marker <- file.path(out, "stale.txt")
  file.create(marker)

  out2 <- distance_ridge(proj, fit_path = fit_path, verbose = FALSE)
  testthat::expect_identical(out2, out)
  testthat::expect_false(file.exists(marker))
  second <- dplyr::collect(arrow::open_dataset(out2, factory_options = list(exclude_invalid_files = TRUE)))
  testthat::expect_equal(
    second$area_distance[order(second$id)],
    first$area_distance[order(first$id)]
  )
  # C2 is far from the reference cloud compared to C1.
  testthat::expect_gt(
    second$area_distance[second$id == "C2"],
    second$area_distance[second$id == "C1"]
  )
})

testthat::test_that("distance_ridge falls back to legacy _tei_info.yaml metadata", {
  proj <- tempfile("ovc_ridge_legacy_")
  emb_dir <- write_label_embeddings(file.path(proj, "embeddings"), small_ridge_emb())
  yaml::write_yaml(
    list(
      model = list(requested_id = "legacy/model"),
      backend = list(provider = "tei", base_url = "http://localhost:3000")
    ),
    file.path(emb_dir, "_tei_info.yaml")
  )

  out <- distance_ridge(proj, verbose = FALSE)
  testthat::expect_match(out, "model_id=legacy_model/corpus_label=corpus")
  meta <- yaml::read_yaml(file.path(out, "embed_model.yaml"))
  testthat::expect_identical(meta$ridge_mode, "reference_area")
  testthat::expect_identical(meta$model$requested_id, "legacy/model")
})

testthat::test_that("distance_ridge rejects missing or invalid fits", {
  proj <- tempfile("ovc_ridge_fit_")
  write_label_embeddings(file.path(proj, "embeddings", "model_id=m"), small_ridge_emb())

  testthat::expect_error(
    distance_ridge(proj, fit_path = file.path(proj, "nope.rds"), verbose = FALSE),
    "`fit_path` does not exist"
  )
  bad_fit <- file.path(proj, "bad.rds")
  saveRDS(list(mu = 1), bad_fit)
  testthat::expect_error(
    distance_ridge(proj, fit_path = bad_fit, verbose = FALSE),
    "not an `ovc_reference_area_fit`"
  )
})

testthat::test_that("distance_ridge errors on bad corpus partitions", {
  run_with <- function(emb, ...) {
    proj <- tempfile("ovc_ridge_bad_")
    write_label_embeddings(file.path(proj, "embeddings", "model_id=m"), emb)
    distance_ridge(proj, verbose = FALSE, ...)
  }
  base <- small_ridge_emb()

  no_v <- base[, c("id", "label")]
  testthat::expect_error(run_with(no_v), "No embedding columns")

  dup_in_batch <- base
  dup_in_batch$id[6] <- "C1"
  testthat::expect_error(run_with(dup_in_batch), "Duplicate ids found in corpus label partition\\.")

  dup_across <- base
  dup_across$id[6] <- "C1"
  dup_across$batch <- c(1L, 1L, 1L, 1L, 1L, 2L)
  testthat::expect_error(run_with(dup_across), "across batches")

  non_finite <- base
  non_finite$V1[6] <- NaN
  testthat::expect_error(run_with(non_finite), "Non-finite embedding values found in corpus")

  testthat::expect_error(
    run_with(base, corpus_label = "missing"),
    "No embeddings found for `corpus_label = missing`"
  )
})

testthat::test_that("fit_ridge handles degenerate reference sets", {
  fit_with <- function(emb, ...) {
    dir <- write_label_embeddings(tempfile("ovc_fit_"), emb)
    out <- tempfile(fileext = ".rds")
    fit_ridge(dir, output = out, verbose = FALSE, ...)
    readRDS(out)
  }
  base <- small_ridge_emb()

  testthat::expect_error(fit_with(base[, c("id", "label")]), "No embedding columns")
  testthat::expect_error(fit_with(base, reference_label = "missing"), "No embeddings found for `reference_label")

  nf <- base
  nf$V2[1] <- Inf
  testthat::expect_error(fit_with(nf), "Non-finite embedding values found in reference")

  testthat::expect_warning(
    fit <- fit_with(base[c(1, 5), ]),
    "< 2 rows; using diagonal covariance fallback"
  )
  testthat::expect_equal(fit$mu, c(1, 0.1))
  testthat::expect_equal(fit$Sigma_inv, diag(1 / (1 + 1e-6), 2))

  collinear <- data.frame(
    id = c("R1", "R2", "R3"),
    V1 = c(1, 2, 3),
    V2 = c(1, 2, 3),
    label = "reference",
    stringsAsFactors = FALSE
  )
  testthat::expect_error(
    fit_with(collinear, regularization = 1e-30),
    "Could not invert regularized covariance"
  )
})

testthat::test_that("distance_reference_cosine validates inputs and dataset shape", {
  testthat::expect_error(distance_reference_cosine(tempdir(), corpus_label = ""), "`corpus_label` must be")
  testthat::expect_error(distance_reference_cosine(tempdir(), reference_label = NA), "`reference_label` must be")
  testthat::expect_error(distance_reference_cosine(tempdir(), max_cells = -1), "`max_cells` must be")

  proj <- tempfile("ovc_cos_shape_")
  mdir <- file.path(proj, "embeddings", "model_id=m")
  dir.create(mdir, recursive = TRUE)
  arrow::write_parquet(data.frame(id = "A", V1 = 1), file.path(mdir, "x.parquet"))
  testthat::expect_error(
    distance_reference_cosine(proj, embeddings_dir = "model_id=m", verbose = FALSE),
    "has no `label` partition"
  )

  proj2 <- tempfile("ovc_cos_nov_")
  write_label_embeddings(
    file.path(proj2, "embeddings", "model_id=m"),
    data.frame(id = c("A", "B"), x = 1, label = c("corpus", "reference"))
  )
  testthat::expect_error(
    distance_reference_cosine(proj2, embeddings_dir = "model_id=m", verbose = FALSE),
    "No embedding columns"
  )
})

testthat::test_that("distance_reference_cosine reports errors for each partition problem", {
  run_with <- function(emb) {
    proj <- tempfile("ovc_cos_bad_")
    write_label_embeddings(file.path(proj, "embeddings", "model_id=m"), emb)
    distance_reference_cosine(proj, embeddings_dir = "model_id=m", verbose = FALSE)
  }

  testthat::expect_error(
    run_with(data.frame(id = "C1", V1 = 1, V2 = 0, label = "corpus")),
    "No embeddings found for `reference_label"
  )
  testthat::expect_error(
    run_with(data.frame(id = c("R1", "C1", "C1"), V1 = 1, V2 = 0, label = c("reference", "corpus", "corpus"))),
    "Duplicate ids found in corpus label partition"
  )
  testthat::expect_error(
    run_with(data.frame(id = c("R1", "C1"), V1 = c(0, 1), V2 = 0, label = c("reference", "corpus"))),
    "Reference partition contains zero-norm"
  )
  testthat::expect_error(
    run_with(data.frame(id = c("R1", "C1", "C2"), V1 = c(1, 1, -1), V2 = 0, label = c("reference", "corpus", "corpus"))),
    "Corpus centroid has zero norm"
  )
})

testthat::test_that("distance_reference_cosine verbose run replaces previous output", {
  proj <- tempfile("ovc_cos_verbose_")
  write_label_embeddings(
    file.path(proj, "embeddings", "model_id=m"),
    data.frame(id = c("R1", "C1"), V1 = c(1, 0), V2 = c(0, 1), label = c("reference", "corpus"))
  )
  out <- distance_reference_cosine(proj, embeddings_dir = "model_id=m", verbose = FALSE)
  marker <- file.path(out, "stale.txt")
  file.create(marker)

  msgs <- testthat::capture_messages(
    out2 <- distance_reference_cosine(proj, embeddings_dir = "model_id=m", verbose = TRUE)
  )
  txt <- paste(msgs, collapse = "")
  testthat::expect_match(txt, "Loading reference and corpus label partitions")
  testthat::expect_match(txt, "for 1 corpus x 1 reference vectors")
  testthat::expect_match(txt, "Wrote cosine distance matrix \\(2 x 2\\)")
  testthat::expect_identical(normalizePath(out2), normalizePath(out))
  testthat::expect_false(file.exists(marker))
  mat <- arrow::read_parquet(file.path(out2, "pairwise-cosine.parquet"))
  testthat::expect_equal(mat$R1[mat$id == "C1"], 1)
})

testthat::test_that("score_ridge validates input and derives output dir", {
  testthat::expect_error(score_ridge(""), "`distance_parquet` must be")
  testthat::expect_error(score_ridge(tempdir(), alpha = 0), "`alpha` must be a positive number")

  td <- tempfile("ovc_score_ridge_")
  dist_dir <- file.path(td, "dists")
  dir.create(dist_dir, recursive = TRUE)
  arrow::write_parquet(data.frame(id = c("A", "B"), area_distance = c(0, 2)), file.path(dist_dir, "d.parquet"))

  testthat::expect_message(
    out <- score_ridge(dist_dir, alpha = 1, verbose = TRUE),
    "Wrote ridge scores for 2 rows"
  )
  testthat::expect_identical(out, normalizePath(file.path(td, "score_ridge"), mustWork = FALSE))
  sc <- dplyr::collect(arrow::open_dataset(out))
  sc <- sc[order(sc$id), ]
  testthat::expect_equal(sc$relevance_score, c(1, exp(-2)))

  bad_cols <- file.path(td, "badcols")
  dir.create(bad_cols)
  arrow::write_parquet(data.frame(id = "A", d = 1), file.path(bad_cols, "d.parquet"))
  testthat::expect_error(score_ridge(bad_cols, verbose = FALSE), "must contain columns `id` and `area_distance`")

  nf <- file.path(td, "nonfinite")
  dir.create(nf)
  arrow::write_parquet(data.frame(id = "A", area_distance = NaN), file.path(nf, "d.parquet"))
  testthat::expect_error(score_ridge(nf, verbose = FALSE), "non-finite values")

  empty <- file.path(td, "empty")
  dir.create(empty)
  arrow::write_parquet(data.frame(id = character(), area_distance = numeric()), file.path(empty, "d.parquet"))
  testthat::expect_error(score_ridge(empty, verbose = FALSE), "No rows found in distance dataset")
})

testthat::test_that("score_reference_cosine derives default output dir and reports", {
  td <- tempfile("ovc_score_cos_")
  dist_dir <- file.path(td, "dists")
  dir.create(dist_dir, recursive = TRUE)
  arrow::write_parquet(data.frame(id = c("A", "centroid"), R1 = c(0.25, 0.5)), file.path(dist_dir, "d.parquet"))

  testthat::expect_message(
    out <- score_reference_cosine(dist_dir, verbose = TRUE),
    "Wrote reference cosine scores"
  )
  testthat::expect_identical(out, normalizePath(file.path(td, "score_reference_cosine"), mustWork = FALSE))
  sc <- dplyr::collect(arrow::open_dataset(out))
  testthat::expect_equal(sc$R1[order(sc$id)], c(0.75, 0.5))

  testthat::expect_error(score_reference_cosine(character()), "`distance_parquet` must be")
})

testthat::test_that("calibrate_threshold builds a grid, picks the best F1 and reports progress", {
  td <- tempfile("ovc_calib_")
  scores_dir <- file.path(td, "scores")
  dir.create(scores_dir, recursive = TRUE)
  # 12 single-row files -> >= 10 scan batches to trigger the progress message.
  ids <- paste0("S", 1:12)
  sc <- c(seq(0.95, 0.65, length.out = 6), seq(0.4, 0.1, length.out = 6))
  for (i in seq_along(ids)) {
    arrow::write_parquet(
      data.frame(id = ids[i], score = sc[i]),
      file.path(scores_dir, sprintf("part-%02d.parquet", i))
    )
  }
  arrow::write_parquet(data.frame(id = "U1", score = NaN), file.path(scores_dir, "part-unlabeled.parquet"))
  arrow::write_parquet(data.frame(id = character(), score = numeric()), file.path(scores_dir, "part-empty.parquet"))
  labels_dir <- file.path(td, "labels")
  dir.create(labels_dir)
  arrow::write_parquet(
    data.frame(id = c(ids, "U1"), label = c(rep(1L, 6), rep(0L, 6), NA)),
    file.path(labels_dir, "labels.parquet")
  )

  msgs <- testthat::capture_messages(
    best <- calibrate_threshold(scores_dir, "score", labels_dir, n_thresholds = 11, batch_size = 1, verbose = TRUE)
  )
  txt <- paste(msgs, collapse = "")
  testthat::expect_match(txt, "First pass: computing score range")
  testthat::expect_match(txt, "Second pass: sweeping 11 thresholds")
  testthat::expect_match(txt, "processed 10 batches")

  testthat::expect_length(best$thresholds, 11L)
  testthat::expect_equal(range(best$thresholds), c(0.1, 0.95))
  testthat::expect_equal(best$f1, 1)
  testthat::expect_gt(best$th, 0.4)
  testthat::expect_lte(best$th, 0.65)

  testthat::expect_error(
    calibrate_threshold(scores_dir, "score", labels_parquet = ""),
    "`labels_parquet` is required"
  )
})
