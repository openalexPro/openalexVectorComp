# Compute corpus distance to a reference embedding area

Fits (or loads) a reference-area model from `reference_label` embeddings
and computes squared Mahalanobis distance for rows in `corpus_label`.

## Usage

``` r
distance_ridge(
  project_dir,
  reference_label = "reference",
  corpus_label = "corpus",
  fit_path = NULL,
  batch_size = 1e+05,
  regularization = 1e-06,
  verbose = TRUE
)
```

## Arguments

- project_dir:

  Project root containing `embeddings/`.

- reference_label:

  Label partition used to fit the reference area. Defaults to
  `"reference"`.

- corpus_label:

  Label partition to score. Defaults to `"corpus"`.

- fit_path:

  Optional path to an existing reference-area fit (`.rds`). If `NULL`, a
  new fit is created at `project_dir/ridge_fit.rds`.

- batch_size:

  Approximate number of rows per Arrow scan batch.

- regularization:

  Diagonal covariance regularization added before inversion.

- verbose:

  Logical; print progress messages.

## Value

Invisibly the model output directory under
`project_dir/distance_ridge/model_id=<...>/corpus_label=<...>/reference_label=<...>/`.
