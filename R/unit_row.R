#' Normalize a numeric vector to unit length
#'
#' Divides a vector by its Euclidean norm with a small stabilizing constant to
#' avoid division by zero.
#'
#' @param x Numeric vector.
#'
#' @return Numeric vector of the same length scaled to unit norm.
#'
#' @examples
#' v <- c(3, 4)
#' unit_row(v)
#'
#' @keywords internal
unit_row <- function(x) x / sqrt(sum(x^2) + 1e-12)

