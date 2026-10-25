test_that("export_wai_web() validates its arguments", {
  expect_error(export_wai_web(c("a", "b")), "single file path")
  expect_error(export_wai_web("no-such-file.Rda"), "does not exist")

  f <- synth_fit_file()
  expect_error(export_wai_web(f, digits = -1), "non-negative whole number")
  expect_error(export_wai_web(f, digits = 2.5), "non-negative whole number")
  # a frame with no `time` column at all is named for what it is missing
  expect_error(export_wai_web(f, gdp = data.frame(t = 1, v = 2)),
               "`time` column")
  # one with `time` but no recognised measure names the alternatives
  expect_error(export_wai_web(f, gdp = data.frame(time = 1, v = 2)),
               "`qoq`, `yoy`, `index`")

  # G4.0: the fit is read with load(), so a file whose name says it is not an
  # R data file is refused by name rather than by magic number. The file has to
  # exist for the check to be reached, so copy the fixture to the wrong name.
  wrong <- file.path(tempdir(), "fit_as_csv.csv")
  file.copy(f, wrong, overwrite = TRUE)
  on.exit(unlink(wrong), add = TRUE)
  expect_error(export_wai_web(wrong), "must be an `.Rda`/`.RData` file",
               fixed = TRUE)

  bare <- file.path(tempdir(), "fit_no_extension")
  file.copy(f, bare, overwrite = TRUE)
  on.exit(unlink(bare), add = TRUE)
  expect_error(export_wai_web(bare), "an extensionless file", fixed = TRUE)
})


test_that("export_wai_web() returns the documented column contract", {
  web <- export_wai_web(synth_fit_file())

  expect_named(web$data, c("date", "wai_qoq", "wai_qoq_lo", "wai_qoq_hi",
                           "wai_yoy", "wai_index", "wai_qoq_q", "wai_yoy_q"))
  expect_s3_class(web$data$date, "Date")
  expect_false(is.unsorted(web$data$date))
  expect_equal(anyDuplicated(web$data$date), 0L)

  # the band is a band
  ok <- !is.na(web$data$wai_qoq)
  expect_true(all(web$data$wai_qoq_lo[ok] < web$data$wai_qoq[ok]))
  expect_true(all(web$data$wai_qoq[ok] < web$data$wai_qoq_hi[ok]))

  # no level band is published - see the export_wai_web() details section
  expect_false(any(grepl("index_(lo|hi)", names(web$data))))
})


test_that("export_wai_web() adds gdp_qoq on the last week of each quarter", {
  f <- synth_fit_file(start = 1990, end = 1992)
  gdp <- data.frame(time = seq(1990, 1991.75, 0.25), value = seq_len(8) / 10)

  web <- export_wai_web(f, gdp = gdp)

  expect_true("gdp_qoq" %in% names(web$data))
  expect_equal(sum(!is.na(web$data$gdp_qoq)), 8L)

  placed <- web$data[!is.na(web$data$gdp_qoq), ]
  expect_equal(placed$gdp_qoq, seq_len(8) / 10)
  # each value sits in the right calendar quarter, on its last weekly period
  expect_equal(as.numeric(format(placed$date, "%m")), c(3, 6, 9, 12, 3, 6, 9, 12))
})


test_that("export_wai_web() writes nothing unless `dir` is given", {
  d <- local_tempdir_base()
  web <- export_wai_web(synth_fit_file())
  expect_named(web, c("data", "meta"))
  expect_length(list.files(d, recursive = TRUE), 0L)
})


test_that("the written CSV matches the front end's parsing assumptions", {
  d <- local_tempdir_base()
  web <- export_wai_web(synth_fit_file(), dir = d)
  lines <- readLines(file.path(d, "wai_data.csv"))

  # bare, unquoted header in the documented order
  expect_identical(lines[1],
                   paste0("date,wai_qoq,wai_qoq_lo,wai_qoq_hi,wai_yoy,",
                          "wai_index,wai_qoq_q,wai_yoy_q"))
  expect_false(any(grepl("\"", lines)))
  # missing is the empty string, never NA/NaN/NULL
  expect_false(any(grepl("\\b(NA|NaN|NULL)\\b", lines)))
  expect_true(any(grepl(",,", lines)))          # the first year has no YoY
  expect_true(all(grepl("^\\d{4}-\\d{2}-\\d{2},", lines[-1])))

  # and it round-trips back to the same numbers
  back <- utils::read.csv(file.path(d, "wai_data.csv"), stringsAsFactors = FALSE)
  expect_equal(back$wai_qoq, web$data$wai_qoq)
  expect_equal(back$wai_index, web$data$wai_index)
  expect_equal(as.Date(back$date), web$data$date)
})


