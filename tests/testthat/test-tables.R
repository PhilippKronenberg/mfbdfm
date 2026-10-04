# The table builders in R/tables.R, plus the $pars_dist component they read
# and the original-scale option on fitted()/residuals().
#
# Short chains throughout: these test the tabulation, not the sampler. Both
# classes and both stochastic-volatility branches are covered, because the
# volatility block of the parameters table is the one place where what is
# reported differs between them.

table_fits <- function() {
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

no_sv_fits <- function() {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2021)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2021)

  set.seed(3)
  a <- suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                                length_sample = 8, burn_in = 4, plots = FALSE,
                                stochastic_volatility = FALSE))
  set.seed(4)
  b <- suppressMessages(suppressWarnings(
    fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2,
              length_sample = 6, burn_in = 3, plots = FALSE,
              stochastic_volatility = FALSE)))
  list(ind_dfm = a, fcast_dfm = b)
}


test_that("both classes store a $pars_dist with the blocks they can report", {
  fl <- table_fits()

  for (nm in names(fl)) {
    d <- fl[[nm]]$pars_dist
    expect_false(is.null(d))
    expect_equal(d$probs, c(0.025, 0.975))

    for (blk in c("lambda", "phi", "sigma", "rho", "h")) {
      expect_setequal(names(d[[blk]]), c("sd", "lower", "upper"))
      expect_true(all(d[[blk]]$sd >= 0))
      expect_true(all(d[[blk]]$lower <= d[[blk]]$upper))
    }

    # the mean is NOT duplicated here - it stays the single value in $pars, so
    # a table cannot disagree with coef() in the last bit
    expect_null(d$lambda$mean)
  }

  # omega is drawn but not retained in the multi-factor model, so there is no
  # posterior summary of it to report
  expect_false(is.null(fl$ind_dfm$pars_dist$omega))
  expect_null(fl$fcast_dfm$pars_dist$omega)

  # with stochastic volatility ON neither model has a constant factor variance
  expect_null(fl$ind_dfm$pars_dist$factor_var)
  expect_null(fl$fcast_dfm$pars_dist$factor_var)

  # $pars_dist$h is aligned with $pars$h period for period
  for (nm in names(fl)) {
    expect_equal(length(fl[[nm]]$pars_dist$h$sd), length(fl[[nm]]$pars$h))
  }
})


test_that("the loadings table's means are exactly coef()", {
  fl <- table_fits()

  tab <- mfbdfm_table_loadings(fl$ind_dfm)
  expect_s3_class(tab, "data.frame")
  expect_identical(tab$mean, unname(coef(fl$ind_dfm)))
  expect_identical(tab$series, fl$ind_dfm$inventory$key)
  expect_equal(nrow(tab), nrow(fl$ind_dfm$inventory))

  # one row per series AND factor for the multi-factor model, in the loading
  # matrix's own column-major order
  tab2 <- mfbdfm_table_loadings(fl$fcast_dfm)
  lam <- coef(fl$fcast_dfm)
  expect_equal(nrow(tab2), nrow(lam) * ncol(lam))
  expect_identical(tab2$mean, as.numeric(lam))
  expect_setequal(unique(tab2$factor), colnames(lam))

  # the `factor` column is present for both classes (the parity rule)
  expect_true("factor" %in% names(tab))
  expect_equal(unique(tab$factor), "factor1")
})


test_that("the ind_dfm target loading is flagged as fixed, and only that one", {
  fl <- table_fits()

  tab <- mfbdfm_table_loadings(fl$ind_dfm)
  expect_true(tab$fixed[tab$series == fl$ind_dfm$target])
  expect_false(any(tab$fixed[tab$series != fl$ind_dfm$target]))

  # it is fixed at exactly 1 by the identifying restriction, so it has no
  # posterior spread
  expect_equal(tab$mean[tab$fixed], 1)
  expect_equal(tab$sd[tab$fixed], 0)

  # fcast_dfm has no fixed loading - identification there is post-hoc rotation
  expect_false(any(mfbdfm_table_loadings(fl$fcast_dfm)$fixed))
})


test_that("the original loading scale round-trips against the inventory", {
  fl <- table_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    std <- mfbdfm_table_loadings(fit)
    org <- mfbdfm_table_loadings(fit, scale = "original")

    sds <- fit$inventory$sd[match(std$series, fit$inventory$key)]
    for (col in c("mean", "sd", "lower", "upper")) {
      expect_equal(org[[col]], std[[col]] * sds)
    }
    # the series mean is an intercept, not a slope, so it must not enter
    expect_equal(org$mean / sds, std$mean)
  }

  # a loading fixed at 1 converts to the target's own standard deviation
  fit <- fl$ind_dfm
  org <- mfbdfm_table_loadings(fit, scale = "original")
  expect_equal(org$mean[org$fixed],
               fit$inventory$sd[fit$inventory$key == fit$target])

  expect_error(mfbdfm_table_loadings(fit, scale = "raw"), "should be one of")
})


