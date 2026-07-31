test_that("run_ar returns the fit and only saves when asked", {
  dat <- make_synth_dat()

  fit <- run_ar(flows = dat$flows, stocks = dat$stocks, target = "gdp",
                date = 2023.5, dataset_used = "synth")
  expect_named(fit, c("nowcast", "nowcast_var"))
  expect_length(fit$nowcast, 1)
  expect_gt(as.numeric(fit$nowcast_var), 0)

  # nothing was written anywhere without output_dir
  expect_false(dir.exists("fits"))

  out_dir <- tempfile(); on.exit(unlink(out_dir, recursive = TRUE))
  run_ar(flows = dat$flows, stocks = dat$stocks, target = "gdp",
         date = 2023.5, dataset_used = "synth", output_dir = out_dir)
  expect_true(file.exists(file.path(out_dir, "synth", "fit_2023.5.Rda")))
})

test_that("run_fcast returns the fit, windows it, and only saves when asked", {

  # the parity rule: run_fcast() must behave like run_wai_adj()/run_ar() at the
  # driver level, since the backcasting loop drives them interchangeably
  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  cut_at <- 2023
  set.seed(2)
  # a 12-draw chain does not converge the rotation within the default cap of 5,
  # which is exactly the case dfm_control()'s warning exists to surface (#46)
  fit <- NULL
  expect_warning(
    fit <- run_fcast(flows = flows, stocks = stocks, target = target,
                     date = cut_at, dataset_used = "synth",
                     q = 2, length_sample = 12, burn_in = 4),
    "Rotation did not converge")

  expect_s3_class(fit, "fcast_dfm")
  # windowed to the evaluation date, as run_wai_adj() does
  expect_lte(max(as.numeric(stats::time(fit$factor))), cut_at)
  expect_equal(ncol(fit$factor), 2)
  # every series' results survive the windowing
  expect_true(all(c("ncst", "data_hf") %in% names(fit)))

  # no side effects without output_dir
  expect_false(dir.exists("fits"))

  out_dir <- tempfile(); on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)
  set.seed(2)
  suppressWarnings(
    run_fcast(flows = flows, stocks = stocks, target = target,
              date = cut_at, dataset_used = "q2", q = 2,
              length_sample = 12, burn_in = 4, output_dir = out_dir))
  # same file layout as run_wai_adj(), so fit discovery works unchanged
  expect_true(file.exists(file.path(out_dir, "q2", "fit_2023.Rda")))

  # and what was written is the fit that was returned
  e <- new.env(); load(file.path(out_dir, "q2", "fit_2023.Rda"), envir = e)
  expect_s3_class(e$mod, "fcast_dfm")
  expect_identical(e$mod$factor, fit$factor)
})


test_that("retrieve_nowcast and retrieve_nowcast_var dispatch on model type", {
  fit <- list(nowcast = stats::ts(c(0.1, 0.7), start = c(2024, 1), frequency = 4),
              nowcast_var = stats::ts(c(0.02, 0.05), start = c(2024, 1), frequency = 4))
  expect_equal(as.numeric(retrieve_nowcast(fit, "wai")), 0.7)
  expect_equal(as.numeric(retrieve_nowcast_var(fit, "wai")), 0.05)
  expect_identical(retrieve_nowcast(fit, "ar"), fit$nowcast)
  expect_identical(retrieve_nowcast_var(fit, "ar"), fit$nowcast_var)
})
