make_plot_embeddings_fixture <- function() {
  td <- tempfile("ovc_plot_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  emb_dir <- file.path(td, "emb")
  dir.create(emb_dir, recursive = TRUE, showWarnings = FALSE)

  set.seed(1)
  emb <- data.frame(
    id = paste0("W", 1:20),
    V1 = rnorm(20),
    V2 = rnorm(20),
    V3 = rnorm(20),
    stringsAsFactors = FALSE
  )
  arrow::write_dataset(emb, path = emb_dir, format = "parquet")

  included_csv <- file.path(td, "included.csv")
  excluded_csv <- file.path(td, "excluded.csv")
  utils::write.csv(data.frame(id = c("W1", "W2")), included_csv, row.names = FALSE)
  utils::write.csv(data.frame(id = c("W10", "W11")), excluded_csv, row.names = FALSE)

  list(
    emb_dir = emb_dir,
    included_csv = included_csv,
    excluded_csv = excluded_csv
  )
}

testthat::test_that("plot_embeddings_pca returns ggplot for vectors and csv ids", {
  fx <- make_plot_embeddings_fixture()

  p1 <- plot_embeddings_pca(
    embeddings = fx$emb_dir,
    included = c("W1", "W2"),
    excluded = c("W10")
  )
  testthat::expect_s3_class(p1, "ggplot")

  p2 <- plot_embeddings_pca(
    embeddings = fx$emb_dir,
    included = fx$included_csv,
    excluded = fx$excluded_csv
  )
  testthat::expect_s3_class(p2, "ggplot")
})

testthat::test_that("plot_embeddings_umap returns ggplot and supports sampling", {
  fx <- make_plot_embeddings_fixture()

  p <- plot_embeddings_umap(
    embeddings = fx$emb_dir,
    included = fx$included_csv,
    excluded = fx$excluded_csv,
    n_neighbors = 5,
    n_epochs = 10
  )
  testthat::expect_s3_class(p, "ggplot")

  p_sample <- plot_embeddings_umap(
    embeddings = fx$emb_dir,
    included = c("W1"),
    excluded = c("W2"),
    n_neighbors = 5,
    n_epochs = 10,
    sample_n = 10,
    seed = 123
  )
  testthat::expect_s3_class(p_sample, "ggplot")
})

testthat::test_that("plot embedding functions validate id csv schema and embedding columns", {
  fx <- make_plot_embeddings_fixture()
  bad_csv <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(not_id = c("W1")), bad_csv, row.names = FALSE)

  testthat::expect_error(
    plot_embeddings_pca(
      embeddings = fx$emb_dir,
      included = bad_csv,
      excluded = c("W2")
    ),
    "must have a column named 'id'"
  )

  nov_dir <- tempfile("ovc_plot_nov_")
  dir.create(nov_dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_dataset(
    data.frame(id = c("A", "B"), stringsAsFactors = FALSE),
    path = nov_dir,
    format = "parquet"
  )

  testthat::expect_error(
    plot_embeddings_pca(
      embeddings = nov_dir,
      included = c("A"),
      excluded = c("B")
    ),
    "No embedding columns"
  )
})
