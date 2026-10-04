# Extended tests: prior/posterior recovery and computational scaling (#122).
#
# rOpenSci Bayesian standards BS7.0, BS7.1, BS7.3, and the refit half of BS7.4.
# The cheap half of BS7.4/BS7.4a is in the default suite (test-methods.R,
# test-model-helpers.R) - this file holds only what needs several fits.
#
# See tests/README.md for runtimes and for the measured values the tolerances
# below are derived from.

# A short chain on the shipped example dataset: 8 series, ~3 s per fit. Long
# enough that the posterior means below are stable to the precision asserted,
# which is all these tests need - none of them is about the sampler's mixing.
ext_quiet <- function(model) dfm_control(model, verbose = FALSE)

ext_ind_fit <- function(priors = dfm_priors("ind_dfm"), seed = 3,
                        length_sample = 40, burn_in = 10) {
  set.seed(seed)
  suppressMessages(suppressWarnings(
    ind_dfm(mfbdfm_example_data, length_sample = length_sample,
            burn_in = burn_in, plots = FALSE, priors = priors,
            control = ext_quiet("ind_dfm"))))
}

# the non-target entries of a per-series parameter vector. The target's own
# entries are governed by the structural priors and are excluded on purpose;
# see the BS7.1 block below.
ext_non_target <- function(fit, x) {
  as.numeric(x)[-which(fit$inventory$key == fit$target)]
}


test_that("the parametric values of a prior are recovered in the estimates (BS7.0)", {

  skip_if_not_extended()

  # The loading prior is N(b0, B0). Tightening B0 around b0 = 0 must pull the
  # posterior loadings toward 0 monotonically - that is what it means for the
  # prior's parametric values to be honoured rather than merely accepted.
  #
  # Measured (seed 3, 40 draws after 10 burn-in, mfbdfm_example_data):
  #   B0 = 1e0  -> max|lambda| = 0.688
  #   B0 = 1e-2 -> max|lambda| = 0.135
  #   B0 = 1e-4 -> max|lambda| = 0.0038
  #   B0 = 1e-8 -> max|lambda| = 2.3e-05
  # i.e. roughly proportional to B0, which is the conjugate-update rule.
  B0 <- c(1, 1e-2, 1e-4, 1e-8)
  shrunk <- ext_timed("BS7.0 lambda prior sweep", vapply(B0, function(b) {
    fit <- ext_ind_fit(dfm_priors("ind_dfm", lambda = list(b0 = 0, B0 = b)))
    max(abs(ext_non_target(fit, fit$pars$lambda)))
  }, numeric(1)))

  ext_report("BS7.0 max|lambda| by B0: ",
             paste(sprintf("%.0e -> %.3g", B0, shrunk), collapse = "  "))

  expect_true(all(diff(shrunk) < 0))
  # the loosest prior leaves a loading the data can see, the tightest does not
  expect_gt(shrunk[1], 0.1)
  expect_lt(shrunk[length(shrunk)], 1e-3)

})


test_that("a prior that dominates the data is recovered (BS7.1)", {

  skip_if_not_extended()

  # BS7.1 asks for recovery of the prior "in the absence of any additional
  # data". A mixed-frequency factor model cannot be fitted to no data at all -
  # there is no panel to augment and no factor to draw - so the well-posed
  # version is a prior made strong enough that the likelihood carries no
  # weight, which must return the prior's own moments.
  #
  # EXCEPTION, deliberate and not a gap: `ind_dfm()`'s `sigma_target` and
  # `rho_target` priors ARE its identification (see ?dfm_priors, "Structural
  # versus tunable priors"). Shrinking the target's measurement error and
  # serial correlation toward zero is what makes the factor track the target,
  # so "recover the prior without data" is not a property they are supposed to
  # have independently of the model - overriding them at all warns. They are
  # therefore excluded here, and only the tunable priors are tested.

  # (a) variance prior: inverse-gamma with c1 = c0 + t, d1 = d0 + SSR, so a
  #     prior sample size of 1e8 against t ~ 550 observations leaves the
  #     posterior mean at d0 / c0. Measured: 0.2500 and 1.5000, every series.
  for (v in c(0.25, 1.5)) {
    fit <- ext_timed(sprintf("BS7.1 sigma_other = %.2f", v),
                     ext_ind_fit(dfm_priors("ind_dfm",
                                            sigma_other = list(c0 = 1e8, d0 = 1e8 * v))))
    got <- ext_non_target(fit, fit$pars$sigma)
    ext_report(sprintf("BS7.1 sigma_other prior %.2f -> [%.4f, %.4f]",
                       v, min(got), max(got)))
    expect_equal(got, rep(v, length(got)), tolerance = 1e-3)
  }

  # (b) serial-correlation prior: normal with prior variance R0 around r0 = 0.
  #     At R0 = 1e-9 the posterior sits on r0. Measured: |rho| <= 1.1e-05,
  #     against a default-prior spread of [-0.13, 0.95] on the same data.
  fit <- ext_timed("BS7.1 rho_other = 0",
                   ext_ind_fit(dfm_priors("ind_dfm",
                                          rho_other = list(r0 = 0, R0 = 1e-9))))
  got <- ext_non_target(fit, fit$pars$rho)
  ext_report(sprintf("BS7.1 rho_other prior 0 -> max|rho| = %.3g", max(abs(got))))
  expect_equal(got, rep(0, length(got)), tolerance = 1e-3)

})


