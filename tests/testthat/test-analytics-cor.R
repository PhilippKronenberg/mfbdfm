test_that("rescale_to_gdp matches the target's mean and sd over the reference window", {
  set.seed(1)
  ind <- data.frame(time = seq(as.Date("2010-01-07"), by = "week", length.out = 200),
                    value = rnorm(200, 5, 2))
  gdp <- data.frame(value = seq(as.Date("2010-01-01"), by = "quarter", length.out = 40),
                    y = rnorm(40, 1, 1))
  out <- rescale_to_gdp(ind, gdp, ref_start = as.Date("2010-01-01"), ref_end = as.Date("2019-12-31"))

  expect_equal(mean(out$value), mean(gdp$y), tolerance = 1e-8)
  expect_equal(sd(out$value), sd(gdp$y), tolerance = 1e-2)
})

test_that("rescale_to_gdp shifts rather than scales when the indicator has zero variance", {
  ind <- data.frame(time = seq(as.Date("2010-01-07"), by = "week", length.out = 20), value = 5)
  gdp <- data.frame(value = seq(as.Date("2010-01-01"), by = "quarter", length.out = 20), y = 1:20)
  out <- rescale_to_gdp(ind, gdp)
  expect_equal(mean(out$value), mean(gdp$y), tolerance = 1e-8)
})

test_that("build_wai_qoq_mean_series computes annualized QoQ growth from levels", {
  lv <- data.frame(time = seq(as.Date("2020-01-07"), by = "week", length.out = 150),
                   value = 100 * cumprod(1 + rep(0.002, 150)))
  out <- build_wai_qoq_mean_series(lv)
  expect_named(out, c("time", "value"))
  expect_false(anyNA(out$value))
  # steady weekly growth of 0.2% compounds to a positive annualized QoQ rate
  expect_true(all(out$value > 0))
})

test_that("prepare_wai_qoq_series dispatches on the aggregation method", {
  qoq_tab <- data.frame(time = as.Date("2020-01-07"), name = "mean", value = 42)
  lv <- data.frame(time = seq(as.Date("2020-01-07"), by = "week", length.out = 150),
                   value = cumprod(1 + rep(0.001, 150)))
  res <- list(tab_gr_qoq = qoq_tab, tab_gr_lv = lv)

  expect_identical(prepare_wai_qoq_series(res, "last"), qoq_tab)
  expect_named(prepare_wai_qoq_series(res, "mean"), c("time", "value"))
})

test_that("plot_comparison returns a ggplot without erroring", {
  wk <- seq(as.Date("2005-01-07"), by = "week", length.out = 200)
  wai <- data.frame(time = wk, value = rnorm(200))
  cmp <- data.frame(time = wk, value = rnorm(200))
  crises <- data.frame(Peak = as.Date("2008-07-07"), Trough = as.Date("2009-09-28"))
  gdp <- data.frame(value = seq(as.Date("2005-01-01"), by = "quarter", length.out = 20), y = rnorm(20))

  p <- plot_comparison(wai, cmp, "Benchmark", crises, gdp,
                       sample_end_date = as.Date("2009-12-31"))
  expect_s3_class(p, "ggplot")
})

test_that("get_combined_cor_table returns bounded correlations for both frequencies", {
  inputs <- make_synth_inputs()
  cor_tab <- suppressMessages(get_combined_cor_table("mean", "indicators", inputs = inputs))

  expect_true(all(c("Frequency", "Series", "Lag_0") %in% names(cor_tab)))
  expect_setequal(as.character(unique(cor_tab$Frequency)), c("QoQ", "YoY"))
  expect_true(all(abs(na.omit(unlist(cor_tab[, -(1:2)]))) <= 1))
})

test_that("get_combined_cor_table validates its inputs", {
  expect_error(
    get_combined_cor_table("mean", "indicators", inputs = list(tab_gr = 1)),
    "Missing required inputs"
  )
})

test_that("render_correlation_heatmap writes a figure file", {
  inputs <- make_synth_inputs()
  cor_tab <- suppressMessages(get_combined_cor_table("mean", "indicators", inputs = inputs))
  dir <- tempfile(); dir.create(dir); on.exit(unlink(dir, recursive = TRUE))

  # ggarrange()/ggsave() can still touch the active graphics device; use a
  # null one so nothing pops up under CI.
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  result <- render_correlation_heatmap(
    cor_tables = list(mean = cor_tab),
    series_order = c("WAI", "SECO-WWA", "F-CURVE", "SECO-SEC", "SNB-BCI", "KOF-BARO"),
    output_file = "heatmap.pdf",
    figures_dir = dir
  )

  expect_true(file.exists(file.path(dir, "heatmap.pdf")))
  expect_s3_class(result, "ggarrange")
})
