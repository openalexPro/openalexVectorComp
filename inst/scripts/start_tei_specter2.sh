#!/usr/bin/env bash
# Start a local TEI server against the merged SPECTER2 proximity model.
#
# Run prepare_specter2_merged.py first to produce the merged model directory.
#
# Environment overrides:
#   OVC_SPECTER2_PATH   Path to merged model dir (default: per-user cache).
#   OVC_TEI_PORT        Port for text-embeddings-router (default: 8080).

set -euo pipefail

default_cache_dir() {
  case "$(uname -s)" in
    Darwin) echo "${HOME}/Library/Caches/org.R-project.R/R/openalexVectorComp/specter2_proximity_merged" ;;
    Linux)  echo "${XDG_CACHE_HOME:-${HOME}/.cache}/R/openalexVectorComp/specter2_proximity_merged" ;;
    *)      echo "${HOME}/.cache/R/openalexVectorComp/specter2_proximity_merged" ;;
  esac
}

MODEL_PATH="${OVC_SPECTER2_PATH:-$(default_cache_dir)}"
PORT="${OVC_TEI_PORT:-8080}"

if [ ! -f "${MODEL_PATH}/config.json" ]; then
  echo "Merged SPECTER2 model not found at: ${MODEL_PATH}" >&2
  echo "Run inst/scripts/prepare_specter2_merged.py first." >&2
  exit 1
fi

if ! command -v text-embeddings-router >/dev/null 2>&1; then
  echo "text-embeddings-router not on PATH. See vignettes/tei-server-operations.qmd." >&2
  exit 1
fi

echo "Serving ${MODEL_PATH} on port ${PORT}"
exec text-embeddings-router --model-id "${MODEL_PATH}" --port "${PORT}"
