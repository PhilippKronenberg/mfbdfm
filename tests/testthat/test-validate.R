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
