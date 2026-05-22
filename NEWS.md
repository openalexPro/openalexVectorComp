# openalexVectorComp news

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
