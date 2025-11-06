#' Predict probabilities from a ridge logistic `cv.glmnet` fit
#'
#' Convenience wrapper around `predict()` that returns a numeric vector of
#' probabilities for new observations.
#'
#' @param fit A `cv.glmnet` object, e.g. from [fit_ridge()].
#' @param X_new Numeric matrix with the same number of columns as used for
#'   training.
#' @param s Lambda value to use (default `"lambda.1se"`).
#'
#' @return Numeric vector of predicted probabilities.
#'
#' @examples
#' set.seed(1)
#' X <- matrix(rnorm(30), nrow = 10)
#' y <- sample(0:1, 10, replace = TRUE)
#' fit <- fit_ridge(X, y)
#' predict_ridge(fit, X)
#'
#' @export
predict_ridge <- function(fit, X_new, s = "lambda.1se") {
  as.numeric(predict(fit, X_new, s = s, type = "response"))
}
