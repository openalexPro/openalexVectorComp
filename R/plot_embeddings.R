#' Plot embeddings via PCA, colored by inclusion/exclusion
#'
#' Reads an embeddings Parquet dataset (produced by [embed_corpus()]) with columns
#' `id` and `V1..Vd`, computes a PCA on the embedding matrix, and returns a
#' scatter plot of the first two principal components. Points are colored by
#' whether their `id` is listed in `included` (green), `excluded` (red), or
#' neither (grey).
#'
#' @param embeddings Path to a Parquet file or dataset directory containing
#'   columns `id` and `V1..Vd`.
#' @param included Either a character vector of ids, or the path to a CSV file
#'   with a column named `id`.
#' @param excluded Either a character vector of ids, or the path to a CSV file
#'   with a column named `id`.
#' @param center,scale. Passed to [stats::prcomp()] for PCA. Defaults
#'   `center = TRUE`, `scale. = FALSE`.
#' @param point_size,alpha Point size and transparency for points in the plot.
#'   Defaults `point_size = 2`, `alpha = 0.5`.
#'
#' @return A `ggplot` object with points mapped to PC1 vs PC2 and colored by
#'   group.
#'
#' @examples
#' \dontrun{
#' p <- plot_embeddings_pca(
#'   embeddings = "inst/examples/embedings/",
#'   included = "inst/examples/included_part.csv",
#'   excluded = "inst/examples/excluded_part.csv"
#' )
#' print(p)
#' }
#'
#' @importFrom arrow open_dataset
#' @importFrom dplyr select collect all_of
#' @importFrom stats prcomp
#' @export
plot_embeddings_pca <- function(
  embeddings,
  included,
  excluded,
  center = TRUE,
  scale. = FALSE,
  point_size = 2,
  alpha = 0.5
) {
  # Helper to resolve ids from vector or CSV path
  resolve_ids <- function(x) {
    if (length(x) == 1L && is.character(x) && file.exists(x)) {
      df <- utils::read.csv(x, stringsAsFactors = FALSE)
      if (!"id" %in% names(df)) {
        stop("CSV at ", x, " must have a column named 'id'.")
      }
      as.character(df$id)
    } else {
      as.character(x)
    }
  }
  incl_ids <- unique(resolve_ids(included))
  excl_ids <- unique(resolve_ids(excluded))

  ds <- arrow::open_dataset(
    embeddings,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  cols <- names(ds)
  vcols <- cols[grepl("^V[0-9]+$", cols)]
  if (!length(vcols)) {
    stop("No embedding columns (V1..Vd) found in dataset.")
  }
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  df <- ds |>
    dplyr::select(id, dplyr::all_of(vcols)) |>
    dplyr::collect()

  # Labels with precedence: included > excluded > other
  lab <- rep("other", nrow(df))
  if (length(excl_ids)) {
    lab[df$id %in% excl_ids] <- "excluded"
  }
  if (length(incl_ids)) {
    lab[df$id %in% incl_ids] <- "included"
  }
  lab <- factor(lab, levels = c("included", "excluded", "other"))

  X <- as.matrix(df[, vcols, drop = FALSE])
  pc <- stats::prcomp(X, center = center, scale. = scale.)
  plot_df <- data.frame(
    id = df$id,
    PC1 = pc$x[, 1],
    PC2 = pc$x[, 2],
    group = lab,
    stringsAsFactors = FALSE
  )

  ggplot2::ggplot(plot_df, ggplot2::aes(PC1, PC2, color = group)) +
    ggplot2::geom_point(alpha = alpha, size = point_size) +
    ggplot2::scale_color_manual(
      values = c(
        included = "#1b9e77",
        excluded = "#d95f02",
        other = "#aaaaaa"
      )
    ) +
    ggplot2::labs(color = "Group") +
    ggplot2::theme_minimal()
}

#' Plot embeddings via UMAP, colored by inclusion/exclusion
#'
#' Computes a 2D UMAP projection of `V1..Vd` and returns a scatter plot colored
#' by `included`/`excluded` membership. Uses cosine distance by default to align
#' with common embedding similarity.
#'
#' @inheritParams plot_embeddings_pca
#' @param n_neighbors,min_dist,metric,n_epochs UMAP parameters passed to
#'   [uwot::umap()]. Defaults: `n_neighbors = 15`, `min_dist = 0.1`,
#'   `metric = "cosine"`, `n_epochs = 500`.
#' @param seed Random seed for reproducibility (set to `NULL` to skip).
#' @param sample_n Optional maximum number of rows to sample for plotting
#'   (applied before UMAP). If `NULL`, uses all rows.
#'
#' @return A `ggplot` object of UMAP1 vs UMAP2 colored by group.
#'
#' @importFrom uwot umap
#' @export
plot_embeddings_umap <- function(
  embeddings,
  included,
  excluded,
  n_neighbors = 15,
  min_dist = 0.1,
  metric = "cosine",
  n_epochs = 500,
  seed = 42,
  sample_n = NULL,
  point_size = 2,
  alpha = 0.5
) {
  # Resolve ids
  resolve_ids <- function(x) {
    if (length(x) == 1L && is.character(x) && file.exists(x)) {
      df <- utils::read.csv(x, stringsAsFactors = FALSE)
      if (!"id" %in% names(df)) stop("CSV at ", x, " must have a column named 'id'.")
      as.character(df$id)
    } else {
      as.character(x)
    }
  }
  incl_ids <- unique(resolve_ids(included))
  excl_ids <- unique(resolve_ids(excluded))

  ds <- arrow::open_dataset(
    embeddings,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  cols <- names(ds)
  vcols <- cols[grepl("^V[0-9]+$", cols)]
  if (!length(vcols)) stop("No embedding columns (V1..Vd) found in dataset.")
  vcols <- vcols[order(as.integer(sub("^V", "", vcols)))]

  df <- ds |>
    dplyr::select(id, dplyr::all_of(vcols)) |>
    dplyr::collect()

  # Optional sampling
  if (!is.null(sample_n) && is.finite(sample_n) && sample_n < nrow(df)) {
    set.seed(seed %||% 1)
    idx <- sample.int(nrow(df), sample_n)
    df <- df[idx, , drop = FALSE]
  }

  lab <- rep("other", nrow(df))
  if (length(excl_ids)) lab[df$id %in% excl_ids] <- "excluded"
  if (length(incl_ids)) lab[df$id %in% incl_ids] <- "included"
  lab <- factor(lab, levels = c("included", "excluded", "other"))

  X <- as.matrix(df[, vcols, drop = FALSE])
  if (!is.null(seed)) set.seed(seed)
  um <- uwot::umap(
    X,
    n_neighbors = n_neighbors,
    min_dist = min_dist,
    metric = metric,
    n_epochs = n_epochs,
    verbose = FALSE
  )

  plot_df <- data.frame(
    id = df$id,
    U1 = um[, 1],
    U2 = um[, 2],
    group = lab,
    stringsAsFactors = FALSE
  )

  ggplot2::ggplot(plot_df, ggplot2::aes(U1, U2, color = group)) +
    ggplot2::geom_point(alpha = alpha, size = point_size) +
    ggplot2::scale_color_manual(
      values = c(included = "#1b9e77", excluded = "#d95f02", other = "#aaaaaa")
    ) +
    ggplot2::labs(color = "Group") +
    ggplot2::theme_minimal()
}
