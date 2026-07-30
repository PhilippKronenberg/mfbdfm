# Tests for R/data-input.R
#
# The point of mfbdfm_data() is that a misclassification or a wrong inferred
# frequency surfaces here instead of silently changing the aggregation weights,
# so most of these tests are about what it *refuses*.

# A small mixed-frequency panel in long form: one monthly flow, one monthly
# stock, one weekly (48-grid) series. Weekly is the highest frequency.
make_long <- function(){
  mon <- seq(as.Date("2020-01-01"), by = "month", length.out = 36)
  wk <- dec2week(2020 + (0:143)/48)
  rbind(
    data.frame(series = "m_flow",  date = mon, value = as.numeric(1:36)),
    data.frame(series = "m_stock", date = mon, value = as.numeric(36:1)),
    data.frame(series = "w_any",   date = wk,  value = as.numeric(seq_along(wk))))
}

make_long_meta <- function(){
  data.frame(series = c("m_flow", "m_stock", "w_any"),
             type = c("flow", "stock", "flow"),
             stringsAsFactors = FALSE)
}


test_that("mfbdfm_data() builds from a long data frame and infers frequencies", {

  d <- mfbdfm_data(make_long(), make_long_meta())

  expect_s3_class(d, "mfbdfm_data")
  expect_named(d, c("flows", "stocks", "meta", "target"))
  expect_setequal(names(d$flows), c("m_flow", "w_any"))
  expect_named(d$stocks, "m_stock")

  # 48, not 52: the weekly grid is identified by its day-of-month convention
  fq <- stats::setNames(d$meta$frequency, d$meta$series)
  expect_equal(fq[["m_flow"]], 12L)
  expect_equal(fq[["m_stock"]], 12L)
  expect_equal(fq[["w_any"]], 48L)

  # start values round-trip through the ts
  expect_equal(as.numeric(stats::start(d$flows$m_flow)), c(2020, 1))
  expect_equal(as.numeric(stats::time(d$flows$w_any)[1]), 2020)
})


test_that("wide data frames give the same result as long ones", {

  long <- make_long()
  mon <- unique(long$date[long$series == "m_flow"])
  wide_mon <- data.frame(date = mon,
                         m_flow = as.numeric(1:36),
                         m_stock = as.numeric(36:1))
  meta <- data.frame(series = c("m_flow", "m_stock"),
                     type = c("flow", "stock"), stringsAsFactors = FALSE)

  from_wide <- mfbdfm_data(wide_mon, meta)
  from_long <- mfbdfm_data(long[long$series != "w_any", ], meta)

  expect_equal(from_wide$flows, from_long$flows)
  expect_equal(from_wide$stocks, from_long$stocks)
})


test_that("wide input trims leading and trailing NAs per series", {

  mon <- seq(as.Date("2020-01-01"), by = "month", length.out = 12)
  v <- c(NA, NA, 3:10, NA, NA)
  wide <- data.frame(date = mon, a = as.numeric(v), b = as.numeric(1:12))

  d <- mfbdfm_data(wide, data.frame(series = c("a", "b"), type = "flow",
                                    stringsAsFactors = FALSE))

  expect_equal(length(d$flows$a), 8L)
  expect_equal(as.numeric(stats::start(d$flows$a)), c(2020, 3))
  expect_equal(length(d$flows$b), 12L)
})


test_that("a list of ts and an mts pass through", {

  data(data_ch_dataset_test)
  series <- c(data_ch_dataset_test$flows[1:3], data_ch_dataset_test$stocks[1:3])
  meta <- data.frame(series = names(series),
                     type = rep(c("flow", "stock"), each = 3),
                     stringsAsFactors = FALSE)

  d <- mfbdfm_data(series, meta)
  expect_equal(d$flows, series[1:3])
  expect_equal(d$stocks, series[4:6])

  m <- stats::ts(cbind(a = 1:24, b = 24:1), start = c(2020, 1), frequency = 12)
  dm <- mfbdfm_data(m, data.frame(series = c("a", "b"),
                                  type = c("flow", "stock"),
                                  stringsAsFactors = FALSE))
  expect_equal(stats::frequency(dm$flows$a), 12)
  expect_equal(as.numeric(dm$stocks$b), 24:1)
})


