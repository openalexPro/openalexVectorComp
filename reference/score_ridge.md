# Convert ridge distances to ridge scores

Reads a distance dataset with columns `id` and `area_distance`, computes
`relevance_score = exp(-alpha * area_distance)`, and writes a scored
Parquet dataset.

## Usage

``` r
score_ridge(distance_parquet, output_dir = NULL, alpha = 0.5, verbose = TRUE)
```

## Arguments

- distance_parquet:

  Path to a Parquet dataset (file or directory) with at least columns
  `id` and `area_distance`.

- output_dir:

  Optional output directory. If `NULL`, defaults to replacing
  `"distance_ridge"` with `"score_ridge"` in `distance_parquet`.

- alpha:

  Positive numeric scaling factor in `exp(-alpha * area_distance)`.
  Default `0.5` reproduces previous behavior.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns output directory.
