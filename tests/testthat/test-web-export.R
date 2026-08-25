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
})


test_that("export_wai_web() returns the documented column contract", {
  web <- export_wai_web(synth_fit_file())

  expect_named(web$data, c("date", "wai_qoq", "wai_qoq_lo", "wai_qoq_hi",
                           "wai_yoy", "wai_index"))
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
                   "date,wai_qoq,wai_qoq_lo,wai_qoq_hi,wai_yoy,wai_index")
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
                    "wai_index", "gdp_qoq", "gdp_yoy", "gdp_index"))
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
