#' Cosine similarity between two numeric vectors
#'
#' Computes cosine similarity for two numeric vectors of equal length. Returns
#' `NA_real_` if either vector has zero norm.
#'
#' @param a Numeric vector.
#' @param b Numeric vector or numeric matrix with embeddings in rows.
#'
#' @return A single numeric similarity value in `[-1, 1]`, or `NA_real_` when
#'   undefined.
#' @export
cosine_similarity <- function(a, b) {
  if (is.matrix(b)) {
    denom <- sqrt(sum(a * a)) * sqrt(rowSums(b * b))
    denom[denom == 0] <- NA_real_
    return(drop((b %*% a) / denom))
  }

  denom <- sqrt(sum(a * a)) * sqrt(sum(b * b))
  if (denom == 0) {
    return(NA_real_)
  }
  sum(a * b) / denom
}

#' Cosine distance between two numeric vectors
#'
#' Computes cosine distance as `1 - cosine_similarity(a, b)`.
#'
#' @param a Numeric vector.
#' @param b Numeric vector or numeric matrix with embeddings in rows.
#'
#' @return A single numeric distance value, or `NA_real_` when undefined.
#' @export
cosine_distance <- function(a, b) {
  1 - cosine_similarity(a, b)
}
