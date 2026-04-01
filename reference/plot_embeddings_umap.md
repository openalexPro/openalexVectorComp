# Plot embeddings via UMAP, colored by arbitrary labels

Computes a 2D UMAP projection of `V1..Vd` and returns a scatter plot
colored by `labels` membership. Uses cosine distance by default to align
with common embedding similarity.

## Usage

``` r
plot_embeddings_umap(
  embeddings,
  labels,
  n_neighbors = 15,
  min_dist = 0.1,
  metric = "cosine",
  n_epochs = 500,
  seed = 42,
  sample_n = NULL,
  point_size = 2,
  alpha = 0.5
)
```

## Arguments

- embeddings:

  Path to a Parquet file or dataset directory containing columns `id`
  and `V1..Vd`.

- labels:

  Label mapping for ids. Supported formats:

  1.  data frame with columns `id` and `label`,

  2.  path to CSV with columns `id` and `label`,

  3.  named character vector where names are ids and values are labels,

  4.  named list where each element is an id vector for that label.

- n_neighbors, min_dist, metric, n_epochs:

  UMAP parameters passed to
  [`uwot::umap()`](https://jlmelville.github.io/uwot/reference/umap.html).
  Defaults: `n_neighbors = 15`, `min_dist = 0.1`, `metric = "cosine"`,
  `n_epochs = 500`.

- seed:

  Random seed for reproducibility (set to `NULL` to skip).

- sample_n:

  Optional maximum number of rows to sample for plotting (applied before
  UMAP). If `NULL`, uses all rows.

- point_size, alpha:

  Point size and transparency for points in the plot. Defaults
  `point_size = 2`, `alpha = 0.5`.

## Value

A `ggplot` object of UMAP1 vs UMAP2 colored by group.
