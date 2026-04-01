# Save backend configuration to YAML

Writes a backend configuration (same shape as returned by
[`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md))
to YAML.

## Usage

``` r
embedding_backend_save(
  backend = embedding_backend_config(),
  fn = "embed_model.yaml"
)
```

## Arguments

- backend:

  Backend configuration from
  [`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).

- fn:

  Output YAML file path. Defaults to `"embed_model.yaml"`.

## Value

Invisibly returns `fn`.
