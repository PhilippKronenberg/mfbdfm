test_that("shipped datasets have the structure ind_dfm() expects", {
  expect_named(data_ch_dataset, c("flows", "stocks"))
  expect_named(data_ch_dataset_test, c("flows", "stocks"))
  # Only the test variant ships the GDP target; the full dataset gets it
  # injected at runtime from the real-time vintage database.
  expect_true("ch.seco.gdp.real.gdp.ssa" %in% names(data_ch_dataset_test$flows))
  expect_true(all(vapply(data_ch_dataset$flows, stats::is.ts, logical(1))))
})

test_that("real-time GDP vintage database ships with the package", {
  gdp_path <- system.file("extdata", "realtime_gdp.csv", package = "mfbdfm")
  gdp_cssa_path <- system.file("extdata", "realtime_gdp_cssa.csv", package = "mfbdfm")
  expect_true(nzchar(gdp_path))
  expect_true(file.exists(gdp_path))
  expect_true(nzchar(gdp_cssa_path))
  expect_true(file.exists(gdp_cssa_path))
})
