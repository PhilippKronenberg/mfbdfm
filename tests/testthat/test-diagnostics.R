# mfbdfm_diagnostics() in R/diagnostics.R.
#
# Two chain lengths are needed here, not one. The statistics only mean anything
# over a chain long enough for geweke.diag()'s windows to exist, so one fit runs
# at 40 draws; the "too few draws" path is a reported outcome of its own and is
# checked on a short one.

diagnostics_fit <- local({

  cache <- NULL

  function() {
    if (is.null(cache)) {
      data(data_ch_dataset_test, envir = environment())
      target <- "ch.seco.gdp.real.gdp.ssa"
      flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                      stats::window, start = 2021)
      stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                       stats::window, start = 2021)
      set.seed(21)
      cache <<- suppressMessages(
        ind_dfm(flows = flows, stocks = stocks, target = target,
                length_sample = 40, burn_in = 10, plots = FALSE))
    }
    cache
  }

})


test_that("diagnostics return one row per parameter, with the expected columns", {
  fit <- diagnostics_fit()
  d <- mfbdfm_diagnostics(fit)

  expect_s3_class(d, "mfbdfm_diagnostics")
  expect_s3_class(d, "data.frame")
  expect_equal(nrow(d), ncol(fit$draws$parameters))
  expect_equal(names(d),
               c("parameter", "block", "mean", "sd", "ess", "geweke_z",
                 "geweke_p", "ok", "note"))
  expect_equal(d$parameter, colnames(fit$draws$parameters))

  # the reported mean/sd are the chain's own
  m <- fit$draws$parameters
  expect_equal(d$mean, unname(colMeans(m)), tolerance = 1e-12)
  expect_equal(d$sd, unname(apply(m, 2, stats::sd)), tolerance = 1e-12)

  # and they agree with the fit's stored posterior means, which is the point
  lam <- d[d$block == "lambda", ]
  expect_equal(lam$mean, as.numeric(fit$pars$lambda), tolerance = 1e-12)
})


test_that("the statistics match coda computed directly", {
  fit <- diagnostics_fit()
  d <- mfbdfm_diagnostics(fit)

  nm <- "phi1"
  v <- fit$draws$parameters[, nm]
  ch <- coda::mcmc(v)

  row <- d[d$parameter == nm, ]
  expect_equal(row$ess, unname(coda::effectiveSize(ch)), tolerance = 1e-10)
  expect_equal(row$geweke_z, unname(coda::geweke.diag(ch)$z), tolerance = 1e-10)
  expect_equal(row$geweke_p, 2 * stats::pnorm(-abs(row$geweke_z)),
               tolerance = 1e-12)
})


test_that("a parameter pinned by the identification is constant, not failed", {
  fit <- diagnostics_fit()
  d <- mfbdfm_diagnostics(fit)

  # lambda[target] is fixed at 1 by ind_dfm()'s identifying restriction, so no
  # convergence statistic is defined for it. Reporting it as a failure would be
  # a wrong answer.
  row <- d[d$parameter == paste0("lambda[", fit$target, "]"), ]
  expect_equal(nrow(row), 1L)
  expect_equal(row$sd, 0)
  expect_equal(row$note, "constant")
  expect_true(is.na(row$ok))
  expect_true(is.na(row$ess))
  expect_true(is.na(row$geweke_z))

  # drawn parameters do get a verdict
  expect_false(is.na(d$ok[d$parameter == "phi1"]))
})


test_that("serial_correlation = FALSE makes every rho constant", {
  data(mfbdfm_example_data, envir = environment())
  set.seed(22)
  fit <- suppressMessages(
    ind_dfm(mfbdfm_example_data, length_sample = 35, burn_in = 5,
            serial_correlation = FALSE))

  d <- as.data.frame(mfbdfm_diagnostics(fit))
  expect_true(all(d$note[d$block == "rho"] == "constant"))
  expect_true(all(is.na(d$ok[d$block == "rho"])))
  # not counted as failures
  expect_false(any(d$note[d$block == "rho"] == ""))
})


test_that("a chain too short for the Geweke windows says so", {
  data(mfbdfm_example_data, envir = environment())
  set.seed(23)
  fit <- suppressMessages(
    ind_dfm(mfbdfm_example_data, length_sample = 8, burn_in = 3))

  d <- as.data.frame(mfbdfm_diagnostics(fit))
  drawn <- d[d$note != "constant", ]
  expect_true(all(drawn$note == "too few draws"))
  # a row with no statistics is neither a pass nor a failure
  expect_true(all(is.na(drawn$ok)))
  expect_true(all(is.na(drawn$ess)))
})


