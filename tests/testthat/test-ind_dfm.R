# Smoke and determinism tests for the MCMC engine. Kept small: a short
# chain on a reduced dataset — structure and reproducibility, not values.

run_small_ind_dfm <- function(seed) {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI", "trendecon_wai")],
                  function(x) if (is.null(x)) NULL else stats::window(x, start = 2019))
  flows <- Filter(Negate(is.null), flows)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2019)

  set.seed(seed)
  suppressMessages(
    ind_dfm(flows = flows, stocks = stocks, target = target,
          length_sample = 30, burn_in = 5, thinning = 1, plots = FALSE)
  )
}

test_that("ind_dfm returns a complete, finite fit object", {
  fit <- run_small_ind_dfm(42)

  expect_s3_class(fit, "ind_dfm")
  expect_named(fit, c("factor", "factor_var", "factor_std", "index", "nowcast",
                      "nowcast_var", "target", "pars", "pars_dist", "data",
                      "data_raw",
                      "data_augmented", "inventory", "draws", "call"))
  expect_s3_class(fit$factor, "ts")
  expect_equal(frequency(fit$factor), 48)
  expect_equal(frequency(fit$nowcast), 4)
  expect_false(anyNA(fit$factor))
  expect_false(anyNA(fit$nowcast))
  expect_true(all(fit$factor_var >= 0))
  expect_true(all(fit$nowcast_var >= 0))
  expect_equal(fit$target, "ch.seco.gdp.real.gdp.ssa")
  # identifying restriction: target loading fixed at 1
  expect_equal(as.numeric(fit$pars$lambda[fit$inventory$key == fit$target]), 1)
})

test_that("factor_std spans the sample plus the aggregation's latent periods", {
  fit <- run_small_ind_dfm(42)

  k <- max(fit$inventory$freq)/min(fit$inventory$freq)
  s <- 2*(k - 1)

  expect_s3_class(fit$factor_std, "ts")
  expect_length(fit$factor_std, nrow(fit$data) + s)
  expect_false(anyNA(fit$factor_std))

  # it leads $data by exactly the s latent periods, on the same frequency -
  # this alignment is what the common-component reconstruction in summary()
  # depends on
  expect_equal(frequency(fit$factor_std), frequency(fit$data))
  expect_equal(as.numeric(stats::time(fit$factor_std))[s + 1],
               as.numeric(stats::time(fit$data))[1])
})

test_that("pars$h is complete and aligned with the factor (#49)", {
  fit <- run_small_ind_dfm(11)

  # h spans the same t in-sample periods as the factor: no trailing NA from
  # slicing one past the end of h, and the same length as the factor
  expect_false(anyNA(fit$pars$h))
  expect_equal(length(fit$pars$h), length(fit$factor))

  # and it carries the factor's time index, not just its length (#67). This is
  # the parity half: fcast_dfm() has always returned a ts here, ind_dfm() a bare
  # numeric, so the same quantity had a date axis from one entry point and an
  # integer index from the other. Length alone cannot catch that - which is why
  # the assertions above passed while windowing h by calendar year matched
  # nothing at all, silently.
  expect_true(stats::is.ts(fit$pars$h))
  expect_equal(as.numeric(stats::time(fit$pars$h)),
               as.numeric(stats::time(fit$factor)))
  expect_gt(length(stats::window(fit$pars$h,
                                 start = stats::time(fit$factor)[2])), 0)

  # positional [ still drops to a plain numeric, which
  # analysis/5_plots/analytics_data.R depends on
  expect_type(fit$pars$h[1:3], "double")
  expect_false(stats::is.ts(fit$pars$h[1:3]))
})

test_that("stochastic_volatility = FALSE gives a constant but estimated variance", {
  run <- function(seed) {
    data(data_ch_dataset_test, envir = environment())
    target <- "ch.seco.gdp.real.gdp.ssa"
    flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                    stats::window, start = 2020)
    stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2020)
    set.seed(seed)
    suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                             length_sample = 10, burn_in = 4, plots = FALSE,
                             stochastic_volatility = FALSE))
  }

  fit <- run(1)
  h <- fit$pars$h[!is.na(fit$pars$h)]

  # constant over time - not a volatility path
  expect_equal(length(unique(h)), 1)
  expect_true(is.finite(h[1]))
  # ... and a positive variance
  expect_gt(exp(2 * h[1]), 0)

  # estimated, not fixed: a different seed gives a different value
  h2 <- run(2)$pars$h[1]
  expect_false(isTRUE(all.equal(h[1], as.numeric(h2))))
})

