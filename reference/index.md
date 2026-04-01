# Package index

## All functions

- [`backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/backend_config.md)
  : Build embedding backend configuration
- [`backend_embed_texts()`](https://rkrug.github.io/openalexVectorComp/reference/backend_embed_texts.md)
  : Embed texts via configured backend
- [`backend_info()`](https://rkrug.github.io/openalexVectorComp/reference/backend_info.md)
  : Get embedding backend model/service information
- [`backend_read()`](https://rkrug.github.io/openalexVectorComp/reference/backend_read.md)
  : Read backend configuration from YAML
- [`backend_save()`](https://rkrug.github.io/openalexVectorComp/reference/backend_save.md)
  : Save backend configuration to YAML
- [`batch_collect_openai()`](https://rkrug.github.io/openalexVectorComp/reference/batch_collect_openai.md)
  : Collect completed OpenAI batch embedding jobs
- [`batch_status_openai()`](https://rkrug.github.io/openalexVectorComp/reference/batch_status_openai.md)
  : Inspect OpenAI batch state for a label
- [`batch_submit_openai()`](https://rkrug.github.io/openalexVectorComp/reference/batch_submit_openai.md)
  : Submit OpenAI Batch jobs for corpus embeddings (asynchronous)
- [`calibrate_threshold()`](https://rkrug.github.io/openalexVectorComp/reference/calibrate_threshold.md)
  : Calibrate threshold from Parquet scores by streaming batches
- [`clean_abstract_for_embedding()`](https://rkrug.github.io/openalexVectorComp/reference/clean_abstract_for_embedding.md)
  : Clean title/abstract rows into embedding-ready text
- [`demo_finalize_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/demo_finalize_openai_batch.md)
  : Finalize OpenAI demo batch jobs and compare direct vs batch
  embeddings
- [`distance_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/distance_cosine.md)
  : Cosine distance between two numeric vectors
- [`distance_reference_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/distance_reference_cosine.md)
  : Pairwise cosine distances with centroid axis between label
  partitions
- [`distance_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/distance_ridge.md)
  : Compute corpus distance to a reference embedding area
- [`distances()`](https://rkrug.github.io/openalexVectorComp/reference/distances.md)
  : Join prototype and ridge distances lazily via Arrow
- [`embed_corpus()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus.md)
  : Stream a corpus dataset, embed in batches, and write Parquets
- [`embed_texts()`](https://rkrug.github.io/openalexVectorComp/reference/embed_texts.md)
  : Embed texts through a configured backend
- [`fit_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/fit_ridge.md)
  : Fit a reference-area model from embeddings parquet
- [`plot_embeddings_pca()`](https://rkrug.github.io/openalexVectorComp/reference/plot_embeddings_pca.md)
  : Plot embeddings via PCA, colored by arbitrary labels
- [`plot_embeddings_umap()`](https://rkrug.github.io/openalexVectorComp/reference/plot_embeddings_umap.md)
  : Plot embeddings via UMAP, colored by arbitrary labels
- [`run_demo_openai()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openai.md)
  : Create and optionally run an OpenAI-based demo project via Quarto
- [`run_demo_openalex()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openalex.md)
  : Create and optionally run a self-contained demo project via Quarto
- [`score_reference_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/score_reference_cosine.md)
  : Convert reference-cosine distances to scores
- [`score_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/score_ridge.md)
  : Convert ridge distances to ridge scores
- [`similarity_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/similarity_cosine.md)
  : Cosine similarity between two numeric vectors
