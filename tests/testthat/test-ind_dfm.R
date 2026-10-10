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


# Forecast error against the forecast horizon (rOpenSci TS3.0-TS3.3). Both
# blocks read one set of six real-time fits from synth_horizon_errors(), which
# generates its data from this model's own measurement equation - see
# helper-synthetic.R.

test_that("nowcast errors widen with the forecast horizon (TS3.0, TS3.2)", {

  err <- synth_horizon_errors()

  expect_setequal(unique(err$h), -2:2)
  expect_identical(err$lag_number, -err$h)
  # the no-information benchmark is where an uninformative forecast sits
  expect_gt(horizon_rmse(err, 0:2, "benchmark_error"), 0.8)

  rmse <- vapply(0:2, function(h) horizon_rmse(err, h), numeric(1))

  # (a) a forecast is worse than the completed-but-unpublished quarter, and
  # (b) the longest horizon is worse than the shortest. Stated as two
  # inequalities with room in them rather than as strict monotonicity of the
  # whole profile: MCMC output is not bit-identical across platforms (see
  # CLAUDE.md), and h = 1 against h = 2 is the pair that can swap. Checked at
  # DGP seeds 3, 5, 7, 11 and 42 before being written down - the two
  # inequalities below hold at all five, strict monotonicity at four.
  expect_gt(horizon_rmse(err, 1:2), rmse[1])
  expect_gt(rmse[3], rmse[1])

  # and the model is doing better than no information at the short horizon,
  # which is what makes the widening a statement about the forecast rather
  # than about an uninformative constant
  expect_lt(rmse[1], horizon_rmse(err, 0, "benchmark_error"))
})

test_that("backcast errors do not widen with distance (TS3.1)", {

  err <- synth_horizon_errors()

  # The counter-case to TS3.0. Distance from the target quarter is not what
  # drives the error - missing data is - so once the quarter has passed and its
  # value has been published, moving the cut-off further away adds data and the
  # error collapses to the noise built into the fixture (target_noise = 0.02)
  # rather than growing.
  back <- vapply(c(-1, -2), function(h) horizon_rmse(err, h), numeric(1))

  expect_true(all(back < 0.1))
  expect_lt(back[2], 5 * back[1])                 # flat in distance, not rising
  expect_lt(max(back), 0.2 * horizon_rmse(err, 0))

  # per target quarter, not just on average. Stated as a bound rather than as
  # a strict improvement quarter by quarter: the pre-publication error is
  # occasionally tiny by luck (0.002 at one quarter here, below the 0.02 noise
  # floor), so "always better afterwards" is not a property of the model.
  both <- intersect(err$quarter[err$h == 0], err$quarter[err$h == -1])
  expect_gt(length(both), 2)
  paired <- function(h) err$error[err$h == h & err$quarter %in% both]
  expect_true(all(abs(paired(-1)) < 0.1))
  expect_lt(sqrt(mean(paired(-1)^2)), sqrt(mean(paired(0)^2)))
})

test_that("the error-table machinery tabulates errors by horizon", {

  err <- synth_horizon_errors()

  # Same errors through create_error_summary_tables(), the builder the published
  # evaluation uses, to show the widening is visible in the package's own
  # tables and not only in a bespoke calculation. `lag_number = -h` is that
  # builder's convention: its "-2" column is the two-quarters-ahead forecast.
  long <- rbind(
    data.frame(observation_date = zoo::as.Date(zoo::as.yearqtr(err$quarter)),
               error = err$error, model = "WAI", method = "mean",
               lag_number = err$lag_number, frequency = "QoQ"),
    data.frame(observation_date = zoo::as.Date(zoo::as.yearqtr(err$quarter)),
               error = err$benchmark_error, model = "MEAN", method = "mean",
               lag_number = err$lag_number, frequency = "QoQ"))
  long <- long[long$lag_number <= 0, , drop = FALSE]

  tabs <- create_error_summary_tables(long, model_order = c("WAI", "MEAN"),
                                      date_col = "observation_date",
                                      lag_range = -2:0)

  expect_named(tabs, c("rel_rmse", "rel_mae", "abs_rmse", "abs_mae", "summary"))

  wai <- tabs$summary[tabs$summary$model == "WAI", ]
  wai <- wai[order(-wai$lag_number), ]           # horizon 0, 1, 2
  expect_equal(wai$lag_number, c(0, -1, -2))
  expect_gt(wai$RMSE[3], wai$RMSE[1])
  expect_gt(sqrt(mean(wai$RMSE[2:3]^2)), wai$RMSE[1])
})


