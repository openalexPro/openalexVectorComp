# Collect completed OpenAI batch embedding jobs

Collect completed OpenAI batch embedding jobs

## Usage

``` r
embed_corpus_collect_openai_batch(
  project_dir,
  backend = embedding_backend_config(provider = "openai"),
  label = "corpus",
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Project root directory.

- backend:

  Backend configuration from
  [`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).
  Must use `provider = "openai"`.

- label:

  Embedding label partition to collect into.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns a list with collection summary.
