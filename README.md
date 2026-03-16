# openalexVectorComp

**Auto-tagging via TEI embeddings + Qdrant**, implemented in R.

- Embeddings served by **TEI** (Text Embeddings Inference; Hugging Face).
- Vector search by **Qdrant**.
- Scoring: **prototype-margin** + **ridge logistic** (glmnet) + simple calibration.
- Works great with DuckDB/Arrow pipelines.

## Install (local)

```r
# install.packages("devtools")
devtools::install_local("openalexVectorComp")
```

Or build & install from the zip you downloaded.

## Runtime dependencies

- TEI server running (CPU is fine):
  ```bash
  text-embeddings-router --model BAAI/bge-small-en-v1.5 --port 8080
  ```

- Qdrant server (optional if you only use modeling; required for ANN search):
  - Binary: `./qdrant`
  - Docker: `docker run -p 6333:6333 -p 6334:6334 qdrant/qdrant`

## Vignette

See `vignettes/simplestart.qmd` for a walkthrough.

## Run a Local Demo Project

Create a full demo in `getwd()/demo_project` (fixtures + Quarto analysis):

```r
run_demo_openalex_quarto(
  demo_dir = file.path(getwd(), "demo_project"),
  render = FALSE
)
```

Set `render = TRUE` to run `quarto render` directly. For hosted backends
(`provider = "hf"` or `"openai"`), set `OVC_API_TOKEN` first.
The Quarto file and backend YAML are placed in `demo_dir`, while all pipeline
artifacts are written under `demo_dir/project/`.

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
