# Clean title/abstract rows into embedding-ready text

Applies lightweight rule-based cleaning to `title`/`abstract` rows and
returns embedding-ready text plus a deterministic `text_hash`.

## Usage

``` r
clean_abstract_for_embedding(
  df,
  mode = c("lenient", "balanced", "strict"),
  no_abstract_policy = c("keep_title_only", "discard", "conditional"),
  min_chars = NULL,
  min_alpha_ratio = NULL,
  placeholder_patterns = NULL,
  boilerplate_patterns = NULL,
  html_patterns = NULL,
  return_flags = TRUE
)
```

## Arguments

- df:

  Data frame with columns `id`, `title`, and `abstract`.

- mode:

  Cleaning intensity: `"lenient"`, `"balanced"` (default), or
  `"strict"`.

- no_abstract_policy:

  Policy when abstract is missing/invalid: `"keep_title_only"`
  (default), `"discard"`, or `"conditional"`.

- min_chars:

  Optional minimum abstract length in characters after cleaning. If
  `NULL`, mode-specific defaults are used.

- min_alpha_ratio:

  Optional minimum ratio of alphabetic characters in the cleaned
  abstract. If `NULL`, mode-specific defaults are used.

- placeholder_patterns:

  Optional regex vector for placeholder abstract detection.

- boilerplate_patterns:

  Optional regex vector for publisher boilerplate detection.

- html_patterns:

  Optional regex vector for HTML/XML artifact detection.

- return_flags:

  If `TRUE`, include provenance/quality columns.

## Value

A data frame with at least columns `id`, `text`, `text_hash`. When
`return_flags = TRUE`, also includes `text_quality`,
`abstract_raw_present`, `abstract_kept`, `discard_reason`, and
`cleaning_mode`.
