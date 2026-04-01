# Read backend configuration from YAML

Reads backend configuration from a YAML file and returns a normalized
object in the same format as
[`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).

## Usage

``` r
embedding_backend_read(fn = "embed_model.yaml")
```

## Arguments

- fn:

  Path to YAML file. Defaults to `"embed_model.yaml"`.

## Value

A backend configuration list compatible with
[`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md).

## Details

Supports both the current flat format and legacy nested metadata format.
