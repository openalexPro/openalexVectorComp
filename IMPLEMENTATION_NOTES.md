# Implementation Notes (March 2026)

## Scope

This note tracks all implementation/documentation changes made in this workstream
for `openalexVectorComp` (not only backend refactors).

## Change Log

### 1) Package/docs alignment after rename

- Updated references from `autotagr` to `openalexVectorComp` in key docs.
- Removed obsolete vignette `vignettes/autotagr.Rmd`.
- Removed obsolete TODO source `R/run_autotag.R.todo` that referenced
  non-existent APIs.
- Updated vignette code in `vignettes/simplestart.qmd` to match current
  function signatures.

### 2) Documentation consistency fixes

- Corrected mismatches between function signatures and docs, including:
  - `calibrate_threshold()` argument behavior/docs.
  - `distance_reference_cosine()` output column naming/docs.
  - `distance_ridge()` stale parameter docs.
  - embedding orchestration behavior/docs.
- Regenerated roxygen2 docs (`man/`, `NAMESPACE`) using source loading.

### 3) Pluggable backend refactor

- Added backend adapter API split across provider-specific files:
  - `R/embed_backend_core.R` (exported config/info/embed dispatch)
  - `R/embed_backend_hf.R` (Hugging Face adapter)
  - `R/embed_backend_openai.R` (OpenAI adapter)
  - `R/embed_backend_tei.R` (TEI/local adapter)
- Removed the previous single-file implementation (`R/embed_backend.R`).
- Central dispatch now supports `provider = "hf"`, `"openai"`, or `"tei"`.

### 4) Authentication convention

- Standardized provider token handling to one environment variable:
  - `OVC_API_TOKEN`
- Adapter sends this token as `Authorization: Bearer <token>` when present.

### 5) Defaults and endpoint behavior

- Default backend configuration now targets HF inference:
  - `provider = "hf"`
  - model default: `BAAI/bge-small-en-v1.5`

### 6) TEI simplification and pipeline behavior updates

- Added generic embedding entry points:
  - `embed_texts()` (single-call text embedding via configured backend)
  - `embed_corpus()` (streaming corpus embedding pipeline)
- Removed TEI-specific embedding entry points:
  - `tei_embed_text()`
  - `tei_embed()`
- `embed_corpus()` now:
  - switched to canonical text construction:
    - `Title: {title}\nAbstract: {abstract}`
    - title-only fallback when abstract is empty.
  - added resumable behavior using `id + text_hash`:
    - unchanged rows are skipped when `delete_existing = FALSE`.
    - full rebuild when `delete_existing = TRUE`.
  - output rows now include:
    - `id`, `text_hash`, `provider`, `model_id`, `created_at`, `V1..Vd`.

### 7) Exports and documentation

- Exports:
  - backend core functions added to `NAMESPACE`.
  - `prototype_centroid()` removed from public API; internal helper moved into
    `R/distance_reference_cosine.R` as `centroid_prototype()`.
- Documentation:
  - maintained via roxygen2 and regenerated `man/` + `NAMESPACE`.
  - added detailed Quarto vignette:
    - `vignettes/backend-architecture.qmd`
    - covers backend internals, dispatch order, sequence and flowchart diagrams,
      and how to add new providers.
  - added detailed TEI operations vignette:
    - `vignettes/tei-server-operations.qmd`
    - documents shell-based TEI process handling (start/stop/health), now that
      lifecycle helpers were removed from package code.

### 8) TEI server lifecycle simplification

- Removed in-package TEI lifecycle/state helpers:
  - `tei_start()`, `tei_stop()`, `tei_state()`, `tei_info()`,
    `tei_default_embed_url()`
- Removed package unload hook/state container by deleting `R/zzz.R`.
- Removed dependency on `processx`.
- TEI backend probing now uses internal lightweight HTTP `/info` probing in
  `R/embed_backend_tei.R`.

### 9) Test suite additions (HF integration)

- Added `testthat` infrastructure:
  - `tests/testthat.R`
  - `Config/testthat/edition: 3` in `DESCRIPTION`
  - `testthat (>= 3.0.0)` in `Suggests`
- Added HF integration helpers:
  - `tests/testthat/helper-hf.R`
  - skips tests unless `OVC_API_TOKEN` is set and HF endpoint is reachable.
- Added end-to-end integration tests:
  - `tests/testthat/test-hf-end-to-end.R`
  - covers:
    - `embed_texts()`
    - `embed_corpus()`
    - `distance_reference_cosine()`
    - `distance_ridge()`
    - `calibrate_threshold()`

### 10) HF router endpoint migration and probe hardening

- Fixed HF adapter URL construction mismatch:
  - router base URL now maps to `/models/{model}`
  - legacy API base URL keeps `/pipeline/feature-extraction/{model}`
