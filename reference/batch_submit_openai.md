# Submit OpenAI Batch jobs for corpus embeddings (asynchronous)

Preprocesses corpus text, performs preflight request-size checks, splits
work into compliant OpenAI batch jobs, submits them, and returns
immediately.

## Usage

``` r
batch_submit_openai(
  project_dir,
  backend = backend_config(provider = "openai"),
  corpus_name = "corpus",
  label = corpus_name,
  batch_size = 5000,
  delete_existing = FALSE,
  text_preprocessor = clean_abstract_for_embedding,
  cleaner_args = list(),
  save_text = TRUE,
  max_requests_per_job = 20000L,
  max_job_bytes = 150 * 1024^2,
  completion_window = "24h",
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Project root directory.

- backend:

  Backend configuration from
  [`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).
  Must use `provider = "openai"`.

- corpus_name:

  Folder name under `project_dir` containing the corpus dataset.
  Defaults to `"corpus"`.

- label:

  Embedding label partition. Defaults to `corpus_name`.

- batch_size:

  Number of corpus rows per Arrow scan batch while preparing requests.

- delete_existing:

  If `TRUE`, remove existing embeddings for `label` and existing OpenAI
  batch state before submitting new jobs.

- text_preprocessor:

  Text-preparation function returning `id`, `text`, `text_hash`.

- cleaner_args:

  Additional named arguments passed to `text_preprocessor`.

- save_text:

  Logical; whether to keep cleaned text for downstream parquet output.

- max_requests_per_job:

  Max requests per submitted OpenAI job. Must be \<= 50000.

- max_job_bytes:

  Max JSONL bytes per submitted OpenAI job. Must be \<= 200 MB.

- completion_window:

  OpenAI batch completion window. Defaults to `"24h"`.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns a list with state path and submission summary.
