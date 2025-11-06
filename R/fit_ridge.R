#' Cross-validated ridge logistic regression using glmnet
#'
#' Wraps `glmnet::cv.glmnet()` with `alpha = 0` for ridge regularisation. The
#' function coerces labels to numeric and returns the `cv.glmnet` object.
#'
#' @param X Numeric feature matrix (`n x d`).
#' @param y Binary response vector (`0/1`).
#'
#' @return A `cv.glmnet` fit object.
#'
#' @examples
#' set.seed(1)
#' X <- matrix(rnorm(30), nrow = 10)
#' y <- sample(0:1, 10, replace = TRUE)
#' fit <- fit_ridge(X, y)
#' fit$lambda.min
#'
#' @importFrom glmnet cv.glmnet
#' @export
fit_ridge <- function(X, y) {
  y <- as.numeric(y)
  glmnet::cv.glmnet(X, y, family = "binomial", alpha = 0, nfolds = 5)
}

