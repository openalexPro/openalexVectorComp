#' Calibrate threshold from Parquet scores by streaming batches
#'
#' Sweeps candidate thresholds over scores stored in a Parquet dataset without
#' loading all rows into memory. Uses two passes: first to determine the score
#' range on the labeled subset; second to accumulate confusion counts across a
#' fixed grid of thresholds. Returns the best threshold per the chosen metric.
#'
#' You can provide labels either as two vectors of ids (`included`/`excluded`)
#' or as a separate labels Parquet with columns `id` and `label` (`0/1`).
#'
#' @param scores_parquet Path to a Parquet dataset (file or directory) with at
#'   least columns `id` and the score column.
#' @param score_col Name of the score column to calibrate (e.g., "ensemble",
#'   "relevance_score", or "margin").
#' @param included Path to a CSV file with a column `id` of positive examples
#'   (label `1`). Ignored when `labels_parquet` is provided.
#' @param excluded Path to a CSV file with a column `id` of negative examples
#'   (label `0`). Ignored when `labels_parquet` is provided.
#' @param labels_parquet Optional Parquet dataset path with columns `id` and
#'   `label` (`0/1`). If provided, it is collected in-memory and matched on `id`.
#'   Prefer this when the labeled set is reasonably small.
#' @param metric Optimisation target: `"f1"` (default) or
#'   `"precision_at_recall"`.
#' @param recall_min Minimum recall required when `metric = "precision_at_recall"`.
#' @param thresholds Optional numeric vector of thresholds to evaluate. If
#'   `NULL`, a regular grid between observed min/max is used (see
#'   `n_thresholds`).
#' @param n_thresholds Number of thresholds to generate when `thresholds` is
#'   `NULL` (default `1001`).
#' @param batch_size Approximate Arrow scan batch size.
#' @param verbose Logical; print progress messages.
#'
#' @return List containing the selected threshold (`th`) and the associated
#'   `precision`, `recall`, and `f1` values.
#'
#' @examples
#' \dontrun{
#' best <- calibrate_threshold(
#'   scores_parquet = "output/scores/",
#'   score_col = "ensemble",
#'   included = "included.csv",
#'   excluded = "excluded.csv",
#'   batch_size = 200000
#' )
#' best$th
#' }
#'
#' @importFrom arrow open_dataset Scanner
#' @importFrom dplyr all_of
#' @export
calibrate_threshold <- function(
  scores_parquet,
  score_col,
  included = NULL,
  excluded = NULL,
  labels_parquet = NULL,
  metric = c("f1", "precision_at_recall"),
  recall_min = 0.8,
  thresholds = NULL,
  n_thresholds = 1001,
  batch_size = 100000,
  verbose = TRUE
) {
  included <- read.csv(included)$id
  excluded <- read.csv(excluded)$id
  stopifnot(is.character(score_col), length(score_col) == 1)
  if (is.null(labels_parquet)) {
    if (is.null(included) || is.null(excluded)) {
      stop(
        "Provide either `included` and `excluded` id vectors, or `labels_parquet`."
      )
    }
    included <- unique(included)
    excluded <- unique(excluded)
  }

  metric <- match.arg(metric)

  # Optional labels from parquet (collected in-memory; assumed small)
  labels_df <- NULL
  if (!is.null(labels_parquet)) {
    lab_ds <- arrow::open_dataset(
      labels_parquet,
      factory_options = list(exclude_invalid_files = TRUE)
    )
    lab_cols <- c("id", "label")
    if (!all(lab_cols %in% names(lab_ds))) {
      stop("`labels_parquet` must have columns: id, label")
    }
    labels_df <- dplyr::collect(arrow::Scanner$create(
      lab_ds,
      columns = lab_cols
    )$ToTable())
  }

  ds <- arrow::open_dataset(
    scores_parquet,
    factory_options = list(exclude_invalid_files = TRUE)
  )
  if (!all(c("id", score_col) %in% names(ds))) {
    stop("`scores_parquet` must contain columns `id` and `", score_col, "`.")
  }

  # Helper to attach labels to a batch data.frame and filter to labeled rows
  attach_labels <- function(df) {
    if (!is.null(labels_df)) {
      df <- merge(
        df[, c("id", score_col)],
        labels_df,
        by = "id",
        all.x = FALSE,
        all.y = FALSE
      )
      df <- df[!is.na(df$label), , drop = FALSE]
      df$label <- as.integer(df$label)
      return(df)
    }
    keep <- df$id %in% included | df$id %in% excluded
    if (!any(keep)) {
      return(df[0, , drop = FALSE])
    }
    df <- df[keep, c("id", score_col), drop = FALSE]
    df$label <- ifelse(df$id %in% included, 1L, 0L)
    df
  }

  # First pass: get min/max over labeled subset (if thresholds not given)
  if (is.null(thresholds)) {
    if (verbose) {
      message("[calib] First pass: computing score range...")
    }
    s_min <- Inf
    s_max <- -Inf
    reader <- arrow::Scanner$create(
      ds,
      columns = c("id", score_col),
      batch_size = as.integer(batch_size)
    )$ToRecordBatchReader()
    repeat {
      batch <- reader$read_next_batch()
      if (is.null(batch)) {
        break
      }
      df <- as.data.frame(batch, stringsAsFactors = FALSE)
      if (!nrow(df)) {
        next
      }
      df <- attach_labels(df)
      if (!nrow(df)) {
        next
      }
      s <- df[[score_col]]
      s_min <- min(s_min, min(s, na.rm = TRUE))
      s_max <- max(s_max, max(s, na.rm = TRUE))
    }
    if (!is.finite(s_min) || !is.finite(s_max)) {
      stop("No labeled rows found in scores dataset.")
    }
    thresholds <- seq(s_min, s_max, length.out = n_thresholds)
  }

  # Second pass: accumulate counts across thresholds
  if (verbose) {
    message(
      "[calib] Second pass: sweeping ",
      length(thresholds),
      " thresholds..."
    )
  }
  tp <- numeric(length(thresholds))
  fp <- numeric(length(thresholds))
  fn <- numeric(length(thresholds))

  reader <- arrow::Scanner$create(
    ds,
    columns = c("id", score_col),
    batch_size = as.integer(batch_size)
  )$ToRecordBatchReader()

  batch_idx <- 0L
  repeat {
    batch <- reader$read_next_batch()
    if (is.null(batch)) {
      break
    }
    df <- as.data.frame(batch, stringsAsFactors = FALSE)
    if (!nrow(df)) {
      next
    }
    df <- attach_labels(df)
    if (!nrow(df)) {
      next
    }

    scores <- df[[score_col]]
    labels <- as.integer(df$label)
    keep <- is.finite(scores) & !is.na(labels)
    if (!any(keep)) {
      next
    }
    scores <- scores[keep]
    labels <- labels[keep]

    o <- order(scores)
    scores_s <- scores[o]
    labels_s <- labels[o]
    n <- length(scores_s)
    if (n == 0) {
      next
    }
    # cumulative positives from the end (suffix sums)
    pos_suffix <- rev(cumsum(rev(labels_s)))
    # map thresholds to first index with score >= th
    idx <- findInterval(thresholds, scores_s) + 1L
    idx[idx > n] <- n + 1L

    # values when idx in [1..n]
    sel <- idx <= n
    tp_batch <- numeric(length(idx))
    tot_suf <- numeric(length(idx))
    tp_batch[sel] <- pos_suffix[idx[sel]]
    tot_suf[sel] <- (n - idx[sel] + 1L)
    # idx == n+1 => no predicted positives
    tp <- tp + tp_batch
    fp <- fp + (tot_suf - tp_batch)
    fn <- fn + (sum(labels_s) - tp_batch)

    batch_idx <- batch_idx + 1L
    if (verbose && (batch_idx %% 10L == 0L)) {
      message("[calib] processed ", batch_idx, " batches...")
    }
  }

  precision <- ifelse((tp + fp) > 0, tp / (tp + fp), 0)
  recall <- ifelse((tp + fn) > 0, tp / (tp + fn), 0)
  f1 <- ifelse(
    (precision + recall) > 0,
    2 * precision * recall / (precision + recall),
    0
  )

  score_vec <- switch(
    metric,
    f1 = f1,
    precision_at_recall = ifelse(recall >= recall_min, precision, -Inf)
  )
  best_i <- which.max(score_vec)
  list(
    th = thresholds[best_i],
    precision = precision[best_i],
    recall = recall[best_i],
    f1 = f1[best_i],
    thresholds = thresholds,
    precision_curve = precision,
    recall_curve = recall,
    f1_curve = f1
  )
}