test_that("`type` is required below the highest frequency but not at it", {

  long <- make_long()

  # monthly type missing -> error, because flow/stock changes its weights
  meta_bad <- data.frame(series = c("m_flow", "m_stock", "w_any"),
                         type = c("flow", NA, "flow"), stringsAsFactors = FALSE)
  expect_error(mfbdfm_data(long, meta_bad), "below the highest")
  expect_error(mfbdfm_data(long, meta_bad), "m_stock")

  # the highest-frequency series' type missing -> filled, no error: at the
  # highest frequency flow and stock give identical aggregation weights
  meta_ok <- data.frame(series = c("m_flow", "m_stock", "w_any"),
                        type = c("flow", "stock", NA), stringsAsFactors = FALSE)
  d <- expect_silent(mfbdfm_data(long, meta_ok))
  expect_equal(d$meta$type[d$meta$series == "w_any"], "flow")
})


test_that("the claim behind that rule holds: flow and stock weights only differ below the highest frequency", {

  # This is the measurement the rule rests on, so it is asserted rather than
  # trusted: identical distributed lags at the highest frequency, different
  # below it. get_distributed_lags() works off an inventory, so the same
  # frequency is entered twice - once as a flow, once as a stock - and the two
  # rows compared.
  for(f in c(48, 12, 4)){
    inv <- data.frame(name = c("as_flow", "as_stock", "anchor"),
                      freq = c(f, f, 48),
                      type = c("flow", "stock", "flow"),
                      stringsAsFactors = FALSE)
    lags <- get_distributed_lags(inv)
    w <- vapply(lags, function(L) as.numeric(Matrix::diag(L))[1:2], numeric(2))
    if(f == 48) expect_equal(w[1, ], w[2, ]) else expect_false(isTRUE(all.equal(w[1, ], w[2, ])))
  }

  # and the specific counts quoted in ?mfbdfm_data
  nonzero <- function(f, type){
    inv <- data.frame(name = c("x", "anchor"), freq = c(f, 48),
                      type = c(type, "flow"), stringsAsFactors = FALSE)
    sum(vapply(get_distributed_lags(inv),
               function(L) as.numeric(Matrix::diag(L))[1], numeric(1)) != 0)
  }
  expect_equal(c(nonzero(12, "flow"), nonzero(12, "stock")), c(7L, 4L))
  expect_equal(c(nonzero(4, "flow"), nonzero(4, "stock")), c(23L, 12L))
})


test_that("a declared frequency is applied to data frames and checked against ts inputs", {

  mon <- seq(as.Date("2020-01-01"), by = "month", length.out = 24)
  wide <- data.frame(date = mon, a = as.numeric(1:24))

  # declared wins over the (here identical) inference; declare something else
  # to show it is actually used
  d <- mfbdfm_data(wide, data.frame(series = "a", type = "flow", frequency = 4L,
                                    stringsAsFactors = FALSE))
  expect_equal(stats::frequency(d$flows$a), 4)

  # for a ts the object is authoritative: a contradicting declaration errors
  # rather than silently reinterpreting the series
  ser <- list(a = stats::ts(1:24, start = c(2020, 1), frequency = 12))
  expect_error(
    mfbdfm_data(ser, data.frame(series = "a", type = "flow", frequency = 4L,
                                stringsAsFactors = FALSE)),
    "will not reinterpret")

  # an agreeing declaration is fine
  expect_silent(mfbdfm_data(ser, data.frame(series = "a", type = "flow",
                                            frequency = 12L,
                                            stringsAsFactors = FALSE)))
})


