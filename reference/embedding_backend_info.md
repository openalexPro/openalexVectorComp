# Get embedding backend model/service information

Returns normalized backend metadata used by the pipeline.

## Usage

``` r
embedding_backend_info(backend = embedding_backend_config())
```

## Arguments

- backend:

  Backend configuration from
  [`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).

## Value

A list with fields `provider`, `model_id`, `dim`, `max_batch_size`, and
`raw`.
