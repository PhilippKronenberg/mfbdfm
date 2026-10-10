# Extended tests: simulation recovery (#122).
#
# rOpenSci standards G5.6, G5.6a, G5.6b, G5.7 and BS7.2. These wrap
# `dev/mc_recovery.R` - the script behind the run reported on #52 - rather than
# restating its data-generating process, so there is one DGP and one agreement
# measure in the repository. tests/README.md carries the runtimes and the
# measured values the tolerances below come from.
#
# The agreement measure is the rotation-invariant trace R-squared of Eckert et
# al. (2025), Eq. 17: factors are identified only up to a q x q rotation, so a
# correlation against a particular rotation would measure the rotation.

# The stored run (dev/mc_results.rds, 40/20/20 replications) is the reference
# the tolerances are set from:
#
#   cell        paper   mean     sd    min    q10  median    max
#   qf1_qhat1    0.68  0.717  0.144  0.000  0.597   0.756  0.862
#   qf2_qhat2    0.84  0.856  0.052  0.726  0.790   0.872  0.920
#   qf2_qhat1    0.39  0.408  0.112  0.002  0.336   0.426  0.538
#
# Note the qf1_qhat1 minimum of 0.000: roughly one replication in forty is
# degenerate. That is why these blocks assert on the MEDIAN of several seeds
# and not on each replication - a per-replication threshold would be flaky for
# a reason that has nothing to do with the code.

mc_env <- function() source_dev("mc_recovery.R")

# Replications at the stored run's own seeds, so the numbers are comparable
# with dev/mc_results.rds rather than merely similar. Memoised: a replication
# costs about a minute, and the negative-control block needs the same correctly
# specified cell the first block measures.
mc_cell <- local({

  cache <- list()

  function(q_f, q_hat, reps = 1:4, ...) {

    key <- paste(q_f, q_hat, max(reps), ...)
    if (is.null(cache[[key]])) {
      env <- mc_env()
      cache[[key]] <<- vapply(reps, function(i) {
        env$mc_one(q_f = q_f, q_hat = q_hat, cut_obs = 0.5, verbose = FALSE,
                   seed = env$mc_seed(q_f, q_hat, i), ...)$trace_r2
      }, numeric(1))
    }
    cache[[key]]

  }

})


test_that("fcast_dfm() recovers the simulated factor space (G5.6, G5.6a, G5.6b)", {

  skip_if_not_extended()

  # G5.6b: several seeds, since both the DGP and the sampler are random.
  # G5.6a: a tolerance, not an exact value - the target is a Monte Carlo mean.
  r2 <- ext_timed("G5.6 qf1_qhat1, 4 seeds", mc_cell(q_f = 1, q_hat = 1, reps = 1:4))
  ext_report(sprintf("G5.6 qf1_qhat1  r2 = %s   median %.3f  (stored median 0.756)",
                     paste(sprintf("%.3f", r2), collapse = ", "), stats::median(r2)))

  expect_length(r2, 4L)
  expect_false(anyNA(r2))
  expect_gt(stats::median(r2), 0.5)
  expect_lt(stats::median(r2), 0.95)   # a correct implementation is not perfect either

})


test_that("a misspecified factor count scores far lower (G5.6, negative control)", {

  skip_if_not_extended()

  # Scoring high everywhere would signal a bug as clearly as scoring low
  # everywhere: fitting one factor to a two-factor DGP must lose most of the
  # second factor. The paper reports 0.39 for this cell against 0.68 for the
  # correctly specified one.
  bad <- ext_timed("G5.6 qf2_qhat1, 3 seeds", mc_cell(q_f = 2, q_hat = 1, reps = 1:3))
  good <- mc_cell(q_f = 1, q_hat = 1, reps = 1:4)   # memoised, no refit

  ext_report(sprintf("G5.6 misspecified median %.3f vs correct median %.3f",
                     stats::median(bad), stats::median(good)))

  # the stored run's misspecified cell never exceeds 0.538 in 20 replications
  expect_lt(stats::median(bad), 0.6)
  expect_gt(stats::median(good) - stats::median(bad), 0.15)

})


