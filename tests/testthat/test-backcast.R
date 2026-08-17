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
  # Warnings are tolerated rather than asserted: whether a 12-draw chain
  # converges the rotation within the default cap depends on the sample length,
  # which `extend` changes. That is incidental to what run_fcast() does, and an
  # earlier version of this test broke when the extend default was added.
  fit <- suppressWarnings(
    run_fcast(flows = flows, stocks = stocks, target = target,
              date = cut_at, dataset_used = "synth",
              q = 2, length_sample = 12, burn_in = 4))

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


test_that("run_fcast extends past the data, or it cannot nowcast at all", {

  # The bug this pins: at a real-time evaluation date the target's last
  # observation is a quarter or two old, so the quarter actually being nowcast
  # lies beyond the data. Without extending, fcast_dfm() only produces values
  # over the observed span and every row is an in-sample fit - measured, the
  # evaluation panel came out with zero out-of-sample rows.
  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  last_obs <- max(as.numeric(stats::time(flows[[target]])))

  set.seed(4)
  extended <- suppressWarnings(
    run_fcast(flows = flows, stocks = stocks, target = target,
              date = last_obs, dataset_used = "x", q = 2,
              length_sample = 10, burn_in = 3))

  set.seed(4)
  not_extended <- suppressWarnings(
    run_fcast(flows = flows, stocks = stocks, target = target,
              date = last_obs, dataset_used = "x", q = 2,
              length_sample = 10, burn_in = 3, extend = NULL))

  # the default reaches past the target's last observation; extend = NULL does not
  expect_gt(max(as.numeric(stats::time(extended$nowcast))), last_obs)
  expect_lte(max(as.numeric(stats::time(not_extended$nowcast))), last_obs)
})


test_that("run_wai_adj does not warn about a no-op window", {

  # Parity with run_fcast(): the evaluation date is usually past the series end,
  # where window() emits "'end' value not changed" four times per call. trim_to()
  # skips the no-op. A wrapper that warns on ordinary use trains people to ignore
  # its warnings.
  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  # Short chain deliberately: what is being tested is whether trim_to() warns,
  # which has nothing to do with chain length. This used to take the 5000-draw
  # default because run_wai_adj() hard-coded it, and that one call was 143s of the
  # suite's 179s - 80% of the runtime for an assertion about a warning. win-builder
  # spent 404s in 'checking tests' largely on this.
  set.seed(6)
  expect_no_warning(
    fit <- run_wai_adj(flows = flows, stocks = stocks, target = target,
                       date = 2030, dataset_used = "x",   # well past the data
                       length_sample = 10, burn_in = 4)
  )
  expect_s3_class(fit, "ind_dfm")
})


test_that("run_wai_adj passes p and serial_correlation through (#48)", {

  # An argument a wrapper accepts and ignores is a bug, not a documentation
  # problem (#48). run_wai_adj() hard-coded p = 1 and serial_correlation = TRUE
  # while run_fcast() exposed both, and its own docs claimed
  # stochastic_volatility reached ind_dfm() "without effect there" - which was
  # false. These assertions fail if any of the three stops being forwarded.
  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  run <- function(...) {
    set.seed(9)
    suppressMessages(run_wai_adj(flows = flows, stocks = stocks, target = target,
                                 date = 2023, dataset_used = "x",
                                 length_sample = 10, burn_in = 4, ...))
  }

  # p reaches the state equation: one autoregressive coefficient per lag
  expect_length(as.numeric(run(p = 1)$pars$phi), 1)
  expect_length(as.numeric(run(p = 2)$pars$phi), 2)

  # serial_correlation reaches the measurement errors
  expect_lt(max(abs(as.numeric(run(serial_correlation = FALSE)$pars$rho))), 1e-6)
  expect_gt(max(abs(as.numeric(run()$pars$rho))), 1e-6)

  # stochastic_volatility too - off gives a single constant, not a path
  expect_equal(length(unique(as.numeric(run(stochastic_volatility = FALSE)$pars$h))), 1)
})


test_that("trim_to keeps the observation a rounded date names", {

  # Evaluation dates travel through this workflow rounded to three decimals,
  # while the series' grid points are not. At frequency 48 the last week of 2021
  # is 2021.979167, which rounds DOWN to 2021.979, so the exact comparison this
  # replaced dropped the observation the date names - silently, since trim_to()
  # exists precisely so that it does not warn. Fits came out 1557 periods long
  # against the paper's 1558.
  x <- stats::ts(1:5, start = 2021 + 43/48, frequency = 48)
  last_week <- 2021 + 47/48

  expect_length(trim_to(x, round(last_week, 3)), 5L)
  expect_length(trim_to(x, last_week), 5L)

  # the tolerance pulls a rounded date back onto the point it names, and must
  # never reach the next one
  expect_length(trim_to(x, round(2021 + 46/48, 3)), 4L)
  expect_length(trim_to(x, 2021 + 45/48), 3L)

  # and it still trims when there is genuinely something to trim
  expect_equal(max(as.numeric(stats::time(trim_to(x, 2021 + 44/48)))),
               2021 + 44/48)
})


test_that("retrieve_nowcast and retrieve_nowcast_var dispatch on model type", {
  fit <- list(nowcast = stats::ts(c(0.1, 0.7), start = c(2024, 1), frequency = 4),
              nowcast_var = stats::ts(c(0.02, 0.05), start = c(2024, 1), frequency = 4))
  expect_equal(as.numeric(retrieve_nowcast(fit, "wai")), 0.7)
  expect_equal(as.numeric(retrieve_nowcast_var(fit, "wai")), 0.05)
  expect_identical(retrieve_nowcast(fit, "ar"), fit$nowcast)
  expect_identical(retrieve_nowcast_var(fit, "ar"), fit$nowcast_var)
})
