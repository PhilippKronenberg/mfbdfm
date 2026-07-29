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
  expect_named(fit, c("factor", "factor_var", "index", "nowcast", "nowcast_var",
                      "target", "pars", "data", "data_augmented", "inventory"))
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
