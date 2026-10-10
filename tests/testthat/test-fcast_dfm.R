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


test_that("fcast_dfm is quiet under verbose = FALSE, messages under TRUE (BS2.13)", {

  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  fit_quiet <- function(verbose){
    set.seed(3)
    # the rotation cap can bind on a chain this short; that warning is the
    # subject of its own test below, not of this one
    suppressWarnings(
      fcast_dfm(flows = flows, stocks = stocks, target = target,
                q = 2, p = 1, length_sample = 8, burn_in = 4, plots = FALSE,
                control = dfm_control("fcast_dfm", verbose = verbose)))
  }

  # verbose = FALSE must also silence run_rotation_fcast()'s per-iteration
  # convergence message, not only the two in fcast_dfm() itself
  printed <- utils::capture.output(expect_no_message(fit <- fit_quiet(FALSE)))
  expect_identical(printed, character(0))
  expect_s3_class(fit, "fcast_dfm")

  printed_on <- utils::capture.output(expect_message(fit_quiet(TRUE)))
  expect_true(any(nzchar(printed_on)))
})


test_that("the rotation cap warning is classed and muffleable (BS2.14)", {

  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  # one rotation iteration cannot converge, so the cap binds for certain
  run <- function(){
    set.seed(3)
    fcast_dfm(flows = flows, stocks = stocks, target = target,
              q = 2, p = 1, length_sample = 8, burn_in = 4, plots = FALSE,
              control = dfm_control("fcast_dfm", verbose = FALSE,
                                    rotation_max_iter = 1))
  }

  expect_warning(run(), class = "mfbdfm_warning_rotation_cap")

  expect_silent(withCallingHandlers(
    run(),
    mfbdfm_warning_rotation_cap = function(w) invokeRestart("muffleWarning")))
})


test_that("fcast_dfm drops a degenerate series and errors on a degenerate target (G5.8c)", {

  # the parity half of the same test in test-ind_dfm.R: the screen lives in
  # R/validate.R precisely so both entry points behave identically here
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  flows$flat <- stats::ts(rep(2, length(flows$SWISSMI)),
                          start = stats::start(flows$SWISSMI),
                          frequency = stats::frequency(flows$SWISSMI))
  stocks$blank <- stats::ts(rep(NA_real_, length(stocks[[1]])),
                            start = stats::start(stocks[[1]]),
                            frequency = stats::frequency(stocks[[1]]))

  run <- function(fl = flows, st = stocks, q = 2){
    set.seed(5)
    fcast_dfm(flows = fl, stocks = st, target = target, q = q,
              length_sample = 8, burn_in = 4, plots = FALSE,
              control = dfm_control("fcast_dfm", verbose = FALSE))
  }

  # the short chain also trips the rotation cap; muffle just that one, so the
  # dropped-series warning is the only one left for expect_warning() to see
  run_quiet <- function(...){
    withCallingHandlers(
      run(...),
      mfbdfm_warning_rotation_cap = function(w) invokeRestart("muffleWarning"),
      mfbdfm_warning_rho_fallback = function(w) invokeRestart("muffleWarning"))
  }

  w <- expect_warning(fit <- run_quiet(),
                      class = "mfbdfm_warning_dropped_series")
  expect_match(conditionMessage(w), "flat")
  expect_match(conditionMessage(w), "blank")

  expect_s3_class(fit, "fcast_dfm")
  expect_false(any(c("flat", "blank") %in% fit$inventory$key))
  expect_false(any(is.na(fit$inventory$sd)))

  flat_target <- flows
  flat_target[[target]] <- stats::ts(rep(1, length(flows[[target]])),
                                     start = stats::start(flows[[target]]),
                                     frequency = stats::frequency(flows[[target]]))
  expect_error(suppressWarnings(run(flat_target)),
               "nothing for the factor to track")

  # q is re-checked against what survives the screen, not against the panel as
  # supplied - dropping two of four series here leaves fewer than q factors
  expect_error(suppressWarnings(run(flows[c(target, "flat")], stocks["blank"],
                                    q = 2)),
               "survived the degenerate-series screen")
})


test_that("fcast_dfm fits a panel with more series than observations (G5.8d)", {

  wide <- make_synth_wide_panel()

  set.seed(5)
  fit <- suppressMessages(suppressWarnings(
    fcast_dfm(flows = wide$flows, target = wide$target, q = 2,
              length_sample = 8, burn_in = 4, plots = FALSE,
              control = dfm_control("fcast_dfm", verbose = FALSE))))

  expect_s3_class(fit, "fcast_dfm")
  expect_gt(nrow(fit$inventory), nrow(fit$factor))
  expect_true(all(is.finite(fit$nowcast)))
  expect_true(all(is.finite(fit$factor)))
})