test_that("thresholds are arguments, and flagging responds to them", {
  fit <- diagnostics_fit()

  strict <- mfbdfm_diagnostics(fit, ess_min = 1e6, geweke_crit = 0)
  loose <- mfbdfm_diagnostics(fit, ess_min = 0, geweke_crit = Inf)

  expect_true(all(!strict$ok[!is.na(strict$ok)]))
  expect_true(all(loose$ok[!is.na(loose$ok)]))

  expect_equal(attr(strict, "ess_min"), 1e6)
  expect_equal(attr(loose, "geweke_crit"), Inf)
})


test_that("the Heidelberger-Welch columns appear only on request", {
  fit <- diagnostics_fit()

  expect_false("heidel_p" %in% names(mfbdfm_diagnostics(fit)))

  d <- mfbdfm_diagnostics(fit, heidel = TRUE)
  expect_true(all(c("heidel_stationary", "heidel_p", "heidel_halfwidth") %in%
                    names(d)))
  # ok/note stay last whatever was added
  expect_equal(utils::tail(names(d), 2), c("ok", "note"))
  expect_type(d$heidel_stationary, "logical")
  expect_true(any(is.finite(d$heidel_p)))
})


test_that("diagnostics work on a fcast_dfm fit and on a draws object", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2022)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2022)

  set.seed(24)
  fit <- suppressMessages(suppressWarnings(
    fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2,
              length_sample = 32, burn_in = 8, plots = FALSE)))

  d <- mfbdfm_diagnostics(fit)
  expect_equal(nrow(d), ncol(fit$draws$parameters))
  expect_true(any(d$block == "phi"))
  expect_true(any(is.finite(d$ess)))

  # the draws object on its own is accepted, and gives the same answer
  expect_equal(as.data.frame(mfbdfm_diagnostics(fit$draws)), as.data.frame(d))

  # "all" reaches the nowcast columns too
  all_d <- mfbdfm_diagnostics(fit, which = "all")
  expect_gt(nrow(all_d), nrow(d))
  expect_true(any(all_d$block == "nowcast"))
})


test_that("diagnostics name the offending argument", {
  fit <- diagnostics_fit()

  expect_error(mfbdfm_diagnostics(fit$pars), "must be a fitted model")
  expect_error(mfbdfm_diagnostics(fit, heidel = NA),
               "`heidel` must be TRUE or FALSE")
  expect_error(mfbdfm_diagnostics(fit, ess_min = -1),
               "`ess_min` must be a single non-negative number")
  expect_error(mfbdfm_diagnostics(fit, geweke_crit = "big"),
               "`geweke_crit` must be a single non-negative number")
})


test_that("print reports the counts and lists what it flagged", {
  fit <- diagnostics_fit()

  out <- utils::capture.output(print(mfbdfm_diagnostics(fit, ess_min = 1e6)))
  expect_true(any(grepl("MCMC convergence diagnostics for a ind_dfm fit", out)))
  expect_true(any(grepl("no R-hat", out)))
  expect_true(any(grepl("constant, not drawn", out)))
  expect_true(any(grepl("Flagged parameters", out)))

  clean <- utils::capture.output(
    print(mfbdfm_diagnostics(fit, ess_min = 0, geweke_crit = Inf)))
  expect_true(any(grepl("No parameter is flagged", clean)))
})


test_that("plot() on the diagnostics shows the failures by default", {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  fit <- diagnostics_fit()

  d <- mfbdfm_diagnostics(fit, ess_min = 0, geweke_crit = 0)
  flagged <- d$parameter[!is.na(d$ok) & !d$ok]
  expect_gt(length(flagged), 0)

  p <- plot(d, which = flagged[1:2])
  expect_s3_class(p, "ggarrange")

  # more failures than panels is truncated with a warning, not drawn
  expect_warning(plot(d, max_panels = 2), "showing the first 2")

  # with nothing flagged it falls back to the draws object's own default
  ok <- mfbdfm_diagnostics(fit, ess_min = 0, geweke_crit = Inf)
  expect_s3_class(plot(ok, type = "trace"), "ggplot")
  expect_s3_class(plot(ok, which = "phi", type = "density"), "ggplot")
})
