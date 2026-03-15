testthat::test_that("clean_abstract_for_embedding returns required columns and stable hash", {
  df <- data.frame(
    id = c("W1", "W2"),
    title = c("Biodiversity patterns", "Ocean systems"),
    abstract = c(
      "Biodiversity patterns across ecosystems are studied extensively.",
      "Ocean systems show strong climate sensitivity."
    ),
    stringsAsFactors = FALSE
  )
  out1 <- clean_abstract_for_embedding(df)
  out2 <- clean_abstract_for_embedding(df)

  testthat::expect_true(all(c("id", "text", "text_hash") %in% names(out1)))
  testthat::expect_true(all(c("text_quality", "abstract_raw_present", "abstract_kept", "discard_reason", "cleaning_mode") %in% names(out1)))
  testthat::expect_equal(out1$text_hash, out2$text_hash)
})

testthat::test_that("clean_abstract_for_embedding handles missing abstracts by policy", {
  df <- data.frame(
    id = c("W1", "W2"),
    title = c("A meaningful title", "Another meaningful title"),
    abstract = c(NA_character_, "No abstract available"),
    stringsAsFactors = FALSE
  )
  keep <- clean_abstract_for_embedding(df, no_abstract_policy = "keep_title_only")
  testthat::expect_equal(nrow(keep), 2L)
  testthat::expect_true(all(grepl("^Title: ", keep$text)))

  drop <- clean_abstract_for_embedding(df, no_abstract_policy = "discard")
  testthat::expect_equal(nrow(drop), 0L)
})

testthat::test_that("clean_abstract_for_embedding removes duplicated title prefix", {
  df <- data.frame(
    id = "W1",
    title = "Biodiversity loss and resilience",
    abstract = "Biodiversity loss and resilience are major global concerns in ecology.",
    stringsAsFactors = FALSE
  )
  out <- clean_abstract_for_embedding(df, mode = "lenient")
  testthat::expect_equal(nrow(out), 1L)
  testthat::expect_false(grepl("Abstract: Biodiversity loss and resilience are", out$text, fixed = TRUE))
})

testthat::test_that("clean_abstract_for_embedding detects placeholder and boilerplate", {
  df <- data.frame(
    id = c("W1", "W2"),
    title = c("A valid title text", "Another valid title text"),
    abstract = c("No abstract available", "Copyright Elsevier all rights reserved"),
    stringsAsFactors = FALSE
  )
  out <- clean_abstract_for_embedding(
    df,
    no_abstract_policy = "keep_title_only",
    mode = "balanced"
  )
  testthat::expect_equal(nrow(out), 2L)
  testthat::expect_true(all(out$text_quality == "title_only"))
})

testthat::test_that("clean_abstract_for_embedding mode thresholds differ", {
  txt <- paste(rep("token", 12), collapse = " ") # short abstract
  df <- data.frame(
    id = "W1",
    title = "A meaningful title",
    abstract = txt,
    stringsAsFactors = FALSE
  )
  lenient <- clean_abstract_for_embedding(df, mode = "lenient", no_abstract_policy = "discard")
  strict <- clean_abstract_for_embedding(df, mode = "strict", no_abstract_policy = "discard")
  testthat::expect_gte(nrow(lenient), nrow(strict))
})
