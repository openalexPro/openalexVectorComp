[![r-universe](https://openalexpro.r-universe.dev/openalexVectorComp/badges/version)](https://openalexpro.r-universe.dev/openalexVectorComp) [![main](https://img.shields.io/github/r-package/v/openalexPro/openalexVectorComp/main?label=main)](https://github.com/openalexPro/openalexVectorComp/tree/main) [![CI main](https://img.shields.io/github/actions/workflow/status/openalexPro/openalexVectorComp/pr-checks.yml?branch=main&label=CI%20main)](https://github.com/openalexPro/openalexVectorComp/actions/workflows/pr-checks.yml?query=branch%3Amain) [![Codecov](https://codecov.io/gh/openalexPro/openalexVectorComp/graph/badge.svg)](https://app.codecov.io/gh/openalexPro/openalexVectorComp)

[![dev](https://img.shields.io/github/r-package/v/openalexPro/openalexVectorComp/dev?label=dev)](https://github.com/openalexPro/openalexVectorComp/tree/dev) [![CI dev](https://img.shields.io/github/actions/workflow/status/openalexPro/openalexVectorComp/pr-checks.yml?branch=dev&label=CI%20dev)](https://github.com/openalexPro/openalexVectorComp/actions/workflows/pr-checks.yml?query=branch%3Adev)

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19607514.svg)](https://doi.org/10.5281/zenodo.19607514) [![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# openalexVectorComp

**Embedding of Corpora**, implemented in R.

- Embeddings served by **TEI** (Text Embeddings Inference; Hugging Face).
- Embeddings via a **backend-neutral interface** (`hf`, `openai`, `tei`).
- Scoring: **prototype cosine-distance** + **reference-area ridge score**
  (`distance_ridge()` + `score_ridge()`) + threshold calibration.
- Works great with DuckDB/Arrow pipelines.

The badges show the released version (r-universe, built from `main`) and the
development version (`dev`); what changed in each release is in
[NEWS.md](NEWS.md).

## Development Continuity

See `DEVELOPMENT_CONTINUITY.md` for design principles, architectural
decisions, and the required pre-commit update checklist that keeps development
context continuous for both humans and AI agents.

## Installation

Released version, from the openalexPro r-universe:

```r
install.packages(
  "openalexVectorComp",
  repos = c("https://openalexpro.r-universe.dev", "https://cloud.r-project.org")
)
```

Development version (the `dev` branch), from GitHub:

```r
# install.packages("remotes")
remotes::install_github("openalexPro/openalexVectorComp", ref = "dev")
```

## Runtime dependencies

- For `provider = "tei"`:
  ```bash
  text-embeddings-router --model BAAI/bge-small-en-v1.5 --port 8080
  ```
- For hosted embedding backends (`provider = "hf"` or `"openai"`), set
  `OVC_API_TOKEN` in your environment.

## Vignettes

Start with `vignettes/simplestart.qmd`, then see:

- `vignettes/package-overview.qmd`
- `vignettes/openai-batch-async.qmd`
- `vignettes/abstract-cleaning.qmd`
- `vignettes/specter2-setup.qmd` (academic-paper embeddings via TEI)

## Run a Local Demo Project

Create a full demo in `getwd()/demos/openalex` (fixtures + Quarto analysis):

```r
run_demo_openalex(
  demo_dir = file.path(getwd(), "demos", "openalex"),
  render = FALSE
)
```

Set `render = TRUE` to run `quarto render` directly. For hosted backends
(`provider = "hf"` or `"openai"`), set `OVC_API_TOKEN` first.
The Quarto file and backend YAML are placed in `demo_dir`, while all pipeline
artifacts are written under `demo_dir/project/`.

OpenAI-specific demo (same structure, explicit API key argument):

```r
run_demo_openai(
  api_key = Sys.getenv("OVC_API_TOKEN"),
  demo_dir = file.path(getwd(), "demos", "openai"),
  render = FALSE
)
```

The OpenAI demo now follows a two-phase async flow:
1. `run_demo_openai(..., render = TRUE)` submits batch and continues.
2. If batch is still pending, finalize later:

```r
demo_finalize_openai_batch(
  demo_dir = file.path(getwd(), "demos", "openai"),
  api_key = Sys.getenv("OVC_API_TOKEN"),
  label = "corpus_batch"
)
```

This writes comparison outputs to:
`project/openai_batch_comparison/label=corpus_batch/`.

## OpenAI Batch Workflow (Async, Pure R)

For long-running OpenAI embedding jobs, use the async batch helpers:

```r
backend <- backend_config(
  provider = "openai",
  model = "text-embedding-3-small"
)

# 1) submit and return immediately
batch_submit_openai(
  project_dir = "my_project",
  backend = backend,
  label = "corpus"
)

# 2) check job status
batch_status_openai(
  project_dir = "my_project",
  label = "corpus"
)

# 3) collect completed jobs and write canonical embeddings parquet
batch_collect_openai(
  project_dir = "my_project",
  backend = backend,
  label = "corpus"
)
```

Preflight checks run before submission. Jobs are auto-split by size/count when
needed. A single oversized request line stops with a clear error.

## Prototype distance output

`distance_reference_cosine()` writes one parquet file:

- `distance_reference_cosine/model_id=<...>/corpus_label=<...>/reference_label=<...>/pairwise-cosine.parquet`

This is a distance-only matrix with centroid axes:

- first column `id`: corpus ids plus one row `"centroid"` (corpus centroid)
- remaining columns: reference ids plus one column `"centroid"` (reference centroid)
- all values are cosine distances (`1 - cosine`)

To convert this full distance matrix to scores:

```r
score_reference_cosine(
  distance_parquet = "my_project/distance_reference_cosine/model_id=.../corpus_label=.../reference_label=...",
  method = "linear" # or "exponential"
)
```
