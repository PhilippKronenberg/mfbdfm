## tests for R/news.R -- the news decomposition of a nowcast revision

# One monthly fixture, two vintages, fitted once: the old vintage stops two
# months earlier than the new one, and the quarterly target is identical in
# both. Leaving the target alone is the point -- when the target's own release
# is part of the news its gain is exactly 1 and it absorbs the whole revision,
# which is a correct answer to a dull question. Here the indicators carry it.
news_fixture <- function(seed = 5, years = 6, lag = 2, length_sample = 30) {

  pan <- make_synth_mm_panel(seed = seed, years = years)
  cut_last <- function(x, k) stats::window(x, end = stats::time(x)[length(x) - k])

  # two quarters short of the indicators, so the old vintage already has a
  # latent target period of its own -- the pure-revision test needs one
  gdp <- cut_last(pan$flows$gdp, 2)

  old <- list(flows = c(list(gdp = gdp), lapply(pan$flows[-1], cut_last, lag)),
              stocks = lapply(pan$stocks, cut_last, lag))
  new <- list(flows = c(list(gdp = gdp), pan$flows[-1]), stocks = pan$stocks)

  set.seed(1)
  fit <- ind_dfm(flows = old$flows, stocks = old$stocks, target = "gdp",
                 length_sample = length_sample, burn_in = 10,
                 control = dfm_control("ind_dfm", verbose = FALSE))

  list(fit = fit, old = old, new = new)

}


test_that("mfbdfm_news() returns the documented structure", {

  fx <- news_fixture()
  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks)

  expect_s3_class(nw, "mfbdfm_news")
  expect_named(nw, c("table", "news", "revisions", "by_component", "totals",
                     "period", "target", "by", "components", "n_added",
                     "n_revised", "model", "call"))

  expect_true(all(c("term", "series", "group", "time", "actual", "forecast",
                    "news", "gain", "impact") %in% names(nw$table)))
  expect_true(all(c("total", "parameter") %in% nw$table$term))
  expect_equal(nw$target, "gdp")
  expect_gt(nw$n_added, 0)
  expect_equal(nw$n_revised, 0)
  expect_identical(nrow(nw$by_component), nrow(fx$fit$inventory))

  expect_identical(as.data.frame(nw), nw$table)
  expect_identical(as.data.frame(nw, what = "component"), nw$by_component)

})


test_that("the impacts add up to the plug-in revision (acceptance criterion 1)", {

  fx <- news_fixture()
  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks)

  d <- nw$table
  expect_equal(sum(d$impact[d$term %in% c("news", "revision")]),
               nw$totals$total, tolerance = 1e-8)
  expect_equal(nw$totals$nowcast_old + nw$totals$total,
               nw$totals$nowcast_new, tolerance = 1e-10)

  # and the revision is the real one: the same plug-in nowcast computed from
  # scratch on each vintage, never going through the decomposition
  pan <- dfm_news_panels(fx$fit, c(fx$new$flows, fx$new$stocks))
  pl_old <- dfm_target_plugin(dfm_joint_precision(fx$fit, Ymat = pan$old), "gdp")
  pl_new <- dfm_target_plugin(dfm_joint_precision(fx$fit, Ymat = pan$new), "gdp")
  m <- match(round(nw$period, 5), round(pl_old$time, 5))

  expect_equal(nw$totals$nowcast_old, pl_old$value[m], tolerance = 1e-8)
  expect_equal(nw$totals$nowcast_new, pl_new$value[m], tolerance = 1e-8)

  # per-component aggregation is a partition of the same number
  expect_equal(sum(nw$by_component$impact), nw$totals$total, tolerance = 1e-8)

})


test_that("an observation equal to its own forecast has zero impact (criterion 2)", {

  fx <- news_fixture()
  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks)

  # overwrite every newly released value with the forecast the old vintage
  # implied for it, then ask again
  nd <- fx$new
  for (i in seq_len(nrow(nw$news))) {
    nm <- nw$news$series[i]
    sl <- if (nm %in% names(nd$flows)) "flows" else "stocks"
    x <- nd[[sl]][[nm]]
    j <- which(abs(as.numeric(stats::time(x)) - nw$news$time[i]) < 1e-5)
    expect_length(j, 1)
    x[j] <- nw$news$forecast[i]
    nd[[sl]][[nm]] <- x
  }

  nw0 <- mfbdfm_news(fx$fit, new_data = nd$flows, stocks = nd$stocks)

  expect_identical(nw0$n_added, nw$n_added)
  expect_equal(max(abs(nw0$news$news)), 0, tolerance = 1e-10)
  expect_equal(max(abs(nw0$news$impact)), 0, tolerance = 1e-12)
  expect_equal(nw0$totals$total, 0, tolerance = 1e-12)

})


