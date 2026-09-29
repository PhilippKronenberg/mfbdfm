# The standardised plotting API (#112). Every view must work on both fit
# classes (the parity rule in CLAUDE.md) and must return a ggplot that builds.
#
# Nothing here prints a plot without a null device: R would otherwise open a
# real default device and leave a stray Rplots.pdf behind.

plot_fits <- function() {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  set.seed(1)
  a <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                length_sample = 8, burn_in = 4, plots = FALSE))
  set.seed(2)
  b <- suppressMessages(suppressWarnings(
    fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2,
              length_sample = 6, burn_in = 3, plots = FALSE)))
  list(ind_dfm = a, fcast_dfm = b)
}

all_types <- c("factor", "nowcast", "loadings", "residuals", "volatility", "fit")


test_that("every plot type returns a ggplot that builds, for both classes", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    for (ty in all_types) {
      p <- plot(fl[[nm]], type = ty)
      expect_s3_class(p, "ggplot")
      expect_warning(ggplot2::ggplot_build(p), regexp = NA)
    }
  }
})


test_that("the default type is the factor view, with one panel per factor", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    expect_equal(plot(fl[[nm]])$labels$title,
                 plot(fl[[nm]], type = "factor")$labels$title)
  }

  # ind_dfm has one factor and no facet; fcast_dfm(q = 2) has two panels
  expect_s3_class(plot(fl$ind_dfm)$facet, "FacetNull")
  expect_equal(nlevels(ggplot2::ggplot_build(plot(fl$fcast_dfm))$data[[1]]$PANEL), 2L)
})


test_that("plot() draws when called for its side effect", {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  fl <- plot_fits()
  for (ty in all_types) {
    expect_no_error(print(plot(fl$ind_dfm, type = ty)))
  }
})


test_that("an unknown type is an error that names the valid ones", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    expect_error(plot(fl[[nm]], type = "trace"), "should be one of")
    expect_error(plot(fl[[nm]], type = "trace"), "factor")
  }
})


test_that("level is validated and controls the band width", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    expect_error(plot(fl[[nm]], level = 1), "strictly between 0 and 1")
    expect_error(plot(fl[[nm]], level = 0), "strictly between 0 and 1")
    expect_error(plot(fl[[nm]], level = c(0.9, 0.95)), "strictly between 0 and 1")
    expect_error(plot(fl[[nm]], level = "95%"), "strictly between 0 and 1")

    wide <- ggplot2::ggplot_build(plot(fl[[nm]], level = 0.99))$data[[1]]
    narrow <- ggplot2::ggplot_build(plot(fl[[nm]], level = 0.5))$data[[1]]
    expect_true(all(wide$ymax - wide$ymin >= narrow$ymax - narrow$ymin))

    expect_match(plot(fl[[nm]], level = 0.5)$labels$subtitle, "50% credible band")
  }
})


test_that("the nowcast view overlays the observed target where it exists", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    p <- plot(fl[[nm]], type = "nowcast")
    expect_match(p$labels$title, fl[[nm]]$target, fixed = TRUE)

    # ribbon, nowcast line, observed points
    expect_equal(length(p$layers), 3L)

    obs <- ggplot2::ggplot_build(p)$data[[3]]
    expect_gt(nrow(obs), 0L)
    expect_false(any(is.na(obs$y)))
  }
})


test_that("the loadings view has one row per series and a facet per factor", {
  fl <- plot_fits()

  n_series <- nrow(fl$ind_dfm$inventory)

  p1 <- plot(fl$ind_dfm, type = "loadings")
  expect_equal(nlevels(p1$data$series), n_series)
  expect_s3_class(p1$facet, "FacetNull")

  p2 <- plot(fl$fcast_dfm, type = "loadings")
  expect_equal(nrow(p2$data), n_series * fl$fcast_dfm$pars$q)
  expect_equal(nlevels(ggplot2::ggplot_build(p2)$data[[3]]$PANEL),
               fl$fcast_dfm$pars$q)

  # the same series sits in the same row of every panel
  expect_equal(nlevels(p2$data$series), n_series)
})


test_that("residuals and fit views honour `series`, and reject a bad one", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    keys <- fl[[nm]]$inventory$key

    for (ty in c("residuals", "fit")) {
      p <- plot(fl[[nm]], type = ty, series = keys[1:2])
      expect_setequal(levels(p$data$series), keys[1:2])

      # numeric positions select the same series as the names do
      expect_equal(levels(plot(fl[[nm]], type = ty, series = 1:2)$data$series),
                   levels(p$data$series))

      expect_error(plot(fl[[nm]], type = ty, series = "not_a_series"),
                   "not in the fit")
      expect_error(plot(fl[[nm]], type = ty, series = 99), "out of range")
      expect_error(plot(fl[[nm]], type = ty, series = list("a")),
                   "character vector")
    }

    # unobserved periods are gaps, not zeros - the residuals() convention
    res <- plot(fl[[nm]], type = "residuals")$data
    expect_true(any(is.na(res$value)))
  }
})


test_that("the fit view separates observed from fitted", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    p <- plot(fl[[nm]], type = "fit")
    expect_setequal(unique(p$data$kind), c("observed", "fitted"))

    # the prepared data encodes missing as 0; those must not be drawn as zeros
    obs <- p$data[p$data$kind == "observed", ]
    expect_true(any(is.na(obs$value)))
    expect_false(any(obs$value == 0, na.rm = TRUE))
  }
})


test_that("the volatility view reports rather than draws a constant path", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  set.seed(3)
  no_sv <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                    length_sample = 8, burn_in = 4, plots = FALSE,
                                    stochastic_volatility = FALSE))

  expect_message(p <- plot(no_sv, type = "volatility"),
                 "stochastic_volatility = FALSE")
  expect_null(p)

  # every other view still works on such a fit
  for (ty in setdiff(all_types, "volatility")) {
    expect_s3_class(plot(no_sv, type = ty), "ggplot")
  }
})


test_that("autoplot() is an alias for plot()", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    for (ty in c("factor", "nowcast", "loadings")) {
      expect_equal(ggplot2::autoplot(fl[[nm]], type = ty)$data,
                   plot(fl[[nm]], type = ty)$data)
    }
  }
})


test_that("the shared style helpers are used by every view", {
  fl <- plot_fits()

  for (nm in names(fl)) {
    for (ty in setdiff(all_types, character(0))) {
      p <- plot(fl[[nm]], type = ty)
      # theme_mfbdfm() puts the legend at the bottom and drops its title
      expect_equal(p$theme$legend.position, "bottom")
    }
  }

  expect_length(mfbdfm_pal_discrete(3), 3L)
  expect_length(mfbdfm_pal_discrete(8), 8L)        # recycled, not dropped
  expect_true(all(c("estimate", "band", "observed") %in% names(mfbdfm_pal())))
})
