# Asynchronous OpenAI Batch Embeddings

## Why this workflow exists

For large corpora, synchronous embedding calls can be slow and fragile
over long sessions. The OpenAI Batch API allows you to submit work once,
then collect results later.

In `openalexVectorComp`, this is implemented as three explicit steps:

1.  [`embed_corpus_submit_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_submit_openai_batch.md)
2.  [`embed_corpus_status_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_status_openai_batch.md)
3.  [`embed_corpus_collect_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_collect_openai_batch.md)

This design is operationally safer than waiting for one long blocking
process.

## OpenAI vs OpenAlex (important)

This vignette describes **OpenAI Batch API** behavior (submission,
completion, retention). If you meant “how long results are on OpenAlex”,
that is a different service and outside this workflow.

## Lifecycle

``` mermaid
%%{init: {'theme': 'forest'}}%%
flowchart TD
  A[Prepare corpus + cleaner] --> B[Submit batches]
  B --> C[State JSON + local manifests]
  C --> D[Status polling]
  D -->|completed| E[Collect outputs]
  E --> F[Write canonical embeddings parquet]
  D -->|pending| G[Exit and retry later]
  F --> H[distance_reference_cosine / distance_ridge / scoring]
```

## Prerequisites

- `OVC_API_TOKEN` is set to a valid OpenAI API token.
- Backend is configured with `provider = "openai"`.
- Corpus exists under `project_dir/<corpus_name>` with columns:
  - `id`, `title`, `abstract`

``` r
library(openalexVectorComp)

backend <- embedding_backend_config(
  provider = "openai",
  model = "text-embedding-3-small"
)

Sys.getenv("OVC_API_TOKEN")
```

## Step 1: Submit jobs

[`embed_corpus_submit_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_submit_openai_batch.md)
preprocesses rows, applies skip logic, performs preflight checks,
auto-splits by limits, then submits jobs.

``` r
submit_info <- embed_corpus_submit_openai_batch(
  project_dir = "my_project",
  backend = backend,
  corpus_name = "corpus",
  label = "corpus",
  max_requests_per_job = 20000,
  max_job_bytes = 150 * 1024^2,
  verbose = TRUE
)

submit_info
```

### What preflight checks do

Before any remote submission:

- validates hard caps:
  - `max_requests_per_job <= 50000`
  - `max_job_bytes <= 200MB`
- builds JSONL request lines locally
- computes UTF-8 bytes per line
- auto-splits jobs if count/bytes would exceed limits
- errors if a **single line** is too large to fit one job

### Where state is written

- State file:
  - `project_dir/openai_batch_state_label=<label>.json`
- Local batch artifacts:
  - `project_dir/openai_batch/model_id=<...>/label=<...>/batch=<n>/`
    - `requests.jsonl`
    - `manifest.parquet`

## Step 2: Check status

Use
[`embed_corpus_status_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_status_openai_batch.md)
to inspect queued jobs.

``` r
status_df <- embed_corpus_status_openai_batch(
  project_dir = "my_project",
  label = "corpus",
  refresh_remote = TRUE
)

status_df
```

### Interpreting status values

Typical values include:

- `validating`
- `in_progress`
- `finalizing`
- `completed`
- `failed`
- `expired`
- `cancelled`

Only `completed` jobs are eligible for collection.

## Step 3: Collect completed jobs

[`embed_corpus_collect_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_collect_openai_batch.md)
downloads completed outputs, joins by `custom_id`, validates mapping,
and writes canonical embeddings parquet.

``` r
collect_info <- embed_corpus_collect_openai_batch(
  project_dir = "my_project",
  backend = backend,
  label = "corpus",
  verbose = TRUE
)

collect_info
```

If nothing is complete yet, the function exits cleanly with an
informational message. You can run collect repeatedly (for example from
cron).

## Output compatibility guarantee

Collected outputs are written to the same embedding contract used by
serial embedding:

- `project_dir/embeddings/model_id=<...>/label=<label>/batch=<n>/embeddings-*.parquet`

Core columns include:

- `id`
- `text_hash`
- `provider`
- `model_id`
- `created_at`
- optional `text`
- embedding columns `V1..Vd`

This keeps downstream functions unchanged:

- [`distance_reference_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/distance_reference_cosine.md)
- [`distance_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/distance_ridge.md)
- [`score_reference_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/score_reference_cosine.md)
- [`score_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/score_ridge.md)

## Common pitfalls and what to check

### 1) Authentication failures (401)

Check token in the render/session that runs submission:

``` r
Sys.getenv("OVC_API_TOKEN")
```

If you can call the embeddings endpoint manually but package calls fail,
confirm no example code overwrites `OVC_API_TOKEN` during execution.

### 2) Single oversized records

Auto-splitting handles oversized *jobs*, not oversized *single records*.
If one request line exceeds `max_job_bytes`, submission fails by design.

Action:

- improve cleaner/truncation policy
- or skip problematic rows intentionally

### 3) Duplicate submission risk

State + manifest tracking prevents re-submitting active rows, but avoid
manually editing state JSON unless necessary.

### 4) Concurrent collectors

The implementation uses a lock file to protect state writes. If a
process dies, a stale lock may need manual cleanup.

### 5) Confusing labels

Always keep labels explicit (`corpus`, `reference`, etc.) so output
partitions remain interpretable and downstream functions read the right
data.

## Data retention and expiry (OpenAI)

Operationally relevant points from OpenAI docs:

- Batch completion window is currently `24h`.
- Batch input files are JSONL and have size/request constraints.
- Batch output/error files support expiration policy
  (`output_expires_after`).
- Files with `purpose=batch` default to finite retention (OpenAI docs
  currently describe default expiry behavior; verify current details
  before production).

Because these details can change, monitor official docs and avoid
hard-coding assumptions into long-lived pipelines.

## Recommended operating pattern

1.  Submit in controlled chunks (`max_requests_per_job`,
    `max_job_bytes`).
2.  Poll status on a schedule.
3.  Collect completed jobs repeatedly.
4.  Archive local state + manifests for auditability.
5.  Run distance/scoring only after collection catches up.

## Monitoring checklist

- pending vs completed job counts
- rows submitted vs downloaded
- failed/expired/cancelled jobs
- ingestion lag (submission time to ingested time)
- lock-file contention incidents

## References

- OpenAI Batch API guide:
  <https://platform.openai.com/docs/guides/batch/>
- OpenAI Batch API reference:
  <https://platform.openai.com/docs/api-reference/batch/retrieve>
- OpenAI Files/Uploads reference:
  <https://platform.openai.com/docs/api-reference/files/object>
- OpenAI data controls:
  <https://platform.openai.com/docs/guides/your-data>
