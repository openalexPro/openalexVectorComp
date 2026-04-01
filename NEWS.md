# openalexVectorComp news

## 0.2.0

### New Features

- Added explicit two-phase async OpenAI demo flow (`run_demo_openai_quarto()`
  plus `finalize_demo_openai_batch()` follow-up).
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

- None.

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
