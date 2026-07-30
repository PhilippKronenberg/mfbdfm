# Tests for R/control.R
#
# The premise of dfm_control() is that omitting it changes nothing, so the first
# test pins every default to the literal it replaced. If someone "improves" a
# default, that test fails and dev/baseline.rds has to be regenerated
# deliberately - which is the point.

test_that("defaults are exactly the literals that were hard-coded", {

  ind <- dfm_control("ind_dfm")
  fc <- dfm_control("fcast_dfm")

  # shared: draw_rho / draw_rho_fcast stationarity screen, numerical guards
  for(x in list(ind, fc)){
    expect_identical(x$rho_max, 0.99)
    expect_identical(x$rho_max_tries, 10)
    expect_identical(x$rho_fallback, 0.98)
    expect_identical(x$jitter, 1e-9)
    expect_identical(x$sv_offset, 0.001)
  }

  # ind_dfm only
  expect_identical(ind$phi_sum_max, 0.9)
  expect_identical(ind$sigma_max, 5)
  expect_null(ind$omega_max)
  expect_null(ind$rotation_criterion)

  # fcast_dfm only
  expect_identical(fc$omega_max, 1)
  expect_identical(fc$rotation_criterion, "mean")
  expect_identical(fc$rotation_tol, 1e-9)
  expect_identical(fc$rotation_max_iter, 5)
  expect_identical(fc$rotation_init_tol, 1e-9)
  expect_identical(fc$rotation_on_failure, "warning")
  expect_null(fc$phi_sum_max)
})


test_that("strict = TRUE selects the published rotation rule", {

  fc <- dfm_control("fcast_dfm", strict = TRUE)

  expect_identical(fc$rotation_criterion, "sum")
  expect_identical(fc$rotation_on_failure, "error")
  expect_gt(fc$rotation_max_iter, dfm_control("fcast_dfm")$rotation_max_iter)
  expect_true(is.finite(fc$rotation_max_iter))
  expect_true(fc$strict)

  # strict has nothing to act on in the single-factor model, so it says so
  expect_warning(dfm_control("ind_dfm", strict = TRUE), "does not")
  expect_error(dfm_control("fcast_dfm", strict = "yes"), "must be TRUE or FALSE")
})


test_that("Inf is refused for the iteration caps", {

  # the user's call: an unbounded loop has no termination guarantee, so a high
  # finite value is the way to make the rule effectively tolerance-driven
  expect_error(dfm_control("fcast_dfm", rotation_max_iter = Inf),
               "unbounded loop has no termination guarantee")
  expect_error(dfm_control("fcast_dfm", rotation_init_max_iter = Inf),
               "unbounded loop")
  expect_error(dfm_control("ind_dfm", rho_max_tries = Inf), "unbounded loop")

  # but a high finite value is fine
  expect_identical(dfm_control("fcast_dfm", rotation_max_iter = 1e4)$rotation_max_iter, 1e4)
})


test_that("invalid settings are refused, naming the argument", {

  expect_error(dfm_control("fcast_dfm", rotation_criterion = "median"),
               "must be \"mean\" or \"sum\"")
  expect_error(dfm_control("fcast_dfm", rotation_on_failure = "shout"),
               "\"warning\", \"error\" or \"ignore\"")
  expect_error(dfm_control("ind_dfm", rho_max = 2), "must be a single number")
  expect_error(dfm_control("ind_dfm", sigma_max = -1), "must be a single number")
  expect_error(dfm_control("ind_dfm", rho_max_tries = 2.5), "whole number")
  expect_error(dfm_control("ind_dfm", jitter = 0), "must be a single number")

  # a typo, or a knob the chosen model does not have, is an error rather than
  # being silently ignored
  expect_error(dfm_control("ind_dfm", rotation_tol = 1e-9),
               "Unknown control setting")
  expect_error(dfm_control("ind_dfm", sigmamax = 5), "Unknown control setting")
  expect_error(dfm_control("fcast_dfm", phi_sum_max = 0.9),
               "Unknown control setting")
})


