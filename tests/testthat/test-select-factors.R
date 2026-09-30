test_that("the criteria recover a known number of factors", {
  for (q_true in c(1, 3)) {
    d <- make_synth_factor_panel(q = q_true, seed = 100 + q_true)
    sel <- select_factors(flows = d$flows, stocks = d$stocks, max_q = 8)

    expect_s3_class(sel, "select_factors")
    expect_equal(unname(sel$q_hat), rep(q_true, 3))
  }
})

test_that("the returned object describes the panel it used", {
  d <- make_synth_factor_panel(q = 2, n = 20, t = 200)
  sel <- select_factors(flows = d$flows, stocks = d$stocks, max_q = 6)

  expect_equal(sel$n_series, 20L)
  expect_equal(sel$n_obs, 200L)
  expect_equal(sel$max_q, 6L)
  expect_length(sel$excluded, 0)
  expect_equal(nrow(sel$ic), 6L)
  expect_named(sel$ic, c("q", "IC1", "IC2", "IC3"))
  expect_true(all(is.finite(as.matrix(sel$ic))))

  # shares of a standardized panel's variance
  expect_equal(sum(sel$var_explained), 1)
  expect_true(all(diff(sel$eigenvalues) <= 1e-12))
  expect_equal(sel$cum_var_explained, cumsum(sel$var_explained))
})

test_that("lower-frequency series are excluded and reported", {
  dat <- make_synth_dat()
  sel <- suppressWarnings(select_factors(flows = dat$flows, stocks = dat$stocks,
                                         target = "gdp", max_q = 1))

  # the fixture is quarterly + monthly + two weekly series at frequency 48
  expect_equal(sel$frequency, 48)
  expect_setequal(sel$series, c("w1", "s1"))
  expect_setequal(sel$excluded, c("gdp", "m1"))
})

test_that("both na_action branches produce a usable panel", {
  d <- make_synth_factor_panel(q = 2, n = 20, t = 120)
  # punch a ragged edge into one series
  d$flows$x1[115:120] <- NA

  omit <- select_factors(flows = d$flows, stocks = d$stocks, max_q = 5)
  interp <- select_factors(flows = d$flows, stocks = d$stocks, max_q = 5,
                           na_action = "interpolate")

  expect_equal(omit$n_dropped, 6L)
  expect_equal(omit$n_obs, 114L)
  expect_equal(interp$n_dropped, 0L)
  expect_equal(interp$n_obs, 120L)
  expect_equal(unname(omit$q_hat), rep(2, 3))
  expect_equal(unname(interp$q_hat), rep(2, 3))
})

test_that("an mfbdfm_data object can be passed as the first argument", {
  d <- make_synth_factor_panel(q = 2, n = 20, t = 120)
  series <- c(d$flows, d$stocks)
  meta <- data.frame(series = names(series),
                     type = rep(c("flow", "stock"), each = 10))
  obj <- mfbdfm_data(series, meta, target = "x1")

  expect_equal(select_factors(obj, max_q = 5)$q_hat,
               select_factors(flows = d$flows, stocks = d$stocks,
                              max_q = 5)$q_hat)
})

test_that("validation names the offending argument", {
  d <- make_synth_factor_panel(q = 2, n = 20, t = 120)

  expect_error(select_factors(flows = d$flows, stocks = d$stocks, max_q = 0),
               "`max_q`")
  expect_error(select_factors(flows = d$flows, stocks = d$stocks, max_q = 2.5),
               "`max_q`")
  # max_q must stay below min(N, T) - 1
  expect_error(select_factors(flows = d$flows, stocks = d$stocks, max_q = 20),
               "`max_q`")
  expect_error(select_factors(flows = d$flows, stocks = d$stocks,
                              target = "nope", max_q = 5),
               "`target`")
  expect_error(select_factors(flows = d$flows, stocks = d$stocks,
                              max_q = 5, na_action = "guess"),
               "'arg'")
  expect_error(select_factors(max_q = 5),
               "`flows` and `stocks`")
})

test_that("a panel with fewer than two highest-frequency series errors", {
  dat <- make_synth_dat()
  expect_error(
    select_factors(flows = dat$flows[c("gdp", "m1", "w1")], target = "gdp"),
    "at least two series at the highest frequency"
  )
})

test_that("print(), plot() and screeplot() work", {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  d <- make_synth_factor_panel(q = 2, n = 20, t = 120)
  sel <- select_factors(flows = d$flows, stocks = d$stocks, max_q = 5)

  expect_output(print(sel), "Bai-Ng factor-count selection")
  expect_output(print(sel), "Chosen q")
  expect_silent(invisible(plot(sel)))

  shares <- screeplot(sel)
  expect_length(shares, 10)
  expect_equal(unname(shares), unname(sel$var_explained[1:10]))
  expect_equal(unname(screeplot(sel, npcs = 3, value = "eigenvalue")),
               unname(sel$eigenvalues[1:3]))
  expect_silent(invisible(screeplot(sel, npcs = 4, type = "lines")))
  expect_error(screeplot(sel, npcs = 99), "`npcs`")
})

test_that("a minimum on the boundary warns instead of being reported as a choice", {
  d <- make_synth_factor_panel(q = 3, n = 20, t = 200)

  expect_warning(sel <- select_factors(flows = d$flows, stocks = d$stocks,
                                       max_q = 3),
                 "minimised at `max_q`")
  expect_setequal(sel$at_boundary, c("IC1", "IC2", "IC3"))
  expect_output(print(sel), "minimised at max_q")

  # and stays quiet when all three settle inside the range
  expect_silent(sel2 <- select_factors(flows = d$flows, stocks = d$stocks,
                                       max_q = 8))
  expect_length(sel2$at_boundary, 0)
})
