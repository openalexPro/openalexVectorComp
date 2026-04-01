# Build embedding backend configuration

Creates a configuration object used by the embedding backend adapter.

## Usage

``` r
backend_config(
  provider = c("hf", "openai", "tei"),
  base_url = NULL,
  model = NULL,
  max_batch_size = NULL,
  timeout = 60,
  retries = 3,
  tei_url = NULL
)
```

## Arguments

- provider:

  Backend provider: `"hf"`, `"openai"`, or `"tei"`.

- base_url:

  Provider base URL. If `NULL`, provider defaults are used.

- model:

  Optional model id. If `NULL`, provider defaults are used.

- max_batch_size:

  Optional max texts per HTTP request.

- timeout:

  Request timeout (seconds) used by backends that support it.

- retries:

  Number of retry attempts for transient failures.

- tei_url:

  Optional TEI compatibility argument. If provided, it is treated as the
  full embedding endpoint URL and overrides `base_url`.

## Value

A named list with backend configuration.
