test_that("cut_data applies the publication-lag conventions per frequency", {
  dat <- make_synth_dat()
  current <- 2023.5
  cut <- cut_data(dat, current_date = current)

  # weekly: observed one week later
  expect_lte(as.numeric(tail(time(cut$flows$w1), 1)), current - 1 / 48)
  # monthly: first week of the next month
  expect_lte(as.numeric(tail(time(cut$flows$m1), 1)), current - 4 / 48)
  # quarterly target: ~10 weeks after quarter end
  expect_lte(as.numeric(tail(time(cut$flows$gdp), 1)), current - 1 / 4 - 8 / 48)
  # too-short series are dropped
  expect_true(all(sapply(c(cut$flows, cut$stocks), length) >= 24))
})

test_that("select_most_recent_GDP_vintage picks the newest available vintage", {
  vint <- make_synth_vintages()
  expect_identical(select_most_recent_GDP_vintage(2023.5, vint), vint[["2023.25"]])
  expect_identical(select_most_recent_GDP_vintage(2024.9, vint), vint[["2024.25"]])
  expect_error(select_most_recent_GDP_vintage(2020.0, vint), "No GDP vintage")
})

test_that("select_most_recent_GDP_vintage names the problem when args are swapped", {

  v <- make_synth_vintages()

  # The reversed call used to reach round() on a data frame and fail with
  # "non-numeric variable(s) in data frame: time" - naming neither argument and
  # pointing at the wrong place entirely.
  expect_error(select_most_recent_GDP_vintage(v, 2024),
               "the other way round")
  expect_error(select_most_recent_GDP_vintage("2024", v),
               "single, non-missing number")
  expect_error(select_most_recent_GDP_vintage(2024, "not a table"),
               "must be a vintage table")

  # the working call still returns the vintage COLUMN, not its name
  out <- select_most_recent_GDP_vintage(2024.3, v)
  expect_type(out, "double")
  expect_equal(length(out), nrow(v))
})


test_that("latest_fit_file defaults to no cutoff", {

  d <- tempfile(); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  for (x in c("2023", "2023.5", "2024.25")) {
    file.create(file.path(d, paste0("fit_", x, ".Rda")))
  }

  # a one-argument call used to fail with "argument \"cutoff_decimal\" is
  # missing, with no default" - the name promises the latest fit, so that is
  # what no argument now gives
  expect_equal(basename(latest_fit_file(d)), "fit_2024.25.Rda")
  expect_equal(basename(latest_fit_file(d, cutoff_decimal = 2023.6)),
               "fit_2023.5.Rda")
  expect_error(latest_fit_file(d, cutoff_decimal = "2024"),
               "must be a single number")
})


test_that("cut_data_real_time substitutes the target with the right vintage", {
  dat <- make_synth_dat()
  vint <- make_synth_vintages()
  cut <- cut_data_real_time(dat, current_date = 2023.9, GDP_gr_vintages = vint)

  expect_equal(frequency(cut$flows$gdp), 4)
  expect_equal(as.numeric(cut$flows$gdp),
               as.numeric(zoo::na.trim(stats::ts(vint[["2023.75"]], start = c(1990, 1), frequency = 4))))
})

test_that("the shipped GDP vintage database reads and is well-formed", {
  vintages <- get_real_time_gdp_vintages("quarterly")
  expect_s3_class(vintages$time, "Date")
  expect_gt(ncol(vintages), 50)
  vintage_names <- suppressWarnings(as.numeric(names(vintages)[-1]))
  expect_false(anyNA(vintage_names))
  expect_true(all(diff(vintage_names) > 0))
})