test_that("the posterior recovers a two-factor DGP (BS7.2)", {

  skip_if_not_extended()

  # BS7.2, recovery of a posterior distribution: the posterior is summarised
  # here by the factor space its mean spans, which is the only rotation-free
  # summary available (q = 2 is identified up to a 2 x 2 rotation, so a
  # parameter-by-parameter comparison would compare rotations). The cell is the
  # one the paper reports 0.84 for; the stored run's 20 replications never fell
  # below 0.726, which is where the per-replication bound comes from.
  r2 <- ext_timed("BS7.2 qf2_qhat2, 2 seeds", mc_cell(q_f = 2, q_hat = 2, reps = 1:2))
  ext_report(sprintf("BS7.2 qf2_qhat2 r2 = %s   median %.3f  (stored median 0.872)",
                     paste(sprintf("%.3f", r2), collapse = ", "), stats::median(r2)))

  expect_false(anyNA(r2))
  expect_gt(min(r2), 0.6)

})


test_that("recovery improves as the sample grows (G5.7)", {

  skip_if_not_extended()

  # G5.7: the estimates must approach the truth as the data grow. Measured on
  # this DGP at the stored run's chain length, as the median of three seeds per
  # point (seeds are distinct from the cells above, so the points are
  # independent of them):
  #
  #   T =  60 months   trace R2  0.618
  #   T = 120 months   trace R2  0.730
  #   T = 240 months   trace R2  0.733
  #
  # An earlier two-seed pass gave 0.624 / 0.743 / 0.715 - i.e. a within-point
  # spread of 0.01-0.04 and, at T = 240, an ordering that two seeds got the
  # wrong way round. That is what the median of three is for.
  #
  # So the improvement is a TREND and not monotone, and the measurement says
  # why rather than the tolerance hiding it: the cross-section is fixed at
  # n = 25, and the factor at time t is estimated from those 25 observations
  # whatever T is. Doubling T sharpens the parameter estimates (O(1/sqrt(T)))
  # but cannot sharpen the per-period factor estimate (O(1/n)), so the gain
  # saturates - 60 -> 120 buys 0.11, and 120 -> 240 buys 0.003.
  # The assertion is therefore on the trend and on the first-to-last gap
  # (measured 0.115, bound 0.03), with the margin set from the within-point
  # spread rather than wished for.
  #
  # Not asserted on: `pars$phi`. It came out at 1.16, 4.46 and 22.1 against a
  # simulated 0.7, because fcast_dfm() resolves its rotational indeterminacy
  # after sampling and `phi` is reported in the sampled, unrotated space. The
  # trace R-squared is rotation-invariant by construction and is the right
  # quantity; a phi-based tolerance would have been measuring the rotation.
  env <- mc_env()
  T_grid <- c(60, 120, 240)

  r2 <- ext_timed("G5.7 sample-length sweep", vapply(T_grid, function(T_m) {
    # median of three seeds: one replication in forty is degenerate on this
    # DGP (see the stored run's minimum of 0.000), and a mean of two would
    # carry it straight into the comparison
    stats::median(vapply(1:3, function(k) {
      env$mc_one(q_f = 1, q_hat = 1, T_m = T_m, cut_obs = 0.5, verbose = FALSE,
                 seed = 4000 + T_m + k)$trace_r2
    }, numeric(1)))
  }, numeric(1)))

  ext_report("G5.7 T = ", paste(T_grid, collapse = ", "), "  ->  ",
             paste(sprintf("%.3f", r2), collapse = ", "))

  expect_false(anyNA(r2))
  expect_gt(r2[length(r2)] - r2[1], 0.03)
  # a positive trend in log T, which is the form the improvement takes
  expect_gt(stats::coef(stats::lm(r2 ~ log(T_grid)))[[2]], 0)

})
