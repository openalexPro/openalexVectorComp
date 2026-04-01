# Implementation Notes

Last updated: 2026-04-01

## Purpose and Scope

This file is the implementation/release engineering log.
It records what changed in code and operational behavior across releases.
User-facing release highlights are tracked in `NEWS.md`.

It is intentionally different from:
- `DEVELOPMENT_CONTINUITY.md` (living handover + design principles + decision continuity).

In short:
- `DEVELOPMENT_CONTINUITY.md` = "how to continue development safely".
- `IMPLEMENTATION_NOTES.md` = "what was implemented and shipped".
- `NEWS.md` = "user-facing release highlights".

## Current Baseline (v0.2.0 branch state)

- Package focus is embedding/vectorization plus distance/scoring workflows.
- Backends are provider-pluggable (`hf`, `openai`, `tei`) through a shared backend config/dispatch interface.
- OpenAI Batch workflow is explicit async:
  - submit -> status -> collect
  - pending state is expected and non-fatal.
- Demo structure uses provider subfolders:
  - `demos/openalex`
  - `demos/openai`
- pkgdown output/deploy target is `_site/`.
- CI includes PR checks matrix and manual triggers.

## Release-Focused Implementation Log

### v0.1.3

- Documentation sync to align with implemented API and current repository layout.
- Clarified ridge/reference-area behavior in docs (`distance_ridge()` + `score_ridge()`).
- Updated vignette paths and internal/exported function descriptions.
- Version bump to `0.1.3`.
- Included repository cleanup scope for stale `inst/qdrant functions/*` helpers.

### v0.1.4

- Introduced stronger OpenAI demo/tutorial flow and async handling guidance.
- Added two-phase demo workflow support:
  - render does not hard-fail when batch is still pending,
  - finalize step performs status/collect/compare later.
- Added persistent direct-vs-batch comparison outputs under:
  - `project/openai_batch_comparison/label=<label>/`.
- Improved tutorial narrative consistency across demos.

### v0.2.0

- Consolidated OpenAI batch helper/module naming and structure.
- Added/updated CI workflows for PR check suites with caching and manual trigger support.
- Added pkgdown GH Pages workflow alignment and `_site` destination usage.
- Documentation cleanup to remove stale scope references and align README/package messaging with embedding + distance computation focus.
- Added `DEVELOPMENT_CONTINUITY.md` as required pre-commit continuity artifact.

## Operational Notes

- OpenAI batch collection may complete after demo rendering; this is expected async behavior.
- Batch/direct embedding comparisons can show tiny numeric differences due to floating-point serialization and runtime-level numerical variance.
- These small differences are not typically semantic regressions when cosine similarity remains effectively 1.0.

## Maintenance Rules

When behavior changes, update both files with non-overlapping intent:

1. Update `IMPLEMENTATION_NOTES.md` for shipped implementation scope.
2. Update `DEVELOPMENT_CONTINUITY.md` for design rationale, decisions, and handover continuity.
3. Update `NEWS.md` for user-facing release notes.
4. Ensure README/vignettes match.
