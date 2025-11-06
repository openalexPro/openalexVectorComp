#' Transfer TEI embeddings from Parquet to Qdrant (streaming)
#'
#' Streams a Parquet dataset of embeddings into a Qdrant collection.
#' Requires an `id` column and embedding columns (default: `V1..Vd`).
#'
#' @param parquet Path to a Parquet file or dataset directory.
#' @param qdrant_base Qdrant base URL, e.g. "http://localhost:6333".
#' @param collection Qdrant collection name.
#' @param id_col Name of the ID column (default "id").
#' @param vector_cols Optional character vector of embedding column names.
#'   If `NULL`, they are auto-detected by `vector_prefix` + integer suffix.
#' @param vector_prefix If `vector_cols` is `NULL`, columns starting with this
#'   prefix followed by digits are treated as vector dims (default "V").
#' @param distance Qdrant distance metric ("Cosine", "Euclid", "Dot").
#' @param batch_rows Approximate number of rows per Arrow scan batch.
#' @param upsert_batch Number of points per Qdrant upsert request.
#' @param payload_cols Optional character vector of columns to include as payload.
#'   If `NULL`, payloads are empty lists.
#'
#' @return Invisibly, the total number of vectors upserted.
#'
#' @examples
#' \dontrun{
#' tei_embeddings_parquet_to_qdrant(
#'   parquet = "output/embeddings_shards",
#'   qdrant_base = "http://localhost:6333",
#'   collection = "bioagora",
#'   payload_cols = c("year","title")  # if present
#' )
#' }
#'
#' @importFrom arrow open_dataset
#' @importFrom httr2 request req_method req_body_json req_perform
#' @export
tei_embeddings_parquet_to_qdrant <- function(
  parquet,
  qdrant_base,
  collection,
  id_col = "id",
  vector_cols = NULL,
  vector_prefix = "V",
  distance = "Cosine",
  batch_rows = 50000L,
  upsert_batch = 1000L,
  payload_cols = NULL
) {
  if (missing(qdrant_base) || is.null(qdrant_base)) {
    stop("'qdrant_base' (e.g. 'http://localhost:6333') is required.")
  }
  if (missing(collection) || !nzchar(collection)) {
    stop("'collection' must be a non-empty name.")
  }

  ds <- arrow::open_dataset(parquet)
  cols <- names(ds)
  if (!(id_col %in% cols)) {
    stop("Dataset is missing id column: '", id_col, "'.")
  }

  # Determine vector columns
  if (is.null(vector_cols)) {
    # Match prefix + digits, e.g., V1, V2, ..., V384
    is_vec <- grepl(paste0("^", vector_prefix, "[0-9]+$"), cols)
    vecs <- cols[is_vec]
    if (!length(vecs)) {
      stop(
        "Could not detect vector columns with prefix '",
        vector_prefix,
        "'. Provide 'vector_cols' explicitly."
      )
    }
    # Order by numeric suffix
    ord <- order(as.integer(sub(paste0("^", vector_prefix), "", vecs)))
    vector_cols <- vecs[ord]
  } else {
    missing_vec <- setdiff(vector_cols, cols)
    if (length(missing_vec)) {
      stop(
        "Missing specified vector columns: ",
        paste(missing_vec, collapse = ", ")
      )
    }
  }

  # Check payload columns (optional)
  if (!is.null(payload_cols)) {
    payload_cols <- intersect(payload_cols, cols)
  }

  # Create a scanner that selects only needed columns
  sel_cols <- unique(c(id_col, vector_cols, payload_cols))
  scanner <- arrow::Scanner$create(
    ds,
    columns = sel_cols,
    batch_size = as.integer(batch_rows)
  )
  reader <- scanner$ToRecordBatchReader()

  created <- FALSE
  total <- 0L
  dim_vec <- length(vector_cols)

  # Helper: build payload list for one row
  .row_payload <- function(df, i) {
    if (is.null(payload_cols) || !length(payload_cols)) {
      return(list())
    }
    p <- as.list(df[i, payload_cols, drop = FALSE])
    # Convert NAs to NULL to avoid sending JSON nulls if undesired
    for (nm in names(p)) {
      if (is.na(p[[nm]])) p[[nm]] <- NULL
    }
    p
  }

  # Upsert a chunk of rows [a:b]
  .upsert_range <- function(df, a, b) {
    n <- b - a + 1L
    if (n <= 0L) {
      return(invisible())
    }
    # vectors as numeric matrix
    M <- as.matrix(df[a:b, vector_cols, drop = FALSE])
    storage.mode(M) <- "double"

    pts <- vector("list", n)
    for (k in 1:n) {
      i <- a + k - 1L
      pts[[k]] <- list(
        id = df[[id_col]][i],
        vector = as.numeric(M[k, ]),
        payload = .row_payload(df, i)
      )
    }
    url <- paste0(qdrant_base, "/collections/", collection, "/points?wait=true")
    httr2::request(url) |>
      httr2::req_method("PUT") |>
      httr2::req_body_json(list(points = pts)) |>
      httr2::req_perform() |>
      invisible(NULL)
  }

  repeat {
    batch <- reader$ReadNext()
    if (is.null(batch)) {
      break
    }
    df <- as.data.frame(batch, stringsAsFactors = FALSE)

    # Create collection on first batch (idempotent PUT)
    if (!created) {
      body <- list(
        vectors = list(size = as.integer(dim_vec), distance = distance)
      )
      httr2::request(paste0(qdrant_base, "/collections/", collection)) |>
        httr2::req_method("PUT") |>
        httr2::req_body_json(body) |>
        httr2::req_perform()
      created <- TRUE
    }

    # Stream upsert in sub-batches
    n <- nrow(df)
    if (n > 0L) {
      starts <- seq.int(1L, n, by = as.integer(upsert_batch))
      for (s in starts) {
        e <- min(s + as.integer(upsert_batch) - 1L, n)
        .upsert_range(df, s, e)
      }
      total <- total + n
    }
  }

  invisible(total)
}