- Updated HF test probe endpoint to:
  - `https://router.huggingface.co/hf-inference/models/BAAI/bge-small-en-v1.5`
- Probe request now uses:
  - `inputs = "ping"` (single string payload)
  - `req_error(is_error = function(resp) FALSE)` to inspect status codes
- Skip policy now only skips on:
  - network/transport errors
  - auth rejection (`401`, `403`)
  - provider outages (`5xx`)
- Removed unconditional `skip_on_cran()` from HF helper so local integration
  tests can run without requiring `NOT_CRAN=true`.
- `4xx` payload/model mismatches no longer force an automatic skip, making
  test behavior easier to diagnose.

### 11) HF default model change

- Switched the HF default model to `BAAI/bge-small-en-v1.5`.
- Updated HF test helper backend and probe request to use this model.
- Updated architecture vignette examples and default-model documentation
  accordingly.

### 12) Distance-function test expansion

- Added offline unit/integration coverage in
  `tests/testthat/test-distance-functions.R` for:
  - `similarity_cosine()` and `distance_cosine()` (vector and matrix inputs)
  - `fit_ridge()` model persistence and class checks
  - `distance_reference_cosine()` output validity and positive-vs-negative separation
  - `distance_ridge()` score range checks (`[0, 1]`) and separation checks
  - internal `distances()` helper join behavior on overlapping `id` keys
- Tests use a synthetic local Parquet embeddings dataset and do not require API
  tokens or network access.

### 13) Validation and faulty-input test expansion

- Added `tests/testthat/test-validation-inputs.R` with negative/edge cases to
  increase branch coverage in lower-covered modules:
  - `embedding_backend_config()` validation:
    - non-positive `timeout`
    - negative `retries`
    - non-positive `max_batch_size`
  - backend dispatch validation:
    - invalid backend objects/providers in `embedding_backend_info()` and
      `embedding_backend_embed_texts()`
    - non-character `texts` and empty-text behavior
  - internal backend helper behavior:
    - `.embedding_as_matrix()` inconsistent/unsupported formats
    - `.embedding_batch_starts()` fallback for invalid batch size
    - `.embedding_with_retry()` success-after-retries and terminal failure
    - HF URL mapping branch coverage (`/models/...` vs legacy
      `/pipeline/feature-extraction/...`)
  - `embed_corpus()` input checks:
    - empty `project_dir`
    - invalid `batch_size`
    - invalid backend object
    - missing required corpus columns
  - `fit_ridge()` / `distance_ridge()` failure modes:
    - embeddings with no `V1..Vd` columns
    - included ids absent from dataset
  - `calibrate_threshold()` validation:
    - missing score column
    - malformed `labels_parquet` schema
    - no labeled rows available for calibration

### 14) Metadata file rename and sidecar behavior

- Renamed embeddings metadata sidecar:
  - from `_tei_info.yaml`
  - to `embed_model.yaml`
- Updated metadata handling in:
  - `embed_corpus()` write path
  - `distance_ridge()` read/copy path
- Added backward compatibility in `distance_ridge()`:
  - prefers `embed_model.yaml`
  - falls back to legacy `_tei_info.yaml` for existing projects
- Expanded metadata payload to better support reproducibility:
  - `model.id`
  - `model.requested_id`
  - `model.embedding_dim`
  - `backend.provider`
  - `backend.base_url`
  - `backend.embed_url`
  - `backend.max_batch_size`
  - `backend.timeout`
  - `backend.retries`
- Because `embed_model.yaml` is a non-parquet sidecar in dataset directories,
  Arrow dataset openings now use:
  - `factory_options = list(exclude_invalid_files = TRUE)`
  in pipeline and plotting paths that scan these directories.

### 15) Backend config YAML read/save API

- Added exported helpers:
  - `embedding_backend_read(fn = "embed_model.yaml")`
  - `embedding_backend_save(backend, fn = "embed_model.yaml")`
- `embedding_backend_save()` writes YAML in the same field shape as
  `embedding_backend_config()` output:
  - `provider`, `base_url`, `model`, `embed_url`, `max_batch_size`,
    `timeout`, `retries`
- `embedding_backend_read()` returns a normalized backend config by calling
  `embedding_backend_config()` under the hood.
- Backward compatibility:
  - `embedding_backend_read()` also accepts legacy nested metadata format
    (`model` + `backend` blocks) from earlier alpha revisions.
- `embed_corpus()` now writes metadata through `embedding_backend_save()`.
- `distance_ridge()` now reads metadata through `embedding_backend_read()` when
  deriving model partition naming.

### 16) Coverage-focused offline test expansion

- Added `tests/testthat/test-embedding-offline.R` to increase branch coverage
  without network/API tokens:
  - `embed_texts()` forwarding behavior
  - HF/OpenAI/TEI adapter batching paths
  - adapter malformed-payload error paths
  - `embed_corpus()` incremental behavior and `delete_existing` branch
