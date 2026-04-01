# Finalize OpenAI demo batch jobs and compare direct vs batch embeddings

Runs OpenAI batch status/collect for a prepared demo workspace and, when
batch embeddings are available, computes direct-vs-batch vector
comparison. Comparison artifacts are written to:
`project/openai_batch_comparison/label=<label>/`.

## Usage

``` r
finalize_demo_openai_batch(
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
  [`run_demo_openai_quarto()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openai_quarto.md)
  or
  [`run_demo_openalex_quarto()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openalex_quarto.md).

- api_key:

  Optional OpenAI API key. If provided, it is set in `OVC_API_TOKEN` for
  the duration of this call.

- label:

  Batch embedding label to finalize. Defaults to `"corpus_batch"`.

- refresh_remote:

  Logical; forwarded to
  [`embed_corpus_status_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_status_openai_batch.md).

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns a list containing status/collect summaries, comparison
readiness, and output paths.
