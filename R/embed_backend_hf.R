.embedding_info_hf <- function(backend) {
  embed_url <- backend$embed_url
  if (is.null(embed_url) || !nzchar(embed_url)) {
    base <- sub("/+$", "", backend$base_url)
    if (grepl("router\\.huggingface\\.co/hf-inference$", base)) {
      embed_url <- paste0(base, "/models/", backend$model)
    } else {
      embed_url <- paste0(base, "/pipeline/feature-extraction/", backend$model)
    }
  }
  list(
    provider = "hf",
    model_id = backend$model,
    dim = NA_integer_,
    max_batch_size = as.integer(.embedding_or(backend$max_batch_size, 128L)),
    raw = list(embed_url = embed_url)
  )
}

.embedding_embed_texts_hf <- function(texts, backend) {
  info <- .embedding_info_hf(backend)
  embed_url <- info$raw$embed_url
  max_batch <- as.integer(.embedding_or(backend$max_batch_size, info$max_batch_size))
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
