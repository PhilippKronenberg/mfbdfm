test_that("shipped datasets have the structure ind_dfm() expects", {
  expect_named(data_ch_dataset, c("flows", "stocks"))
  expect_named(data_ch_dataset_test, c("flows", "stocks"))
  # Only the test variant ships the GDP target; the full dataset gets it
  # injected at runtime from the real-time vintage database.
  expect_true("ch.seco.gdp.real.gdp.ssa" %in% names(data_ch_dataset_test$flows))
  expect_true(all(vapply(data_ch_dataset$flows, stats::is.ts, logical(1))))
})

test_that("mfbdfm_example_data is a ready mfbdfm_data object with the target", {
  expect_s3_class(mfbdfm_example_data, "mfbdfm_data")
  expect_named(mfbdfm_example_data, c("flows", "stocks", "meta", "target"))

  # the whole point of this dataset: the target is present and is carried on
  # the object, so an example needs no `target =` argument
  target <- "ch.seco.gdp.real.gdp.ssa"
  expect_identical(mfbdfm_example_data$target, target)
  expect_true(target %in% names(mfbdfm_example_data$flows))

  series <- c(mfbdfm_example_data$flows, mfbdfm_example_data$stocks)
  expect_length(series, 8L)
  expect_true(all(vapply(series, stats::is.ts, logical(1))))

  # all three modelled frequencies and both aggregation types are represented,
  # which is what makes it exercise the temporal aggregation at all
  expect_setequal(mfbdfm_example_data$meta$frequency, c(4L, 12L, 48L))
  expect_setequal(mfbdfm_example_data$meta$type, c("flow", "stock"))
  expect_identical(nrow(mfbdfm_example_data$meta), 8L)

  # only the ragged edge is missing: no interior gaps
  expect_false(any(vapply(series, function(x) anyNA(x), logical(1))))
})

test_that("real-time GDP vintage database ships with the package", {
  gdp_path <- system.file("extdata", "realtime_gdp.csv", package = "mfbdfm")
  gdp_cssa_path <- system.file("extdata", "realtime_gdp_cssa.csv", package = "mfbdfm")
  expect_true(nzchar(gdp_path))
  expect_true(file.exists(gdp_path))
  expect_true(nzchar(gdp_cssa_path))
  expect_true(file.exists(gdp_cssa_path))
})