test_that("exact conditioning agrees with the sampler's 1e-9 nugget", {

  # the samplers pin an observed entry with a 1e-9 observation variance;
  # dfm_target_plugin() conditions on it exactly, which is the limit that
  # nugget approximates. This checks they are the same thing.
  fx <- news_fixture()
  pan <- dfm_news_panels(fx$fit, c(fx$new$flows, fx$new$stocks))
  jp <- dfm_joint_precision(fx$fit, Ymat = pan$old)
  pl <- dfm_target_plugin(jp, "gdp")

  nz <- nrow(jp$Q)
  dd <- numeric(nz)
  dd[jp$ix_obs] <- 1e9
  Qn <- Matrix::forceSymmetric(jp$Q + Matrix::Diagonal(x = dd))
  rhs <- numeric(nz)
  rhs[jp$ix_obs] <- 1e9 * jp$y
  z <- as.numeric(as.matrix(Matrix::solve(Qn, rhs)))

  inv <- fx$fit$inventory
  jt <- which(inv$key == "gdp")
  tt <- as.numeric(stats::time(pan$old))
  idx <- target_period_rows(tt, max(inv$freq), inv$freq[jt])
  pos <- (idx - 1L) * jp$n + jt
  nugget <- z[jp$q * (jp$t + jp$s) + pos] * inv$sd[jt] + inv$mean[jt]

  lat <- !pl$observed
  expect_equal(nugget[lat], pl$value[lat], tolerance = 1e-6)

})


test_that("data revisions are attributed per observation and are exact", {

  fx <- news_fixture()

  # revise one monthly indicator two periods back, and extend nothing: the
  # whole revision then has to come out of the `revision` block
  nd <- fx$old
  x <- nd$flows$x1
  x[length(x) - 2] <- x[length(x) - 2] + 0.5
  nd$flows$x1 <- x

  nw <- mfbdfm_news(fx$fit, new_data = nd$flows, stocks = nd$stocks)

  expect_equal(nw$n_added, 0)
  expect_equal(nw$n_revised, 1)
  expect_null(nw$news)
  expect_equal(nw$revisions$series, "x1")
  expect_equal(sum(nw$revisions$impact), nw$totals$revision, tolerance = 1e-10)
  expect_equal(nw$totals$news, 0)

  pan <- dfm_news_panels(fx$fit, c(nd$flows, nd$stocks))
  pl_new <- dfm_target_plugin(dfm_joint_precision(fx$fit, Ymat = pan$new), "gdp")
  m <- match(round(nw$period, 5), round(pl_new$time, 5))
  expect_equal(nw$totals$nowcast_new, pl_new$value[m], tolerance = 1e-8)

})


test_that("the decomposition is exact with serial_correlation = FALSE", {

  # with rho = 1e-9 the quasi-differencing operator K is effectively the
  # identity, so this is the textbook case the general one has to reduce to
  pan <- make_synth_mm_panel(seed = 7, years = 5)
  cut_last <- function(x, k) stats::window(x, end = stats::time(x)[length(x) - k])
  # two quarters short of the indicators, so the old vintage already has a
  # latent target period of its own -- the pure-revision test needs one
  gdp <- cut_last(pan$flows$gdp, 2)

  old <- list(flows = c(list(gdp = gdp), lapply(pan$flows[-1], cut_last, 2)),
              stocks = lapply(pan$stocks, cut_last, 2))
  new <- list(flows = c(list(gdp = gdp), pan$flows[-1]), stocks = pan$stocks)

  set.seed(2)
  fit <- ind_dfm(flows = old$flows, stocks = old$stocks, target = "gdp",
                 length_sample = 20, burn_in = 5, serial_correlation = FALSE,
                 control = dfm_control("ind_dfm", verbose = FALSE))

  nw <- mfbdfm_news(fit, new_data = new$flows, stocks = new$stocks)
  expect_equal(sum(nw$news$impact), nw$totals$total, tolerance = 1e-8)

})


test_that("the parameter term is reported when a new fit is supplied", {

  fx <- news_fixture()

  set.seed(3)
  new_fit <- ind_dfm(flows = fx$new$flows, stocks = fx$new$stocks,
                     target = "gdp", length_sample = 30, burn_in = 10,
                     control = dfm_control("ind_dfm", verbose = FALSE))

  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks,
                    new_fit = new_fit)

  expect_true(is.finite(nw$totals$parameter))
  expect_equal(nw$table$impact[nw$table$term == "parameter"],
               nw$totals$parameter)

  # the parameter term closes the gap to the plug-in nowcast of the refit,
  # which is what it is defined to be
  pl <- dfm_target_plugin(dfm_joint_precision(new_fit), "gdp")
  m <- match(round(nw$period, 5), round(pl$time, 5))
  expect_equal(nw$totals$nowcast_new + nw$totals$parameter, pl$value[m],
               tolerance = 1e-10)

  # without it the term is NA rather than silently zero
  nw2 <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks)
  expect_true(is.na(nw2$totals$parameter))

})


