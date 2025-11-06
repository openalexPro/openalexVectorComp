#' One-vs-rest multi-label auto-tagging pipeline
#'
#' For each tag in a long labeled data frame, this function trains the same
#' prototype + ridge ensemble as [run_autotag()] and applies it to labeled and
#' unlabeled items, storing scores in long format.
#'
#' @param df_labeled_long Data frame with columns `id`, `text`, `tag`, `label`
#'   (`0/1`) for the labeled subset.
#' @param df_unlabeled Data frame with columns `id`, `text`.
#' @param tei_url TEI `/embed` endpoint passed to [tei_embed()].
#' @param output_parquet Where to write the resulting Parquet file.
#'
#' @return List containing the long-format tibble of scores (`scores`) and the
#'   Parquet path (`parquet`).
#'
#' @details
#' All unique texts are embedded once; results are reused per tag to avoid
#' redundant TEI calls. Each tag is processed independently with
#' [prototype_margin()], [fit_ridge()], and [calibrate_threshold()].
#'
#' @examples
#' \dontrun{
#' df_lab <- tibble::tibble(
#'   id = rep(1:5, each = 2),
#'   text = paste("Doc", rep(1:5, each = 2)),
#'   tag = rep(c("A", "B"), times = 5),
#'   label = sample(0:1, 10, replace = TRUE)
#' )
#' df_unl <- tibble::tibble(id = 6:7, text = paste("Doc", 6:7))
#' res <- run_autotag_multilabel(df_lab, df_unl)
#' head(res$scores)
#' }
#'
#' @importFrom stats setNames
#' @importFrom dplyr bind_rows
#' @importFrom tibble tibble
#' @importFrom arrow write_parquet
#' @export
run_autotag_multilabel <- function(
  df_labeled_long,
  df_unlabeled,
  tei_url = "http://localhost:8080/embed",
  output_parquet = "autotag_multilabel.parquet"
) {
  # Embed all texts once
  all_ids <- unique(c(df_labeled_long$id, df_unlabeled$id))
  id_to_text <- c(stats::setNames(df_labeled_long$text, df_labeled_long$id),
                  stats::setNames(df_unlabeled$text, df_unlabeled$id))
  id_to_text <- id_to_text[match(all_ids, names(id_to_text))]
  X_all <- tei_embed(unname(id_to_text), tei_url = tei_url)
  rownames(X_all) <- all_ids

  # Prepare labeled/unlabeled index
  unl_ids <- df_unlabeled$id

  tags <- unique(df_labeled_long$tag)
  res <- lapply(tags, function(tag) {
    df_tag <- df_labeled_long[df_labeled_long$tag == tag, , drop = FALSE]
    lab_ids <- df_tag$id
    y <- df_tag$label
    X_lab <- X_all[lab_ids, , drop = FALSE]
    X_unl <- X_all[unl_ids, , drop = FALSE]

    m_lab <- prototype_margin(X_lab, y, X_lab)
    m_unl <- prototype_margin(X_lab, y, X_unl)
    fit <- fit_ridge(X_lab, y)
    r_lab <- predict_ridge(fit, X_lab)
    r_unl <- predict_ridge(fit, X_unl)
    s_lab <- (m_lab + r_lab) / 2
    s_unl <- (m_unl + r_unl) / 2

    best <- calibrate_threshold(y, s_lab, metric = "f1")
    th <- best$th

    dplyr::bind_rows(
      tibble::tibble(id = lab_ids, tag = tag, score = s_lab, decision = as.integer(s_lab >= th), split = "labeled"),
      tibble::tibble(id = unl_ids, tag = tag, score = s_unl, decision = as.integer(s_unl >= th), split = "unlabeled")
    )
  })
  out <- dplyr::bind_rows(res)
  arrow::write_parquet(out, output_parquet)
  list(scores = out, parquet = output_parquet)
}

