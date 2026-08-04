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