test_that("by = 'group' aggregates to the supplied grouping", {

  fx <- news_fixture()
  keys <- fx$fit$inventory$key
  grp <- stats::setNames(c("target", rep(c("a", "b"), length.out = length(keys) - 1)),
                         keys)

  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks,
                    by = "group", groups = grp)

  expect_equal(nw$by, "group")
  expect_setequal(nw$components, unique(unname(grp)))
  expect_equal(sum(nw$by_component$impact), nw$totals$total, tolerance = 1e-8)
  expect_true(all(nw$news$group %in% unname(grp)))

  # by = "group" without a grouping and without an inventory column errors
  expect_error(mfbdfm_news(fx$fit, new_data = fx$new$flows,
                           stocks = fx$new$stocks, by = "group"),
               "needs a grouping")

})


test_that("the target period can be chosen and a pinned one is refused", {

  fx <- news_fixture()
  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks)

  # the default is the LAST period the old vintage had not observed; the one
  # before it is also unobserved here, and is a different, smaller revision
  back <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks,
                      period = nw$period - 0.25)
  expect_equal(back$period, nw$period - 0.25)
  expect_false(isTRUE(all.equal(back$totals$total, nw$totals$total)))
  expect_equal(sum(back$news$impact), back$totals$total, tolerance = 1e-8)

  # a period whose target value the old vintage already observed is pinned to
  # that observation, so no news can revise it
  obs_period <- nw$period - 0.5
  expect_error(mfbdfm_news(fx$fit, new_data = fx$new$flows,
                           stocks = fx$new$stocks, period = obs_period),
               "already observed")

  expect_error(mfbdfm_news(fx$fit, new_data = fx$new$flows,
                           stocks = fx$new$stocks, period = 1800),
               "must be one of the target's periods")

})


test_that("mfbdfm_news() validates fit and vintage", {

  fx <- news_fixture()

  expect_error(mfbdfm_news(fx$fit$inventory, new_data = fx$new$flows),
               "must be a fitted model from ind_dfm")

  # fcast_dfm() is deferred, and says so rather than returning a number
  bad <- structure(list(target = "gdp"), class = "fcast_dfm")
  expect_error(mfbdfm_news(bad, new_data = fx$new$flows),
               "implemented for ind_dfm\\(\\) fits only")

  short <- fx$new
  short$flows$x1 <- NULL
  expect_error(mfbdfm_news(fx$fit, new_data = short$flows,
                           stocks = short$stocks),
               "missing 1 of the fit's series")

  wide <- fx$new
  wide$flows$extra <- fx$new$flows$x1
  expect_error(mfbdfm_news(fx$fit, new_data = wide$flows,
                           stocks = wide$stocks),
               "series the fit does not")

  # an observation that disappeared is neither news nor a revision
  gone <- fx$old
  gone$flows$x1 <- stats::window(
    gone$flows$x1,
    end = stats::time(gone$flows$x1)[length(gone$flows$x1) - 1])
  expect_error(mfbdfm_news(fx$fit, new_data = gone$flows, stocks = gone$stocks),
               "superset")

  expect_error(mfbdfm_news(fx$fit, new_data = fx$new$flows,
                           stocks = fx$new$stocks, new_fit = fx$fit$inventory),
               "`new_fit` must be a fitted model")

})


test_that("print() and plot() work on a news object", {

  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  fx <- news_fixture()
  nw <- mfbdfm_news(fx$fit, new_data = fx$new$flows, stocks = fx$new$stocks)

  expect_output(print(nw), "News decomposition")
  expect_output(print(nw), "nowcast, new vintage")
  expect_output(print(nw), "not computed")
  expect_invisible(plot(nw))
  # fewer bars than components, so the "other" bucket is exercised
  expect_invisible(plot(nw, n_show = 2))

})


test_that("mfbdfm_news() accepts an mfbdfm_data object", {

  fx <- news_fixture()
  series <- c(fx$new$flows, fx$new$stocks)
  meta <- data.frame(series = names(series),
                     type = rep(c("flow", "stock"),
                                c(length(fx$new$flows), length(fx$new$stocks))),
                     stringsAsFactors = FALSE)
  md <- mfbdfm_data(series, meta, target = "gdp")

  nw <- mfbdfm_news(fx$fit, md)
  expect_s3_class(nw, "mfbdfm_news")
  expect_equal(sum(nw$news$impact), nw$totals$total, tolerance = 1e-8)

})
