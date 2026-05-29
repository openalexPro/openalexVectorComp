# Collect completed OpenAI batch embedding jobs

Collect completed OpenAI batch embedding jobs

## Usage

``` r
batch_collect_openai(
  project_dir,
  backend = backend_config(provider = "openai"),
  label = "corpus",
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Project root directory.

- backend:

  Backend configuration from
  [`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).
  Must use `provider = "openai"`.

- label:

  Embedding label partition to collect into.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns a list with collection summary.
