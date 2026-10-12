# Tests for R/starting-values.R
#
# Unit level: the RNG bookkeeping and the starting-value resolver on their own,
# with a synthetic specification rather than a fit, so none of this costs a
# chain. The integration tests -- seed reproducibility, the global stream being
# handed back, and the continuation identity -- live with the entry points they
# are about, in test-ind_dfm.R and test-fcast_dfm.R (#117).

spec_ind <- function(n = 4, t = 20, s = 2, p = 1) {
  fit_spec("ind_dfm", n = n, t = t, s = s, p = p, q = 1,
           stochastic_volatility = TRUE, serial_correlation = TRUE)
}


test_that("rng_state() initialises a stream that does not exist yet", {

  # nothing has drawn in a fresh session, so .Random.seed is absent; recording
  # the state must not consume a draw the sampler would otherwise have had
  set.seed(1)
  old <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
  on.exit(assign(".Random.seed", old, envir = globalenv()), add = TRUE)

  rm(".Random.seed", envir = globalenv())
  st <- rng_state()

  expect_type(st, "integer")
  expect_true(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
  expect_identical(st, get(".Random.seed", envir = globalenv(), inherits = FALSE))
})


test_that("rng_set_state() puts a recorded position back exactly", {

  set.seed(1)
  st <- rng_state()
  a <- stats::runif(3)

  rng_set_state(st)
  expect_identical(stats::runif(3), a)
})


test_that("rng_begin() records, sets and gives the caller's stream back", {

  set.seed(99)
  caller <- rng_state()

  # no seed, no continuation: the stream is left alone and nothing is restored,
  # which is the long-standing behaviour
  rng <- rng_begin(NULL, NULL)
  expect_false(rng$restore)
  expect_null(rng$seed)
  expect_identical(rng$start, caller)
  expect_identical(rng$kind, RNGkind())
  rng_restore_caller(rng)
  expect_identical(rng_state(), caller)

  # a seed takes the stream over, and hands it back
  rng <- rng_begin(7, NULL)
  expect_true(rng$restore)
  expect_identical(rng$seed, 7L)
  expect_false(identical(rng$start, caller))
  invisible(stats::runif(5))
  rng_restore_caller(rng)
  expect_identical(rng_state(), caller)

  # continuing picks up the supplied position
  set.seed(3)
  target <- rng_state()
  set.seed(99)
  rng <- rng_begin(NULL, target)
  expect_identical(rng$start, target)
  expect_true(rng$restore)
  rng_restore_caller(rng)
  expect_identical(rng_state(), caller)
})


test_that("rng_begin() warns when a seed and a continuation disagree", {

  set.seed(5)
  other <- rng_state()

  expect_warning(rng <- rng_begin(1, other), "`seed` wins")
  # the seed is what actually took effect
  set.seed(1)
  expect_identical(rng$start, rng_state())
})


test_that("rng_finish() reports the position the sampler left behind", {

  set.seed(4)
  rng <- rng_begin(4, NULL)
  invisible(stats::rnorm(10))
  rec <- rng_finish(rng)

  expect_named(rec, c("seed", "kind", "start", "end"))
  expect_identical(rec$end, rng_state())
  expect_false(identical(rec$start, rec$end))
  # the caller's bookkeeping is deliberately not carried onto the fit
  expect_false("caller" %in% names(rec))
})


test_that("NULL starting values resolve to nothing at all", {

  res <- resolve_starting_values(NULL, spec_ind())
  expect_null(res$state)
  expect_null(res$rng)
})


test_that("unknown and unnamed starting values are refused by name", {

  expect_error(resolve_starting_values(list(nope = 1), spec_ind()),
               "Unknown element in `starting_values`")
  expect_error(resolve_starting_values(list(nope = 1), spec_ind()), "nope")
  expect_error(resolve_starting_values(list(1), spec_ind()),
               "must have a distinct name")
  expect_error(resolve_starting_values(list(f = 1, f = 2), spec_ind()),
               "must have a distinct name")
  expect_error(resolve_starting_values(1:3, spec_ind()),
               "must be a named list of parameter blocks")
})


test_that("every block is checked for shape and put in the sampler's own type", {

  sp <- spec_ind(n = 4, t = 20, s = 2, p = 2)

  ok <- resolve_starting_values(
    list(f = rnorm(22), lambda = 1:4, phi = c(0.4, 0.2),
         sigma = rep(0.5, 4), rho = rep(0.1, 4), h = rep(-5, 22),
         omega = 0.01, Xmat = matrix(0, 20, 4), indicators = rep(3, 22)),
    sp)$state

  expect_identical(dim(ok$f), c(22L, 1L))
  expect_identical(dim(ok$lambda), c(4L, 1L))
  expect_true(methods::is(ok$lambda, "Matrix"))
  expect_identical(ok$phi, c(0.4, 0.2))
  expect_true(methods::is(ok$sigma, "Matrix"))
  expect_identical(as.numeric(diag(ok$sigma)), rep(0.5, 4))
  expect_identical(dim(ok$h), c(22L, 1L))
  expect_identical(ok$omega, 0.01)

  bad <- function(x) resolve_starting_values(x, sp)
  expect_error(bad(list(f = rnorm(21))), "starting_values$f", fixed = TRUE)
  expect_error(bad(list(f = c(NA, rnorm(21)))), "non-missing")
  expect_error(bad(list(phi = c(0.1, 0.2, 0.3))), "starting_values$phi",
               fixed = TRUE)
  expect_error(bad(list(Xmat = matrix(0, 4, 20))), "20 x 4")
  expect_error(bad(list(omega = -1)), "single positive finite number")
  expect_error(bad(list(omega = c(1, 2))), "single positive finite number")
  expect_error(bad(list(sigma = rep(0, 4))), "must be > 0")
  expect_error(bad(list(sigma = rep(0.5, 3))), "vector of 4")
  expect_error(bad(list(indicators = rep(8, 22))), "whole numbers in 1:7")
  expect_error(bad(list(indicators = rep(3, 21))), "whole numbers in 1:7")

  # a dense matrix is accepted for sigma/rho only if it really is diagonal:
  # this model has no cross-series covariance, so quietly dropping the
  # off-diagonal would be a silent wrong answer
  m <- diag(rep(0.5, 4)); m[1, 2] <- 0.1
  expect_error(bad(list(sigma = m)), "off-diagonal entries must be zero")
  expect_silent(bad(list(sigma = diag(rep(0.5, 4)))))
})


test_that("the multi-factor phi is a list of q x q blocks, one per lag", {

  sp <- fit_spec("fcast_dfm", n = 4, t = 20, s = 2, p = 2, q = 3,
                 stochastic_volatility = TRUE, serial_correlation = TRUE)

  ok <- resolve_starting_values(
    list(phi = list(diag(0.1, 3), diag(0.2, 3)),
         lambda = matrix(0.1, 4, 3),
         f = matrix(0, 22, 3),
         indicators = matrix(4, 22, 3)), sp)$state

  expect_length(ok$phi, 2)
  expect_identical(dim(ok$phi[[1]]), c(3L, 3L))
  expect_identical(dim(ok$lambda), c(4L, 3L))
  expect_identical(dim(ok$f), c(22L, 3L))
  expect_identical(dim(ok$indicators), c(22L, 3L))

  expect_error(resolve_starting_values(list(phi = diag(0.1, 3)), sp),
               "a list of 2 3 x 3 coefficient matrices")
  expect_error(resolve_starting_values(list(phi = list(diag(0.1, 3))), sp),
               "a list of 2 3 x 3 coefficient matrices")
  expect_error(resolve_starting_values(list(phi = list(diag(0.1, 2),
                                                       diag(0.1, 2))), sp),
               "phi[[1]]", fixed = TRUE)
})


test_that("fit_spec() normalises whole numbers so 1 and 1L are one spec", {

  expect_identical(spec_ind(p = 1), spec_ind(p = 1L))
  expect_identical(spec_ind()$stochastic_volatility, TRUE)
})


test_that("a fit of the wrong model or specification cannot be continued", {

  fake <- structure(list(final_state = structure(list(), spec = spec_ind()),
                         rng = list(end = 1:3)),
                    class = "ind_dfm")

  expect_error(resolve_starting_values(fake, spec_ind(n = 5)),
               "different model specification")
  expect_error(resolve_starting_values(fake, spec_ind(n = 5)), "n: 4 -> 5")
  expect_error(resolve_starting_values(fake, spec_ind(t = 30)), "t: 20 -> 30")

  sv_off <- fit_spec("ind_dfm", n = 4, t = 20, s = 2, p = 1, q = 1,
                     stochastic_volatility = FALSE, serial_correlation = TRUE)
  expect_error(resolve_starting_values(fake, sv_off),
               "stochastic_volatility: TRUE -> FALSE")

  # the other model's sampler has a different parameter state entirely
  fc_spec <- fit_spec("fcast_dfm", n = 4, t = 20, s = 2, p = 1, q = 1,
                      stochastic_volatility = TRUE, serial_correlation = TRUE)
  expect_error(resolve_starting_values(fake, fc_spec),
               "can only be continued by the model that produced it")

  # a fit from before #117 carries no state to continue from, and says so
  old_fit <- structure(list(), class = "ind_dfm")
  expect_error(resolve_starting_values(old_fit, spec_ind()),
               "carries no `$final_state`", fixed = TRUE)

  # and an incomplete state is refused rather than topped up from the stream,
  # which would quietly make the two legs something other than one chain
  expect_error(resolve_starting_values(fake, spec_ind()),
               "is incomplete \\(missing f, lambda")
})