test_that("the reason for converting: frequency 52 silently discards monthly observations", {

  # This is what the conversion exists to prevent, so it is measured rather than
  # asserted in prose. prepare_data() shifts observations by
  # (max(freq)/frequency(x) - 1)/max(freq) and matches them onto a 1/max(freq)
  # grid by an exact join. With max(freq) = 48 the ratio is a whole number for
  # monthly and quarterly series; with 52 it is 52/12 = 4.33, the shifted
  # monthly observations miss the grid, and the join records them as missing.
  # Crucially this raises no error - the fit completes on mangled data.
  observed <- function(wk_freq){
    n_wk <- if(wk_freq == 52) 260 else 240
    raw <- list(gdp  = stats::ts(rnorm(20), start = c(2018, 1), frequency = 4),
                surv = stats::ts(rnorm(60), start = c(2018, 1), frequency = 12),
                wk   = stats::ts(rnorm(n_wk), start = c(2018, 1), frequency = wk_freq))
    inv <- create_inventory(flows = raw["gdp"], stocks = raw[c("surv", "wk")])
    Y <- prepare_data(flows = raw["gdp"], stocks = raw[c("surv", "wk")],
                      inventory = inv, target = "gdp")
    # 0 encodes missing in the prepared data
    vapply(colnames(Y), function(nm) sum(Y[, nm] != 0), integer(1))
  }

  set.seed(7)
  at48 <- observed(48)
  set.seed(7)
  at52 <- observed(52)

  # on the 48-grid every observation survives
  expect_equal(unname(at48[c("gdp", "surv")]), c(20L, 60L))
  # at 52 the monthly series loses most of its observations, silently
  expect_equal(unname(at52["surv"]), 20L)
  expect_lt(at52[["surv"]], at48[["surv"]])
})


test_that("weekly and daily series are put on the 48-week grid", {

  wk <- seq(as.Date("2020-01-06"), by = "week", length.out = 157)
  mon <- seq(as.Date("2020-01-01"), by = "month", length.out = 36)
  long <- rbind(
    data.frame(series = "w52", date = wk, value = as.numeric(seq_along(wk))),
    data.frame(series = "m", date = mon, value = as.numeric(1:36)))
  meta <- data.frame(series = c("w52", "m"), type = c("flow", "stock"),
                     stringsAsFactors = FALSE)

  expect_message(d <- mfbdfm_data(long, meta), "48-week grid")
  expect_message(mfbdfm_data(long, meta), "w52.*52 -> 48")

  expect_equal(stats::frequency(d$flows$w52), 48)
  expect_equal(d$meta$frequency[d$meta$series == "w52"], 48L)
  expect_equal(d$meta$frequency_in[d$meta$series == "w52"], 52L)
  # the untouched series carries no original frequency
  expect_true(is.na(d$meta$frequency_in[d$meta$series == "m"]))

  # and the ratios the model needs are now whole numbers
  expect_equal(max(d$meta$frequency) %% min(d$meta$frequency), 0)

  # daily too: the same incompatibility, the same function
  dy <- seq(as.Date("2020-01-01"), by = "day", length.out = 500)
  long_d <- rbind(
    data.frame(series = "d365", date = dy, value = as.numeric(seq_along(dy))),
    data.frame(series = "m", date = mon, value = as.numeric(1:36)))
  d2 <- suppressMessages(mfbdfm_data(long_d, meta = data.frame(
    series = c("d365", "m"), type = c("flow", "stock"), stringsAsFactors = FALSE)))
  expect_equal(stats::frequency(d2$flows$d365), 48)
  expect_equal(d2$meta$frequency_in[d2$meta$series == "d365"], 365L)
})


