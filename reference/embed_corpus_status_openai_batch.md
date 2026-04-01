# Inspect OpenAI batch state for a label

Inspect OpenAI batch state for a label

## Usage

``` r
embed_corpus_status_openai_batch(
  project_dir,
  label = "corpus",
  refresh_remote = TRUE
)
```

## Arguments

- project_dir:

  Project root directory.

- label:

  Embedding label.

- refresh_remote:

  Logical; if `TRUE`, refresh non-terminal job statuses from OpenAI
  before returning.

## Value

A data frame with one row per tracked job.
