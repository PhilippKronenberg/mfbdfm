# The retained draws of R/draws.R: what the fit stores, that storing it changes
# nothing, and the trace/density plots over it.
#
# Short chains throughout - these test the container and the bookkeeping, not
# the sampler. The one thing that is NOT about chain length is the
# "changes nothing" block: that is the acceptance criterion of #110 and is
# checked by refitting with the same seed and comparing the whole object.

#' Two short fits, built once and reused across the blocks below.
#'
#' Memoized deliberately: nothing here mutates a fit, and fitting the pair
#' once per `test_that()` instead of once per file was most of this file's
#' run time.
draws_fits <- local({

  cache <- NULL

  function() {
    if (is.null(cache)) cache <<- build_draws_fits()
    cache
  }

})

build_draws_fits <- function() {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  set.seed(1)
  a <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                length_sample = 10, burn_in = 4, plots = FALSE))
  set.seed(2)
  b <- suppressMessages(suppressWarnings(
    fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2,
              length_sample = 8, burn_in = 3, plots = FALSE)))
  list(ind_dfm = a, fcast_dfm = b)
}


test_that("both fit classes store draws by default, with consistent shapes", {
  fl <- draws_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    d <- fit$draws

    expect_s3_class(d, "mfbdfm_draws")
    expect_equal(d$info$model, nm)
    expect_true(is.matrix(d$parameters))
    expect_equal(nrow(d$parameters), d$info$length_sample)
    expect_equal(nrow(d$nowcast), d$info$length_sample)
    expect_equal(ncol(d$nowcast), length(fit$nowcast))

    # one column per scalar parameter, every column named and classified
    expect_equal(ncol(d$parameters), length(d$info$blocks))
    expect_equal(colnames(d$parameters), names(d$info$blocks))
    expect_true(all(c("lambda", "phi", "sigma", "rho", "omega", "h") %in%
                      d$info$blocks))

    # factor paths are the one large component and are opt-in
    expect_null(d$factor)
  }
})


test_that("the stored means are the means of the stored draws", {
  fl <- draws_fits()

  # ind_dfm: lambda/phi/sigma/rho are plain vectors in $pars
  a <- fl$ind_dfm
  pa <- a$draws$parameters
  expect_equal(unname(colMeans(pa[, a$draws$info$blocks == "lambda"])),
               as.numeric(a$pars$lambda), tolerance = 1e-12)
  expect_equal(unname(colMeans(pa[, a$draws$info$blocks == "phi", drop = FALSE])),
               as.numeric(a$pars$phi), tolerance = 1e-12)
  expect_equal(unname(colMeans(pa[, a$draws$info$blocks == "sigma"])),
               as.numeric(a$pars$sigma), tolerance = 1e-12)
  expect_equal(unname(colMeans(a$draws$nowcast)), as.numeric(a$nowcast),
               tolerance = 1e-12)

  # fcast_dfm: the draws are the ROTATED ones, so the same identity holds -
  # if they were stored before rotation it would not
  b <- fl$fcast_dfm
  pb <- b$draws$parameters
  expect_equal(unname(colMeans(pb[, b$draws$info$blocks == "lambda"])),
               as.numeric(as.matrix(b$pars$lambda)), tolerance = 1e-12)
  expect_equal(unname(colMeans(pb[, b$draws$info$blocks == "phi", drop = FALSE])),
               as.numeric(unlist(lapply(b$pars$phi, as.numeric))),
               tolerance = 1e-12)
  expect_equal(unname(colMeans(b$draws$nowcast)), as.numeric(b$nowcast),
               tolerance = 1e-12)
})


