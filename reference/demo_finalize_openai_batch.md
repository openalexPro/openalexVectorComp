# Finalize OpenAI demo batch jobs and compare direct vs batch embeddings

Runs OpenAI batch status/collect for a prepared demo workspace and, when
batch embeddings are available, computes direct-vs-batch vector
comparison. Comparison artifacts are written to:
`project/openai_batch_comparison/label=<label>/`.

## Usage

``` r
demo_finalize_openai_batch(
  demo_dir,
  api_key = NULL,
  label = "corpus_batch",
  refresh_remote = TRUE,
  verbose = TRUE
)
```

## Arguments

- demo_dir:

  Demo workspace directory created by
  [`run_demo_openai()`](https://openalexpro.github.io/openalexVectorComp/reference/run_demo_openai.md)
  or
  [`run_demo_openalex()`](https://openalexpro.github.io/openalexVectorComp/reference/run_demo_openalex.md).

- api_key:

  Optional OpenAI API key. If provided, it is set in `OVC_API_TOKEN` for
  the duration of this call.

- label:

  Batch embedding label to finalize. Defaults to `"corpus_batch"`.

- refresh_remote:

  Logical; forwarded to
  [`batch_status_openai()`](https://openalexpro.github.io/openalexVectorComp/reference/batch_status_openai.md).

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns a list containing status/collect summaries, comparison
readiness, and output paths.
