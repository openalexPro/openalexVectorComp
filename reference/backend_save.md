# Save backend configuration to YAML

Writes a backend configuration (same shape as returned by
[`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md))
to YAML.

## Usage

``` r
backend_save(backend = backend_config(), fn = "embed_model.yaml")
```

## Arguments

- backend:

  Backend configuration from
  [`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).

- fn:

  Output YAML file path. Defaults to `"embed_model.yaml"`.

## Value

Invisibly returns `fn`.
