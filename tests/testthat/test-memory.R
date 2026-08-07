test_that("dfm_memory reproduces its own calibration points", {

  # The seven measured fits behind the constants (?dfm_memory), at n = 53,
  # t = 1535, s = 22, extend = 0.5.
  meas <- data.frame(q = c(1, 2, 3, 4, 2, 2, 2),
                     L = c(30, 30, 30, 30, 120, 240, 500),
                     peak = c(465, 604, 745, 916, 686, 846, 1538))

  est <- vapply(seq_len(nrow(meas)), function(i)
    dfm_memory(n = 53, t = 1535, s = 22, q = meas$q[i],
               length_sample = meas$L[i], extend = 0.5), numeric(1))

  # COVERAGE, not closeness. dfm_memory() is a safety bound: under-predicting
  # hands out too many workers and kills a sweep hours in, so no measured point
  # may sit above the estimate. Asserting |error| < 10% instead would pass while
  # the estimate was 27% low at 500 draws, which is exactly what happened.
  expect_true(all(est >= meas$peak))

  # and not so loose as to be useless
  expect_true(all(est / meas$peak < 1.6))

  # out-of-sample point: a different dataset and a different version of the code
  expect_gte(dfm_memory(n = 43, t = 1464, s = 22, q = 2,
                        length_sample = 200, extend = 0), 744)
})


test_that("dfm_memory is monotone and linear in the right arguments", {

  base <- list(n = 50, t = 1000, s = 22, length_sample = 200)
  m <- function(...) do.call(dfm_memory, utils::modifyList(base, list(...)))

  # more of anything costs more
  expect_gt(m(q = 3), m(q = 2))
  expect_gt(m(length_sample = 400), m(length_sample = 200))
  expect_gt(m(q = 2, extend = 1), m(q = 2, extend = 0))

  # linear in q, not quadratic - the measured result the model encodes, and the
  # thing most likely to be "corrected" back to a q^2 term by someone reasoning
  # from the Cholesky rather than from a measurement
  d21 <- m(q = 2) - m(q = 1)
  d43 <- m(q = 4) - m(q = 3)
  expect_equal(d21, d43, tolerance = 0.02)

  # exactly linear in the number of retained draws
  d1 <- m(length_sample = 200) - m(length_sample = 100)
  d2 <- m(length_sample = 400) - m(length_sample = 300)
  expect_equal(d1, d2, tolerance = 1e-8)
})


test_that("dfm_memory takes dimensions from the data when given it", {

  data(data_ch_dataset_test)
  flows <- data_ch_dataset_test$flows
  stocks <- data_ch_dataset_test$stocks

  from_data <- dfm_memory(flows = flows, stocks = stocks, q = 2,
                          length_sample = 100)

  inv <- create_inventory(flows = flows, stocks = stocks)
  Ymat <- prepare_data(flows, stocks, inv,
                       target = "ch.seco.gdp.real.gdp.ssa")
  k <- max(inv$freq) / min(inv$freq)
  from_dims <- dfm_memory(n = ncol(Ymat), t = nrow(Ymat), s = 2 * (k - 1),
                          q = 2, length_sample = 100,
                          frequency = max(inv$freq))

  expect_equal(from_data, from_dims)
  expect_gt(from_data, 0)
})


test_that("dfm_memory names the offending argument", {

  expect_error(dfm_memory(q = 2), "Supply either")
  expect_error(dfm_memory(n = 5, t = 10, s = 2, q = 0),
               "`q` must be a single positive whole number")
  expect_error(dfm_memory(n = 5, t = 10, s = 2, p = 1.5),
               "`p` must be a single positive whole number")
  expect_error(dfm_memory(n = 5, t = 10, s = 2, length_sample = -1),
               "`length_sample` must be a single positive whole number")
  expect_error(dfm_memory(n = 5, t = 10, s = 2, extend = -1),
               "`extend` must be a single non-negative number")
  expect_error(dfm_memory(n = 0, t = 10, s = 2), "`n` must be")
})


test_that("dfm_workers divides the budget and respects its bounds", {

  args <- list(n = 53, t = 1535, s = 22, q = 2, length_sample = 500)
  per_fit <- do.call(dfm_memory, args)

  w <- do.call(dfm_workers, c(args, list(available_mb = 20000, safety = 0.7,
                                         max_workers = 32)))
  expect_equal(as.integer(w), as.integer(floor(20000 * 0.7 / per_fit)))
  expect_equal(attr(w, "per_fit_mb"), per_fit)
  expect_equal(attr(w, "budget_mb"), 14000)

  # the core count is a ceiling
  expect_equal(as.integer(do.call(dfm_workers,
    c(args, list(available_mb = 1e6, max_workers = 3)))), 3L)

  # never zero: a machine too small for one fit still gets one worker, because
  # failing inside the fit is a better error than a sweep that runs no jobs
  expect_equal(as.integer(do.call(dfm_workers,
    c(args, list(available_mb = 10, max_workers = 8)))), 1L)

  # more factors, fewer workers for the same budget
  w2 <- do.call(dfm_workers, c(utils::modifyList(args, list(q = 1)),
                               list(available_mb = 20000, max_workers = 32)))
  w4 <- do.call(dfm_workers, c(utils::modifyList(args, list(q = 4)),
                               list(available_mb = 20000, max_workers = 32)))
  expect_gt(as.integer(w2), as.integer(w4))

  expect_error(do.call(dfm_workers, c(args, list(available_mb = 100, safety = 0))),
               "`safety` must be a single number")
  expect_error(do.call(dfm_workers, c(args, list(available_mb = 100, safety = 2))),
               "`safety` must be a single number")
})
