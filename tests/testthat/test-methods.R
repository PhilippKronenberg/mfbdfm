# Both fit classes must support the same generics (the parity rule in
# CLAUDE.md). Kept to short chains: these test the methods, not the sampler.

fits <- function() {
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

test_that("both classes support the same generics", {
  fl <- fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]

    expect_s3_class(fit, nm)
    expect_false(is.null(fit$call))            # match.call() is stored

    expect_true(is.numeric(as.matrix(coef(fit))))
    expect_equal(nrow(as.matrix(coef(fit))), nrow(fit$inventory))

    expect_equal(dim(fitted(fit)), dim(fit$data))
    expect_equal(dim(residuals(fit)), dim(fit$data))

    df <- as.data.frame(fit)
    expect_s3_class(df, "data.frame")
    expect_true("time" %in% names(df))

    expect_s3_class(summary(fit), "summary.mfbdfm_fit")
  }
})

test_that("both classes agree on what $data and $data_raw mean (#50)", {
  fl <- fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]

    # $data is the PREPARED matrix in both classes
    expect_true(is.matrix(fit$data) || inherits(fit$data, "mts"))
    expect_false(is.null(colnames(fit$data)))
    expect_equal(ncol(fit$data), nrow(fit$inventory))

    # $data_raw is the series as supplied, in both classes
    expect_true(is.list(fit$data_raw))
    expect_false(is.null(names(fit$data_raw)))
    expect_setequal(names(fit$data_raw), fit$inventory$key)
    expect_true(all(vapply(fit$data_raw, stats::is.ts, logical(1))))

    # the old fcast_dfm-only name is gone
    expect_null(fit$data_missings)
  }

  # and the same expression means the same thing for both - the failure mode
  # that motivated this was length(fit$data) returning 1250 for one class and
  # 5 for the other
  expect_equal(ncol(fl$ind_dfm$data), ncol(fl$fcast_dfm$data))
  expect_equal(length(fl$ind_dfm$data_raw), length(fl$fcast_dfm$data_raw))
})

test_that("residuals are NA exactly where the series was not observed", {
  fl <- fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    obs <- fit$data
    res <- residuals(fit)

    # 0 encodes "missing" in the prepared data - a residual there would be
    # spurious, so it must be NA rather than obs - fitted
    expect_true(all(is.na(res[obs == 0])))
    expect_true(all(is.finite(res[obs != 0])))
    expect_equal(sum(is.na(res)), sum(obs == 0))
  }
})

test_that("as.data.frame gives ordered 95% bands", {
  fl <- fits()

  for (nm in names(fl)) {
    df <- as.data.frame(fl[[nm]])
    cols <- setdiff(names(df), "time")
    means <- cols[!grepl("_lower$|_upper$", cols)]

    for (m in means) {
      expect_true(all(df[[paste0(m, "_lower")]] <= df[[m]]))
      expect_true(all(df[[m]] <= df[[paste0(m, "_upper")]]))
    }
  }
})

test_that("coef reflects the identifying restriction in ind_dfm", {
  fit <- fits()$ind_dfm
  # lambda on the target is fixed to 1 during sampling
  expect_equal(unname(coef(fit)[fit$target]), 1)
})

test_that("summary reports a per-series R-squared for both classes (#99)", {
  fl <- fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    r2 <- summary(fit)$r_squared

    expect_s3_class(r2, "data.frame")
    expect_named(r2, c("series", "freq", "n_obs", "r_squared"))
    expect_setequal(r2$series, fit$inventory$key)
    expect_equal(nrow(r2), nrow(fit$inventory))

    # 1 is the ceiling; there is no floor, since the common component is not a
    # least-squares fit to each series
    expect_true(all(r2$r_squared <= 1))
    expect_false(anyNA(r2$r_squared))

    # sorted best-first, so print() can take the ends
    expect_equal(r2$r_squared, sort(r2$r_squared, decreasing = TRUE))

    # missing observations are excluded: 0 encodes missing, and the quarterly
    # target is observed in a small fraction of the weekly periods
    obs_counts <- colSums(fit$data != 0)
    expect_equal(r2$n_obs, unname(obs_counts[r2$series]))
    expect_lt(r2$n_obs[r2$series == fit$target], nrow(fit$data))
  }
})

