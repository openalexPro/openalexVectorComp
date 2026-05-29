# Convert reference-cosine distances to scores

Reads a wide reference-cosine distance matrix (as written by
[`distance_reference_cosine()`](https://openalexpro.github.io/openalexVectorComp/reference/distance_reference_cosine.md))
and converts all numeric distance columns to scores.

## Usage

``` r
score_reference_cosine(
  distance_parquet,
  output_dir = NULL,
  method = c("linear", "exponential"),
  alpha = 1,
  verbose = TRUE
)
```

## Arguments

- distance_parquet:

  Path to a Parquet dataset (file or directory) with first column `id`
  and one or more numeric distance columns.

- output_dir:

  Optional output directory. If `NULL`, defaults to replacing
  `"distance_reference_cosine"` with `"score_reference_cosine"` in
  `distance_parquet`.

- method:

  Scoring transform: `"linear"` (default, `1 - distance`) or
  `"exponential"` (`exp(-alpha * distance)`).

- alpha:

  Positive numeric scaling factor used when `method = "exponential"`.

- verbose:

  Logical; print progress messages.

## Value

Invisibly returns output directory.
