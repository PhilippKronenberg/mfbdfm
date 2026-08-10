test_that("mfbdfm_example_inputs returns the shape the table builders require", {

  inputs <- mfbdfm_example_inputs()

  # the union of what get_insample_fit_table(), get_combined_cor_table() and
  # get_insample_error_details() validate against for analysis_set = "indicators"
  expect_named(inputs,
               c("tab_wai_yoy", "wwa_gr_df", "wwa_gr_df_qoq", "fcurve_gr_df",
                 "tab_kss", "tab_snb", "tab_baro", "tab_gr", "tab_gr_lv",
                 "x_hist_gr_yoy", "x_hist_gr_ann"))

  weekly <- setdiff(names(inputs), c("x_hist_gr_yoy", "x_hist_gr_ann"))
  for (nm in weekly) {
    expect_s3_class(inputs[[nm]], "data.frame")
    expect_true(all(c("time", "value") %in% names(inputs[[nm]])), info = nm)
    expect_s3_class(inputs[[nm]]$time, "Date")
  }

  # the two realised-GDP stand-ins are quarterly ts
  for (nm in c("x_hist_gr_yoy", "x_hist_gr_ann")) {
    expect_true(stats::is.ts(inputs[[nm]]), info = nm)
    expect_equal(stats::frequency(inputs[[nm]]), 4)
  }
})


test_that("mfbdfm_example_inputs is reproducible, and seed = NULL is not", {

  expect_identical(mfbdfm_example_inputs(), mfbdfm_example_inputs())
  expect_identical(mfbdfm_example_inputs(7), mfbdfm_example_inputs(7))
  expect_false(isTRUE(all.equal(mfbdfm_example_inputs(1),
                                mfbdfm_example_inputs(2))))

  # seed = NULL draws from the current RNG state, so two calls differ
  set.seed(1)
  a <- mfbdfm_example_inputs(NULL)
  b <- mfbdfm_example_inputs(NULL)
  expect_false(isTRUE(all.equal(a, b)))

  expect_error(mfbdfm_example_inputs("99"), "`seed` must be")
})


test_that("the bundle actually drives the analytics builders", {

  # The point of exporting it: the reference examples run on this, so if the
  # required input shape changes, both the examples and this test fail together.
  inputs <- mfbdfm_example_inputs()

  fit_tabs <- suppressMessages(
    get_insample_fit_table("mean", "indicators", inputs = inputs))
  expect_named(fit_tabs, c("RMSE", "MAE", "R2", "PVAL_RMSE", "PVAL_MAE"))

  cor_tab <- suppressMessages(
    get_combined_cor_table("mean", "indicators", inputs = inputs))
  expect_gt(nrow(cor_tab), 0)

  details <- suppressMessages(
    get_insample_error_details("mean", "indicators", inputs = inputs))
  expect_true(all(c("Series", "observation_date", "error") %in% names(details)))
})


test_that("the test helper and the exported fixture are the same thing", {
  # make_synth_inputs() delegates, so the tests and the documentation cannot
  # drift onto different fixtures
  expect_identical(make_synth_inputs(), mfbdfm_example_inputs())
  expect_identical(make_synth_inputs(42), mfbdfm_example_inputs(42))
})
