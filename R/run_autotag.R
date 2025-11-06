#' End-to-end binary auto-tagging workflow
#'
#' Embeds labeled and unlabeled texts with [tei_embed()], scores them using a
#' prototype margin plus ridge logistic regression ensemble, calibrates a
#' decision threshold, writes scores to Parquet, and returns the components.
#'
#' @param df_labeled Data frame with columns `id`, `text`, `label` (`0/1`).
#' @param df_unlabeled Data frame with columns `id`, `text`.
#' @param tei_url TEI `/embed` endpoint passed to [tei_embed()].
#' @param use_qdrant Logical flag reserved for future Qdrant augmentation.
#' @param qdrant Named list of Qdrant settings (currently unused unless
#'   extending the pipeline).
#' @param output_parquet Path where the combined scores should be written.
#'
#' @return List containing the tibble of scores, the calibrated threshold, the
#'   calibration diagnostics, and the Parquet path.
#'
#' @details
#' The pipeline performs the following steps:
#' 1. Embed labeled and unlabeled texts via [tei_embed()].
#' 2. Compute prototype-margin scores for both sets with [prototype_margin()].
#' 3. Fit ridge logistic regression ([fit_ridge()]) and predict probabilities
#'    with [predict_ridge()].
#' 4. Average prototype and ridge scores to form an ensemble.
#' 5. Calibrate a decision threshold using [calibrate_threshold()].
#' 6. Persist results to Parquet with [`arrow::write_parquet()`].
#'
#' @examples
#' \dontrun{
#' df_lab <- tibble::tibble(
#'   id = 1:10,
#'   text = paste("Short text", 1:10),
#'   label = sample(0:1, 10, replace = TRUE)
#' )
#' df_unl <- tibble::tibble(
#'   id = 11:13,
#'   text = paste("Short text", 11:13)
#' )
#' res <- run_autotag(df_lab, df_unl)
#' res$threshold
#' }
#'
#' @importFrom dplyr bind_rows
#' @importFrom tibble tibble
#' @importFrom arrow write_parquet
#' @export
run_autotag <- function(
  df_labeled,
  df_unlabeled,
  tei_url = "http://localhost:8080/embed",
  use_qdrant = FALSE,
  qdrant = list(collection = "bioagora", base = "http://localhost:6333", k = 25),
  output_parquet = "autotag_scores.parquet"
) {
  stopifnot(all(c("id", "text", "label") %in% names(df_labeled)))
  stopifnot(all(c("id", "text") %in% names(df_unlabeled)))

  # 1) Embeddings
  X_lab <- tei_embed(df_labeled$text, tei_url = tei_url)
  X_unl <- tei_embed(df_unlabeled$text, tei_url = tei_url)

  # 2) Prototype margin
  m_lab <- prototype_margin(X_lab, df_labeled$label, X_lab)
  m_unl <- prototype_margin(X_lab, df_labeled$label, X_unl)

  # 3) Ridge logistic
  fit <- fit_ridge(X_lab, df_labeled$label)
  r_lab <- predict_ridge(fit, X_lab)
  r_unl <- predict_ridge(fit, X_unl)

  # 4) Optional: combine with Qdrant kNN vote (not implemented here by default)
  # (User can extend using qdrant_search_batch and a vote function.)

  # 5) Ensemble (simple mean)
  s_lab <- (m_lab + r_lab) / 2
  s_unl <- (m_unl + r_unl) / 2

  # 6) Calibrate threshold
  best <- calibrate_threshold(df_labeled$label, s_lab, metric = "f1")
  th <- best$th

  # 7) Decisions
  decision_lab <- as.integer(s_lab >= th)
  decision_unl <- as.integer(s_unl >= th)

  out <- dplyr::bind_rows(
    tibble::tibble(id = df_labeled$id, score = s_lab, decision = decision_lab, split = "labeled"),
    tibble::tibble(id = df_unlabeled$id, score = s_unl, decision = decision_unl, split = "unlabeled")
  )
  arrow::write_parquet(out, output_parquet)
  list(scores = out, threshold = th, calib = best, parquet = output_parquet)
}

