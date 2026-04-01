# Embed texts via configured backend

Uses the configured backend adapter to embed a character vector of
texts. For authenticated providers, set `OVC_API_TOKEN` in the
environment. The adapter sends it as a bearer token.

## Usage

``` r
embedding_backend_embed_texts(texts, backend = embedding_backend_config())
```

## Arguments

- texts:

  Character vector of input texts.

- backend:

  Backend configuration from
  [`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).

## Value

Numeric matrix with one row per text and columns `V1..Vd`.