# A hand-built ind_dfm-shaped object with a KNOWN factor: one series is exactly
# the common component, the other is independent noise. Every series is at the
# same frequency, so k = 1 and the temporal aggregation reduces to a weight of 1
# at lag 0 - which is what makes the expected R-squared exactly 1 and 0 rather
# than "whatever a short chain converged to".
synth_r2_fit <- function(seed = 11, t = 200) {
  set.seed(seed)
  f <- as.numeric(stats::filter(stats::rnorm(t), 0.7, method = "recursive"))

  dat <- cbind(driven = 1.5 * f, noise = stats::rnorm(t))
  dat[1:10, "noise"] <- 0          # 0 encodes "not observed"

  structure(
    list(factor_std = stats::ts(f, start = c(2000, 1), frequency = 12),
         pars = list(lambda = matrix(c(1.5, 0), ncol = 1),
                     sigma = c(1e-9, 1), rho = c(0, 0), phi = 0.7),
         data = stats::ts(dat, start = c(2000, 1), frequency = 12),
         data_augmented = stats::ts(dat, start = c(2000, 1), frequency = 12),
         inventory = data.frame(key = c("driven", "noise"),
                                type = factor("flow",
                                              levels = c("stock", "flow")),
                                freq = c(12, 12), stringsAsFactors = FALSE),
         target = "driven"),
    class = "ind_dfm")
}

test_that("R-squared separates a factor-driven series from pure noise (#99)", {
  fit <- synth_r2_fit()
  r2 <- summary(fit)$r_squared
  get <- function(k) r2$r_squared[r2$series == k]

  # `driven` IS the common component, so nothing is left over
  expect_equal(get("driven"), 1)
  # `noise` loads on nothing, so the common component explains none of it
  expect_equal(get("noise"), 0)

  # missing observations are excluded, not treated as observed zeros
  expect_equal(r2$n_obs[r2$series == "noise"], 190)
  expect_equal(r2$n_obs[r2$series == "driven"], 200)

  expect_output(print(summary(fit)), "R-squared of the common component")
})

test_that("R-squared is reported as absent for a fit that predates it", {
  fit <- synth_r2_fit()
  fit$factor_std <- NULL          # as an object saved before #99 would be

  s <- summary(fit)
  expect_null(s$r_squared)
  expect_output(print(s), "residual RMSE")   # the rest still prints
})

test_that("ind_dfm's target R-squared is ~1 by construction (#99)", {
  # the one value-level assertion that needs a real chain: the target's loading
  # is fixed to 1 and its measurement error shrunk towards zero to identify the
  # factor, so its R-squared is identification showing through rather than a
  # finding - which is what print() warns about. Synthetic data with a known
  # weekly factor, aggregated to a quarterly target.
  set.seed(5)
  freq <- 48
  tt <- freq * 5
  f <- as.numeric(stats::filter(stats::rnorm(tt), 0.8, method = "recursive"))

  flows <- list(gdp = stats::ts(colSums(matrix(f, nrow = freq/4)),
                                start = c(2015, 1), frequency = 4),
                signal = stats::ts(f + stats::rnorm(tt, 0, 0.05),
                                   start = c(2015, 1), frequency = freq))
  stocks <- list(noise = stats::ts(stats::rnorm(tt),
                                   start = c(2015, 1), frequency = freq))

  set.seed(3)
  fit <- suppressMessages(ind_dfm(flows = flows, stocks = stocks,
                                  target = "gdp", length_sample = 100,
                                  burn_in = 50, plots = FALSE))

  r2 <- summary(fit)$r_squared
  get <- function(k) r2$r_squared[r2$series == k]

  expect_gt(get("gdp"), 0.9)
  expect_output(print(summary(fit)), "by construction")

  # the indicator that carries the factor still beats the one that does not,
  # though both are small: the factor's scale is pinned by the target, so a
  # weekly series' common component is necessarily a fraction of its variance
  expect_gt(get("signal"), get("noise"))
})

test_that("print, summary and plot work and return invisibly", {
  fl <- fits()
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  for (nm in names(fl)) {
    fit <- fl[[nm]]

    expect_output(print(fit), "dynamic factor model")
    expect_false(withVisible(print(fit))$visible)

    expect_output(print(summary(fit)), "Factor loadings")
    expect_output(print(summary(fit)), "residual RMSE")

    expect_false(withVisible(plot(fit))$visible)
  }
})

test_that("plot restores the caller's graphics state", {
  fit <- fits()$fcast_dfm
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  graphics::par(mfrow = c(2, 3))
  before <- graphics::par("mfrow")
  invisible(plot(fit))
  expect_identical(graphics::par("mfrow"), before)
})
