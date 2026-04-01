# Package index

## All functions

- [`calibrate_threshold()`](https://rkrug.github.io/openalexVectorComp/reference/calibrate_threshold.md)
  : Calibrate threshold from Parquet scores by streaming batches
- [`clean_abstract_for_embedding()`](https://rkrug.github.io/openalexVectorComp/reference/clean_abstract_for_embedding.md)
  : Clean title/abstract rows into embedding-ready text
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
- [`embed_corpus_collect_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_collect_openai_batch.md)
  : Collect completed OpenAI batch embedding jobs
- [`embed_corpus_status_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_status_openai_batch.md)
  : Inspect OpenAI batch state for a label
- [`embed_corpus_submit_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/embed_corpus_submit_openai_batch.md)
  : Submit OpenAI Batch jobs for corpus embeddings (asynchronous)
- [`embed_texts()`](https://rkrug.github.io/openalexVectorComp/reference/embed_texts.md)
  : Embed texts through a configured backend
- [`embedding_backend_config()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_config.md)
  : Build embedding backend configuration
- [`embedding_backend_embed_texts()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_embed_texts.md)
  : Embed texts via configured backend
- [`embedding_backend_info()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_info.md)
  : Get embedding backend model/service information
- [`embedding_backend_read()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_read.md)
  : Read backend configuration from YAML
- [`embedding_backend_save()`](https://rkrug.github.io/openalexVectorComp/reference/embedding_backend_save.md)
  : Save backend configuration to YAML
- [`finalize_demo_openai_batch()`](https://rkrug.github.io/openalexVectorComp/reference/finalize_demo_openai_batch.md)
  : Finalize OpenAI demo batch jobs and compare direct vs batch
  embeddings
- [`fit_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/fit_ridge.md)
  : Fit a reference-area model from embeddings parquet
- [`plot_embeddings_pca()`](https://rkrug.github.io/openalexVectorComp/reference/plot_embeddings_pca.md)
  : Plot embeddings via PCA, colored by arbitrary labels
- [`plot_embeddings_umap()`](https://rkrug.github.io/openalexVectorComp/reference/plot_embeddings_umap.md)
  : Plot embeddings via UMAP, colored by arbitrary labels
- [`run_demo_openai_quarto()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openai_quarto.md)
  : Create and optionally run an OpenAI-based demo project via Quarto
- [`run_demo_openalex_quarto()`](https://rkrug.github.io/openalexVectorComp/reference/run_demo_openalex_quarto.md)
  : Create and optionally run a self-contained demo project via Quarto
- [`score_reference_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/score_reference_cosine.md)
  : Convert reference-cosine distances to scores
- [`score_ridge()`](https://rkrug.github.io/openalexVectorComp/reference/score_ridge.md)
  : Convert ridge distances to ridge scores
- [`similarity_cosine()`](https://rkrug.github.io/openalexVectorComp/reference/similarity_cosine.md)
  : Cosine similarity between two numeric vectors
