# Fit a reference-area model from embeddings parquet

Fits a reference-area model (centroid + regularized covariance inverse)
using rows from `reference_label`.

## Usage

``` r
fit_ridge(
  embeddings,
  reference_label = "reference",
  output,
  regularization = 1e-06,
  verbose = TRUE
)
```

## Arguments

- embeddings:

  Path to a Parquet dataset (file or directory opened by Arrow) with
  columns `id`, `label`, and `V1..Vd`.

- reference_label:

  Label partition used to define the reference area.

- output:

  Name of the `.rds` file to save the fit object.

- regularization:

  Positive numeric diagonal regularization added to covariance.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns `output`.
