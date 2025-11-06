#' Score points by distance to positive and negative prototypes
#'
#' Computes cosine similarity against the mean vector of the positive class and
#' the mean vector of the negative class, returning their difference. Useful as
#' a lightweight classifier for binary problems.
#'
#' @param X_labeled Numeric matrix (`n x d`) of labeled embeddings.
#' @param y_labeled Integer or logical vector of labels (`0/1`).
#' @param X_new Numeric matrix of embeddings to score.
#'
#' @return Numeric vector of length `nrow(X_new)` containing prototype margins
#'   (higher implies more similarity to the positive prototype).
#'
#' @examples
#' set.seed(1)
#' X <- matrix(rnorm(20), nrow = 5)
#' y <- c(1, 1, 0, 0, 1)
#' prototype_margin(X, y, X)
#'
#' @export
prototype_margin <- function(
  X_labeled,
  y_labeled,
  X_new
) {
  stopifnot(nrow(X_labeled) == length(y_labeled))
  y_labeled <- as.integer(y_labeled)
  pos <- colMeans(X_labeled[y_labeled == 1, , drop = FALSE])
  neg <- colMeans(X_labeled[y_labeled == 0, , drop = FALSE])
  sims_pos <- as.numeric(
    (X_new / sqrt(rowSums(X_new^2) + 1e-12)) %*%
      (pos / sqrt(sum(pos^2) + 1e-12))
  )
  sims_neg <- as.numeric(
    (X_new / sqrt(rowSums(X_new^2) + 1e-12)) %*%
      (neg / sqrt(sum(neg^2) + 1e-12))
  )
  sims_pos - sims_neg
}
