# Cosine similarity between two numeric vectors

Computes cosine similarity for two numeric vectors of equal length.
Returns `NA_real_` if either vector has zero norm.

## Usage

``` r
similarity_cosine(a, b)
```

## Arguments

- a:

  Numeric vector.

- b:

  Numeric vector or numeric matrix with embeddings in rows.

## Value

A single numeric similarity value in `[-1, 1]`, or `NA_real_` when
undefined.