test_that("retaining draws consumes no RNG and changes nothing else", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  fit_ind <- function(...) {
    set.seed(11)
    f <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                  length_sample = 8, burn_in = 4, plots = FALSE,
                                  control = dfm_control("ind_dfm", ...)))
    f$draws <- NULL
    f$call <- NULL
    f
  }

  base <- fit_ind()
  # identical(), not a tolerance: the draws are assembled from values the
  # sampler has already produced, so any difference at all would mean the
  # sampling loop itself had moved
  expect_identical(base, fit_ind(keep_draws = FALSE))
  expect_identical(base, fit_ind(keep_burn_in = TRUE))
  expect_identical(base, fit_ind(keep_factor_draws = TRUE))

  fit_fcast <- function(...) {
    set.seed(12)
    f <- suppressMessages(suppressWarnings(
      fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2,
                length_sample = 6, burn_in = 3, plots = FALSE,
                control = dfm_control("fcast_dfm", ...))))
    f$draws <- NULL
    f$call <- NULL
    f
  }

  expect_identical(fit_fcast(), fit_fcast(keep_draws = FALSE))
})


test_that("keep_draws = FALSE leaves no draws on the fit", {
  data(mfbdfm_example_data, envir = environment())
  set.seed(3)
  fit <- suppressMessages(
    ind_dfm(mfbdfm_example_data, length_sample = 6, burn_in = 3,
            control = dfm_control("ind_dfm", keep_draws = FALSE)))

  expect_null(fit$draws)
  expect_error(mfbdfm_diagnostics(fit), "carries no retained draws")
})


test_that("keep_factor_draws stores the factor on the fit's own scale", {
  data(mfbdfm_example_data, envir = environment())

  set.seed(4)
  a <- suppressMessages(
    ind_dfm(mfbdfm_example_data, length_sample = 8, burn_in = 3,
            control = dfm_control("ind_dfm", keep_factor_draws = TRUE)))

  expect_equal(ncol(a$draws$factor), length(a$factor))
  # the point of storing the rescaled, annualized path rather than the
  # sampler's internal one: colMeans() reproduces $factor
  expect_equal(unname(colMeans(a$draws$factor)), as.numeric(a$factor),
               tolerance = 1e-10)

  set.seed(5)
  b <- suppressMessages(suppressWarnings(
    fcast_dfm(mfbdfm_example_data, q = 2, length_sample = 6, burn_in = 3,
              control = dfm_control("fcast_dfm", keep_factor_draws = TRUE))))

  expect_equal(ncol(b$draws$factor), length(as.numeric(b$factor)))
  expect_equal(unname(colMeans(b$draws$factor)), as.numeric(b$factor),
               tolerance = 1e-10)
})


test_that("keep_burn_in prepends burn-in rows, on the sampler's own index", {
  data(mfbdfm_example_data, envir = environment())
  set.seed(6)
  fit <- suppressMessages(
    ind_dfm(mfbdfm_example_data, length_sample = 7, burn_in = 4, thinning = 2,
            control = dfm_control("ind_dfm", keep_burn_in = TRUE)))

  d <- fit$draws
  expect_equal(d$info$n_burn_in, 4L)
  expect_equal(nrow(d$parameters), 4L + 7L)
  # the burn-in rows are iterations 1..4; the kept rows follow the thinning
  expect_equal(d$info$iteration, c(1:4, 4 + 2*(1:7)))

  # derived quantities are retained draws only, deliberately
  expect_equal(nrow(d$nowcast), 7L)

  # and the diagnostics are computed on the posterior, not on the burn-in
  expect_equal(nrow(as.mcmc(d, which = "phi")), 7L)
})


test_that("keep_burn_in is an ind_dfm-only setting", {
  expect_error(dfm_control("fcast_dfm", keep_burn_in = TRUE),
               "Unknown control setting")
  expect_true(dfm_control("fcast_dfm")$keep_draws)
  expect_false(dfm_control("fcast_dfm")$keep_factor_draws)
  expect_false(dfm_control("ind_dfm")$keep_burn_in)
  expect_error(dfm_control("ind_dfm", keep_draws = "yes"),
               "`keep_draws` must be TRUE or FALSE")
})


