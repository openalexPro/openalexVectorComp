#' Calibrate a binary decision threshold by sweeping score quantiles
#'
#' Evaluates candidate thresholds derived from score quantiles using either the
#' F1-score or precision-at-recall objective. Returns the best-performing
#' threshold along with diagnostic metrics.
#'
#' @param target Binary reference labels (`0/1`).
#' @param scores Numeric scores where larger values indicate the positive class.
#' @param metric Optimisation target: `"f1"` (default) or `"precision_at_recall"`.
#' @param recall_min Minimum recall required when `metric = "precision_at_recall"`.
#'
#' @return List containing the selected threshold (`th`) and the associated
#'   `precision`, `recall`, and `f1` values.
#'
#' @examples
#' set.seed(1)
#' y <- sample(0:1, 200, replace = TRUE)
#' s <- y * runif(200, 0.6, 1) + (1 - y) * runif(200, 0, 0.4)
#' calibrate_threshold(y, s, metric = "f1")
#'
#' @importFrom stats quantile median
#' @export
calibrate_threshold <- function(target, scores, metric = c("f1", "precision_at_recall"), recall_min = 0.8) {
  metric <- match.arg(metric)
  probs <- seq(0, 1, by = 0.001)
  ths <- as.numeric(stats::quantile(scores, probs = probs, na.rm = TRUE))
  best <- list(th = stats::median(scores, na.rm = TRUE), score = -Inf,
               precision = NA_real_, recall = NA_real_, f1 = NA_real_)
  for (th in ths) {
    pred <- as.integer(scores >= th)
    tp <- sum(pred == 1 & target == 1); fp <- sum(pred == 1 & target == 0)
    fn <- sum(pred == 0 & target == 1)
    precision <- if ((tp + fp) > 0) tp / (tp + fp) else 0
    recall <- if ((tp + fn) > 0) tp / (tp + fn) else 0
    f1 <- if ((precision + recall) > 0) 2 * precision * recall / (precision + recall) else 0
    keep <- switch(metric,
                   f1 = f1,
                   precision_at_recall = if (recall >= recall_min) precision else -Inf)
    if (keep > best$score) best <- list(th = th, score = keep,
                                        precision = precision, recall = recall, f1 = f1)
  }
  best
}