test_that("nowcasts are equivariant to the target's units (BS7.4)", {

  skip_if_not_extended()

  # The cheap BS7.4 checks (fitted values and nowcasts on the input scale) are
  # in the default suite. This is the one that needs two fits: multiplying the
  # target series by 100 must multiply the nowcast by 100 and nothing else,
  # which is the property the un-standardisation slip recorded in CLAUDE.md
  # violated (nowcasts returned in standard deviations).
  d <- mfbdfm_example_data
  base <- ext_timed("BS7.4 fit, target as given", ext_ind_fit())

  d100 <- d
  d100$flows[[d$target]] <- d$flows[[d$target]] * 100
  scaled <- ext_timed("BS7.4 fit, target x100", {
    set.seed(3)
    suppressMessages(suppressWarnings(
      ind_dfm(d100, length_sample = 40, burn_in = 10, plots = FALSE,
              control = ext_quiet("ind_dfm"))))
  })

  a <- mfbdfm_nowcast(base)$nowcast
  b <- mfbdfm_nowcast(scaled)$nowcast
  err <- max(abs(b - 100 * a))
  ext_report(sprintf("BS7.4 max|nowcast(100y) - 100*nowcast(y)| = %.3g  (sd = %.3g)",
                     err, stats::sd(b)))

  # not exact: the two chains diverge in the last bits of the standardised
  # matrix. They agree anyway, because each reproduces its own observed target
  # to ~1e-7 of that target's standard deviation (the anchoring).
  expect_lt(err, 1e-3 * stats::sd(b))

})


test_that("estimation time scales no worse than documented with n and T (BS7.3)", {

  skip_if_not_extended()

  # BS7.3 asks for the scaling of computational cost with input size. Memory is
  # already covered by dfm_memory()/dfm_workers() (#64); this is the time half.
  # ind_dfm() is used rather than fcast_dfm() because the latter parallelises
  # its rotation, which would measure the runner's core count.
  #
  # The assertion is a loose, documented bound on the log-log slope, not a
  # performance target: a shared CI runner's timings are noisy by a factor of
  # two. The number worth having is the one reported.
  #
  # The grid spans a factor of 16 and the chain is 220 iterations because a
  # smaller version measured nothing: at n = 4/8/16 with 25 iterations the three
  # fits came out at 0.7, 0.8 and 0.8 s - entirely the ~0.5 s of fixed overhead
  # (data preparation, output processing) - for a slope of 0.12 that was noise
  # with a plausible sign, and the block passed. Hence the guard below that the
  # largest size must actually cost more than the smallest: without it this test
  # cannot tell a scaling law from an idle loop.
  #
  # Measured here (R 4.6.1, x86_64-pc-linux-gnu, OpenBLAS):
  #   n   =   8,  32, 128  ->   7.1,  9.2, 18.2 s   log-log slope 0.34
  #   T_q =  40, 160, 640  ->   6.4,  7.8, 11.3 s   log-log slope 0.20
  # i.e. SUB-linear in both, because the dominant term is per-iteration and
  # nearly size-independent: 29 ms per iteration at n = 8, T_q = 60, against
  # 0.5 s of fixed cost. Chain length, not panel size, is what a user's runtime
  # is made of.

  panel <- function(n, T_q, seed = 1) {
    set.seed(seed)
    T_m <- 3 * T_q
    f <- as.numeric(stats::filter(stats::rnorm(T_m, 0, 0.3), 0.7, "recursive"))
    flows <- list(target = stats::ts(stats::rnorm(T_q, 0.4, 0.5),
                                     start = c(2000, 1), frequency = 4))
    for (i in seq_len(n)) {
      flows[[paste0("x", i)]] <- stats::ts(stats::runif(1, 0.5, 1.5) * f +
                                             stats::rnorm(T_m),
                                           start = c(2000, 1), frequency = 12)
    }
    flows
  }

  time_fit <- function(flows) {
    t0 <- Sys.time()
    set.seed(5)
    suppressMessages(suppressWarnings(
      ind_dfm(flows = flows, stocks = NULL, target = "target",
              length_sample = 200, burn_in = 20, plots = FALSE,
              control = ext_quiet("ind_dfm"))))
    as.numeric(difftime(Sys.time(), t0, units = "secs"))
  }

  # log-log slope through the measured points
  slope <- function(size, secs) stats::coef(stats::lm(log(secs) ~ log(size)))[[2]]

  n_grid <- c(8, 32, 128)
  n_secs <- ext_timed("BS7.3 series-count sweep",
                      vapply(n_grid, function(n) time_fit(panel(n, 60)), numeric(1)))
  ext_report("BS7.3 n   = ", paste(n_grid, collapse = ", "),
             "  ->  ", paste(sprintf("%.1f s", n_secs), collapse = ", "),
             sprintf("   slope %.2f", slope(n_grid, n_secs)))

  t_grid <- c(40, 160, 640)
  t_secs <- ext_timed("BS7.3 sample-length sweep",
                      vapply(t_grid, function(tq) time_fit(panel(8, tq)), numeric(1)))
  ext_report("BS7.3 T_q = ", paste(t_grid, collapse = ", "),
             "  ->  ", paste(sprintf("%.1f s", t_secs), collapse = ", "),
             sprintf("   slope %.2f", slope(t_grid, t_secs)))

  # the measurement has to be signal before its slope means anything.
  # Measured 2.55 and 1.76 over a 16-fold range; the bound is 1.4.
  expect_gt(n_secs[length(n_secs)] / n_secs[1], 1.4)
  expect_gt(t_secs[length(t_secs)] / t_secs[1], 1.4)

  # and then: both grow, and neither grows faster than the input size does
  expect_gt(slope(n_grid, n_secs), 0)
  expect_gt(slope(t_grid, t_secs), 0)
  expect_lt(slope(n_grid, n_secs), 1.5)
  expect_lt(slope(t_grid, t_secs), 1.5)

})