test_that("ind_dfm drops a degenerate series and errors on a degenerate target (G5.8c)", {

  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  # a constant and an all-missing series, both well-formed and both impossible
  # to standardize: create_inventory() would divide by 0 and by NA
  flows$flat <- stats::ts(rep(2, length(flows$SWISSMI)),
                          start = stats::start(flows$SWISSMI),
                          frequency = stats::frequency(flows$SWISSMI))
  stocks$blank <- stats::ts(rep(NA_real_, length(stocks[[1]])),
                            start = stats::start(stocks[[1]]),
                            frequency = stats::frequency(stocks[[1]]))

  run <- function(fl = flows, st = stocks){
    set.seed(5)
    ind_dfm(flows = fl, stocks = st, target = target,
            length_sample = 6, burn_in = 2, plots = FALSE,
            control = dfm_control("ind_dfm", verbose = FALSE))
  }

  w <- expect_warning(fit <- run(), class = "mfbdfm_warning_dropped_series")
  expect_match(conditionMessage(w), "flat")
  expect_match(conditionMessage(w), "blank")

  # the fit goes ahead on the surviving panel, and the dropped series are
  # absent from the inventory rather than present with an NaN sd
  expect_s3_class(fit, "ind_dfm")
  expect_false(any(c("flat", "blank") %in% fit$inventory$key))
  expect_false(any(is.na(fit$inventory$sd)))

  # and the result is the one you get by dropping them yourself
  set.seed(5)
  ref <- suppressWarnings(run(flows[c(target, "SWISSMI")], stocks[1:2]))
  expect_equal(fit$nowcast, ref$nowcast)

  # the target is the exception: there is no model left without it
  flat_target <- flows
  flat_target[[target]] <- stats::ts(rep(1, length(flows[[target]])),
                                     start = stats::start(flows[[target]]),
                                     frequency = stats::frequency(flows[[target]]))
  expect_error(suppressWarnings(run(flat_target)),
               "nothing for the factor to track")
})


test_that("ind_dfm fits a panel with more series than observations (G5.8d)", {

  # n > t is the normal case for a factor model, not an edge case to reject
  wide <- make_synth_wide_panel()

  set.seed(5)
  fit <- suppressMessages(
    ind_dfm(flows = wide$flows, target = wide$target,
            length_sample = 12, burn_in = 4, plots = FALSE,
            control = dfm_control("ind_dfm", verbose = FALSE)))

  expect_s3_class(fit, "ind_dfm")
  expect_gt(ncol(fit$data), nrow(fit$data))
  expect_true(all(is.finite(fit$nowcast)))
  expect_true(all(is.finite(fit$factor)))
})


test_that("the headline components of an ind_dfm fit carry no NA/NaN/Inf (G5.3)", {

  fit <- run_small_ind_dfm(42)

  expect_all_finite(fit, c("factor", "factor_var", "factor_std", "index",
                           "nowcast", "nowcast_var", "data", "data_augmented"))
  expect_all_finite(fit$pars, c("h", "lambda", "phi", "sigma", "omega", "rho",
                                "rho_var"))
  expect_all_finite(fit$inventory, c("freq", "mean", "sd"))
})


# Reproducibility across seeds and under input noise (G5.9a, G5.9b).
#
# These are quantified tolerances, not pass/fail claims of "no difference".
# The thresholds below sit just under the worst value measured on five seeds
# (1:5) at length_sample = 300, burn_in = 100, on data_ch_dataset_test
# windowed from 2019 - the same numbers recorded in ?ind_dfm. An MCMC chain is
# not bit-reproducible across BLAS implementations, so the measurement is
# platform-dependent in the same way dev/baseline.R is; treat a miss as a
# reason to re-measure and update both places, not as a silent failure.
#
# Behind the extended-test switch because five chains of 400 iterations is
# ~90 s, which the default suite's budget does not have room for.
ind_seed_fits <- function(seeds = 1:5, flows, stocks, target,
                          length_sample = 300, burn_in = 100) {
  lapply(seeds, function(s) {
    set.seed(s)
    suppressMessages(suppressWarnings(
      ind_dfm(flows = flows, stocks = stocks, target = target,
              length_sample = length_sample, burn_in = burn_in,
              control = dfm_control("ind_dfm", verbose = FALSE))))
  })
}

ind_seed_data <- function() {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  list(target = target,
       flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI", "FINANSW")],
                      stats::window, start = 2019),
       stocks = lapply(data_ch_dataset_test$stocks[c("SWCONPRCE", "VIX")],
                       stats::window, start = 2019))
}


test_that("ind_dfm agrees across seeds to the documented tolerance (G5.9b)", {

  skip_if_not_extended()

  d <- ind_seed_data()
  fits <- ind_seed_fits(flows = d$flows, stocks = d$stocks, target = d$target)

  # measured: 0.9868 to 1.0000
  expect_gte(min(pairwise_cor(lapply(fits, function(x) as.numeric(x$nowcast)))),
             0.98)
  # measured: 0.9502 to 0.9875. The weekly factor is the least pinned down of
  # the three, which is why it gets the loosest bound.
  expect_gte(min(pairwise_cor(lapply(fits, function(x) as.numeric(x$factor)))),
             0.94)
  # measured: 0.9936 to 0.9997. Includes the target's loading, which the
  # identifying restriction fixes at 1 and which therefore agrees exactly.
  expect_gte(min(pairwise_cor(lapply(fits, function(x) as.numeric(x$pars$lambda)))),
             0.99)
})


test_that("ind_dfm is insensitive to double.eps-scale input noise (G5.9a)", {

  skip_if_not_extended()

  d <- ind_seed_data()
  plain <- ind_seed_fits(1, d$flows, d$stocks, d$target)[[1]]
  noised <- ind_seed_fits(1, jitter_double_eps(d$flows),
                          jitter_double_eps(d$stocks), d$target)[[1]]

  # measured: correlation 1 to within printing, max absolute nowcast
  # difference 1.53e-16. Six orders of headroom on both, because the size of
  # the propagated perturbation is itself platform-dependent.
  expect_lt(max(abs(plain$nowcast - noised$nowcast)), 1e-10)
  expect_gt(stats::cor(as.numeric(plain$factor), as.numeric(noised$factor)),
            1 - 1e-9)
  expect_gt(stats::cor(as.numeric(plain$nowcast), as.numeric(noised$nowcast)),
            1 - 1e-9)
})
