# Notes

Scratchpad for ideas and follow-ups that are not yet decisions. Excluded
from the built package via `.Rbuildignore`.

## Publishing the merged SPECTER2 model to HuggingFace Hub

Currently, users must run `inst/scripts/prepare_specter2_merged.py`
themselves to produce the merged `specter2_base` + proximity-adapter
model directory that TEI can serve. This requires a Python environment
with `transformers` + `adapters`, ~500 MB on disk, and a few minutes of
compute.

If SPECTER2 becomes a first-class supported backend, the cleaner path is
to publish the merged model to HuggingFace Hub once and let users pull
it directly.

### Why not bundle the weights in the package

- CRAN size limit is 5 MB; merged model is ~500 MB. Hard no.
- Off-CRAN bundling still bloats git history, slows `install_local()`,
  and couples model release cadence to code release cadence. R packages
  are source code, not weight stores.

### Proposed workflow

1.  Run the merge once locally.

2.  Publish:

    ``` bash
    huggingface-cli login
    huggingface-cli upload <org>/specter2_proximity_merged \
      ~/Library/Caches/org.R-project.R/R/openalexVectorComp/specter2_proximity_merged
    ```

3.  Users skip the merge entirely:

    ``` bash
    text-embeddings-router --model-id <org>/specter2_proximity_merged --port 8080
    ```

4.  `inst/scripts/prepare_specter2_merged.py` stays as a reproducibility
    artifact (how we built it) but is no longer required for setup.

5.  `inst/scripts/start_tei_specter2.sh` defaults `--model-id` to the
    published repo when no local merged model is found.

6.  [`backend_specter2_tei()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_specter2_tei.md)
    default `model` arg updates to the published id.

7.  Vignette `specter2-setup.qmd` collapses to: install TEI, run one
    command, use from R.

### Open questions

- Which HF org/account hosts the published model? Personal vs project
  org.
- License compatibility — SPECTER2 base + adapter licenses (verify
  Apache-2.0 on both before redistributing the merged weights).
- Versioning: tag the HF repo on each re-merge; pin the tag in
  [`backend_specter2_tei()`](https://openalexpro.github.io/openalexVectorComp/reference/backend_specter2_tei.md)
  for reproducibility.

### Middle-ground alternative

If publishing to HF Hub is undesirable, host the merged tarball on
GitHub Releases (2 GB per-asset limit) or S3, and have an R function
lazy-download into `tools::R_user_dir("openalexVectorComp", "cache")` on
first use. Packages like `piggyback` automate the GitHub Releases case.
Keeps weights out of the package source either way.
