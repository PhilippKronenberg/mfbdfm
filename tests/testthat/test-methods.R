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

test_that("mfbdfm_nowcast returns the stored nowcasts for both classes", {
  fl <- fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    nc <- mfbdfm_nowcast(fit)

    expect_s3_class(nc, "data.frame")
    expect_named(nc, c("time", "nowcast", "sd", "lower", "upper"))

    # the values are the stored ones, not a recomputation
    expect_equal(nc$nowcast, as.numeric(fit$nowcast))
    expect_equal(nc$time, as.numeric(stats::time(fit$nowcast)))
    expect_equal(nc$sd, sqrt(as.numeric(fit$nowcast_var)))

    # bands are ordered and symmetric about the mean
    expect_true(all(nc$lower <= nc$nowcast))
    expect_true(all(nc$nowcast <= nc$upper))
    expect_equal(nc$upper - nc$nowcast, nc$nowcast - nc$lower)

    # last = TRUE is the final period, and only that
    lastrow <- mfbdfm_nowcast(fit, last = TRUE)
    expect_equal(nrow(lastrow), 1L)
    expect_equal(lastrow$nowcast, as.numeric(utils::tail(fit$nowcast, 1)))
    expect_equal(lastrow, nc[nrow(nc), , drop = FALSE], ignore_attr = TRUE)

    # a narrower level gives a narrower band, same mean
    narrow <- mfbdfm_nowcast(fit, level = 0.5)
    expect_equal(narrow$nowcast, nc$nowcast)
    expect_true(all(narrow$upper - narrow$lower <= nc$upper - nc$lower))
    expect_true(any(narrow$upper - narrow$lower < nc$upper - nc$lower))
  }
})

test_that("mfbdfm_nowcast rejects bad last/level values by name", {
  fit <- fits()$ind_dfm

  expect_error(mfbdfm_nowcast(fit, last = "yes"), "`last`")
  expect_error(mfbdfm_nowcast(fit, last = c(TRUE, FALSE)), "`last`")
  expect_error(mfbdfm_nowcast(fit, level = 0), "`level`")
  expect_error(mfbdfm_nowcast(fit, level = 1), "`level`")
  expect_error(mfbdfm_nowcast(fit, level = "95%"), "`level`")
})

test_that("coef reflects the identifying restriction in ind_dfm", {
  fit <- fits()$ind_dfm
  # lambda on the target is fixed to 1 during sampling
  expect_equal(unname(coef(fit)[fit$target]), 1)
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