- Expanded `tests/testthat/test-validation-inputs.R` with a successful
  `calibrate_threshold()` run using `labels_parquet`,
  `metric = "precision_at_recall"`, and explicit thresholds.

### 17) Plot function rename and tests

- Renamed plotting API from TEI-specific names to backend-neutral names:
  - `tei_plot_pca()` -> `plot_embeddings_pca()`
  - `tei_plot_umap()` -> `plot_embeddings_umap()`
- Renamed source file:
  - `R/tei_plot.R` -> `R/plot_embeddings.R`
- Regenerated docs/exports:
  - removed `man/tei_plot_pca.Rd`, `man/tei_plot_umap.Rd`
  - added `man/plot_embeddings_pca.Rd`, `man/plot_embeddings_umap.Rd`
- Added `tests/testthat/test-plot-embeddings.R` covering:
  - PCA and UMAP happy paths
  - CSV/vector include/exclude id inputs
  - sampling path in UMAP
  - schema/embedding-column validation errors

### 18) Pluggable text preparation in `embed_corpus()`

- Added exported default cleaner:
  - `clean_abstract_for_embedding()`
  - returns contract columns `id`, `text`, `text_hash`
  - optionally returns provenance fields:
    - `text_quality`, `abstract_raw_present`, `abstract_kept`,
      `discard_reason`, `cleaning_mode`
- `embed_corpus()` now accepts:
  - `text_preprocessor` (function)
  - `cleaner_args` (list passed to preprocessor)
- `embed_corpus()` now validates preprocessor outputs:
  - must be a data frame
  - must include `id`, `text`, `text_hash`
  - no ids outside the current batch
  - no duplicated ids
  - drops empty/NA `id` or `text`
- Resume/skip logic remains `id + text_hash`, but hash is now produced by the
  preprocessor.
- Output parquet now preserves extra preprocessor-provided provenance columns.
- `embed_model.yaml` now includes a `text_preprocessor` section with:
  - `name`
  - `mode` (if set via `cleaner_args`)
  - `no_abstract_policy` (if set via `cleaner_args`)

### 19) Tests for new cleaner/preprocessor contract

- Added `tests/testthat/test-clean-abstract-for-embedding.R`:
  - happy path
  - missing abstract policies
  - duplicated title removal
  - placeholder/boilerplate handling
  - mode behavior differences
  - hash stability
- Expanded `tests/testthat/test-embedding-offline.R`:
  - custom `text_preprocessor` usage
  - `cleaner_args` passthrough verification
  - contract error handling for bad preprocessor outputs
  - metadata assertions for `embed_model.yaml` preprocessor block

### 20) Detailed abstract-cleaning vignette

- Added a dedicated Quarto vignette:
  - `vignettes/abstract-cleaning.qmd`
- Covers:
  - cleaning rationale and pipeline stages
  - mermaid flow diagram of cleaning/decision path
  - mode/policy behavior (`lenient|balanced|strict`,
    `keep_title_only|discard|conditional`)
  - step-by-step examples, including before/after kept vs discarded outputs
  - custom pattern overrides
  - integration with `embed_corpus(text_preprocessor, cleaner_args)`
  - preprocessor contract validation and provenance columns

## Main Design Considerations

The complexity does not mainly come from TEI itself.
It comes from combining these concerns:

- backend abstraction (config/info/embed separation),
- resumable/idempotent writes (`id + text_hash`),
- variable endpoint capabilities (model info, request limits),
- robust long-run behavior (retry handling, metadata tracking).

Supporting both local TEI and hosted inference APIs can increase variability, but
resume/reliability requirements are the biggest complexity driver.

## Simplification Tradeoff

A simpler alternative would be:

- one TEI embedding function with fixed arguments (`url`, `texts`, `batch_size`),
- no backend registry/dispatch,
- minimal/no retries,
- no service probing in adapter,
- keep resume logic only in pipeline layer.

This is easier to maintain but less extensible for additional providers.

## Process Notes

- `roxygen2::roxygenise(load = "source")` was used because full package loading
  in this environment can fail due to system restrictions around some dependencies.
- Existing unrelated repo changes were preserved.
- `inst/openalex_embedding_pipeline_v4.md` was intentionally left in place.

## Ongoing Updates

This file should be updated as additional changes are made in this branch so it
remains a single place to review implementation decisions and rationale.

### 21) Label-partitioned embeddings and pairwise prototype distances

- `embed_corpus()` gained a new `label` argument (default `"corpus"`).
- Embeddings path changed from `model/batch` to `model/label/batch`:
  - `embeddings/model_id=<...>/label=<label>/batch=<n>/embeddings-*.parquet`
- `delete_existing = TRUE` now deletes only the selected `label` subtree.
- Resume hash loading now reads only the selected `label` partition.
- Dry-run preview filename is now model-independent and corpus-based:
  - `<corpus_name>_dryrun.parquet`
