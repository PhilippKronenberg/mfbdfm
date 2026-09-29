# The decomposition is exact by construction, so these tests check that
# arithmetic rather than a stored value: contributions must sum to the plug-in
# smoothed factor, and a series the factor does not load on must contribute
# nothing. Short chains throughout - this tests the decomposition, not the
# sampler.

contrib_fits <- function() {
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

test_that("contributions sum to the plug-in smoothed factor, for both classes", {
  fl <- contrib_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    ct <- mfbdfm_contributions(fit)

    expect_s3_class(ct, "mfbdfm_contributions")
    expect_equal(ct$model, nm)
    expect_equal(ct$by, "series")
    expect_setequal(ct$components, fit$inventory$key)
    expect_equal(ct$q, if (nm == "fcast_dfm") fit$pars$q else 1L)

    d <- as.data.frame(ct)
    expect_named(d, c("time", "series", "factor", "contribution"))
    expect_true(all(is.finite(d$contribution)))

    # one decomposition per factor, and each of them exact
    expect_setequal(unique(d$factor), paste0("factor", seq_len(ct$q)))

    for (fl_lab in unique(d$factor)) {
      dd <- d[d$factor == fl_lab, ]
      tt <- ct$totals[ct$totals$factor == fl_lab, ]
      agg <- as.numeric(tapply(dd$contribution, dd$time, sum))
      expect_equal(agg, tt$plugin[order(tt$time)], tolerance = 1e-8)
    }

    # the residual is reported rather than folded into a series
    expect_equal(ct$totals$residual, ct$totals$posterior - ct$totals$plugin)
  }
})

test_that("the reported time axis covers the whole factor path", {
  fl <- contrib_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    ct <- mfbdfm_contributions(fit)

    k <- max(fit$inventory$freq) / min(fit$inventory$freq)
    s <- 2 * (k - 1)
    tms <- unique(ct$totals$time)
    expect_length(tms, nrow(fit$data) + s)

    # the in-sample periods line up with the prepared data
    expect_equal(utils::tail(tms, nrow(fit$data)),
                 as.numeric(stats::time(fit$data)), tolerance = 1e-6)

    # ind_dfm() stores only the t in-sample periods (#49), so the posterior is
    # unavailable for the s pre-sample ones rather than guessed
    if (nm == "ind_dfm") {
      expect_true(all(is.na(utils::head(ct$totals$posterior, s))))
      expect_true(all(is.finite(utils::tail(ct$totals$posterior,
                                           nrow(fit$data)))))
    } else {
      expect_true(all(is.finite(ct$totals$posterior)))
    }
  }
})

test_that("a series with a zero loading contributes nothing", {
  fl <- contrib_fits()

  fit <- fl$ind_dfm
  j <- which(fit$inventory$key == "SWISSMI")
  fit$pars$lambda[j] <- 0

  ct <- mfbdfm_contributions(fit)
  d <- as.data.frame(ct)
  expect_true(all(abs(d$contribution[d$series == "SWISSMI"]) < 1e-10))

  # and the remaining series still account for the whole factor
  agg <- as.numeric(tapply(d$contribution, d$time, sum))
  expect_equal(agg, ct$totals$plugin, tolerance = 1e-8)
})

test_that("nowcast contributions split the target's smoothed value exactly", {
  fl <- contrib_fits()

  for (nm in names(fl)) {
    fit <- fl[[nm]]
    ct <- mfbdfm_contributions(fit)

    dn <- as.data.frame(ct, what = "nowcast")
    expect_named(dn, c("time", "series", "contribution"))

    tot <- ct$nowcast_totals
    agg <- as.numeric(tapply(dn$contribution, dn$time, sum))
    expect_equal(agg, tot$systematic, tolerance = 1e-8)
    expect_equal(tot$plugin, tot$systematic + tot$idiosyncratic)

    # the target's own periods, and the same ones the fit reports a nowcast for
    expect_equal(nrow(tot), length(fit$nowcast))
    expect_true(all(is.finite(tot$posterior)))

    # the nowcast is dominated by the observation where there is one, so the
    # plug-in and the posterior mean agree closely in sample
    expect_equal(tot$plugin, tot$posterior, tolerance = 1e-3)
  }
})

test_that("by = 'group' aggregates the series decomposition", {
  fit <- contrib_fits()$ind_dfm

  keys <- fit$inventory$key
  grp <- ifelse(keys == fit$target, "target", "indicators")
  names(grp) <- keys

  bys <- mfbdfm_contributions(fit)
  byg <- mfbdfm_contributions(fit, by = "group", groups = grp)

  expect_equal(byg$by, "group")
  expect_setequal(byg$components, c("target", "indicators"))
  expect_named(as.data.frame(byg), c("time", "group", "factor", "contribution"))

  # grouping is a column sum, so the totals cannot move
  expect_equal(byg$totals$plugin, bys$totals$plugin, tolerance = 1e-8)
  expect_equal(byg$nowcast_totals$systematic, bys$nowcast_totals$systematic,
               tolerance = 1e-8)

  ds <- as.data.frame(bys)
  dg <- as.data.frame(byg)
  own <- ds$contribution[ds$series == fit$target]
  expect_equal(dg$contribution[dg$group == "target"], own, tolerance = 1e-8)
})

test_that("a group column on the inventory is used when there is one", {
  fit <- contrib_fits()$ind_dfm
  fit$inventory$group <- ifelse(fit$inventory$type == "flow", "flows", "stocks")

  ct <- mfbdfm_contributions(fit, by = "group")
  expect_setequal(ct$components, c("flows", "stocks"))
})

test_that("one group is still a decomposition, and still plots", {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  fit <- contrib_fits()$ind_dfm
  one <- rep("all", nrow(fit$inventory))
  names(one) <- fit$inventory$key

  ct <- mfbdfm_contributions(fit, by = "group", groups = one)
  expect_equal(ct$components, "all")
  # with a single group the contribution IS the plug-in factor
  expect_equal(as.data.frame(ct)$contribution, ct$totals$plugin,
               tolerance = 1e-8)
  expect_identical(plot(ct), ct)

  expect_error(mfbdfm_contributions(fit, by = "group", groups = unname(one)),
               "NAMED")
})

test_that("a missing or incomplete grouping is an error naming the argument", {
  fit <- contrib_fits()$ind_dfm

  expect_error(mfbdfm_contributions(fit, by = "group"), "`groups`")

  partial <- c("target")
  names(partial) <- fit$target
  expect_error(mfbdfm_contributions(fit, by = "group", groups = partial),
               "missing an entry")

  expect_error(mfbdfm_contributions(fit$data), "ind_dfm")
  expect_error(mfbdfm_contributions(fit, by = "everything"), "'arg'")
})

test_that("print and plot run on both classes and both quantities", {
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  fl <- contrib_fits()

  for (nm in names(fl)) {
    ct <- mfbdfm_contributions(fl[[nm]])

    expect_output(print(ct), "Contributions to the factor")
    expect_output(print(ct), ct$model)
    expect_output(print(ct), "Mean absolute contribution")

    for (qx in seq_len(ct$q))
      expect_identical(plot(ct, factor = qx), ct)
    expect_identical(plot(ct, what = "nowcast"), ct)
    expect_error(plot(ct, factor = ct$q + 1), "index into")
  }
})
