# Stream a corpus dataset, embed in batches, and write Parquets

Processes a Parquet dataset without loading it fully in memory. Reads
Arrow record batches, builds canonical text from `title` + `abstract`,
calls the configured embedding backend, and writes Parquet batch files.

## Usage

``` r
embed_corpus(
  project_dir = NULL,
  backend = backend_config(),
  corpus_name = "corpus",
  batch_size = 5000,
  delete_existing = FALSE,
  text_preprocessor = clean_abstract_for_embedding,
  cleaner_args = list(),
  save_text = TRUE,
  label = corpus_name,
  dry_run = FALSE,
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Project root directory. Must contain `project_dir/<corpus_name>` with
  columns `id`, `title`, `abstract`.

- backend:

  Backend configuration created with
  [`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).

- corpus_name:

  Folder name under `project_dir` containing the corpus parquet dataset.
  Defaults to `"corpus"`.

- batch_size:

  Number of corpus rows per Arrow scan batch.

- delete_existing:

  If `TRUE`, old embeddings for the target model are deleted before
  processing. If `FALSE`, unchanged rows are skipped using
  `id + text_hash`.

- text_preprocessor:

  Function that prepares embedding text from a batch data frame and
  returns at least columns `id`, `text`, `text_hash`. Defaults to
  [`clean_abstract_for_embedding()`](https://openalexpro.github.io/openalexVectorComp/reference/clean_abstract_for_embedding.md).

- cleaner_args:

  Named list of additional arguments passed to `text_preprocessor`.

- save_text:

  Logical; if `TRUE` (default), store the cleaned embedding text in
  output Parquet files as column `text`. If `FALSE`, only `text_hash` is
  stored.

- label:

  Partition label written under
  `project_dir/embeddings/model_id=<...>/label=<label>/batch=<n>/`.
  Defaults to `corpus_name`.

- dry_run:

  Logical; if `TRUE`, run preprocessing and unchanged-row filtering
  without requesting embeddings or writing output files. In this mode, a
  Parquet preview file is written to
  `project_dir/<corpus_name>_dryrun.parquet`.

- verbose:

  Logical; print progress and summary messages.

## Value

Invisibly the model-specific embeddings directory under
`project_dir/embeddings/model_id=<...>/`.
