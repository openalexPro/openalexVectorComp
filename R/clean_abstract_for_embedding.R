#' Clean title/abstract rows into embedding-ready text
#'
#' Applies lightweight rule-based cleaning to `title`/`abstract` rows and
#' returns embedding-ready text plus a deterministic `text_hash`.
#'
#' @param df Data frame with columns `id`, `title`, and `abstract`.
#' @param mode Cleaning intensity: `"lenient"`, `"balanced"` (default), or
#'   `"strict"`.
#' @param no_abstract_policy Policy when abstract is missing/invalid:
#'   `"keep_title_only"` (default), `"discard"`, or `"conditional"`.
#' @param min_chars Optional minimum abstract length in characters after
#'   cleaning. If `NULL`, mode-specific defaults are used.
#' @param min_alpha_ratio Optional minimum ratio of alphabetic characters in the
#'   cleaned abstract. If `NULL`, mode-specific defaults are used.
#' @param placeholder_patterns Optional regex vector for placeholder abstract
#'   detection.
#' @param boilerplate_patterns Optional regex vector for publisher boilerplate
#'   detection.
#' @param html_patterns Optional regex vector for HTML/XML artifact detection.
#' @param return_flags If `TRUE`, include provenance/quality columns.
#'
#' @return A data frame with at least columns `id`, `text`, `text_hash`.
#'   When `return_flags = TRUE`, also includes `text_quality`,
#'   `abstract_raw_present`, `abstract_kept`, `discard_reason`, and
#'   `cleaning_mode`.
#' @export
clean_abstract_for_embedding <- function(
  df,
  mode = c("lenient", "balanced", "strict"),
  no_abstract_policy = c("keep_title_only", "discard", "conditional"),
  min_chars = NULL,
  min_alpha_ratio = NULL,
  placeholder_patterns = NULL,
  boilerplate_patterns = NULL,
  html_patterns = NULL,
  return_flags = TRUE
) {
  mode <- match.arg(mode)
  no_abstract_policy <- match.arg(no_abstract_policy)

  if (!is.data.frame(df)) {
    stop("`df` must be a data frame.")
  }
  req <- c("id", "title", "abstract")
  miss <- setdiff(req, names(df))
  if (length(miss)) {
    stop("`df` must contain columns: ", paste(miss, collapse = ", "))
  }

  mode_defaults <- switch(
    mode,
    lenient = list(min_chars = 40L, min_alpha_ratio = 0.30),
    balanced = list(min_chars = 80L, min_alpha_ratio = 0.55),
    strict = list(min_chars = 120L, min_alpha_ratio = 0.70)
  )
  if (is.null(min_chars)) min_chars <- mode_defaults$min_chars
  if (is.null(min_alpha_ratio)) min_alpha_ratio <- mode_defaults$min_alpha_ratio

  if (is.null(placeholder_patterns)) {
    placeholder_patterns <- c(
      "no abstract available",
      "abstract unavailable",
      "^not available$",
      "no summary available",
      "^n/?a$",
      "^none$"
    )
  }
  if (is.null(boilerplate_patterns)) {
    boilerplate_patterns <- c(
      "copyright",
      "all rights reserved",
      "creative commons",
      "published by",
      "springer",
      "elsevier",
      "wiley",
      "taylor\\s*&\\s*francis"
    )
  }
  if (is.null(html_patterns)) {
    html_patterns <- c(
      "<\\s*/?\\s*(div|p|span|br|xml)[^>]*>",
      "&nbsp;",
      "&amp;",
      "xmlns"
    )
  }

  normalize_text <- function(x) {
    x <- ifelse(is.na(x), "", as.character(x))
    x <- gsub("\\s+", " ", x)
    trimws(x)
  }
  safe_regex <- function(patterns) {
    paste0("(", paste(patterns, collapse = "|"), ")")
  }

  id <- normalize_text(df$id)
  title <- normalize_text(df$title)
  abstract <- normalize_text(df$abstract)
  abstract_raw_present <- nzchar(abstract)

  abs_clean <- gsub("<[^>]+>", " ", abstract)
  abs_clean <- normalize_text(abs_clean)

  # Remove duplicated title prefix at abstract start (regex-free for stability).
  has_title <- nzchar(title) & nzchar(abs_clean)
  idx <- which(has_title)
  if (length(idx)) {
    for (i in idx) {
      t_l <- tolower(title[i])
      a_l <- tolower(abs_clean[i])
      t_n <- nchar(t_l, type = "chars")
      if (t_n > 0L && startsWith(a_l, t_l)) {
        rem <- substr(abs_clean[i], t_n + 1L, nchar(abs_clean[i], type = "chars"))
        rem <- sub("^[\\s:;,.\\-]+", "", rem, perl = TRUE)
        abs_clean[i] <- normalize_text(rem)
      }
    }
  }

  placeholder_re <- safe_regex(placeholder_patterns)
  boiler_re <- safe_regex(boilerplate_patterns)
  html_re <- safe_regex(html_patterns)

  is_placeholder <- nzchar(abs_clean) & grepl(placeholder_re, tolower(abs_clean), perl = TRUE)
  has_boilerplate <- nzchar(abs_clean) & grepl(boiler_re, tolower(abs_clean), perl = TRUE)
  has_html <- nzchar(abs_clean) & grepl(html_re, tolower(abs_clean), perl = TRUE)

  n_chars <- nchar(abs_clean, type = "chars", allowNA = FALSE, keepNA = FALSE)
  alpha_chars <- nchar(gsub("[^[:alpha:]]", "", abs_clean), type = "chars")
  denom <- pmax(nchar(gsub("\\s+", "", abs_clean), type = "chars"), 1L)
  alpha_ratio <- alpha_chars / denom

  abstract_invalid <- !abstract_raw_present |
    !nzchar(abs_clean) |
    is_placeholder |
    (n_chars < as.integer(min_chars)) |
    (alpha_ratio < as.numeric(min_alpha_ratio)) |
    (has_boilerplate & n_chars < as.integer(min_chars) * 2L) |
    (has_html & n_chars < as.integer(min_chars) * 2L)

  discard_reason <- rep("", length(id))
  discard_reason[!abstract_raw_present] <- "missing_abstract"
  discard_reason[abstract_raw_present & !nzchar(abs_clean)] <- "empty_after_clean"
  discard_reason[is_placeholder] <- "placeholder"
  discard_reason[n_chars < as.integer(min_chars)] <- "too_short"
  discard_reason[alpha_ratio < as.numeric(min_alpha_ratio)] <- "low_alpha_ratio"
  discard_reason[has_boilerplate & n_chars < as.integer(min_chars) * 2L] <- "boilerplate_short"
  discard_reason[has_html & n_chars < as.integer(min_chars) * 2L] <- "html_artifact_short"

  title_ok <- nchar(title, type = "chars") >= 12L &
    (nchar(gsub("[^[:alpha:]]", "", title), type = "chars") / pmax(nchar(gsub("\\s+", "", title), type = "chars"), 1L)) >= 0.6

  keep_title_only <- switch(
    no_abstract_policy,
    keep_title_only = abstract_invalid,
    discard = rep(FALSE, length(id)),
    conditional = abstract_invalid & title_ok
  )

  text <- rep(NA_character_, length(id))
  with_abs <- !abstract_invalid & nzchar(abs_clean)
  text[with_abs] <- paste0("Title: ", title[with_abs], "\nAbstract: ", abs_clean[with_abs])
  text[keep_title_only] <- paste0("Title: ", title[keep_title_only])

  out <- data.frame(
    id = id,
    text = text,
    stringsAsFactors = FALSE
  )
  out <- out[
    !is.na(out$id) & !is.na(out$text) & nzchar(out$id) & nzchar(out$text),
    ,
    drop = FALSE
  ]
  out$text_hash <- vapply(
    out$text,
    function(x) digest::digest(x, algo = "xxhash64", serialize = FALSE),
    character(1)
  )

  if (isTRUE(return_flags)) {
    idx_map <- match(out$id, id)
    kept_abs <- with_abs[idx_map]
    out$text_quality <- ifelse(kept_abs, "title_abstract", "title_only")
    out$abstract_raw_present <- abstract_raw_present[idx_map]
    out$abstract_kept <- kept_abs
    out$discard_reason <- ifelse(kept_abs, "", discard_reason[idx_map])
    out$cleaning_mode <- rep(mode, nrow(out))
  }

  out
}