test_that("the headline components of a fcast_dfm fit carry no NA/NaN/Inf (G5.3)", {

  fit <- run_small_fcast(42)

  expect_all_finite(fit, c("factor", "factor_var", "nowcast", "nowcast_var"))
  expect_all_finite(fit$ncst, c("mean", "var"))
  expect_all_finite(fit$pars, c("lambda", "phi", "sigma", "rho", "h"))
  expect_all_finite(fit$inventory, c("freq", "mean", "sd"))
})


# Reproducibility across seeds and under input noise (G5.9a, G5.9b). Same
# construction as in test-ind_dfm.R, same measurement settings (seeds 1:5,
# length_sample = 300, burn_in = 100, data_ch_dataset_test from 2019), and the
# numbers below are the ones recorded in ?fcast_dfm.
#
# The factors and the loadings agree far less well here than in ind_dfm(), and
# that is the documented behaviour rather than a defect: this model samples an
# unidentified system and resolves the rotation afterwards, and the post-hoc
# rotation is not unique across runs (#46). The nowcast, which is invariant to
# the rotation, agrees as closely as ind_dfm()'s.
fcast_seed_fits <- function(seeds = 1:5, flows, stocks, target, q = 2,
                            length_sample = 300, burn_in = 100) {
  lapply(seeds, function(s) {
    set.seed(s)
    suppressMessages(suppressWarnings(
      fcast_dfm(flows = flows, stocks = stocks, target = target, q = q,
                length_sample = length_sample, burn_in = burn_in,
                control = dfm_control("fcast_dfm", verbose = FALSE))))
  })
}

fcast_seed_data <- function() {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  list(target = target,
       flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI", "FINANSW")],
                      stats::window, start = 2019),
       stocks = lapply(data_ch_dataset_test$stocks[c("SWCONPRCE", "VIX")],
                       stats::window, start = 2019))
}


test_that("fcast_dfm agrees across seeds to the documented tolerance (G5.9b)", {

  skip_if_not_extended()

  d <- fcast_seed_data()
  fits <- fcast_seed_fits(flows = d$flows, stocks = d$stocks, target = d$target)

  # measured: 0.9982 to 1.0000
  expect_gte(min(pairwise_cor(lapply(fits, function(x) as.numeric(x$nowcast)))),
             0.99)

  ij <- utils::combn(length(fits), 2)

  # measured: 0.5732 to 0.9388, after matching factors by absolute correlation
  fa <- apply(ij, 2, function(k)
    align_factors(fits[[k[1]]]$factor, fits[[k[2]]]$factor))
  expect_gte(min(fa), 0.55)

  # measured: 0.6344 to 0.9962. The loadings are permuted onto a common order
  # by the factor correlations first, since a permuted rotation permutes the
  # loading columns with it.
  la <- apply(ij, 2, function(k) {
    A <- fits[[k[1]]]$pars$lambda; B <- fits[[k[2]]]$pars$lambda
    C <- abs(stats::cor(as.matrix(fits[[k[1]]]$factor),
                        as.matrix(fits[[k[2]]]$factor)))
    perm <- apply(C, 1, which.max)
    if (anyDuplicated(perm)) perm <- seq_len(ncol(A))
    vapply(seq_len(ncol(A)),
           function(j) abs(stats::cor(A[, j], B[, perm[j]])), numeric(1))
  })
  expect_gte(min(la), 0.60)
})


test_that("fcast_dfm is insensitive to double.eps-scale input noise (G5.9a)", {

  skip_if_not_extended()

  d <- fcast_seed_data()
  plain <- fcast_seed_fits(1, d$flows, d$stocks, d$target)[[1]]
  noised <- fcast_seed_fits(1, jitter_double_eps(d$flows),
                            jitter_double_eps(d$stocks), d$target)[[1]]

  # measured: max absolute nowcast difference 1.53e-16, and both factors
  # matched at correlation 1 to within printing
  expect_lt(max(abs(plain$nowcast - noised$nowcast)), 1e-10)
  expect_gt(stats::cor(as.numeric(plain$nowcast), as.numeric(noised$nowcast)),
            1 - 1e-9)
  expect_true(all(align_factors(plain$factor, noised$factor) > 1 - 1e-9))
})