- `embed_model.yaml` now stores `embedding_label` for traceability.

- `distance_reference_cosine()` was redesigned from `included/excluded` centroid margin
  to label-based cosine distance computation:
  - inputs: `corpus_label`, `reference_label`
  - computes pairwise matrix between all `reference` and `corpus` vectors
  - output path:
    - `distance_reference_cosine/model_id=<...>/corpus_label=<...>/reference_label=<...>/pairwise-cosine.parquet`
  - includes `max_cells` guard for memory safety.

### 22) Ridge refactor to reference-area scoring

- `fit_ridge()` was redesigned to fit a reference-area model instead of binary
  ridge logistic classification.
- New fit contract:
  - inputs: embeddings dataset + `reference_label`
  - computes:
    - centroid `mu`
    - covariance `Sigma` (with fallback for very small reference sets)
    - regularized inverse covariance `Sigma_inv`
  - saves a fit object with class `ovc_reference_area_fit`.

- `distance_ridge()` now:
  - fits (or loads) reference-area model
  - computes squared Mahalanobis distance `area_distance` for
    `corpus_label` vectors
  - writes parquet with columns:
    - `id`
    - `area_distance`
  - output path:
    - `distance_ridge/model_id=<...>/corpus_label=<...>/reference_label=<...>/batch=<n>/ridge-area-*.parquet`

- Added `score_ridge()`:
  - reads `distance_ridge()` output
  - computes `relevance_score = exp(-alpha * area_distance)` (default
    `alpha = 0.5`)
  - writes scored parquet under `score_ridge/...`.

- Metadata copy for distance outputs now includes ridge-mode context fields:
  - `ridge_mode: reference_area`
  - `reference_label`
  - `corpus_label`
  - `regularization`

### 23) Calibration flow alignment

- `calibrate_threshold()` was fixed to only read `included`/`excluded` CSVs
  when `labels_parquet` is not provided.
- This enables labels-only calibration for the new ridge workflow.

### 24) `distance_reference_cosine()` distance-only matrix with centroid axis

- `distance_reference_cosine()` was further simplified to be distance-only and
  single-file:
  - removed selectable `output` mode argument.
  - removed separate `centroid-cosine.parquet` output.
- Current output is always:
  - `pairwise-cosine.parquet` under
    `distance_reference_cosine/model_id=<...>/corpus_label=<...>/reference_label=<...>/`.
- Output schema now encodes both pairwise and centroid distances in one wide
  matrix:
  - first column: `id` (corpus ids + one `"centroid"` row for corpus centroid),
  - remaining columns: reference ids + one `"centroid"` column for reference
    centroid.
- Cell semantics:
  - regular cells: `dist(corpus_i, reference_j)`,
  - centroid column: `dist(corpus_i, reference_centroid)`,
  - centroid row: `dist(corpus_centroid, reference_j)`,
  - centroid corner: `dist(corpus_centroid, reference_centroid)`.

### 25) `score_reference_cosine()` for full-matrix cosine scoring

- Added exported `score_reference_cosine()` to transform the full output matrix
  from `distance_reference_cosine()`.
- Supports scoring methods:
  - `linear` (default): `score = 1 - distance`
  - `exponential`: `score = exp(-alpha * distance)`
- Preserves matrix shape (`id` + all value columns) and writes scored output
  under `score_reference_cosine/...`.
- Implementation simplified to lazy Arrow/dplyr selection + single
  materialization/write (no synthetic batch partition output).

### 26) User-facing demo project runner + Quarto template

- Added exported `run_demo_openalex_quarto()`:
  - default demo location: `file.path(getwd(), "demo_project")`
  - creates and preserves:
    - `demo_backend.yaml` in `demo_dir/`
    - `openalex_demo_analysis.qmd` in `demo_dir/`
    - `project/corpus/` in `demo_dir/`
    - `project/reference_corpus/` in `demo_dir/`
  - optional `render = TRUE` runs `quarto render` inside `demo_dir`.
- Added install-time demo fixtures in `inst/ovc_demo/`:
  - `project/corpus/corpus_small.parquet` (<= 100 rows, `id/title/abstract`)
  - `project/reference_corpus/reference_small.parquet` (<= 10 rows, `id/title/abstract`)
- Added Quarto analysis template in `inst/ovc_demo/openalex_demo_analysis.qmd`
  covering:
  - `embed_corpus(label = "corpus")`
  - `embed_corpus(label = "reference")` via temporary corpus swap
  - `distance_reference_cosine()`
  - `score_reference_cosine()`
  - `distance_ridge()`
  - `score_ridge()`
- Added tests in `tests/testthat/test-demo-runner.R` for setup, overwrite
  handling, fixture/schema caps, template call coverage, and optional render.
