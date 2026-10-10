test_that("is_count accepts a single finite whole number and nothing else", {

  expect_true(is_count(1))
  expect_true(is_count(1L))
  expect_true(is_count(0))
  expect_true(is_count(-3))          # sign is the caller's business, not this one's

  expect_false(is_count(1.5))
  expect_false(is_count(c(1, 2)))
  expect_false(is_count(integer(0)))
  expect_false(is_count(NA_real_))
  expect_false(is_count(Inf))
  expect_false(is_count("1"))
  expect_false(is_count(TRUE))       # logical is not numeric, deliberately
  expect_false(is_count(NULL))
})


test_that("validate_model_inputs names the offending argument", {

  # The whole point of validating in the entry points rather than the samplers
  # is that the message says which argument was wrong (#48). Each expectation
  # below pins the argument name, not just that an error occurred.
  flows <- list(a = stats::ts(1:8, start = 2020, frequency = 4))
  stocks <- list(b = stats::ts(1:8, start = 2020, frequency = 4))
  # built explicitly rather than with modifyList(), which drops NULL entries and
  # would silently turn "target = NULL" into "target missing" - a different code
  # path from the one under test
  call_it <- function(flows = flows0, stocks = stocks0, target = "a",
                      p = 1, length_sample = 10, burn_in = 5, thinning = 1){
    validate_model_inputs(flows = flows, stocks = stocks, target = target,
                          p = p, length_sample = length_sample,
                          burn_in = burn_in, thinning = thinning)
  }
  flows0 <- flows; stocks0 <- stocks

  expect_true(call_it())

  expect_error(call_it(flows = NULL, stocks = NULL),
               "At least one of `flows` and `stocks`")
  expect_error(call_it(flows = 1:3), "`flows` must be a named list")
  expect_error(call_it(flows = list(stats::ts(1:8))), "Every element of `flows` must be named")
  expect_error(call_it(flows = list(a = 1:8)), "only `ts` objects")

  expect_error(call_it(target = NULL), "single series name")
  expect_error(call_it(target = c("a", "b")), "single series name")
  expect_error(call_it(target = "nope"), "not among the supplied series")

  for (nm in c("p", "length_sample", "burn_in", "thinning")) {
    for (bad in list(0, 2.5, "1", c(1, 2))) {
      expect_error(do.call(call_it, stats::setNames(list(bad), nm)),
                   paste0("`", nm, "` must be a single positive whole number"),
                   fixed = TRUE)
    }
  }
})


test_that("validate_model_inputs checks q only when it is given", {

  flows <- list(a = stats::ts(1:8, start = 2020, frequency = 4),
                b = stats::ts(1:8, start = 2020, frequency = 4))
  base <- list(flows = flows, stocks = NULL, target = "a",
               p = 1, length_sample = 10, burn_in = 5, thinning = 1)

  # ind_dfm() passes no q at all, so nothing about q may be enforced
  expect_true(do.call(validate_model_inputs, base))

  expect_true(do.call(validate_model_inputs, c(base, list(q = 2))))
  expect_error(do.call(validate_model_inputs, c(base, list(q = 0))),
               "`q` must be a single positive whole number")
  expect_error(do.call(validate_model_inputs, c(base, list(q = 1.5))),
               "`q` must be a single positive whole number")
  # more factors than series
  expect_error(do.call(validate_model_inputs, c(base, list(q = 3))),
               "must be smaller than the number of input series")
})


test_that("validate_model_inputs rejects empty and non-numeric series (G5.8a, G5.8b)", {

  flows <- list(a = stats::ts(rnorm(40), start = 2014, frequency = 4),
                b = stats::ts(rnorm(40), start = 2014, frequency = 4))
  call_it <- function(extra) {
    validate_model_inputs(flows = c(flows, extra), stocks = NULL, target = "a",
                          p = 1, length_sample = 10, burn_in = 5, thinning = 1)
  }

  # G5.8a. The length check deliberately precedes the is.ts() one, because
  # stats::is.ts() is `inherits(x, "ts") && length(x) > 0L` - so without it a
  # zero-length series is reported as "not a `ts` object", which is the wrong
  # reason. Both forms must give the length message.
  empty_ts <- flows$a[0]; class(empty_ts) <- "ts"
  expect_error(call_it(list(e = empty_ts)), "these have length zero: 'e'",
               fixed = TRUE)
  expect_error(call_it(list(e = numeric(0))), "these have length zero: 'e'",
               fixed = TRUE)

  # G5.8b: `ts` constrains the time attributes, not the storage mode
  expect_error(call_it(list(ch = stats::ts(letters[1:40], start = 2014, frequency = 4))),
               "only numeric series; these are not: 'ch' (character)", fixed = TRUE)
  expect_error(call_it(list(cx = stats::ts(complex(real = 1:40, imaginary = 1),
                                           start = 2014, frequency = 4))),
               "only numeric series; these are not: 'cx' (complex)", fixed = TRUE)
  expect_error(call_it(list(lg = stats::ts(rep(TRUE, 40), start = 2014, frequency = 4))),
               "only numeric series; these are not: 'lg' (logical)", fixed = TRUE)

  # integer storage is numeric and must stay accepted
  expect_true(call_it(list(i = stats::ts(1:40 * 1L + rep(c(0L, 3L), 20),
                                         start = 2014, frequency = 4))))
})


