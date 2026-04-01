# Join prototype and ridge distances lazily via Arrow

Opens two Parquet datasets (prototype margins and ridge scores) as Arrow
datasets and performs a lazy inner join on the common key (typically
`id`). The result is an Arrow-dplyr query that is not materialized until
you call
[`dplyr::collect()`](https://dplyr.tidyverse.org/reference/compute.html)
or write it with
[`arrow::write_dataset()`](https://arrow.apache.org/docs/r/reference/write_dataset.html).

## Usage

``` r
distances(prototype_distances, ridge_distance)
```

## Arguments

- prototype_distances:

  Path to a Parquet dataset (file or directory) containing prototype
  distances, e.g., columns `id` and `margin`.

- ridge_distance:

  Path to a Parquet dataset (file or directory) containing ridge-based
  scores, e.g., columns `id` and `relevance_score`.

## Value

A lazy Arrow dplyr query representing the joined datasets.

## Examples

``` r
if (FALSE) { # \dontrun{
joined <- distances(
  prototype_distances = "path/to/prototype_distances/",
  ridge_distance      = "path/to/ridge_scores/"
)

# Continue piping lazily and write without loading into memory
joined |>
  dplyr::mutate(ensemble = (margin + relevance_score) / 2) |>
  arrow::write_dataset(path = "path/to/output_scores/", format = "parquet")

# Or collect a small sample for inspection
head(dplyr::collect(joined))
} # }
```