test_that("the metadata sidecar is valid JSON describing the run", {
  skip_if_not_installed("jsonlite")

  d <- local_tempdir_base()
  web <- export_wai_web(synth_fit_file(), dir = d)
  meta <- jsonlite::fromJSON(file.path(d, "wai_meta.json"))

  expect_setequal(names(meta), names(web$meta))
  expect_identical(meta$n_obs, nrow(web$data))
  expect_identical(meta$columns, names(web$data))
  expect_identical(as.Date(meta$last_obs_date), max(web$data$date))
  expect_identical(as.Date(meta$first_obs_date), min(web$data$date))
  expect_equal(meta$latest_wai_qoq, web$data$wai_qoq[nrow(web$data)])
  expect_match(meta$run_timestamp, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})


test_that("`digits` controls the published precision", {
  f <- synth_fit_file()
  expect_equal(export_wai_web(f, digits = 1)$data$wai_qoq,
               round(export_wai_web(f, digits = 8)$data$wai_qoq, 1))
})


test_that("export_wai_web() covers the full fitted window, past 2025", {
  # the horizon extract_wai_data() used to hard-code
  web <- export_wai_web(synth_fit_file(start = 1990, end = 2027))
  expect_gt(as.numeric(format(max(web$data$date), "%Y")), 2025)
  expect_false(anyNA(web$data$wai_index))
})


test_that("gdp_on_weekly_grid() accepts Dates and both decimal conventions", {
  f <- synth_fit_file(start = 1990, end = 1992)
  vals <- seq_len(8) / 10

  as_dates   <- data.frame(time = seq(as.Date("1990-01-01"), by = "quarter",
                                      length.out = 8), value = vals)
  # the package's own decimal convention: quarter starts at .000/.247/.496/.748
  as_local   <- data.frame(time = decimal_date_local(as_dates$time), value = vals)
  # the exact-fraction convention
  as_exact   <- data.frame(time = seq(1990, 1991.75, 0.25), value = vals)

  placed <- lapply(list(as_dates, as_local, as_exact), function(g) {
    d <- export_wai_web(f, gdp = g)$data
    d$gdp_qoq[!is.na(d$gdp_qoq)]
  })

  # all three must place all eight quarters, and place them identically
  expect_equal(placed[[1]], vals)
  expect_equal(placed[[2]], vals)
  expect_equal(placed[[3]], vals)
})


test_that("export_wai_web() writes one column per GDP measure supplied", {
  f <- synth_fit_file(start = 1990, end = 1994)
  qs <- seq(as.Date("1990-01-01"), by = "quarter", length.out = 16)

  all_three <- data.frame(time = qs, qoq = seq_len(16) / 10,
                          yoy = seq_len(16) / 5, index = 90 + seq_len(16))
  d <- export_wai_web(f, gdp = all_three)$data
  expect_named(d, c("date", "wai_qoq", "wai_qoq_lo", "wai_qoq_hi", "wai_yoy",
                    "wai_index", "wai_qoq_q", "wai_yoy_q",
                    "gdp_qoq", "gdp_yoy", "gdp_index"))
  expect_equal(d$gdp_qoq[!is.na(d$gdp_qoq)], seq_len(16) / 10)
  expect_equal(d$gdp_index[!is.na(d$gdp_index)], 90 + seq_len(16))

  # a subset of measures yields a subset of columns
  d2 <- export_wai_web(f, gdp = all_three[, c("time", "yoy")])$data
  expect_true("gdp_yoy" %in% names(d2))
  expect_false(any(c("gdp_qoq", "gdp_index") %in% names(d2)))

  # and the older time/value shape still lands in gdp_qoq
  d3 <- export_wai_web(f, gdp = data.frame(time = qs, value = seq_len(16)))$data
  expect_true("gdp_qoq" %in% names(d3))
  expect_equal(d3$gdp_qoq[!is.na(d3$gdp_qoq)], as.numeric(seq_len(16)))

  expect_error(export_wai_web(f, gdp = data.frame(x = 1)), "`time` column")
})


test_that("gdp_web_series() puts GDP on the published scale", {
  g <- gdp_web_series()

  expect_named(g, c("time", "qoq", "yoy", "index"))
  expect_s3_class(g$time, "Date")
  expect_false(is.unsorted(g$time))

  # rebased exactly to the 2019Q4 base, matching wai_index's base
  expect_equal(g$index[g$time == as.Date("2019-10-01")], 100)

  # lags are computed on the full history before the 1990 window is applied, so
  # the first returned quarter carries a real value rather than an NA
  expect_false(anyNA(g$qoq))
  expect_false(anyNA(g$yoy))
  expect_false(anyNA(g$index))
  expect_equal(min(g$time), as.Date("1990-01-01"))

  # annualised percent, not a log difference: same order of magnitude as the WAI
  expect_true(max(abs(g$qoq), na.rm = TRUE) > 1)
  expect_true(max(abs(g$qoq), na.rm = TRUE) < 100)

  # and it is the annualisation of what the vintage table returns
  q <- get_real_time_gdp_vintages("quarterly")
  raw <- as.numeric(q[[ncol(q)]])[match(g$time, as.Date(q$time))]
  expect_equal(g$qoq, (exp(raw * 4) - 1) * 100, tolerance = 1e-8)
})


test_that("gdp_web_series() rejects an unknown vintage", {
  expect_error(gdp_web_series(vintage = "not-a-vintage"), "not a column")
})


test_that("wai_qoq_q aggregates the level index as a flow, not by endpoints", {
  # a level index that falls and fully recovers WITHIN one quarter: endpoint
  # growth is ~0, mean growth is deeply negative. This is the 2020Q2 shape, and
  # the whole reason wai_qoq_q exists.
  dates <- seq(as.Date("2020-01-07"), by = "week", length.out = 26)
  idx <- c(rep(100, 12), c(100, 92, 85, 82, 85, 92, 99, 100, 100, 100, 100, 100), 100, 100)
  q <- mfbdfm:::wai_quarterly_flow(dates, idx[seq_along(dates)])

  placed <- which(!is.na(q$qoq))
  expect_gt(length(placed), 0)
  # the quarter containing the dip must come out clearly negative
  expect_lt(min(q$qoq, na.rm = TRUE), -10)

  # and it lands on the last week of its quarter
  for (i in placed) {
    same_q <- format(dates, "%Y-%m") >= format(dates[i], "%Y-%m")
    expect_equal(dates[i], max(dates[format(dates, "%Y") == format(dates[i], "%Y") &
      (as.integer(format(dates, "%m")) - 1) %/% 3 ==
      (as.integer(format(dates[i], "%m")) - 1) %/% 3]))
  }
})


test_that("wai_quarterly_flow() does not difference across a gap in quarters", {
  # two quarters, then a year missing, then another quarter
  d1 <- seq(as.Date("2020-01-07"), as.Date("2020-06-28"), by = "week")
  d3 <- seq(as.Date("2021-07-07"), as.Date("2021-09-28"), by = "week")
  dates <- c(d1, d3)
  idx <- c(rep(100, length(d1)), rep(120, length(d3)))

  q <- mfbdfm:::wai_quarterly_flow(dates, idx)
  vals <- q$qoq[!is.na(q$qoq)]
  # only the one genuinely adjacent pair inside d1 produces a growth rate;
  # the jump across the gap must not be differenced
  expect_true(all(abs(vals) < 1))
})


# Two short-chain fits on consecutive vintages of the shipped example data,
# saved the way run_wai_adj() saves them (object `mod`). Built once per file run.
measures_fixture <- local({
  cache <- NULL
  function() {
    if (!is.null(cache)) return(cache)
    new <- mfbdfm_example_data
    old <- new
    cut4 <- function(x) stats::window(x, end = stats::time(x)[length(x) - 4])
    old$flows <- lapply(old$flows, function(x)
      if (stats::frequency(x) > 4) cut4(x) else x)
    old$stocks <- lapply(old$stocks, cut4)
    fit_file <- function(d, seed) {
      set.seed(seed)
      mod <- suppressWarnings(ind_dfm(d, length_sample = 30, burn_in = 10,
                                      control = dfm_control(verbose = FALSE)))
      p <- tempfile(fileext = ".Rda")
      save(mod, file = p)
      list(path = p, fit = mod)
    }
    cache <<- list(old = fit_file(old, 1), new = fit_file(new, 2), new_data = new)
    cache
  }
})


test_that("export_wai_measures() validates its arguments", {
  fx <- measures_fixture()
  expect_error(export_wai_measures("no-such-file.Rda"), "existing fit file")
  expect_error(export_wai_measures(synth_fit_file()), "must hold an `ind_dfm` fit")
  expect_error(export_wai_measures(fx$new$path, news_fit_path = fx$old$path),
               "give both or neither")
  expect_error(export_wai_measures(fx$new$path, series_info = data.frame(a = 1)),
               "columns `key`, `name` and `group`")
})


test_that("contributions add up to the published wai_qoq exactly", {
  fx <- measures_fixture()
  out <- export_wai_measures(fx$new$path, digits = 10)
  co <- out$contributions
  expect_named(co, c("date", "component", "value"))
  expect_true(all(c("trend", "parameter_uncertainty") %in% co$component))

  tot <- tapply(co$value, co$date, sum)
  wai <- stats::setNames(as.numeric(fx$new$fit$factor),
                         as.character(dec2week(as.numeric(stats::time(fx$new$fit$factor)))))
  common <- intersect(names(tot), names(wai))
  expect_gt(length(common), 100)
  expect_equal(as.numeric(tot[common]), as.numeric(wai[common]), tolerance = 1e-6)
})


test_that("the series table carries names, groups, R-squared and loadings", {
  fx <- measures_fixture()
  keys <- fx$new$fit$inventory$key
  info <- data.frame(key = keys, name = paste("Series", seq_along(keys)),
                     group = rep(c("G1", "G2"), length.out = length(keys)))
  out <- export_wai_measures(fx$new$path, series_info = info)
  s <- out$series
  expect_setequal(s$series, keys)
  expect_true(all(s$group %in% c("G1", "G2")))
  expect_equal(s$name[match(keys, s$series)], info$name)
  expect_true(all(s$loading_lo <= s$loading & s$loading <= s$loading_hi, na.rm = TRUE))
  expect_true(all(s$r2 <= 1, na.rm = TRUE))
  # the target is the anchor: loading fixed at 1
  expect_equal(s$loading[s$series == fx$new$fit$target], 1)
  # series_info is optional: keys as names, everything in "Other"
  plain <- export_wai_measures(fx$new$path)$series
  expect_true(all(plain$group == "Other"))
})


test_that("news impacts add up to the revision on the published scale", {
  fx <- measures_fixture()
  out <- export_wai_measures(fx$new$path, news_fit_path = fx$old$path,
                             news_new_data = fx$new_data, digits = 10)
  expect_named(out$news, c("component", "impact"))
  m <- out$meta
  expect_true(m$news_available)
  expect_gt(m$news_new_obs, 0)
  expect_equal(sum(out$news$impact), m$news_nowcast_new - m$news_nowcast_old,
               tolerance = 1e-6)
  # without the news arguments there is no news, and the metadata says so
  expect_false(export_wai_measures(fx$new$path)$meta$news_available)
})


test_that("export_wai_measures() writes its files, and nothing without `dir`", {
  fx <- measures_fixture()
  d <- local_tempdir_base()
  export_wai_measures(fx$new$path, dir = d, news_fit_path = fx$old$path,
                      news_new_data = fx$new_data)
  expect_setequal(list.files(d), c("wai_contributions.csv", "wai_series.csv",
                                   "wai_news.csv", "wai_measures_meta.json"))
  co <- utils::read.csv(file.path(d, "wai_contributions.csv"))
  expect_named(co, c("date", "component", "value"))

  # the files are unquoted, so free text must not carry a comma: every row has
  # exactly as many fields as the header
  keys <- fx$new$fit$inventory$key
  info <- data.frame(key = keys, name = paste0("Flights, airport ", seq_along(keys)),
                     group = "Alternative, mobility")
  d3 <- local_tempdir_base()
  export_wai_measures(fx$new$path, dir = d3, series_info = info)
  for (f in c("wai_series.csv", "wai_contributions.csv")) {
    n_fields <- lengths(strsplit(readLines(file.path(d3, f)), ",", fixed = TRUE))
    expect_true(all(n_fields == n_fields[1]), label = paste("field count in", f))
  }
  expect_false(any(grepl(",", utils::read.csv(file.path(d3, "wai_series.csv"))$name)))
  meta <- readLines(file.path(d, "wai_measures_meta.json"))
  expect_true(any(grepl("\"news_available\": true", meta, fixed = TRUE)))

  d2 <- local_tempdir_base()
  export_wai_measures(fx$new$path)
  expect_length(list.files(d2), 0)
})
