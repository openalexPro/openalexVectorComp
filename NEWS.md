# openalexVectorComp news

## 0.3.5

### Bug Fixes

- With `delete_existing = FALSE`, `embed_corpus()` and
  `batch_submit_openai()` are supposed to skip rows that already have
  embeddings with the same text hash. They never did: the existing
  embeddings were opened with the label folder passed as the `schema`
  argument of `arrow::open_dataset()`, which always failed silently. As a
  result every run re-embedded the whole corpus, and `batch_submit_openai()`
  resubmitted already-embedded rows as new (paid) OpenAI batch jobs. The
  existing `label=<label>` folder is now read correctly and unchanged rows
  are skipped.
- When a row's text has changed and it is embedded again, its old row is
  now removed, so each id appears exactly once per `label=<label>` folder
  and distance and score functions no longer see duplicate ids. This applies
  to `embed_corpus()` with `delete_existing = FALSE` and to
  `batch_collect_openai()`. New rows are written to a new `batch=<n>` folder
  first (`embed_corpus()` no longer restarts at `batch=1`, which would have
  overwritten unchanged rows); only then are the old rows removed from older
  shards. Shards and `batch=` folders left empty are deleted. Duplicates left
  by earlier versions are cleaned up the next time new embeddings are written
  to that label.

## 0.3.4

### Bug Fixes

- The TEI backend's id uses the server's `served_model_name` before
  `model_id`.

### Continuous integration

- R CMD check also runs on pushes to `main` and `dev`; test coverage only
  on pushes to `main`.

## 0.3.3

### New Features

- Added `backend_specter2_tei()` convenience helper for serving the merged
  SPECTER2 proximity model via a local TEI server.
- Added `specter2-setup` vignette and `inst/scripts/prepare_specter2_merged.py`
  + `inst/scripts/start_tei_specter2.sh` for one-time model preparation and
  serving.

## 0.3.0

### New Features

- Added explicit two-phase async OpenAI demo flow (`run_demo_openai()`
  plus `demo_finalize_openai_batch()` follow-up).
- Standardized demo defaults to `demos/openalex` and `demos/openai`.
- Consolidated OpenAI batch helper naming and module organization.

### Bug Fixes

- Improved non-blocking async demo behavior so pending batch jobs do not
  terminate the render workflow.
- Updated CI workflow arguments to avoid unintended vignette/example execution
  during matrix checks.

### Documentation

- Improved tutorial-style demo narratives and direct-vs-batch comparison
  guidance.
- Updated docs to align package scope with embedding + distance/scoring
  workflows.
- Updated pkgdown workflow/output alignment with `_site` deployment.

### Breaking Changes

- Immediate API rename cleanup (no compatibility wrappers). Function mapping:

| Old name | New name |
|---|---|
| `embed_corpus_submit_openai_batch()` | `batch_submit_openai()` |
| `embed_corpus_status_openai_batch()` | `batch_status_openai()` |
| `embed_corpus_collect_openai_batch()` | `batch_collect_openai()` |
| `finalize_demo_openai_batch()` | `demo_finalize_openai_batch()` |
| `run_demo_openai_quarto()` | `run_demo_openai()` |
| `run_demo_openalex_quarto()` | `run_demo_openalex()` |
| `embedding_backend_config()` | `backend_config()` |
| `embedding_backend_info()` | `backend_info()` |
| `embedding_backend_embed_texts()` | `backend_embed_texts()` |
| `embedding_backend_read()` | `backend_read()` |
| `embedding_backend_save()` | `backend_save()` |

## 0.1.4

### New Features

- Added finalize workflow for status/collect/compare when batch jobs complete.
- Added persisted direct-vs-batch comparison outputs.

### Bug Fixes

- Added robust non-blocking OpenAI batch demo behavior.

### Documentation

- Improved demo readability and tutorial consistency.

### Breaking Changes

- None.

## 0.1.3

### New Features

- None.

### Bug Fixes

- Included cleanup of stale qdrant helper files.

### Documentation

- Synchronized documentation with current API and repository layout.
- Clarified ridge/reference-area scoring behavior in docs.
- Updated vignette paths and exported/internal function descriptions.
- Bumped version to `0.1.3`.

### Breaking Changes

- None.
