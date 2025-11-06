# Example script for command line usage
# Rscript inst/examples/run_autotag_example.R

library(autotagr)
library(tibble)

df_labeled <- tibble(
  id = c("A1","A2","A3","A4"),
  text = c(
    "Biodiversity loss impacts ecosystem services and human wellbeing.",
    "Ecosystem restoration supports biodiversity targets and NBSAPs.",
    "Quantum computing for lattice models (unrelated).",
    "High-energy physics experiment on collider data."
  ),
  label = c(1,1,0,0)
)

df_unlabeled <- tibble(
  id = c("U1","U2","U3"),
  text = c(
    "Nature-based solutions help climate adaptation and biodiversity.",
    "Particle physics advances in hadron collisions.",
    "Spatial planning for protected areas and OECMs."
  )
)

res <- run_autotag(df_labeled, df_unlabeled, tei_url = "http://localhost:8080/embed")
print(res$threshold)
print(head(res$scores))
cat("Wrote:", res$parquet, "\n")
