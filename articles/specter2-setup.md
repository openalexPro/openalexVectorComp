# specter2-setup

## Why SPECTER2 for academic papers

SPECTER2 (AllenAI, 2023; arXiv:2211.13308) is a transformer encoder
trained on citation-linked scientific papers. For topic similarity over
titles and abstracts, the proximity adapter typically separates academic
topics more cleanly than general-purpose embedding models, at 768
dimensions (smaller and faster than OpenAI’s 1536/3072-dim alternatives)
and at zero per-token cost when served locally via TEI.

The catch: the proximity quality lives in an adapter on top of
`allenai/specter2_base`, and TEI does not load adapter-transformers
adapters. This vignette walks through the one-time merge that produces a
standalone HuggingFace-format model directory, then serves it via TEI.

## One-time setup

### Python environment

Create an isolated environment for the merge. This is used only to
produce the merged weights and can be deleted afterwards.

``` bash
python -m venv ~/.venvs/specter2-merge
source ~/.venvs/specter2-merge/bin/activate
pip install transformers adapters torch
```

### Run the merge script

The script ships with the package under `inst/scripts/`:

``` bash
SCRIPT=$(Rscript -e 'cat(system.file("scripts","prepare_specter2_merged.py",package="openalexVectorComp"))')
python "$SCRIPT"
```

By default the merged model is written to a per-user R cache directory
(see `tools::R_user_dir("openalexVectorComp", "cache")`). Override with
`--out-dir` or the `OVC_SPECTER2_PATH` environment variable:

``` bash
OVC_SPECTER2_PATH=/data/models/specter2_proximity_merged python "$SCRIPT"
```

The script downloads `allenai/specter2_base`, attaches the
`allenai/specter2` proximity adapter, calls `merge_adapter()`, and saves
the merged model and tokenizer. Expect ~500 MB on disk.

## Serving via TEI

Use the bundled launcher script. It reads the same `OVC_SPECTER2_PATH`
convention and a port from `OVC_TEI_PORT` (default `8080`):

``` bash
LAUNCH=$(Rscript -e 'cat(system.file("scripts","start_tei_specter2.sh",package="openalexVectorComp"))')
bash "$LAUNCH"
```

Or invoke `text-embeddings-router` directly against the merged model
directory. See `vignettes/tei-server-operations.qmd` for general TEI ops
(health, info, stop/restart).

### Verify

``` bash
curl -s http://localhost:8080/info | jq .model_id
curl -s -X POST http://localhost:8080/embed \
  -H 'Content-Type: application/json' \
  -d '{"inputs":["graph neural networks"]}' | jq '.[0] | length'
# expect 768
```

## Using from R

The package ships a convenience helper that builds the right
[`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md)
for a local TEI on `localhost:<port>`:

``` r

library(openalexVectorComp)

backend <- backend_specter2_tei(port = 8080)
backend
```

The model string is metadata only — it is written to `embed_model.yaml`
and becomes part of the parquet partition path
(`model_id=allenai_specter2_proximity_merged/...`). TEI itself loads
whatever model directory it was started with.

### Smoke test

``` r

texts <- c(
  "Graph neural networks for citation prediction",
  "Knitting techniques in 19th century Scotland"
)
m <- backend_embed_texts(texts, backend)
stopifnot(ncol(m) == 768, nrow(m) == 2)

similarity_cosine(m[1, ], m[2, ])   # expect a small value (topics differ)
```

## Where this fits

For 4M+ papers you can run the full pipeline with SPECTER2:

``` r

backend <- backend_specter2_tei()

embed_corpus(project_dir = "project", backend = backend, label = "corpus")

distance_reference_cosine(
  project_dir     = "project",
  backend         = backend,
  corpus_label    = "corpus",
  reference_label = "reference"
)
```

There is no batch API for TEI (and none is needed) — throughput is
bounded by local GPU/CPU and TEI’s continuous batching, not by
per-request HTTP cost.

## Notes

- The merged model is a standard HuggingFace transformer directory and
  is not tied to this package. You can serve it from any TEI deployment.
- AllenAI may publish new SPECTER2 checkpoints. Re-run the merge script
  to pick them up; the output path is overwritten in place.
- The `adapters` Python library has been renamed from
  `adapter-transformers`. If your environment has the old package,
  install `adapters` fresh.
