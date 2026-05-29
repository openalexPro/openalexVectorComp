# Create and optionally run a self-contained demo project via Quarto

Sets up a demo workspace under `demo_dir`, creates a pipeline project
under `demo_dir/project`, copies small corpus and reference fixtures and
Quarto template from `inst/ovc_demo`, and optionally renders the
analysis.

## Usage

``` r
run_demo_openalex(
  demo_dir = file.path(getwd(), "demos", "openalex"),
  render = TRUE,
  backend = NULL,
  max_corpus = 100,
  max_reference = 10,
  overwrite = FALSE,
  quarto_file = "openalex_demo_analysis.qmd",
  verbose = TRUE
)
```

## Arguments

- demo_dir:

  Demo workspace directory. Defaults to
  `file.path(getwd(), "demos", "openalex")`.

- render:

  Logical; if `TRUE` (default), run `quarto render` on the copied
  template.

- backend:

  Optional backend config from
  [`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).
  If `NULL`, defaults to Hugging Face (`provider = "hf"`, model
  `"BAAI/bge-small-en-v1.5"`).

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

## Details

The workspace keeps all generated directories and output artifacts. The
Quarto file is created in `demo_dir`, while embedding pipeline data is
stored in `demo_dir/project`.
