# simplestart

## Introduction

This vignette walks through a minimal end‑to‑end run using
openalexVectorComp:

- use a running TEI (Text Embeddings Inference) server endpoint,
- embed a small Parquet corpus into shard files,
- compute prototype margins and ridge distances.

The code mirrors the package functions directly, with more context and
guidance.

For detailed text-preparation logic before embedding (including abstract
cleaning rules, policies, and customization), see the vignette
`abstract-cleaning`.

## Requirements

- A running TEI server endpoint, e.g. `http://localhost:3000/embed`.
- Suggested R packages (for vignette rendering): `knitr`, `rmarkdown`,
  and `quarto`.
- Demo fixtures available under `inst/ovc_demo/project/` in this package
  source.

### Notes on execution

- Chunks in this vignette default to `eval: false` to avoid launching
  external processes during package build. Remove or set `eval: true` to
  run locally.
- Long‑running steps (embedding) are intentionally small in batch size
  to keep resource usage low when you do run them.

## TEI endpoint

Start TEI outside the package, for example from a shell:

``` bash
text-embeddings-router --model-id BAAI/bge-small-en-v1.5 --port 3000
```

For detailed operational guidance (start/stop/health checks), see the
vignette `tei-server-operations`.

## Embed a small corpus

This example uses the demo fixture project under
`inst/ovc_demo/project/`. The fixture already contains:

- `corpus/corpus_small.parquet`
- `reference_corpus/reference_small.parquet`

``` r

embed_corpus(
  project_dir = "inst/ovc_demo/project",
  backend = backend_config(
    provider = "tei",
    base_url = "http://localhost:3000"
  ),
  label = "corpus",
  batch_size = 15,
  verbose = TRUE
)

embed_corpus(
  project_dir = "inst/ovc_demo/project",
  backend = backend_config(
    provider = "tei",
    base_url = "http://localhost:3000"
  ),
  corpus_name = "reference_corpus",
  label = "reference",
  batch_size = 15,
  verbose = TRUE
)
```

## Compute prototype distances

Prototype distances are computed pairwise between all vectors in a
reference label partition and all vectors in a corpus label partition.
[`distance_reference_cosine()`](https://openalexpro.github.io/openalexVectorComp/reference/distance_reference_cosine.md)
writes one file `pairwise-cosine.parquet` with:

- rows: corpus ids plus one `centroid` row (corpus centroid)
- columns: reference ids plus one `centroid` column (reference centroid)
- values: cosine distances only

``` r

distance_reference_cosine(
  project_dir = "inst/ovc_demo/project",
  embeddings_dir = "model_id=BAAI_bge-small-en-v1.5",
  corpus_label = "corpus",
  reference_label = "reference"
)

# Optional: convert full cosine-distance matrix to scores
score_reference_cosine(
  distance_parquet = file.path(
    "inst/ovc_demo/project",
    "distance_reference_cosine",
    "model_id=BAAI_bge-small-en-v1.5",
    "corpus_label=corpus",
    "reference_label=reference"
  ),
  method = "linear"
)
```

## Compute ridge distances and scores

[`distance_ridge()`](https://openalexpro.github.io/openalexVectorComp/reference/distance_ridge.md)
models the `reference` label as an embedding area (centroid +
covariance) and computes Mahalanobis-style `area_distance` for all
`corpus` rows. Use
[`score_ridge()`](https://openalexpro.github.io/openalexVectorComp/reference/score_ridge.md)
to convert distances to `relevance_score`.

``` r

ridge_dist_dir <- distance_ridge(
  project_dir = "inst/ovc_demo/project",
  reference_label = "reference",
  corpus_label = "corpus"
)

ridge_score_dir <- score_ridge(
  distance_parquet = ridge_dist_dir
)
```

## Troubleshooting

- Can’t find `text-embeddings-router`:
  - Install the binary and ensure it is on PATH.
- Port in use:
  - Start TEI on another port and update
    `backend = backend_config(provider = "tei", base_url = "http://localhost:3001")`.
- Slow embedding or timeouts:
  - Reduce `batch_size`, and verify the server’s `/info` limits.

## Reproducibility

``` r

sessionInfo()
```
