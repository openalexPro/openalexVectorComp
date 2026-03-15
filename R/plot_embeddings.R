#' Plot embeddings via PCA, colored by arbitrary labels
#'
#' Reads an embeddings Parquet dataset (produced by [embed_corpus()]) with columns
#' `id` and `V1..Vd`, computes a PCA on the embedding matrix, and returns a
#' scatter plot of the first two principal components. Points are colored by
#' labels provided via `labels`. Rows not found in `labels` are shown as
#' `"other"`.
#'
#' @param embeddings Path to a Parquet file or dataset directory containing
#'   columns `id` and `V1..Vd`.
#' @param labels Label mapping for ids. Supported formats:
#'   1) data frame with columns `id` and `label`,
#'   2) path to CSV with columns `id` and `label`,
#'   3) named character vector where names are ids and values are labels,
#'   4) named list where each element is an id vector for that label.
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
#'   labels = data.frame(
#'     id = c("W1", "W2", "W10"),
#'     label = c("reference", "reference", "corpus")
#'   )
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
  labels,
  center = TRUE,
  scale. = FALSE,
  point_size = 2,
  alpha = 0.5
) {
  labels_df <- .plot_resolve_labels(labels)

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

  # Labels with precedence by row order in labels_df; default to "other".
  lab <- rep("other", nrow(df))
  if (nrow(labels_df)) {
    idx <- match(df$id, labels_df$id)
    has_lab <- !is.na(idx)
    lab[has_lab] <- labels_df$label[idx[has_lab]]
  }
  label_levels <- unique(c(sort(unique(labels_df$label)), "other"))
  lab <- factor(lab, levels = label_levels)

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
    ggplot2::scale_color_hue() +
    ggplot2::labs(color = "Group") +
    ggplot2::theme_minimal()
}

#' Plot embeddings via UMAP, colored by arbitrary labels
#'
#' Computes a 2D UMAP projection of `V1..Vd` and returns a scatter plot colored
#' by `labels` membership. Uses cosine distance by default to align
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
  labels,
  n_neighbors = 15,
  min_dist = 0.1,
  metric = "cosine",
  n_epochs = 500,
  seed = 42,
  sample_n = NULL,
  point_size = 2,
  alpha = 0.5
) {
  labels_df <- .plot_resolve_labels(labels)

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
    `%||%` <- function(x, y) if (is.null(x)) y else x
    set.seed(seed %||% 1)
    idx <- sample.int(nrow(df), sample_n)
    df <- df[idx, , drop = FALSE]
  }

  lab <- rep("other", nrow(df))
  if (nrow(labels_df)) {
    idx <- match(df$id, labels_df$id)
    has_lab <- !is.na(idx)
    lab[has_lab] <- labels_df$label[idx[has_lab]]
  }
  label_levels <- unique(c(sort(unique(labels_df$label)), "other"))
  lab <- factor(lab, levels = label_levels)

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
    ggplot2::scale_color_hue() +
    ggplot2::labs(color = "Group") +
    ggplot2::theme_minimal()
}

.plot_resolve_labels <- function(labels) {
  as_labels_df <- function(df) {
    if (!all(c("id", "label") %in% names(df))) {
      stop("Label data must contain columns 'id' and 'label'.")
    }
    out <- data.frame(
      id = as.character(df$id),
      label = as.character(df$label),
      stringsAsFactors = FALSE
    )
    out <- out[!is.na(out$id) & nzchar(out$id) & !is.na(out$label) & nzchar(out$label), , drop = FALSE]
    if (anyDuplicated(out$id)) {
      stop("Label mapping contains duplicated ids.")
    }
    out
  }

  if (is.data.frame(labels)) {
    return(as_labels_df(labels))
  }
  if (is.character(labels) && length(labels) == 1L && file.exists(labels)) {
    return(as_labels_df(utils::read.csv(labels, stringsAsFactors = FALSE)))
  }
  if (is.character(labels) && !is.null(names(labels))) {
    out <- data.frame(
      id = as.character(names(labels)),
      label = as.character(unname(labels)),
      stringsAsFactors = FALSE
    )
    return(as_labels_df(out))
  }
  if (is.list(labels) && !is.null(names(labels))) {
    parts <- lapply(names(labels), function(lbl) {
      data.frame(
        id = as.character(labels[[lbl]]),
        label = lbl,
        stringsAsFactors = FALSE
      )
    })
    out <- do.call(rbind, parts)
    return(as_labels_df(out))
  }

  stop(
    "`labels` must be one of: data.frame(id,label), CSV path, ",
    "named character vector (names=id), or named list(label -> ids)."
  )
}
