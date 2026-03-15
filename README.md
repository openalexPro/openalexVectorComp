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