test_that("degenerate_reason flags only series that cannot be standardized", {

  expect_null(degenerate_reason(stats::ts(c(1, 2, 3))))
  expect_null(degenerate_reason(stats::ts(c(1, NA, 3))))   # interior NAs are fine

  expect_match(degenerate_reason(stats::ts(rep(NA_real_, 5))),
               "no non-missing observations")
  expect_match(degenerate_reason(stats::ts(rep(2, 5))), "is constant")
  # a single observation: sd() is NA, not 0, so an sd()-based test would miss it
  expect_match(degenerate_reason(stats::ts(c(NA, 7, NA))), "is constant")

  # Inf must NOT be reported as constant - its sd() is NaN, but the values do
  # vary, and Inf/NaN screening is G2.16's job (#125), not this function's
  expect_null(degenerate_reason(stats::ts(c(1, 2, Inf))))
})


test_that("screen_degenerate_series drops with a classed warning, errors on the target (G5.8c)", {

  set.seed(1)
  flows <- list(
    gdp   = stats::ts(rnorm(40, 0.4, 0.5), start = 2014, frequency = 4),
    ok    = stats::ts(rnorm(120), start = 2014, frequency = 12),
    flat  = stats::ts(rep(2, 120), start = 2014, frequency = 12))
  stocks <- list(
    s1    = stats::ts(rnorm(120), start = 2014, frequency = 12),
    blank = stats::ts(rep(NA_real_, 120), start = 2014, frequency = 12))

  # nothing degenerate: a pass-through, and silent
  expect_silent(kept <- screen_degenerate_series(flows[c("gdp", "ok")],
                                                 stocks["s1"], "gdp"))
  expect_identical(kept, list(flows = flows[c("gdp", "ok")], stocks = stocks["s1"]))

  w <- expect_warning(out <- screen_degenerate_series(flows, stocks, "gdp"),
                      class = "mfbdfm_warning_dropped_series")
  # the warning names every series dropped, and says why for each
  expect_match(conditionMessage(w), "flat")
  expect_match(conditionMessage(w), "blank")
  expect_match(conditionMessage(w), "is constant")
  expect_match(conditionMessage(w), "no non-missing observations")
  expect_named(out$flows, c("gdp", "ok"))
  expect_named(out$stocks, "s1")

  # the whole family is muffleable at once, per dfm_control()'s contract
  expect_silent(withCallingHandlers(
    screen_degenerate_series(flows, stocks, "gdp"),
    mfbdfm_warning = function(w) invokeRestart("muffleWarning")))

  # the target cannot be dropped: the factor is anchored to it
  flat_target <- flows; flat_target$gdp <- stats::ts(rep(1, 40), start = 2014,
                                                     frequency = 4)
  expect_error(screen_degenerate_series(flat_target, stocks["s1"], "gdp"),
               "`target` (\"gdp\") is constant", fixed = TRUE)

  # emptying the panel entirely is an error, not an empty fit
  expect_error(suppressWarnings(
    screen_degenerate_series(flows["flat"], stocks["blank"], "nope")),
    "Every supplied series was degenerate")

  # and q is re-checked against what survives, since dropping can leave fewer
  # series than factors
  expect_error(suppressWarnings(
    screen_degenerate_series(flows[c("gdp", "flat")], stocks["blank"], "gdp", q = 2)),
    "only 1 survived the degenerate-series screen")
})


