# Embed texts through a configured backend

Sends a character vector to the configured backend and returns
embeddings as a numeric matrix.

## Usage

``` r
embed_texts(texts, backend = embedding_backend_config())
```

## Arguments

- texts:

  Character vector of texts to embed. Empty inputs return a 0-row
  matrix; missing values are not supported.

- backend:

  Backend configuration created with
  [`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).

## Value

A numeric matrix with one row per input text and one column per
embedding dimension.
