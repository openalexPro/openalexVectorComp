# abstract-cleaning

## Purpose

This vignette documents the abstract-cleaning stage used before
embedding in `openalexVectorComp`.

It explains:

- what the default cleaner does,
- why each cleaning step exists,
- how different strictness modes change behavior,
- how missing abstracts are handled,
- how to provide your own custom cleaner.

The cleaner is central to embedding quality because it determines the
final text that is sent to the embedding backend.

## Where Cleaning Happens

[`embed_corpus()`](https://openalexpro.github.io/openalexVectorComp/reference/embed_corpus.md)
now accepts a pluggable preprocessor:

- `text_preprocessor` (function)
- `cleaner_args` (named list passed to that function)

By default:

``` r

text_preprocessor = clean_abstract_for_embedding
```

So this call:

``` r

embed_corpus(project_dir = "my_project")
```

implicitly applies default abstract cleaning before embeddings are
requested.

## Cleaner Contract

`clean_abstract_for_embedding(df, ...)` expects a data frame with:

- `id`
- `title`
- `abstract`

It returns a data frame containing at least:

- `id`
- `text` (final embedding input)
- `text_hash` (xxhash64 hash of `text`)

By default it also returns provenance columns:

- `text_quality` (`"title_abstract"` or `"title_only"`)
- `abstract_raw_present` (logical)
- `abstract_kept` (logical)
- `discard_reason` (character)
- `cleaning_mode` (`lenient`/`balanced`/`strict`)

[`embed_corpus()`](https://openalexpro.github.io/openalexVectorComp/reference/embed_corpus.md)
validates this contract and fails early if violated.

## Cleaning Pipeline (Step by Step)

The default cleaner applies a rule-based sequence:

1.  Normalize text:
    - collapse repeated whitespace
    - trim leading/trailing whitespace
    - convert `NA` to empty strings for robust handling
2.  Remove inline markup:
    - strips HTML-like tags (`<...>`) from abstracts
3.  Remove duplicated title prefix in abstract:
    - if abstract starts with the title, remove that repeated prefix
    - avoids over-weighting title words twice
4.  Detect low-quality abstract content:
    - placeholder phrases (`"no abstract available"`, `"n/a"`, etc.)
    - boilerplate-like text (`"copyright"`, publisher fragments)
    - HTML/XML artifact hints
    - too-short abstract length
    - low alphabetic character ratio
5.  Apply policy for invalid/missing abstract:
    - `keep_title_only` (default): keep record with `Title: ...`
    - `discard`: drop row from embedding input
    - `conditional`: keep title-only only when title quality is
      acceptable
6.  Build final embedding input text:
    - with valid abstract:
      - `Title: {title}\nAbstract: {abstract_clean}`
    - fallback:
      - `Title: {title}`
7.  Hash final text:
    - `text_hash = digest(text, algo = "xxhash64")`
    - used by
      [`embed_corpus()`](https://openalexpro.github.io/openalexVectorComp/reference/embed_corpus.md)
      resume logic (`id + text_hash`)

### Cleaning Flow Diagram

``` mermaid
flowchart TD
  A[Input rows: id, title, abstract] --> B[Normalize whitespace and NA handling]
  B --> C[Strip simple HTML/XML tags]
  C --> D[Remove duplicated title prefix from abstract]
  D --> E[Compute quality signals]
  E --> E1[Placeholder phrase]
  E --> E2[Boilerplate/artifact hint]
  E --> E3[Length threshold]
  E --> E4[Alphabetic-ratio threshold]
  E1 --> F{Abstract valid?}
  E2 --> F
  E3 --> F
  E4 --> F
  F -->|yes| G[Build text: Title + Abstract]
  F -->|no| H{no_abstract_policy}
  H -->|keep_title_only| I[Build text: Title only]
  H -->|conditional| J[Title quality check]
  J -->|pass| I
  J -->|fail| K[Discard row]
  H -->|discard| K
  G --> L[Compute text_hash]
  I --> L
  K --> M[No embedding request]
  L --> N[Return id, text, text_hash + flags]
```

## Why These Rules

The implementation deliberately avoids aggressive NLP preprocessing
(stemming/stopword removal/full punctuation stripping), because modern
embedding models generally perform better on natural text.

The default approach targets obvious noise while preserving semantics:

- **Keep recall** by default (`title-only` fallback).
- **Protect precision** by suppressing known junk patterns.
- **Preserve reproducibility** via deterministic `text_hash`.
- **Enable auditing** via provenance columns.

## Mode Behavior (`lenient`, `balanced`, `strict`)

`mode` controls threshold aggressiveness.

Conceptually:

- `lenient`: minimal filtering, retain more abstracts
- `balanced` (default): moderate filtering
- `strict`: stronger filtering, discard more weak abstracts

In practice, mode adjusts defaults such as:

- minimum abstract length
- minimum alphabetic character ratio

You can override thresholds explicitly via:

- `min_chars`
- `min_alpha_ratio`

## Example: Default Cleaning

``` r

library(openalexVectorComp)

df <- data.frame(
  id = c("W1", "W2", "W3"),
  title = c(
    "Biodiversity and ecosystem resilience",
    "Ocean circulation dynamics",
    "Land-use transition analysis"
  ),
  abstract = c(
    "Biodiversity and ecosystem resilience are central to adaptation planning.",
    "No abstract available",
    "<p>Published by Example Press</p>"
  ),
  stringsAsFactors = FALSE
)

cleaned <- clean_abstract_for_embedding(df)
cleaned[, c("id", "text_quality", "abstract_kept", "discard_reason", "text")]
```

Expected interpretation:

- `W1`: likely `title_abstract`
- `W2`: placeholder -\> fallback `title_only`
- `W3`: boilerplate/artifact may become `title_only` (mode-dependent)

## Example: Before/After on Individual Cases

The following example demonstrates three outcomes in one run:

- kept as `title_abstract`
- fallback to `title_only`
- removed (`discard` policy)

``` r

examples <- data.frame(
  id = c("A1", "A2", "A3", "A4"),
  title = c(
    "Ecosystem service valuation",
    "Marine heatwave impacts",
    "Forest carbon accounting",
    "Urban biodiversity monitoring"
  ),
  abstract = c(
    # duplicated title prefix -> should be removed from abstract start
    "Ecosystem service valuation examines policy trade-offs and uncertainty.",
    # placeholder -> invalid abstract
    "No abstract available",
    # boilerplate/short artifact -> likely invalid
    "<p>Copyright 2025 Elsevier. All rights reserved.</p>",
    # clean abstract
    "We present a field protocol for repeat biodiversity monitoring in cities."
  ),
  stringsAsFactors = FALSE
)

# Keep title-only fallback for invalid abstracts
keep_case <- clean_abstract_for_embedding(
  examples,
  mode = "balanced",
  no_abstract_policy = "keep_title_only"
)
keep_case[, c("id", "text_quality", "abstract_kept", "discard_reason", "text")]

# Discard invalid abstracts entirely
discard_case <- clean_abstract_for_embedding(
  examples,
  mode = "balanced",
  no_abstract_policy = "discard"
)
discard_case[, c(
  "id",
  "text_quality",
  "abstract_kept",
  "discard_reason",
  "text"
)]
```

Interpretation:

- In `keep_case`, `A2`/`A3` are retained as `title_only`.
- In `discard_case`, invalid rows are not returned at all.
- `A1` shows title-prefix cleanup before building final text.

## Example: Change Missing-Abstract Policy

``` r

drop_missing <- clean_abstract_for_embedding(
  df,
  no_abstract_policy = "discard"
)
nrow(drop_missing)
```

With `discard`, rows with invalid/missing abstracts are removed from
embedding input entirely.

## Example: Use a Stricter Cleaning Configuration

``` r

strict_clean <- clean_abstract_for_embedding(
  df,
  mode = "strict",
  min_chars = 140,
  min_alpha_ratio = 0.70
)
```

This configuration is useful for high-precision workflows where noisy
abstracts must be aggressively filtered.

## Using Custom Patterns

You can override detection patterns for
placeholders/boilerplate/artifacts:

``` r

custom_clean <- clean_abstract_for_embedding(
  df,
  placeholder_patterns = c("abstract unavailable", "^none$"),
  boilerplate_patterns = c("all rights reserved", "publisher notice"),
  html_patterns = c("<[^>]+>", "&nbsp;")
)
```

## Integration with `embed_corpus()`

Default integration:

``` r

embed_corpus(
  project_dir = "my_project",
  cleaner_args = list(
    mode = "balanced",
    no_abstract_policy = "keep_title_only"
  )
)
```

Custom preprocessor integration:

``` r

my_preprocessor <- function(df, suffix = "") {
  text <- paste0("Title: ", df$title, " ", suffix)
  data.frame(
    id = as.character(df$id),
    text = text,
    text_hash = vapply(
      text,
      digest::digest,
      character(1),
      algo = "xxhash64",
      serialize = FALSE
    ),
    text_quality = "custom",
    stringsAsFactors = FALSE
  )
}

embed_corpus(
  project_dir = "my_project",
  text_preprocessor = my_preprocessor,
  cleaner_args = list(suffix = "[custom]")
)
```

## Preprocessor Validation in `embed_corpus()`

[`embed_corpus()`](https://openalexpro.github.io/openalexVectorComp/reference/embed_corpus.md)
validates custom preprocessor output:

- must return a data frame
- must contain `id`, `text`, `text_hash`
- no duplicated `id`
- no ids outside the current input batch

Rows with empty/`NA` `id` or `text` are dropped before embedding.

## Output Provenance and Auditability

When using default cleaner flags, embedding output parquet includes
cleaning provenance columns in addition to embedding metadata
(`provider`, `model_id`, `created_at`, `text_hash`, `V1..Vd`).

This makes it straightforward to:

- analyze quality tiers (`title_abstract` vs `title_only`)
- filter rows for downstream scoring/calibration
- debug why some abstracts were not kept

## Recommended Operational Defaults

For most large OpenAlex-style corpora:

- `mode = "balanced"`
- `no_abstract_policy = "keep_title_only"`
- keep provenance columns enabled (`return_flags = TRUE`)

Then tune stricter settings only if evaluation shows too much noise in
downstream relevance scoring.

## Summary

[`clean_abstract_for_embedding()`](https://openalexpro.github.io/openalexVectorComp/reference/clean_abstract_for_embedding.md)
provides a practical, auditable, and pluggable cleaning layer for
embedding pipelines:

- conservative semantic-preserving cleaning
- configurable strictness and missing-abstract policy
- deterministic hashing for resume
- clear provenance for analysis and debugging
