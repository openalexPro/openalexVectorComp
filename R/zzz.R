.onUnload <- function(libpath) {
  # Best-effort stop of any background TEI server started by this package
  try(tei_stop(silent = TRUE), silent = TRUE)
}

# Internal: package-level TEI server state
# Holds the background process handle and connection info for the session.
.tei_server_state <- local({
  .env <- new.env(parent = emptyenv())
  .env$proc <- NULL
  .env$pid <- NA_integer_
  .env$port <- NA_integer_
  .env$url <- NULL
  .env$cmd <- NULL
  .env$log_out <- NULL
  .env$log_err <- NULL
  function() .env
})

#' TEI server session state
#'
#' Returns the current TEI server session state remembered by this package,
#' including PID, port, URL, and whether the background process is alive.
#'
#' @return A named list with fields `pid`, `port`, `url`, `cmd`, `running`.
#' @export
tei_state <- function() {
  st <- .tei_server_state()
  running <- FALSE
  if (!is.null(st$proc) && inherits(st$proc, "processx_process")) {
    running <- isTRUE(tryCatch(st$proc$is_alive(), error = function(e) FALSE))
  } else if (!is.null(st$pid) && !is.na(st$pid)) {
    # Best-effort check via pskill 0 (may not be portable everywhere)
    alive <- try(tools::pskill(st$pid, 0L), silent = TRUE)
    running <- !identical(alive, FALSE)
  }
  list(
    pid = st$pid,
    port = st$port,
    url = st$url,
    cmd = st$cmd,
    running = running
  )
}
