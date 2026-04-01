# openalexVectorComp Development Continuity

Purpose: keep project intent, architecture, and decision history explicit so
both humans and AI agents can resume work safely and quickly.

This file must be updated before every commit that changes behavior, interfaces,
or workflow.

## 1. Design Principles

1. R-first pipeline ergonomics:
- Functions should compose in plain R workflows without hidden services.
- File-based outputs (Parquet/YAML/JSON) are first-class artifacts.

2. Reproducibility and inspectability:
- Every major step writes persistent artifacts that can be inspected manually.
- Metadata should make model/provider/label provenance explicit.

3. Async-safe OpenAI batch behavior:
- Batch flows must tolerate pending states.
- Pending jobs are expected states, not hard failures.
- Submit/status/collect responsibilities remain separate and explicit.

4. Non-destructive evolution:
- Prefer additive changes and backward-compatible defaults where possible.
- Preserve existing user workflows unless a deliberate migration is documented.

5. Practical clarity over abstraction:
- Optimize for operational clarity in demo and package-facing APIs.
- Explain trade-offs directly (latency/cost/throughput; sync vs async).

## 2. Architectural Snapshot

Core flow:
1. Prepare input text (`embed_corpus(..., dry_run = TRUE)` optional).
2. Generate embeddings (direct or OpenAI batch).
3. Compute distances:
- reference cosine matrix (`distance_reference_cosine()`),
- reference-area distance (`distance_ridge()`).
4. Convert to scores:
- `score_reference_cosine()`,
- `score_ridge()`.
5. Optional threshold calibration (`calibrate_threshold()`).

OpenAI batch flow:
1. Submit (`batch_submit_openai()`).
2. Refresh status (`batch_status_openai()`).
3. Collect completed jobs (`batch_collect_openai()`).
4. Demo convenience wrapper:
- `demo_finalize_openai_batch()` = status + collect + direct-vs-batch compare.

## 3. Current Demo Conventions (0.3.0)

Default demo locations:
- `demos/openalex`
- `demos/openai`

OpenAI demo behavior:
- `run_demo_openai(..., render = TRUE)` may complete before batch does.
- User is given explicit follow-up commands for status/finalize.
- Batch comparison outputs are written to:
  `project/openai_batch_comparison/label=corpus_batch/`.

## 4. Decision Log

Add one entry per relevant change.

Template:
- Date:
- Scope:
- Decision:
- Why:
- Alternatives considered:
- Impact:
- Follow-up tasks:

### Entries

- Date: 2026-04-01
- Scope: OpenAI demo and batch comparison robustness
- Decision: Implement two-phase OpenAI batch demo flow with
  `demo_finalize_openai_batch()`.
- Why: Batch completion is asynchronous; render should not fail on pending jobs.
- Alternatives considered: long blocking poll in render; hard-fail on timeout.
- Impact: Clearer async semantics; stable demo render; persisted comparison
  outputs.
- Follow-up tasks: keep tutorial narrative and command output examples aligned.

- Date: 2026-04-01
- Scope: Demo organization and docs
- Decision: Default demo directories changed to `demos/<provider>`.
- Why: Consistent multi-demo layout and easier discoverability.
- Alternatives considered: provider-specific root folders with no shared parent.
- Impact: Cleaner workspace structure; updated README examples.
- Follow-up tasks: ensure any automation scripts assume new defaults.

## 5. Pre-Commit Update Checklist (Required)

Before committing, update this file:

1. Architectural changes:
- Did any function responsibility or data flow change?
- If yes, update **Architectural Snapshot**.

2. Public behavior changes:
- Were defaults, file paths, or outputs changed?
- If yes, update **Current Demo Conventions**.

3. Decisions:
- Add/append entries in **Decision Log** for all non-trivial changes.

4. Risks and follow-ups:
- Record known limitations, pending cleanup, and next tasks.

5. Consistency:
- Ensure README/demo docs and this file agree on:
  - defaults,
  - API usage,
  - async behavior.

## 6. Handover Notes for AI Agents

When resuming work:
1. Read this file first.
2. Confirm current version in `DESCRIPTION`.
3. Check README demo examples against actual defaults.
4. Run focused tests for touched areas before broad checks.
5. Update this file before final commit if behavior changed.