test_that("serial_correlation = FALSE holds the autocorrelations at zero", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2020)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2020)

  set.seed(3)
  off <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                  length_sample = 10, burn_in = 4, plots = FALSE,
                                  serial_correlation = FALSE))
  set.seed(3)
  on <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                 length_sample = 10, burn_in = 4, plots = FALSE))

  expect_lt(max(abs(off$pars$rho)), 1e-6)
  # the default really does estimate them, so the flag is doing something
  expect_gt(max(abs(on$pars$rho)), 1e-6)
  expect_false(identical(off$factor, on$factor))
})

test_that("ind_dfm is deterministic given a seed", {
  fit1 <- run_small_ind_dfm(7)
  fit2 <- run_small_ind_dfm(7)
  expect_identical(fit1, fit2)
})

test_that("ind_dfm(plots = TRUE) restores the caller's graphics state", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")], stats::window, start = 2019)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2019)

  grDevices::pdf(NULL) # avoid popping up a window/writing Rplots.pdf
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mfrow = c(2, 3))
  before <- graphics::par(no.readonly = TRUE)

  set.seed(1)
  suppressMessages(
    ind_dfm(flows = flows, stocks = stocks, target = target,
          length_sample = 5, burn_in = 2, thinning = 1, plots = TRUE)
  )

  expect_identical(graphics::par("mfrow"), before$mfrow)
})

# NOTE: there is deliberately no fit-level test tying $index to $factor. Both are
# posterior MEANS over draws, and the mean of a nonlinear transform is not the
# transform of the mean, so the per-draw identity between them does not survive
# averaging - a first attempt at such a test failed for exactly that reason, not
# because the code was wrong. The identical arithmetic is covered on the exported
# path by test-backcast.R's "the level index compounds the net growth rate, not
# exp() of it". Adding `index` to dev/baseline.R's snapshot would give this
# component proper regression cover (#92).


test_that("ind_dfm is quiet under verbose = FALSE, messages under TRUE (BS2.13)", {

  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  fit_quiet <- function(verbose){
    set.seed(3)
    ind_dfm(flows = flows, stocks = stocks, target = target,
            length_sample = 8, burn_in = 4, plots = FALSE,
            control = dfm_control("ind_dfm", verbose = verbose))
  }

  # Both channels, because they are silenced by different mechanisms: the
  # message() calls go to stderr, the txtProgressBar writes with cat() and so
  # survives suppressMessages() entirely - which was the gap in #118.
  printed <- utils::capture.output(expect_no_message(fit <- fit_quiet(FALSE)))
  expect_identical(printed, character(0))
  expect_s3_class(fit, "ind_dfm")

  # the default is still verbose, on both channels
  printed_on <- utils::capture.output(expect_message(fit_quiet(TRUE)))
  expect_true(any(nzchar(printed_on)))
})


test_that("the rho stationarity fallback warns once per fit, with a class", {

  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  # A screen this tight rejects essentially every draw, so the fallback is
  # guaranteed to fire. Forcing it is the only reliable way to reach the branch
  # on a short, well-behaved fit.
  run <- function(){
    set.seed(3)
    ind_dfm(flows = flows, stocks = stocks, target = target,
            length_sample = 6, burn_in = 2, plots = FALSE,
            control = dfm_control("ind_dfm", verbose = FALSE,
                                  rho_max = 1e-6, rho_fallback = 1e-7))
  }

  w <- expect_warning(run(), class = "mfbdfm_warning_rho_fallback")
  # one warning for the whole chain, not one per series per draw
  expect_match(conditionMessage(w), "stationarity screen")

  expect_silent(withCallingHandlers(
    run(),
    mfbdfm_warning_rho_fallback = function(w) invokeRestart("muffleWarning")))
})