test_that("Inf/NaN observations are screened at the entry points (G2.16)", {

  skip("Enabled by #125")

  set.seed(1)
  flows <- list(gdp = stats::ts(rnorm(40, 0.4, 0.5), start = 2014, frequency = 4),
                bad = stats::ts(c(rnorm(119), Inf), start = 2014, frequency = 12))

  expect_error(
    validate_model_inputs(flows = flows, stocks = NULL, target = "gdp",
                          p = 1, length_sample = 10, burn_in = 5, thinning = 1),
    "bad")

  flows$bad[120] <- NaN
  expect_error(
    validate_model_inputs(flows = flows, stocks = NULL, target = "gdp",
                          p = 1, length_sample = 10, burn_in = 5, thinning = 1),
    "bad")
})


test_that("resolve_data_arg accepts either calling convention", {

  # Covered from the mfbdfm_data() side in test-data-input.R; this pins the
  # plain flows/stocks path, which has to stay a pass-through.
  flows <- list(a = stats::ts(1:8, start = 2020, frequency = 4))
  stocks <- list(b = stats::ts(1:8, start = 2020, frequency = 4))

  expect_identical(resolve_data_arg(flows, stocks, "a"),
                   list(flows = flows, stocks = stocks, target = "a"))
  # nothing is invented when the caller gives nothing
  expect_identical(resolve_data_arg(NULL, NULL, NULL),
                   list(flows = NULL, stocks = NULL, target = NULL))
})


# A panel long enough to clear the 24-observation overlap floor: a monthly
# series, an exact copy, an affinely rescaled copy, and an independent one.
make_collinear_panel <- function(seed = 11, n = 60) {
  set.seed(seed)
  v <- stats::rnorm(n)
  mk <- function(x) stats::ts(x, start = c(2014, 1), frequency = 12)
  list(base = mk(v), copy = mk(v), scaled = mk(3 * v + 10),
       other = mk(stats::rnorm(n)))
}


test_that("align_series_on_grid reproduces prepare_data()'s alignment, keeping NAs", {

  # The mask is the whole point of the helper existing separately, so it is
  # pinned against the matrix the models actually see: same shape, and NA
  # exactly where prepare_data() wrote its missing-encoding zero.
  data(data_ch_dataset_test)
  flows <- data_ch_dataset_test$flows
  stocks <- data_ch_dataset_test$stocks

  inv <- create_inventory(flows = flows, stocks = stocks)
  Y <- prepare_data(flows = flows, stocks = stocks, inventory = inv,
                    target = "ch.seco.gdp.real.gdp.ssa")
  A <- align_series_on_grid(c(flows, stocks))[, colnames(Y)]

  # `Y` is a ts matrix, so its mask carries a tsp attribute the plain one does
  # not; the comparison is of the masks, not of the time bases
  mask_prepared <- matrix(Y != 0, nrow(Y), ncol(Y), dimnames = dimnames(A))
  expect_identical(dim(A), dim(mask_prepared))
  expect_identical(!is.na(A), mask_prepared)

  # and the values are the same series, up to the standardization
  j <- "ch.seco.gdp.real.gdp.ssa"
  ok <- !is.na(A[, j])
  expect_equal(stats::cor(A[ok, j], Y[ok, j]), 1)
})


test_that("collinear_pairs flags duplicated and rescaled series, not independent ones", {

  p <- make_collinear_panel()
  out <- collinear_pairs(p)

  # base~copy and base~scaled and copy~scaled, but nothing involving `other`
  expect_equal(nrow(out), 3L)
  expect_false("other" %in% c(out$series1, out$series2))
  expect_true(all(abs(out$correlation) > 0.99))
  expect_true(all(out$n_overlap == 60L))

  # an affine rescaling is exactly as collinear as an exact copy; correlation
  # is invariant to it, which is also why the statistic does not need the
  # standardized matrix
  expect_equal(out$correlation, rep(1, 3))

  # ordered by decreasing |r|, and the column contract is stable
  expect_identical(names(out),
                   c("series1", "series2", "correlation", "n_overlap"))
  expect_equal(out$correlation, sort(abs(out$correlation), decreasing = TRUE))

  # a negated copy is just as much a duplicate, so the test is on |r|
  p2 <- list(a = p$base, b = -p$base)
  expect_equal(collinear_pairs(p2)$correlation, -1)
})