test_that("the parameters table reports every block in $pars, and no other", {
  fl <- table_fits()

  tab <- mfbdfm_table_parameters(fl$ind_dfm)
  expect_setequal(unique(tab$block), c("phi", "sigma", "rho", "omega"))
  expect_equal(tab$mean[tab$block == "sigma"], as.numeric(fl$ind_dfm$pars$sigma))
  expect_equal(tab$mean[tab$block == "rho"], as.numeric(fl$ind_dfm$pars$rho))
  expect_equal(tab$mean[tab$block == "phi"], as.numeric(fl$ind_dfm$pars$phi))
  expect_equal(tab$mean[tab$block == "omega"], as.numeric(fl$ind_dfm$pars$omega))
  expect_equal(tab$series[tab$block == "sigma"], fl$ind_dfm$inventory$key)

  # the structural priors of ind_dfm are the target's own sigma and rho - the
  # two dfm_priors() also calls structural
  for (blk in c("sigma", "rho")) {
    rows <- tab[tab$block == blk, ]
    expect_true(rows$structural[rows$series == fl$ind_dfm$target])
    expect_false(any(rows$structural[rows$series != fl$ind_dfm$target]))
  }
  expect_false(any(tab$fixed))

  # fcast_dfm: a q x q phi block per lag, no omega row (it is never retained),
  # and no structural flag (its structural prior is on the loadings)
  tab2 <- mfbdfm_table_parameters(fl$fcast_dfm)
  expect_setequal(unique(tab2$block), c("phi", "sigma", "rho"))
  q <- fl$fcast_dfm$pars$q
  expect_equal(sum(tab2$block == "phi"), length(fl$fcast_dfm$pars$phi) * q^2)
  expect_equal(tab2$mean[tab2$block == "phi"],
               unlist(lapply(fl$fcast_dfm$pars$phi, as.numeric)))
  expect_false(any(tab2$structural))
})


test_that("the volatility block reflects which branch the fit actually took", {
  fl <- no_sv_fits()

  # ind_dfm estimates a constant factor variance when SV is off (its loadings
  # carry the identification), and omega is never drawn, so omega must not be
  # reported from its untouched start value
  tab <- mfbdfm_table_parameters(fl$ind_dfm)
  expect_true("factor_var" %in% tab$block)
  expect_false("omega" %in% tab$block)
  expect_null(fl$ind_dfm$pars_dist$omega)

  fv <- tab[tab$block == "factor_var", ]
  expect_false(fv$fixed)                   # estimated, not imposed
  expect_gt(fv$sd, 0)
  expect_gt(fv$mean, 0)
  # `h` is the log sd of the (constant) factor innovation, so the variance is
  # exp(2h) and what is reported is its POSTERIOR MEAN - the mean of exp(2h)
  # over draws, not exp(2h) at the mean of h. The two differ by Jensen's
  # inequality, and the convex direction is why this is a lower bound.
  expect_gte(fv$mean, exp(2 * mean(as.numeric(fl$ind_dfm$pars$h))))
  expect_lt(fv$lower, fv$upper)

  # fcast_dfm fixes the variance at exactly 1 instead - there it carries the
  # identification
  tab2 <- mfbdfm_table_parameters(fl$fcast_dfm)
  fv2 <- tab2[tab2$block == "factor_var", ]
  expect_equal(fv2$mean, 1)
  expect_equal(fv2$sd, 0)
  expect_true(fv2$fixed)
  expect_true(fv2$structural)
})


test_that("the nowcast table matches the stored nowcast and its variance", {
  fl <- table_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    tab <- mfbdfm_table_nowcast(fit)

    expect_named(tab, c("time", "observed", "nowcast", "sd", "lower", "upper"))
    expect_equal(tab$nowcast, as.numeric(fit$nowcast))
    expect_equal(tab$sd, sqrt(as.numeric(fit$nowcast_var)))
    expect_equal(tab$time, as.numeric(stats::time(fit$nowcast)))

    # a symmetric 95% normal band around the mean
    expect_equal(tab$upper - tab$nowcast, tab$nowcast - tab$lower)
    expect_equal(tab$upper - tab$lower, 2 * stats::qnorm(0.975) * tab$sd)

    # the observed target lines up where the series covers the period
    obs <- fit$data_raw[[fit$target]]
    expect_true(any(!is.na(tab$observed)))
    hit <- match(round(tab$time, 5), round(as.numeric(stats::time(obs)), 5))
    expect_equal(tab$observed, as.numeric(obs)[hit])
  }
})


