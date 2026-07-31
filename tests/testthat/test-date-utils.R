test_that("decimal_date_local follows the day-of-year convention", {
  expect_equal(decimal_date_local(as.Date("2020-01-01")), 2020)
  expect_equal(decimal_date_local(as.Date("2021-12-31")), 2021 + 364 / 365)
})

test_that("is_crisis_period flags the two crisis windows", {
  dates <- as.Date(c("2008-09-15", "2015-06-01", "2020-04-01", "2022-01-01"))
  expect_equal(is_crisis_period(dates), c(TRUE, FALSE, TRUE, FALSE))
})

test_that("is_crisis_period_fcast flags the four Eckert et al. windows", {

  # Windows are inclusive at both ends, so the boundaries are pinned explicitly:
  # a shifted edge would silently reclassify whole quarters of the evaluation.
  expect_true(all(is_crisis_period_fcast(
    c(2008.75, 2009.5,      # global financial crisis, both edges
      2011.5,  2013,        # euro crisis
      2015,    2015.25,     # Swiss franc shock
      2020,    2021.5))))   # Covid-19

  # just outside each window
  expect_false(any(is_crisis_period_fcast(
    c(2008.5, 2009.75, 2011.25, 2013.25, 2014.75, 2015.5, 2019.75, 2021.75))))

  expect_equal(is_crisis_period_fcast(c(2019, 2020, 2021.25, 2022)),
               c(FALSE, TRUE, TRUE, FALSE))
})


test_that("the two crisis definitions are different and not interchangeable", {

  # This is the trap the _fcast suffix exists to prevent. 2012 is a crisis
  # quarter for Eckert et al. (euro crisis) but is not in is_crisis_period()'s
  # windows at all; 2015Q1 likewise. Measured on the paper's own panel the two
  # agree on only 124 of its 240 crisis rows.
  expect_true(is_crisis_period_fcast(2012))
  expect_false(is_crisis_period(as.Date("2012-06-01")))

  expect_true(is_crisis_period_fcast(2015))
  expect_false(is_crisis_period(as.Date("2015-02-01")))

  # and they take different inputs, so a mixed-up call is an error rather than
  # a silently wrong classification
  expect_error(is_crisis_period_fcast(as.Date("2020-04-01")),
               "must be numeric decimal time")
})


test_that("daily2weekly averages onto the 48-period grid", {
  daily <- zoo::zoo(rep(2, 96), order.by = seq(as.Date("2022-01-01"), by = "day", length.out = 96))
  weekly <- daily2weekly(daily)
  expect_equal(frequency(weekly), 48)
  expect_true(all(abs(na.omit(as.numeric(weekly)) - 2) < 1e-12))
})

test_that("aggregate_predictor_to_quarterly aggregates by the requested method", {
  df <- data.frame(time = seq(as.Date("2015-01-01"), by = "month", length.out = 12),
                   value = rep(1:4, each = 3))

  by_mean <- aggregate_predictor_to_quarterly(df, method = "mean")
  expect_equal(nrow(by_mean), 4)
  expect_equal(by_mean$value, 1:4)

  by_last <- aggregate_predictor_to_quarterly(df, cut_off_month_pos = 3, method = "last")
  expect_equal(by_last$value, 1:4)

  expect_error(aggregate_predictor_to_quarterly(df, method = "bogus"), "Unknown method")
})

test_that("aggregate_predictor_to_quarterly dispatches on an 'AR'-named argument", {
  AR_df <- data.frame(time = as.Date(c("2020-01-01", "2020-04-01")), value = c(1, 2))
  out <- aggregate_predictor_to_quarterly(AR_df)
  expect_true("yearqtr" %in% names(out))
  expect_identical(out$value, AR_df$value)
})

test_that("get_next_target_vintage finds the first later vintage", {
  expect_equal(get_next_target_vintage(2023.5, c(2023.25, 2023.75, 2024.25)), 2023.75)
  expect_true(is.na(get_next_target_vintage(2025, c(2023.25, 2023.75))))
})
