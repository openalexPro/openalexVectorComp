# Pairwise cosine distances with centroid axis between label partitions

Reads embeddings from a model-specific dataset and computes cosine
distances between all vectors in `corpus_label` and all vectors in
`reference_label`. A centroid row/column is added to the matrix:

- rows are corpus ids plus `"centroid"` (corpus centroid),

- columns are reference ids plus `"centroid"` (reference centroid).

## Usage

``` r
distance_reference_cosine(
  project_dir,
  embeddings_dir = "model_id=BAAI_bge-small-en-v1.5",
  corpus_label = "corpus",
  reference_label = "reference",
  batch_size = 1e+05,
  max_cells = 5e+07,
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Project root directory containing `embeddings/`.

- embeddings_dir:

  Model subfolder under `project_dir/embeddings`, e.g.
  `"model_id=BAAI_bge-small-en-v1.5"`.

- corpus_label:

  Label partition used as corpus side. Defaults to `"corpus"`.

- reference_label:

  Label partition used as reference side. Defaults to `"reference"`.

- batch_size:

  Unused placeholder for compatibility with planned streaming extension.

- max_cells:

  Maximum allowed matrix size (`(n_corpus + 1) * (n_reference + 1)`) to
  guard memory use.

- verbose:

  Logical; print progress messages.

## Value

Invisibly the output directory
`project_dir/distance_reference_cosine/model_id=<...>/corpus_label=<...>/reference_label=<...>/`.

## Details

Embeddings are expected under:
`project_dir/embeddings/model_id=<...>/label=<label>/batch=<n>/...`

Output file:

- `pairwise-cosine.parquet`: wide table with first column `id` (corpus
  id or `"centroid"`), reference-id columns, and a final `centroid`
  column.
