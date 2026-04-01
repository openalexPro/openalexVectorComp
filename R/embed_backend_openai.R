.embedding_info_openai <- function(backend) {
  embed_url <- backend$embed_url
  if (is.null(embed_url) || !nzchar(embed_url)) {
    embed_url <- paste0(backend$base_url, "/embeddings")
  }
  list(
    provider = "openai",
    model_id = backend$model,
    dim = NA_integer_,
    max_batch_size = as.integer(.embedding_or(backend$max_batch_size, 2048L)),
    raw = list(embed_url = embed_url)
  )
}

.embedding_embed_texts_openai <- function(texts, backend) {
  info <- .embedding_info_openai(backend)
  embed_url <- info$raw$embed_url
  max_batch <- as.integer(.embedding_or(backend$max_batch_size, 512L))
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
          httr2::req_body_json(list(
            model = .embedding_or(backend$model, "text-embedding-3-small"),
            input = as.list(batch)
          )) |>
          httr2::req_perform() |>
          httr2::resp_body_json(simplifyVector = TRUE)
      }
    )

    if (is.null(res$data) || !length(res$data)) {
      stop("OpenAI embedding response did not contain `data`.")
    }
    data_part <- res$data
    emb_raw <- NULL

    if (is.data.frame(data_part)) {
      if (!("embedding" %in% names(data_part))) {
        stop("OpenAI embedding response `data` did not include `embedding`.")
      }
      emb_raw <- data_part$embedding
    } else if (is.list(data_part)) {
      # Typical shape: list(list(embedding = ...), ...)
      has_embedding <- vapply(
        data_part,
        function(x) is.list(x) && !is.null(x$embedding),
        logical(1)
      )
      if (length(has_embedding) && all(has_embedding)) {
        emb_raw <- lapply(data_part, function(x) x$embedding)
      } else {
        # Fallback for already-extracted embedding vectors.
        emb_raw <- data_part
      }
    } else {
      stop("OpenAI embedding response `data` has unsupported shape.")
    }

    emb <- .embedding_as_matrix(emb_raw)
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