test_that("collinear_pairs returns nothing for a clean panel or too little overlap", {

  dat <- make_synth_dat()
  expect_equal(nrow(collinear_pairs(c(dat$flows, dat$stocks))), 0L)

  # the shipped data has no flagged pair, which is what keeps the examples quiet
  data(data_ch_dataset_test)
  expect_equal(nrow(collinear_pairs(c(data_ch_dataset_test$flows,
                                      data_ch_dataset_test$stocks))), 0L)

  # exactly collinear but overlapping in only 20 observations: skipped, because
  # a correlation off a handful of points is noise, not evidence of duplication
  set.seed(3)
  v <- stats::rnorm(20)
  short <- list(a = stats::ts(v, start = c(2014, 1), frequency = 12),
                b = stats::ts(v, start = c(2014, 1), frequency = 12))
  expect_equal(nrow(collinear_pairs(short)), 0L)
  # the same pair with 24 observations is flagged, pinning the boundary
  v <- stats::rnorm(24)
  long <- list(a = stats::ts(v, start = c(2014, 1), frequency = 12),
               b = stats::ts(v, start = c(2014, 1), frequency = 12))
  expect_equal(nrow(collinear_pairs(long)), 1L)

  # degenerate inputs are not the screen's business to error on
  expect_equal(nrow(collinear_pairs(list())), 0L)
  expect_equal(nrow(collinear_pairs(list(a = stats::ts(1:30, frequency = 12)))), 0L)
  # a constant series has no correlation with anything; cor()'s own warning
  # must not leak out as the screen's
  flat <- list(a = stats::ts(rep(1, 30), start = c(2014, 1), frequency = 12),
               b = stats::ts(stats::rnorm(30), start = c(2014, 1), frequency = 12))
  expect_silent(expect_equal(nrow(collinear_pairs(flat)), 0L))
})


test_that("collinear_pairs works across frequencies, on the overlapping span", {

  # A quarterly series and the quarterly average of itself observed monthly:
  # they only share the quarter-end grid points, which is the span the statistic
  # has to be computed on.
  set.seed(5)
  v <- stats::rnorm(40)
  q <- stats::ts(v, start = c(2014, 1), frequency = 4)
  m <- stats::ts(rep(v, each = 3), start = c(2014, 1), frequency = 12)

  out <- collinear_pairs(list(q = q, m = m))
  expect_equal(nrow(out), 1L)
  expect_equal(out$correlation, 1)
  expect_equal(out$n_overlap, 40L)
})


test_that("warn_collinear_series names the pair and carries its condition class", {

  p <- make_collinear_panel()

  w <- expect_warning(warn_collinear_series(p),
                      class = "mfbdfm_warning_collinear")
  expect_match(conditionMessage(w), "base", fixed = TRUE)
  expect_match(conditionMessage(w), "copy", fixed = TRUE)
  expect_match(conditionMessage(w), "3 pairs")
  # it says what collinearity costs, not just that it is present
  expect_match(conditionMessage(w), "splits the loading")

  # family class, so it can be muffled alongside the other fit warnings
  expect_warning(warn_collinear_series(p), class = "mfbdfm_warning")
  expect_silent(withCallingHandlers(
    warn_collinear_series(p),
    mfbdfm_warning_collinear = function(w) invokeRestart("muffleWarning")))

  # returns the pairs invisibly either way, so a caller can act on them
  expect_equal(nrow(suppressWarnings(warn_collinear_series(p))), 3L)
  expect_equal(nrow(warn_collinear_series(make_synth_dat()$flows)), 0L)
  expect_silent(warn_collinear_series(make_synth_dat()$flows))
})


test_that("both model entry points warn about collinear inputs (parity)", {

  # BS3.1 at the entry points. The warning is raised during validation, before
  # any sampling, so the chains only have to run - the shipped test data
  # windowed short is the same fixture the other short fits use, with one
  # series duplicated into the panel.
  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  flows$SWISSMI_dup <- flows$SWISSMI
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  ctl_i <- dfm_control("ind_dfm", verbose = FALSE)
  ctl_f <- dfm_control("fcast_dfm", verbose = FALSE)

  expect_warning(
    ind_dfm(flows = flows, stocks = stocks, target = target,
            length_sample = 12, burn_in = 4, control = ctl_i),
    class = "mfbdfm_warning_collinear")

  expect_warning(
    fcast_dfm(flows = flows, stocks = stocks, target = target, q = 1,
              length_sample = 12, burn_in = 4, control = ctl_f),
    class = "mfbdfm_warning_collinear")
})
