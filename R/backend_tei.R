.embedding_info_tei <- function(backend) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  embed_url <- backend$embed_url
  if (is.null(embed_url) || !nzchar(embed_url)) {
    embed_url <- paste0(backend$base_url, "/embed")
  }

  info <- .embedding_probe_tei(embed_url)
  has_info <- !is.null(info)

  model_id <- if (has_info) {
    info$model$id %||% info$model$requested_id %||% backend$model
  } else {
    backend$model
  }
  if (is.null(model_id) || !nzchar(model_id)) {
    model_id <- sub("^.*/pipeline/feature-extraction/", "", embed_url)
  }

  dim <- if (has_info) {
    info$model$embedding_dim %||% info$probe$embedding_dim
  } else {
    NA_integer_
  }
  max_batch <- if (has_info) {
    backend$max_batch_size %||% info$server$max_client_batch_size %||% 128L
  } else {
    backend$max_batch_size %||% 128L
  }

  list(
    provider = "tei",
    model_id = model_id,
    dim = as.integer(dim),
    max_batch_size = as.integer(max_batch),
    raw = if (has_info) info else list(embed_url = embed_url)
  )
}

.embedding_embed_texts_tei <- function(texts, backend) {
  `%||%` <- function(x, y) if (is.null(x)) y else x

  info <- .embedding_info_tei(backend)
  embed_url <- info$raw$server$embed_url %||% info$raw$embed_url %||% paste0(backend$base_url, "/embed")
  max_batch <- as.integer(backend$max_batch_size %||% info$max_batch_size)
  starts <- .embedding_batch_starts(length(texts), max_batch)
  emb_list <- vector("list", length(starts))

  for (i in seq_along(starts)) {
    start <- starts[[i]]
    end <- min(length(texts), start + max_batch - 1L)
    batch <- texts[start:end]

    res <- .embedding_with_retry(
      backend,
      function() {
        .embedding_request_base(embed_url, backend) |>
          httr2::req_body_json(list(inputs = as.list(batch))) |>
          httr2::req_perform() |>
          httr2::resp_body_json(simplifyVector = TRUE)
      }
    )
    emb <- .embedding_as_matrix(res)
    if (nrow(emb) != length(batch)) {
      stop(
        "Embedding count mismatch: got ",
        nrow(emb),
        " vectors for ",
        length(batch),
        " submitted texts."
      )
    }
    emb_list[[i]] <- emb
  }

  out <- do.call(rbind, emb_list)
  colnames(out) <- paste0("V", seq_len(ncol(out)))
  out
}

.embedding_probe_tei <- function(embed_url) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
  base <- sub("/embed/?$", "", embed_url)
  base <- sub("/+$", "", base)
  info_url <- paste0(base, "/info")

  info <- try(
    httr2::request(info_url) |>
      httr2::req_perform() |>
      httr2::resp_body_json(simplifyVector = TRUE),
    silent = TRUE
  )
  if (inherits(info, "try-error")) {
    return(NULL)
  }

  list(
    model = list(
      id = info$model_id %||% NA_character_,
      requested_id = info$model_id %||% NA_character_,
      embedding_dim = info$embedding_size %||% NA_integer_
    ),
    server = list(
      max_client_batch_size = info$max_client_batch_size %||% NA_integer_,
      embed_url = embed_url
    )
  )
}