test_that("series already on the 48-week grid are left alone", {

  # a 48-grid series must not be re-aggregated, which is why the 48-vs-52
  # distinction still has to be drawn
  wk48 <- dec2week(2020 + (0:143)/48)
  long <- data.frame(series = "w48", date = wk48, value = as.numeric(1:144))
  meta <- data.frame(series = "w48", type = "flow", stringsAsFactors = FALSE)

  d <- expect_silent(mfbdfm_data(long, meta))
  expect_equal(stats::frequency(d$flows$w48), 48)
  expect_equal(as.numeric(d$flows$w48), as.numeric(1:144))
  expect_false("frequency_in" %in% names(d$meta))
})


test_that("a weekly `ts` supplied directly is converted too, and round-trips", {

  # no Dates here - they are reconstructed from the ts's decimal time
  x <- stats::ts(as.numeric(1:104), start = c(2020, 1), frequency = 52)
  d <- suppressMessages(mfbdfm_data(list(w = x),
                                    data.frame(series = "w", type = "flow",
                                               stringsAsFactors = FALSE)))
  expect_equal(stats::frequency(d$flows$w), 48)
  expect_equal(d$meta$frequency_in, 52L)
  # roughly 48/52 of the observations survive, values in the original range
  expect_gt(length(d$flows$w), 90)
  expect_lt(length(d$flows$w), 104)
  rng <- range(d$flows$w, na.rm = TRUE)
  expect_gte(rng[1], 1)
  expect_lte(rng[2], 104)
})


test_that("`aggregate` selects how observations sharing a slot are combined", {

  wk <- seq(as.Date("2020-01-06"), by = "week", length.out = 157)
  long <- data.frame(series = "w", date = wk, value = rep(1, length(wk)))
  meta <- data.frame(series = "w", type = "flow", stringsAsFactors = FALSE)

  a <- suppressMessages(mfbdfm_data(long, meta, aggregate = "mean"))
  b <- suppressMessages(mfbdfm_data(long, meta, aggregate = "sum"))

  # with a constant series of 1s, mean gives 1 in every slot; sum gives 2 in the
  # slots that received two weekly observations, and conserves the total - no
  # observation is dropped or counted twice
  expect_true(all(stats::na.omit(as.numeric(a$flows$w)) == 1))
  expect_setequal(unique(stats::na.omit(as.numeric(b$flows$w))), c(1, 2))
  expect_equal(sum(b$flows$w, na.rm = TRUE), length(wk))
  expect_gt(sum(stats::na.omit(as.numeric(b$flows$w)) == 2), 0)

  expect_error(mfbdfm_data(long, meta, aggregate = "median"), "'arg'")
})


test_that("daily2weekly()'s new FUN argument defaults to the old behaviour", {

  d <- seq(as.Date("2024-01-01"), by = "day", length.out = 200)
  z <- zoo::zoo(as.numeric(seq_along(d)), order.by = d)
  expect_equal(daily2weekly(z), daily2weekly(z, FUN = mean))
  expect_false(isTRUE(all.equal(as.numeric(daily2weekly(z)),
                                as.numeric(daily2weekly(z, FUN = sum)))))
})


test_that("an unmodelled frequency is an error, not a guess", {

  # 10-day spacing matches nothing this package models
  tm <- seq(as.Date("2020-01-01"), by = "10 days", length.out = 30)
  wide <- data.frame(date = tm, a = as.numeric(1:30))
  expect_error(mfbdfm_data(wide, data.frame(series = "a", type = "flow",
                                            stringsAsFactors = FALSE)),
               "Could not infer a frequency")

  # 7-day spacing off the 48-grid convention is read as weekly (52), and then
  # aggregated onto the 48-week grid
  tm <- seq(as.Date("2020-01-02"), by = "week", length.out = 60)
  wide <- data.frame(date = tm, a = as.numeric(1:60))
  d <- suppressMessages(mfbdfm_data(wide, data.frame(series = "a", type = "flow",
                                                     stringsAsFactors = FALSE)))
  expect_equal(d$meta$frequency_in, 52L)
  expect_equal(stats::frequency(d$flows$a), 48)
})


