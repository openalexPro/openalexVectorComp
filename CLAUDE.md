# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`openalexVectorComp` is an R package for text embedding generation and distance/score-based corpus comparison. It is **R-first** with file-based artifacts (Parquet/YAML/JSON) as first-class outputs — functions are designed to compose in plain R workflows without hidden services.

Current version: see `DESCRIPTION` (treat it as the source of truth, not docs).

## Common Commands

Run from the package root in R:

```r
# Install local source
devtools::install_local(".")

# Document (regenerate man/ and NAMESPACE from roxygen)
devtools::document()

# Run all tests
devtools::test()

# Run a single test file
devtools::test(filter = "name-without-test-prefix-or-.R")
# or: testthat::test_file("tests/testthat/test-<name>.R")

# Full R CMD check (mirrors CI)
devtools::check(args = c("--no-manual", "--no-multiarch", "--no-examples", "--ignore-vignettes"))

# Build pkgdown site (output: _site/)
pkgdown::build_site()
```

CI (`.github/workflows/pr-checks.yml`) runs `R CMD check` across Ubuntu (release/oldrel-1/devel), macOS, and Windows, **skipping vignette execution and examples**. Match this locally before committing.

## Architecture

### Backend abstraction
`R/backend_core.R` exposes a provider-neutral interface (`backend_config()`, `backend_info()`, `backend_embed_texts()`, `backend_read()`, `backend_save()`). It dispatches on `provider` ∈ {`hf`, `openai`, `tei`} to internal `.embedding_*` functions in:

- `R/backend_hf.R` — HuggingFace Inference router
- `R/backend_openai.R` — OpenAI embeddings API
- `R/backend_tei.R` — local Text Embeddings Inference server

Auth for hosted backends uses the `OVC_API_TOKEN` env var (bearer token). Backend configs serialize to/from YAML (`embed_model.yaml`); `backend_read()` also accepts a legacy nested format — preserve that path when editing.

### Pipeline (sync)
1. `embed_corpus()` — prepare/clean input texts (supports `dry_run = TRUE`).
2. `embed_texts()` / `backend_embed_texts()` — generate embeddings.
3. Distances:
   - `distance_reference_cosine()` — full pairwise cosine matrix with centroid axes, written as a single parquet under `distance_reference_cosine/model_id=.../corpus_label=.../reference_label=.../pairwise-cosine.parquet`. First column `id` includes a `"centroid"` row; one `"centroid"` column on the reference side.
   - `distance_ridge()` — reference-area distance.
4. Scores: `score_reference_cosine()` (methods: `"linear"`, `"exponential"`), `score_ridge()`.
5. Optional: `calibrate_threshold()`.

### OpenAI Batch (async, explicit three-phase)
`batch_submit_openai()` → `batch_status_openai()` → `batch_collect_openai()`. **Pending state is an expected, non-fatal outcome.** Jobs are auto-split by size/count; a single oversized request line is a hard error. Helpers live in `R/batch_openai_helpers.R` and `R/batch_openai_http.R`.

The demo wrapper `demo_finalize_openai_batch()` = status + collect + direct-vs-batch comparison, with persistent outputs at `project/openai_batch_comparison/label=<label>/`.

### Demos
`R/demo_run.R` provides `run_demo_openalex()` and `run_demo_openai()`. Default demo directories are `demos/openalex` and `demos/openai`. Quarto and YAML live in `demo_dir`; pipeline artifacts under `demo_dir/project/`. `run_demo_openai(..., render = TRUE)` may return before batch completes — this is intentional; finalize separately.

## Continuity Documents (Required Workflow)

Three docs have non-overlapping roles. Update the appropriate one(s) **before every commit that changes behavior**:

- `DEVELOPMENT_CONTINUITY.md` — design principles, decision log, pre-commit checklist. Read this first when resuming work. Add a Decision Log entry for non-trivial changes.
- `IMPLEMENTATION_NOTES.md` — what was shipped per release (engineering log).
- `NEWS.md` — user-facing release notes.

Keep README and vignette commands aligned with actual defaults (paths, async behavior, API names).

## Conventions / Gotchas

- **Don't hard-fail on pending OpenAI batch jobs** — async pending is a normal state in submit/status/collect and demo flows.
- **Backend YAML compatibility**: support both the current flat format and the legacy nested (`meta$backend$...`, `meta$model$requested_id`) format in any reader changes.
- **File-based artifacts are the contract.** Parquet layout includes Hive-style partition dirs (`model_id=.../corpus_label=.../reference_label=...`). Don't change these paths casually — downstream demos/tests assume them.
- Tiny numeric drift between direct and batch OpenAI embeddings is expected (serialization/floating-point). Cosine ≈ 1.0 is not a regression.
- pkgdown site builds to `_site/` (configured in `_pkgdown.yml`).
- `.Rbuildignore` excludes `demos/`, `_site/`, continuity docs, and `inst/qdrant functions/` — don't expect those in the built package.