test_that("the volatility columns follow how each model pins the scale", {
  data(mfbdfm_example_data, envir = environment())

  set.seed(7)
  a <- suppressMessages(
    ind_dfm(mfbdfm_example_data, length_sample = 6, burn_in = 3,
            stochastic_volatility = FALSE))
  # ind_dfm still ESTIMATES the constant variance, and omega is never drawn
  expect_true("factor_var" %in% colnames(a$draws$parameters))
  expect_false("omega" %in% colnames(a$draws$parameters))
  expect_equal(mean(a$draws$parameters[, "factor_var"]),
               a$pars_dist$factor_var$mean, tolerance = 1e-12)

  set.seed(8)
  b <- suppressMessages(suppressWarnings(
    fcast_dfm(mfbdfm_example_data, q = 1, length_sample = 6, burn_in = 3,
              stochastic_volatility = FALSE)))
  # there the variance is FIXED at one, so there is no volatility parameter
  expect_false(any(c("omega", "h_mean", "factor_var") %in%
                     colnames(b$draws$parameters)))
})


test_that("which = accepts names, blocks, positions and errors on the rest", {
  fl <- draws_fits()
  d <- fl$ind_dfm$draws

  expect_equal(draws_matrix(d, "phi"), d$parameters[, "phi1", drop = FALSE])
  expect_equal(ncol(draws_matrix(d, "parameters")), ncol(d$parameters))
  expect_equal(ncol(draws_matrix(d, "all")),
               ncol(d$parameters) + ncol(d$nowcast))
  expect_equal(colnames(draws_matrix(d, c("omega", "phi"))),
               c("omega", "phi1"))
  expect_equal(colnames(draws_matrix(d, 1:2)), colnames(d$parameters)[1:2])

  # duplicates collapse rather than producing two identical panels
  expect_equal(ncol(draws_matrix(d, c("phi", "phi1"))), 1L)

  expect_error(draws_matrix(d, "nonsense"), "neither a draw column nor a block")
  expect_error(draws_matrix(d, 999), "must index the available draw columns")
  expect_error(draws_matrix(d, list("phi")), "must be a character vector")

  # the default is a readable handful, and skips the columns that are pinned
  # rather than drawn
  def <- colnames(draws_matrix(d))
  expect_lt(length(def), ncol(d$parameters))
  expect_true("phi1" %in% def)
  expect_false(paste0("lambda[", fl$ind_dfm$target, "]") %in% def)
})


test_that("print, as.data.frame and as.mcmc describe the same chain", {
  fl <- draws_fits()
  d <- fl$fcast_dfm$draws

  expect_output(print(d), "Retained posterior draws of a fcast_dfm fit")
  expect_output(print(d), "not kept \\(keep_factor_draws = FALSE\\)")

  df <- as.data.frame(d, which = c("phi", "omega"))
  expect_named(df, c("parameter", "iteration", "value", "phase"))
  expect_equal(nrow(df), 5L * d$info$length_sample)
  expect_true(all(df$phase == "sampling"))

  m <- as.mcmc(d, which = "omega")
  expect_s3_class(m, "mcmc")
  expect_equal(nrow(m), d$info$length_sample)
  expect_equal(stats::start(m), d$info$burn_in + d$info$thinning)
})


test_that("plot() on the draws returns ggplot objects for every type", {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  fl <- draws_fits()
  d <- fl$ind_dfm$draws

  expect_s3_class(plot(d, which = "phi", type = "trace"), "ggplot")
  expect_s3_class(plot(d, which = "phi", type = "density"), "ggplot")
  expect_s3_class(plot(d, which = c("phi", "omega")), "ggarrange")

  # a constant chain has no density to estimate; it must not error
  expect_s3_class(
    plot(d, which = paste0("lambda[", fl$ind_dfm$target, "]"),
         type = "density"),
    "ggplot")

  # too many panels is truncated with a warning rather than drawn unreadably
  expect_warning(p <- plot(d, which = "all", max_panels = 3),
                 "showing the first 3")
  expect_s3_class(p, "ggarrange")

  expect_error(plot(d, which = "phi", level = 2), "`level` must be a single")
})