test_that("every format renders, and the data frame stays unrounded", {
  fl <- table_fits()
  builders <- list(mfbdfm_table_loadings, mfbdfm_table_parameters,
                   mfbdfm_table_nowcast)

  for (build in builders) {
    expect_s3_class(build(fl$ind_dfm), "data.frame")
    for (fmt in c("latex", "html", "markdown")) {
      out <- build(fl$ind_dfm, format = fmt)
      expect_s3_class(out, "knitr_kable")
      expect_true(length(out) > 0)
    }
  }

  # digits affects the rendered output only; the data frame is the primary
  # return value and must not be lossy
  tab <- mfbdfm_table_loadings(fl$fcast_dfm, digits = 2)
  expect_false(isTRUE(all.equal(tab$mean, round(tab$mean, 2))))

  expect_true(any(grepl("caption", mfbdfm_table_loadings(
    fl$ind_dfm, format = "html", caption = "Loadings"), fixed = TRUE)))

  expect_error(mfbdfm_table_loadings(fl$ind_dfm, format = "docx"),
               "should be one of")
})


test_that("mfbdfm_kable renders a plain data frame and rejects non-frames", {
  df <- data.frame(series = c("a", "b"), mean = c(1.23456789, 2))

  out <- mfbdfm_kable(df, format = "markdown", digits = 3)
  expect_s3_class(out, "knitr_kable")
  expect_true(any(grepl("1.235", out, fixed = TRUE)))
  # row.names = FALSE, so the row numbers do not become a column
  expect_false(any(grepl("|1 ", out, fixed = TRUE)))

  expect_error(mfbdfm_kable(1:3), "must be a data frame")
  expect_error(mfbdfm_kable(df, digits = 2.5), "non-negative integer")
})


test_that("the table builders reject anything that is not a fit", {
  for (build in list(mfbdfm_table_loadings, mfbdfm_table_parameters,
                     mfbdfm_table_nowcast)) {
    expect_error(build(list(pars = list())), "must be a fit from")
    expect_error(build(42), "must be a fit from")
  }
})


test_that("a fit without $pars_dist still tabulates, with NA uncertainty", {
  fl <- table_fits()

  for (nm in names(fl)) {
    old <- fl[[nm]]
    old$pars_dist <- NULL

    tab <- mfbdfm_table_loadings(old)
    expect_identical(tab$mean, mfbdfm_table_loadings(fl[[nm]])$mean)
    expect_true(all(is.na(tab$sd)))
    expect_true(all(is.na(tab$lower)))

    par <- mfbdfm_table_parameters(old)
    expect_true(all(is.na(par$sd)))
    # the means are still the real ones
    expect_equal(par$mean[par$block == "sigma"], as.numeric(old$pars$sigma))
  }
})


test_that("fitted() and residuals() convert to the original scale", {
  fl <- table_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    sds <- fit$inventory$sd
    mns <- fit$inventory$mean

    # default is unchanged
    expect_identical(fitted(fit), fitted(fit, scale = "standardized"))
    expect_identical(residuals(fit), residuals(fit, scale = "standardized"))
    expect_identical(fitted(fit), fit$data_augmented)

    f0 <- as.matrix(fitted(fit))
    f1 <- fitted(fit, scale = "original")
    # prepare_data() standardizes as (x - mean)/sd, so both moments come back
    expect_equal(as.matrix(f1), sweep(sweep(f0, 2, sds, "*"), 2, mns, "+"))
    expect_equal(stats::tsp(f1), stats::tsp(fitted(fit)))
    expect_equal(dim(f1), dim(fit$data))

    r0 <- as.matrix(residuals(fit))
    r1 <- residuals(fit, scale = "original")
    # a residual is a difference, so only the scale factor applies
    expect_equal(as.matrix(r1), sweep(r0, 2, sds, "*"))
    # NA-masking of unobserved periods is unchanged by rescaling
    expect_identical(is.na(as.matrix(r1)), is.na(r0))

    expect_error(fitted(fit, scale = "percent"), "should be one of")
    expect_error(residuals(fit, scale = "percent"), "should be one of")
  }
})


test_that("summary() carries the tables and prints the same numbers", {
  fl <- table_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    s <- summary(fit)

    expect_identical(s$loadings_table, mfbdfm_table_loadings(fit))
    expect_identical(s$parameters_table, mfbdfm_table_parameters(fit))

    # the printed numbers come from those tables, so a printed summary and a
    # tabulated one cannot disagree
    out <- utils::capture.output(print(s))
    lam <- s$loadings_table$mean[!s$loadings_table$fixed][1]
    expect_true(any(grepl(format(round(lam, 4), nsmall = 4), out, fixed = TRUE)))

    # the old fields stay for compatibility
    expect_false(is.null(s$loadings))
    expect_false(is.null(s$sigma))
  }
})
