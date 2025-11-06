#' Cosine similarity between two numeric vectors
#'
#' Computes the cosine similarity by normalizing each vector with `unit_row()`
#' and summing the product of their elements.
#'
#' @param a Numeric vector.
#' @param b Numeric vector of the same length as `a`.
#'
#' @return Scalar cosine similarity.
#'
#' @examples
#' cos_sim(c(1, 0, 0), c(0.2, 0, 0))
#'
#' @keywords internal
cos_sim <- function(a, b) sum(unit_row(a) * unit_row(b))

