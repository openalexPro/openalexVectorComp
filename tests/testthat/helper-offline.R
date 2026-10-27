# Offline test helpers: no network, no keyring.

# Set (or unset, with `value = NA`) OVC_API_TOKEN for the calling test only.
ovc_local_token <- function(value = "test-token", env = parent.frame()) {
  old <- Sys.getenv("OVC_API_TOKEN", unset = NA)
  if (is.na(value)) {
    Sys.unsetenv("OVC_API_TOKEN")
  } else {
    Sys.setenv(OVC_API_TOKEN = value)
  }
  restore <- substitute(
    if (is.na(OLD)) Sys.unsetenv("OVC_API_TOKEN") else Sys.setenv(OVC_API_TOKEN = OLD),
    list(OLD = old)
  )
  do.call(base::on.exit, list(restore, add = TRUE), envir = env)
  invisible(value)
}

ovc_ns <- function(name) getFromNamespace(name, "openalexVectorComp")
