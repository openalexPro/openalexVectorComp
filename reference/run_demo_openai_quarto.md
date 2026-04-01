# Create and optionally run an OpenAI-based demo project via Quarto

Uses the same demo structure as
[`run_demo_openalex_quarto()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openalex_quarto.md),
but configures an OpenAI backend and requires an explicit API key
argument. The key is set in `OVC_API_TOKEN` for the duration of the
call.

## Usage

``` r
run_demo_openai_quarto(
  api_key,
  demo_dir = file.path(getwd(), "demos", "openai"),
  render = TRUE,
  model = "text-embedding-3-small",
  max_corpus = 100,
  max_reference = 10,
  overwrite = FALSE,
  quarto_file = "openai_demo_analysis.qmd",
  verbose = TRUE
)
```

## Arguments

- api_key:

  OpenAI API key. Must be a non-empty string.

- demo_dir:

  Demo workspace directory. Defaults to
  `file.path(getwd(), "demos", "openai")`.

- render:

  Logical; if `TRUE` (default), run `quarto render` on the copied
  template.

- model:

  OpenAI embedding model id. Defaults to `"text-embedding-3-small"`.

- max_corpus:

  Maximum number of corpus fixture rows to copy.

- max_reference:

  Maximum number of reference fixture rows to copy.

- overwrite:

  Logical; if `FALSE` (default), stop when demo-managed files already
  exist. If `TRUE`, refresh demo-managed files.

- quarto_file:

  Name of the analysis file created in `demo_dir`.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns a list with project paths and render status.