test_that("rho_fallback must be inside rho_max, or the redraw loop cannot exit", {

  # the fallback is used once the tries are exhausted, and is then itself tested
  # against rho_max; if it fails that test the while loop never terminates
  expect_error(dfm_control("ind_dfm", rho_fallback = 0.995),
               "would never exit")
  expect_error(dfm_control("ind_dfm", rho_max = 0.9, rho_fallback = 0.95),
               "must be smaller than")
  expect_silent(dfm_control("ind_dfm", rho_max = 0.995, rho_fallback = 0.99))
})


test_that("resolve_control() accepts an object, a list or NULL", {

  expect_identical(resolve_control(NULL, "ind_dfm"), dfm_control("ind_dfm"))
  expect_identical(resolve_control(list(sigma_max = 10), "ind_dfm")$sigma_max, 10)
  expect_identical(resolve_control(dfm_control("ind_dfm"), "ind_dfm"),
                   dfm_control("ind_dfm"))

  # a control built for the wrong model is caught rather than silently ignored
  expect_error(resolve_control(dfm_control("fcast_dfm"), "ind_dfm"),
               "was built for fcast_dfm")
  expect_error(resolve_control(42, "ind_dfm"), "must be a `dfm_control` object")
})


test_that("both entry points accept control, and the default changes nothing", {

  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  set.seed(3)
  a <- ind_dfm(flows = flows, stocks = stocks, target = target,
               length_sample = 10, burn_in = 4)
  set.seed(3)
  b <- ind_dfm(flows = flows, stocks = stocks, target = target,
               length_sample = 10, burn_in = 4, control = dfm_control("ind_dfm"))
  set.seed(3)
  d <- ind_dfm(flows = flows, stocks = stocks, target = target,
               length_sample = 10, burn_in = 4, control = list())

  # omitting control, passing the defaults explicitly, and passing an empty list
  # must all be the same run
  expect_identical(a$factor, b$factor)
  expect_identical(a$pars, b$pars)
  expect_identical(a$factor, d$factor)

  # a control for the wrong model is rejected at the entry point
  expect_error(ind_dfm(flows = flows, stocks = stocks, target = target,
                       length_sample = 5, burn_in = 2,
                       control = dfm_control("fcast_dfm")),
               "was built for fcast_dfm")
})


test_that("a bound that actually binds changes the result", {

  # a knob nobody can move is not a knob: force sigma_max low enough to bite and
  # confirm the fit differs from the default run at the same seed
  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  run <- function(ctrl){
    set.seed(5)
    ind_dfm(flows = flows, stocks = stocks, target = target,
            length_sample = 10, burn_in = 4, control = ctrl)
  }
  base <- run(NULL)
  tight <- run(dfm_control("ind_dfm", sigma_max = 0.05))

  expect_false(isTRUE(all.equal(as.numeric(base$pars$sigma),
                                as.numeric(tight$pars$sigma))))
  expect_lte(max(tight$pars$sigma), 0.05 + 1e-8)
})


test_that("print.dfm_control() marks non-defaults and flags the weak criterion", {

  out <- paste(utils::capture.output(print(dfm_control("fcast_dfm"))),
               collapse = "\n")
  expect_match(out, "Control settings for fcast_dfm")
  expect_match(out, "rotation_criterion")
  expect_match(out, "weaker than the published rule")

  out2 <- paste(utils::capture.output(print(dfm_control("ind_dfm", sigma_max = 10))),
                collapse = "\n")
  expect_match(out2, "sigma_max")
  expect_match(out2, "default 5")           # the changed value is marked

  out3 <- paste(utils::capture.output(print(dfm_control("fcast_dfm", strict = TRUE))),
                collapse = "\n")
  expect_match(out3, "strict")
  expect_no_match(out3, "weaker than the published rule")

  expect_invisible(print(dfm_control("ind_dfm")))
})
