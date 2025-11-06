#' Stream a Parquet dataset, embed in batches, and write shard Parquets
#'
#' Processes a Parquet *dataset* without loading it fully in memory.
#' Reads Arrow record batches, builds `text` from `title` + `abstract`,
#' calls TEI in sub-batches, and writes out embeddings as many Parquet
#' shard files under `out_dir` (or returns a list of shards if `out_dir` is NULL).
#'
#' @param parquet Path to a Parquet dataset (file or directory opened by Arrow).
#' @param tei_url TEI `/embed` endpoint (default "http://localhost:8080/embed").
#' @param batch_rows Approximate number of rows per Arrow scan batch (controls RAM).
#' @param request_batch Number of texts per TEI HTTP request.
#' @param out_dir If set, embeddings are written as shard files into this directory.
#'   Each shard contains columns: `id`, `V1..Vd`.
#' @return If `out_dir` is `NULL`, returns a list of data.frames (one per shard).
#'   Otherwise (recommended), returns (invisibly) the vector of written file paths.
#'
#' @details
#' Requires that the dataset has columns `id`, `title`, `abstract`.
#' Vector dimension `d` is inferred from the first TEI response.
#'
#' @examples
#' \dontrun{
#' paths <- tei_embed_parquet_stream(
#'   parquet = "input/openalex_dataset/",
#'   tei_url = "http://localhost:8080/embed",
#'   batch_rows = 5000, request_batch = 128,
#'   out_dir = "output/embeddings_shards"
#' )
#' # Later:
#' ds <- arrow::open_dataset("output/embeddings_shards")
#' }
#'
#' @importFrom arrow open_dataset
#' @importFrom httr2 request req_method req_body_json req_perform resp_body_json
#' @importFrom utils head
#' @importFrom stats setNames
#' @export
tei_embed_parquet <- function(
  parquet,
  tei_url = "http://localhost:8080/embed",
  batch_rows = 5000,
  request_batch = 128,
  out_dir = NULL
) {
  ds <- arrow::open_dataset(parquet)

  # Validate required columns lazily (names(ds) is available without materializing)
  req_cols <- c("id", "title", "abstract")
  missing <- setdiff(req_cols, names(ds))
  if (length(missing)) {
    stop("Dataset must contain columns: ", paste(missing, collapse = ", "))
  }

  # Create a Scanner that only selects needed columns and controls batch size.
  # We avoid dplyr verbs here to keep streaming explicit and minimal.
  scanner <- arrow::Scanner$create(
    ds,
    columns = req_cols,
    batch_size = as.integer(batch_rows)
  )
  reader <- scanner$ToRecordBatchReader()

  # Output preparation
  shard_idx <- 0L
  written <- character()
  out_list <- list()

  # Helper: embed a character vector via TEI in request-sized chunks
  .embed_chunked <- function(texts) {
    n <- length(texts)
    if (!n) {
      return(matrix(numeric(0), nrow = 0))
    }
    starts <- seq.int(1L, n, by = request_batch)
    mats <- vector("list", length(starts))
    for (j in seq_along(starts)) {
      a <- starts[[j]]
      b <- min(a + request_batch - 1L, n)
      body <- list(inputs = as.list(texts[a:b]))
      res <- httr2::request(tei_url) |>
        httr2::req_method("POST") |>
        httr2::req_body_json(body) |>
        httr2::req_perform() |>
        httr2::resp_body_json(simplifyVector = TRUE)
      mats[[j]] <- do.call(rbind, lapply(res, as.numeric))
    }
    do.call(rbind, mats)
  }

  repeat {
    batch <- reader$ReadNext()
    if (is.null(batch)) {
      break
    } # end of stream

    # Convert this record batch to a data.frame (bounded size)
    df <- as.data.frame(batch, stringsAsFactors = FALSE)

    # Build text safely (handle NA)
    title <- ifelse(is.na(df$title), "", df$title)
    abstr <- ifelse(is.na(df$abstract), "", df$abstract)
    text <- paste(title, abstr, sep = "\n\n")

    # Drop rows with missing id or empty text
    keep <- (!is.na(df$id)) & nzchar(text)
    if (!any(keep)) {
      next
    }
    ids <- df$id[keep]
    text <- text[keep]

    # Call TEI in sub-requests
    emb <- .embed_chunked(text) # matrix n x d

    # Build a shard data.frame: id + V1..Vd (dimension inferred from first response)
    if (nrow(emb) != length(ids)) {
      stop(
        "Embedding count mismatch: got ",
        nrow(emb),
        " vectors for ",
        length(ids),
        " ids."
      )
    }
    d <- ncol(emb)
    colnames(emb) <- paste0("V", seq_len(d))
    shard <- data.frame(id = ids, emb, check.names = FALSE)

    shard_idx <- shard_idx + 1L
    if (is.null(out_dir)) {
      out_list[[shard_idx]] <- shard
    } else {
      if (!dir.exists(out_dir)) {
        dir.create(out_dir, recursive = TRUE)
      }
      path <- file.path(out_dir, sprintf("embeddings-%05d.parquet", shard_idx))
      # Write one shard per batch (append-safe by design)
      arrow::write_parquet(shard, path)
      written <- c(written, path)
    }
  }

  if (is.null(out_dir)) {
    return(out_list)
  } else {
    return(invisible(written))
  }
}
