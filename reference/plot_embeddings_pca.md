# Plot embeddings via PCA, colored by arbitrary labels

Reads an embeddings Parquet dataset (produced by
[`embed_corpus()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus.md))
with columns `id` and `V1..Vd`, computes a PCA on the embedding matrix,
and returns a scatter plot of the first two principal components. Points
are colored by labels provided via `labels`. Rows not found in `labels`
are shown as `"other"`.

## Usage

``` r
plot_embeddings_pca(
  embeddings,
  labels,
  center = TRUE,
  scale. = FALSE,
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

- center, scale.:

  Passed to [`stats::prcomp()`](https://rdrr.io/r/stats/prcomp.html) for
  PCA. Defaults `center = TRUE`, `scale. = FALSE`.

- point_size, alpha:

  Point size and transparency for points in the plot. Defaults
  `point_size = 2`, `alpha = 0.5`.

## Value

A `ggplot` object with points mapped to PC1 vs PC2 and colored by group.

## Examples

``` r
if (FALSE) { # \dontrun{
p <- plot_embeddings_pca(
  embeddings = "inst/examples/embedings/",
  labels = data.frame(
    id = c("W1", "W2", "W10"),
    label = c("reference", "reference", "corpus")
  )
)
print(p)
} # }
```
