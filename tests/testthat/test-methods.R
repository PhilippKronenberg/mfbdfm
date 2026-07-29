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

    expect_equal(dim(fitted(fit)), dim(prepared_data(fit)))
    expect_equal(dim(residuals(fit)), dim(prepared_data(fit)))

    df <- as.data.frame(fit)
    expect_s3_class(df, "data.frame")
    expect_true("time" %in% names(df))

    expect_s3_class(summary(fit), "summary.mfbdfm_fit")
  }
})

test_that("residuals are NA exactly where the series was not observed", {
  fl <- fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    obs <- prepared_data(fit)
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
