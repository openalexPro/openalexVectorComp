# Get embedding backend model/service information

Returns normalized backend metadata used by the pipeline.

## Usage

``` r
backend_info(backend = backend_config())
```

## Arguments

- backend:

  Backend configuration from
  [`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).

## Value

A list with fields `provider`, `model_id`, `dim`, `max_batch_size`, and
`raw`.
