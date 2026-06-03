# openalexVectorComp Development Continuity

Purpose: keep project intent, architecture, and decision history
explicit so both humans and AI agents can resume work safely and
quickly.

This file must be updated before every commit that changes behavior,
interfaces, or workflow.

## 1. Design Principles

1.  R-first pipeline ergonomics:

- Functions should compose in plain R workflows without hidden services.
- File-based outputs (Parquet/YAML/JSON) are first-class artifacts.

2.  Reproducibility and inspectability:

- Every major step writes persistent artifacts that can be inspected
  manually.
- Metadata should make model/provider/label provenance explicit.

3.  Async-safe OpenAI batch behavior:

- Batch flows must tolerate pending states.
- Pending jobs are expected states, not hard failures.
- Submit/status/collect responsibilities remain separate and explicit.

4.  Non-destructive evolution:

- Prefer additive changes and backward-compatible defaults where
  possible.
- Preserve existing user workflows unless a deliberate migration is
  documented.

5.  Practical clarity over abstraction:

- Optimize for operational clarity in demo and package-facing APIs.
- Explain trade-offs directly (latency/cost/throughput; sync vs async).

## 2. Architectural Snapshot

Core flow: 1. Prepare input text (`embed_corpus(..., dry_run = TRUE)`
optional). 2. Generate embeddings (direct or OpenAI batch). 3. Compute
distances: - reference cosine matrix
([`distance_reference_cosine()`](https://openalexpro.github.io/openalexVectorComp/reference/distance_reference_cosine.md)), -
reference-area distance
([`distance_ridge()`](https://openalexpro.github.io/openalexVectorComp/reference/distance_ridge.md)).
4. Convert to scores: -
[`score_reference_cosine()`](https://openalexpro.github.io/openalexVectorComp/reference/score_reference_cosine.md), -
[`score_ridge()`](https://openalexpro.github.io/openalexVectorComp/reference/score_ridge.md).
5. Optional threshold calibration
([`calibrate_threshold()`](https://openalexpro.github.io/openalexVectorComp/reference/calibrate_threshold.md)).

OpenAI batch flow: 1. Submit
([`batch_submit_openai()`](https://openalexpro.github.io/openalexVectorComp/reference/batch_submit_openai.md)).
2. Refresh status
([`batch_status_openai()`](https://openalexpro.github.io/openalexVectorComp/reference/batch_status_openai.md)).
3. Collect completed jobs
([`batch_collect_openai()`](https://openalexpro.github.io/openalexVectorComp/reference/batch_collect_openai.md)).
4. Demo convenience wrapper: -
[`demo_finalize_openai_batch()`](https://openalexpro.github.io/openalexVectorComp/reference/demo_finalize_openai_batch.md)
= status + collect + direct-vs-batch compare.

## 3. Current Demo Conventions (0.3.0)

Default demo locations: - `demos/openalex` - `demos/openai`

OpenAI demo behavior: - `run_demo_openai(..., render = TRUE)` may
complete before batch does. - User is given explicit follow-up commands
for status/finalize. - Batch comparison outputs are written to:
`project/openai_batch_comparison/label=corpus_batch/`.

## 4. Decision Log

Add one entry per relevant change.

Template: - Date: - Scope: - Decision: - Why: - Alternatives
considered: - Impact: - Follow-up tasks:

### Entries

- Date: 2026-04-01

- Scope: OpenAI demo and batch comparison robustness

- Decision: Implement two-phase OpenAI batch demo flow with
  [`demo_finalize_openai_batch()`](https://openalexpro.github.io/openalexVectorComp/reference/demo_finalize_openai_batch.md).

- Why: Batch completion is asynchronous; render should not fail on
  pending jobs.

- Alternatives considered: long blocking poll in render; hard-fail on
  timeout.

- Impact: Clearer async semantics; stable demo render; persisted
  comparison outputs.

- Follow-up tasks: keep tutorial narrative and command output examples
  aligned.

- Date: 2026-05-22

- Scope: SPECTER2 support for academic paper topic comparison

- Decision: Add SPECTER2 proximity model support via a documented
  one-time merge step (Python script) + local TEI serving, exposed
  through a thin R helper
  [`backend_specter2_tei()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_specter2_tei.md).
  Setup material lives in `inst/scripts/` and
  `vignettes/specter2-setup.qmd`.

- Why: Domain-specific model gives better topic separation than general
  OpenAI embeddings for academic corpora, at 768 dim and zero per-token
  cost. TEI cannot load adapter-transformers adapters, so a one-time
  merge is required. Keeping the merge out of the R API surface avoids
  forcing a Python dependency on this R-first package.

- Alternatives considered: bundling the merge as an R function
  (rejected: Python toolchain dependency, unstable `adapters` library
  API, conflicts with the principle that the package does not manage
  external services); shipping the merged model itself (rejected: ~500
  MB).

- Impact: Users can opt into SPECTER2 with one merge + one TEI launch;
  the rest of the pipeline is unchanged.

- Follow-up tasks: revisit if the `adapters` library API shifts again;
  add a benchmark comparing SPECTER2 vs `text-embedding-3-small` once we
  have a reference corpus.

- Date: 2026-04-01

- Scope: Demo organization and docs

- Decision: Default demo directories changed to `demos/<provider>`.

- Why: Consistent multi-demo layout and easier discoverability.

- Alternatives considered: provider-specific root folders with no shared
  parent.

- Impact: Cleaner workspace structure; updated README examples.

- Follow-up tasks: ensure any automation scripts assume new defaults.

## 5. Pre-Commit Update Checklist (Required)

Before committing, update this file:

1.  Architectural changes:

- Did any function responsibility or data flow change?
- If yes, update **Architectural Snapshot**.

2.  Public behavior changes:

- Were defaults, file paths, or outputs changed?
- If yes, update **Current Demo Conventions**.

3.  Decisions:

- Add/append entries in **Decision Log** for all non-trivial changes.

4.  Risks and follow-ups:

- Record known limitations, pending cleanup, and next tasks.

5.  Consistency:

- Ensure README/demo docs and this file agree on:
  - defaults,
  - API usage,
  - async behavior.

## 6. Handover Notes for AI Agents

When resuming work: 1. Read this file first. 2. Confirm current version
in `DESCRIPTION`. 3. Check README demo examples against actual defaults.
4. Run focused tests for touched areas before broad checks. 5. Update
this file before final commit if behavior changed.