test_that("meta problems are reported specifically", {

  long <- make_long()
  meta <- make_long_meta()

  expect_error(mfbdfm_data(long), "`meta` is required")
  expect_error(mfbdfm_data(long, "nope"), "must be a data frame")
  expect_error(mfbdfm_data(long, data.frame(series = "m_flow")),
               "must have columns")
  expect_error(mfbdfm_data(long, transform(meta, type = "level")),
               "\"flow\" or \"stock\"")
  expect_error(mfbdfm_data(long, rbind(meta, meta[1, ])),
               "more than one row")
  expect_error(mfbdfm_data(long, transform(meta, frequency = 7L)),
               "must be one of")
  expect_warning(mfbdfm_data(long, rbind(meta, data.frame(series = "ghost",
                                                          type = "flow"))),
                 "not present in `data`")
})


test_that("data problems are reported specifically", {

  meta <- make_long_meta()

  expect_error(mfbdfm_data(1:10, meta), "must be a data frame")
  expect_error(mfbdfm_data(stats::ts(1:24, frequency = 12), meta),
               "univariate `ts` carries no series name")
  expect_error(mfbdfm_data(list(a = 1:10), data.frame(series = "a", type = "flow")),
               "not `ts` objects")
  expect_error(mfbdfm_data(data.frame(x = 1:5, a = 1:5),
                           data.frame(series = "a", type = "flow")),
               "Could not find a date column")
})


test_that("target is checked at construction and defaulted into the models", {

  long <- make_long()
  meta <- make_long_meta()

  expect_error(mfbdfm_data(long, meta, target = "typo"),
               "is not among the supplied series")
  expect_error(mfbdfm_data(long, meta, target = c("a", "b")),
               "single series name")

  d <- mfbdfm_data(long, meta, target = "m_flow")
  expect_equal(d$target, "m_flow")

  # the object's target is used when the call does not give one, and a target
  # given at the call site wins
  expect_equal(resolve_data_arg(d, NULL, NULL)$target, "m_flow")
  expect_equal(resolve_data_arg(d, NULL, "m_stock")$target, "m_stock")

  # supplying both an mfbdfm_data object and stocks is refused
  expect_error(resolve_data_arg(d, d$stocks, NULL), "must not also be supplied")

  # the flows/stocks path is untouched
  expect_equal(resolve_data_arg(d$flows, d$stocks, "m_flow"),
               list(flows = d$flows, stocks = d$stocks, target = "m_flow"))
})


test_that("ind_dfm() gives an identical fit from mfbdfm_data() and from flows/stocks", {

  data(data_ch_dataset_test)
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  meta <- data.frame(series = c(names(flows), names(stocks)),
                     type = rep(c("flow", "stock"), c(length(flows), length(stocks))),
                     stringsAsFactors = FALSE)
  d <- mfbdfm_data(c(flows, stocks), meta, target = target)
  expect_equal(d$flows, flows)
  expect_equal(d$stocks, stocks)

  set.seed(42)
  a <- ind_dfm(flows = flows, stocks = stocks, target = target,
               length_sample = 12, burn_in = 4)
  set.seed(42)
  b <- ind_dfm(d, length_sample = 12, burn_in = 4)

  expect_identical(a$factor, b$factor)
  expect_identical(a$nowcast, b$nowcast)
  expect_identical(a$pars, b$pars)
})


test_that("print.mfbdfm_data() reports the classification and flags the highest frequency", {

  d <- mfbdfm_data(make_long(), make_long_meta(), target = "m_flow")
  out <- paste(utils::capture.output(print(d)), collapse = "\n")

  expect_match(out, "3 series")
  expect_match(out, "2 flow, 1 stock")
  expect_match(out, "target: m_flow")
  expect_match(out, "48.*highest; flow/stock has no effect here")
  expect_match(out, "m_stock\\s+stock\\s+freq\\s+12")
  expect_invisible(print(d))
})
