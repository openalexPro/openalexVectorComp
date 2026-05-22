#!/usr/bin/env python3
"""
Merge the SPECTER2 proximity adapter into the base encoder and save a standalone
HuggingFace-format model directory that TEI (text-embeddings-inference) can serve.

One-time setup. Run once per machine. Output directory is then passed to
text-embeddings-router via --model-id.

Usage:
    python prepare_specter2_merged.py [--out-dir PATH]

Environment overrides:
    OVC_SPECTER2_PATH   Output directory (takes precedence over --out-dir default).

Dependencies:
    pip install transformers adapters torch
"""

import argparse
import os
import sys
from pathlib import Path


DEFAULT_SUBDIR = "specter2_proximity_merged"


def default_out_dir() -> Path:
    env = os.environ.get("OVC_SPECTER2_PATH")
    if env:
        return Path(env).expanduser()
    if sys.platform == "darwin":
        base = Path.home() / "Library" / "Caches" / "org.R-project.R" / "R" / "openalexVectorComp"
    elif sys.platform.startswith("linux"):
        xdg = os.environ.get("XDG_CACHE_HOME")
        base = Path(xdg).expanduser() if xdg else Path.home() / ".cache"
        base = base / "R" / "openalexVectorComp"
    else:
        base = Path.home() / "AppData" / "Local" / "R" / "cache" / "R" / "openalexVectorComp"
    return base / DEFAULT_SUBDIR


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out-dir",
        default=None,
        help="Destination for the merged model. Defaults to a per-user cache path.",
    )
    args = parser.parse_args()

    out_dir = Path(args.out_dir).expanduser() if args.out_dir else default_out_dir()
    out_dir.mkdir(parents=True, exist_ok=True)

    try:
        from transformers import AutoTokenizer
        from adapters import AutoAdapterModel
    except ImportError as e:
        print(
            "Missing Python dependency. Install with:\n"
            "    pip install transformers adapters torch\n"
            f"Original error: {e}",
            file=sys.stderr,
        )
        return 2

    base_id = "allenai/specter2_base"
    adapter_id = "allenai/specter2"
    adapter_name = "proximity"

    print(f"Loading base model: {base_id}")
    tokenizer = AutoTokenizer.from_pretrained(base_id)
    model = AutoAdapterModel.from_pretrained(base_id)

    print(f"Loading adapter: {adapter_id} ({adapter_name})")
    model.load_adapter(adapter_id, source="hf", load_as=adapter_name, set_active=True)

    print(f"Merging adapter '{adapter_name}' into base weights")
    model.merge_adapter(adapter_name)

    print(f"Saving merged model + tokenizer to: {out_dir}")
    model.save_pretrained(str(out_dir))
    tokenizer.save_pretrained(str(out_dir))

    print(str(out_dir))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
