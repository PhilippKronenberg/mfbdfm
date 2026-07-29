# Smoke and structure tests for the multi-factor model. Kept small: a short
# chain on a reduced dataset - structure and reproducibility, not values
# (see test-ind_dfm.R for the same rationale).
#
# Note fcast_dfm() is NOT expected to agree with ind_dfm() at q = 1: the two
# models differ in identification and priors (see ?fcast_dfm Details).

run_small_fcast <- function(seed, q = 2) {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI", "FINANSW")],
                  stats::window, start = 2019)
  stocks <- lapply(data_ch_dataset_test$stocks[c("SWCONPRCE", "VIX")],
                   stats::window, start = 2019)

  set.seed(seed)
  suppressMessages(suppressWarnings(
    fcast_dfm(flows = flows, stocks = stocks, target = target,
              q = q, p = 1, length_sample = 8, burn_in = 4, thinning = 1,
              plots = FALSE)
  ))
}

test_that("fcast_dfm returns a complete, finite fit object", {
  fit <- run_small_fcast(42)

  expect_s3_class(fit, "fcast_dfm")
  expect_true(all(c("factor", "factor_var", "target", "nowcast", "nowcast_var",
                    "pars", "ncst", "data_hf", "data_augmented",
                    "inventory") %in% names(fit)))

  # q factors, one column each
  expect_equal(ncol(fit$factor), 2)
  expect_equal(ncol(fit$factor_var), 2)
  expect_equal(dim(fit$pars$lambda), c(nrow(fit$inventory), 2))

  expect_false(anyNA(fit$factor))
  expect_true(all(is.finite(fit$factor)))
  expect_true(all(fit$factor_var >= 0))

  # the target's nowcast is surfaced at the top level, at its own frequency
  expect_equal(fit$target, "ch.seco.gdp.real.gdp.ssa")
  expect_equal(frequency(fit$nowcast), 4)
  expect_true(all(is.finite(fit$nowcast)))

  # per-series output covers every input series
  expect_equal(length(fit$ncst$mean), nrow(fit$inventory))
  expect_equal(length(fit$data_hf$mean), nrow(fit$inventory))
  expect_true(fit$target %in% names(fit$ncst$mean))
})

test_that("fcast_dfm is deterministic given a seed", {
  # $call records the matched call, which differs between the two invocations
  # only via the enclosing frame; compare everything else.
  a <- run_small_fcast(7); b <- run_small_fcast(7)
  a$call <- NULL; b$call <- NULL
  expect_identical(a, b)
})

test_that("target_series collects the target's results for inspection", {
  fit <- run_small_fcast(5)
  ts_target <- fit$target_series

  expect_equal(ts_target$name, fit$target)
  expect_named(ts_target$nowcast, c("time", "observed", "mean", "lower", "upper"))
  expect_named(ts_target$high_frequency, c("time", "mean", "lower", "upper"))

  # bands must bracket the mean
  expect_true(all(ts_target$nowcast$lower <= ts_target$nowcast$mean))
  expect_true(all(ts_target$nowcast$mean <= ts_target$nowcast$upper))
  expect_true(all(ts_target$high_frequency$lower <= ts_target$high_frequency$mean))

  # observed values are aligned, and at least some are present
  expect_true(sum(!is.na(ts_target$nowcast$observed)) > 0)
  expect_true(all(is.finite(ts_target$nowcast$mean)))
})

test_that("print.fcast_dfm is registered and returns invisibly", {
  fit <- run_small_fcast(5)

  # dispatch actually happens (not default list printing)
  expect_output(print(fit), "Multi-factor mixed-frequency dynamic factor model")
  expect_output(print(fit), fit$target)
  expect_output(print(fit), "Most recent nowcasts")

  expect_false(withVisible(print(fit))$visible)
  expect_identical(suppressWarnings(capture.output(res <- print(fit))) , capture.output(print(fit)))
  expect_s3_class(res, "fcast_dfm")
})

test_that("fcast_dfm runs with a single factor", {
  fit <- run_small_fcast(3, q = 1)
  expect_s3_class(fit, "fcast_dfm")
  expect_equal(ncol(as.matrix(fit$factor)), 1)
})

test_that("fcast_dfm validates its inputs", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2020)

  expect_error(fcast_dfm(flows = NULL, stocks = NULL, target = target),
               "At least one of")
  expect_error(fcast_dfm(flows = flows, stocks = NULL, target = "not_a_series"),
               "not among the supplied series")
  expect_error(fcast_dfm(flows = flows, stocks = NULL, target = target, q = 99),
               "must be smaller than the number of input series")
})

test_that("create_inventory accepts flows-only and stocks-only input", {
  data(data_ch_dataset_test, envir = environment())
  flows <- data_ch_dataset_test$flows[1:3]
  stocks <- data_ch_dataset_test$stocks[1:2]

  expect_equal(nrow(create_inventory(flows, NULL)), 3)
  expect_equal(nrow(create_inventory(NULL, stocks)), 2)
  expect_equal(nrow(create_inventory(flows, stocks)), 5)
  expect_true(all(create_inventory(flows, NULL)$type == "flow"))
  expect_true(all(create_inventory(NULL, stocks)$type == "stock"))
})
