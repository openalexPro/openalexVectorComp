# openalexVectorComp

**Auto-tagging via TEI embeddings + Qdrant**, implemented in R.

## Version

Current development version: **0.1.4**.

- Embeddings served by **TEI** (Text Embeddings Inference; Hugging
  Face).
- Vector search by **Qdrant**.
- Scoring: **prototype cosine-distance** + **reference-area ridge
  score**
  ([`distance_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/distance_ridge.md) +
  [`score_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/score_ridge.md)) +
  threshold calibration.
- Works great with DuckDB/Arrow pipelines.

## 0.1.4 Highlights

- Demo defaults now use a shared structure:
  - `demos/openalex`
  - `demos/openai`
- OpenAI demo uses an explicit two-phase async workflow:
  - render now (submit/poll briefly),
  - finalize later (status/collect/compare) if batch is still pending.
- Added tutorial-style demo narratives with clearer explanation of
  workflow choices, costs/latency trade-offs, and interpretation of
  direct-vs-batch embedding differences.

## Development Continuity

See `inst/DEVELOPMENT_CONTINUITY.md` for design principles,
architectural decisions, and the required pre-commit update checklist
that keeps development context continuous for both humans and AI agents.

## Install (local)

``` r
# install.packages("devtools")
devtools::install_local("openalexVectorComp")
```

Or build & install from the zip you downloaded.

## Runtime dependencies

- TEI server running (CPU is fine):

  ``` bash
  text-embeddings-router --model BAAI/bge-small-en-v1.5 --port 8080
  ```

- Qdrant server (optional if you only use modeling; required for ANN
  search):

  - Binary: `./qdrant`
  - Docker: `docker run -p 6333:6333 -p 6334:6334 qdrant/qdrant`

## Vignettes

Start with `vignettes/simplestart.qmd`, then see:

- `vignettes/package-overview.qmd`
- `vignettes/openai-batch-async.qmd`
- `vignettes/abstract-cleaning.qmd`

## Run a Local Demo Project

Create a full demo in `getwd()/demos/openalex` (fixtures + Quarto
analysis):

``` r
run_demo_openalex_quarto(
  demo_dir = file.path(getwd(), "demos", "openalex"),
  render = FALSE
)
```

Set `render = TRUE` to run `quarto render` directly. For hosted backends
(`provider = "hf"` or `"openai"`), set `OVC_API_TOKEN` first. The Quarto
file and backend YAML are placed in `demo_dir`, while all pipeline
artifacts are written under `demo_dir/project/`.

OpenAI-specific demo (same structure, explicit API key argument):

``` r
run_demo_openai_quarto(
  api_key = Sys.getenv("OVC_API_TOKEN"),
  demo_dir = file.path(getwd(), "demos", "openai"),
  render = FALSE
)
```

The OpenAI demo now follows a two-phase async flow: 1.
`run_demo_openai_quarto(..., render = TRUE)` submits batch and
continues. 2. If batch is still pending, finalize later:

``` r
finalize_demo_openai_batch(
  demo_dir = file.path(getwd(), "demos", "openai"),
  api_key = Sys.getenv("OVC_API_TOKEN"),
  label = "corpus_batch"
)
```

This writes comparison outputs to:
`project/openai_batch_comparison/label=corpus_batch/`.

## OpenAI Batch Workflow (Async, Pure R)

For long-running OpenAI embedding jobs, use the async batch helpers:

``` r
backend <- embedding_backend_config(
  provider = "openai",
  model = "text-embedding-3-small"
)

# 1) submit and return immediately
embed_corpus_submit_openai_batch(
  project_dir = "my_project",
  backend = backend,
  label = "corpus"
)

# 2) check job status
embed_corpus_status_openai_batch(
  project_dir = "my_project",
  label = "corpus"
)

# 3) collect completed jobs and write canonical embeddings parquet
embed_corpus_collect_openai_batch(
  project_dir = "my_project",
  backend = backend,
  label = "corpus"
)
```

Preflight checks run before submission. Jobs are auto-split by
size/count when needed. A single oversized request line stops with a
clear error.

## Prototype distance output

[`distance_reference_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/distance_reference_cosine.md)
writes one parquet file:

- `distance_reference_cosine/model_id=<...>/corpus_label=<...>/reference_label=<...>/pairwise-cosine.parquet`

This is a distance-only matrix with centroid axes:

- first column `id`: corpus ids plus one row `"centroid"` (corpus
  centroid)
- remaining columns: reference ids plus one column `"centroid"`
  (reference centroid)
- all values are cosine distances (`1 - cosine`)

To convert this full distance matrix to scores:

``` r
score_reference_cosine(
  distance_parquet = "my_project/distance_reference_cosine/model_id=.../corpus_label=.../reference_label=...",
  method = "linear" # or "exponential"
)
```
