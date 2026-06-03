# Backend preset for a local TEI server serving the merged SPECTER2 proximity model

Convenience wrapper around
[`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md)
for a SPECTER2 setup served by a local TEI (text-embeddings-inference)
server. The model itself must be prepared and started externally (see
`inst/scripts/prepare_specter2_merged.py` and
`inst/scripts/start_tei_specter2.sh`, and the `specter2-setup`
vignette).

## Usage

``` r
backend_specter2_tei(
  port = 8080L,
  host = "localhost",
  model = "allenai/specter2_proximity_merged"
)
```

## Arguments

- port:

  Port that TEI is listening on. Defaults to `8080`.

- host:

  Host for TEI. Defaults to `"localhost"`.

- model:

  Provenance label for the served model. Defaults to
  `"allenai/specter2_proximity_merged"`.

## Value

A backend configuration list compatible with
[`backend_config()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_config.md).

## Details

The `model` argument is metadata only and is recorded in
`embed_model.yaml` and parquet partition paths; TEI itself loads
whichever model it was started with.
