# Calibrate threshold from Parquet scores by streaming batches

Sweeps candidate thresholds over scores stored in a Parquet dataset
without loading all rows into memory. Uses two passes: first to
determine the score range on the labeled subset; second to accumulate
confusion counts across a fixed grid of thresholds. Returns the best
threshold per the chosen metric.

## Usage

``` r
calibrate_threshold(
  scores_parquet,
  score_col,
  labels_parquet,
  metric = c("f1", "precision_at_recall"),
  recall_min = 0.8,
  thresholds = NULL,
  n_thresholds = 1001,
  batch_size = 1e+05,
  verbose = TRUE
)
```

## Arguments

- scores_parquet:

  Path to a Parquet dataset (file or directory) with at least columns
  `id` and the score column.

- score_col:

  Name of the score column to calibrate (e.g., "ensemble",
  "relevance_score", or "margin").

- labels_parquet:

  Parquet dataset path with columns `id` and `label` (`0/1`) used for
  calibration labels.

- metric:

  Optimisation target: `"f1"` (default) or `"precision_at_recall"`.

- recall_min:

  Minimum recall required when `metric = "precision_at_recall"`.

- thresholds:

  Optional numeric vector of thresholds to evaluate. If `NULL`, a
  regular grid between observed min/max is used (see `n_thresholds`).

- n_thresholds:

  Number of thresholds to generate when `thresholds` is `NULL` (default
  `1001`).

- batch_size:

  Approximate Arrow scan batch size.

- verbose:

  Logical; print progress messages.

## Value

List containing the selected threshold (`th`) and the associated
`precision`, `recall`, and `f1` values.

## Examples

``` r
if (FALSE) { # \dontrun{
best <- calibrate_threshold(
  scores_parquet = "output/scores/",
  score_col = "ensemble",
  labels_parquet = "output/labels/",
  batch_size = 200000
)
best$th
} # }
```
