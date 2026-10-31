quality_fit <- local({
  fit <- NULL
  function(){
    if(is.null(fit)){
      data(mfbdfm_example_data, envir = environment())
      set.seed(5)
      fit <<- suppressMessages(suppressWarnings(
        ind_dfm(mfbdfm_example_data, length_sample = 80, burn_in = 20,
                control = dfm_control("ind_dfm", verbose = FALSE))))
    }
    fit
  }
})

test_that("rank-normalised ESS and split R-hat see what they should", {
  set.seed(1)
  iid <- rnorm(4000)
  stuck <- c(rep(0, 2000), rep(1, 2000)) + rnorm(4000, sd = 0.01)
  expect_gt(mfbdfm:::ess_rank(iid), 3000)
  expect_lt(mfbdfm:::ess_rank(stuck), 50)
  expect_lt(mfbdfm:::rhat_split(iid), 1.01)
  expect_gt(mfbdfm:::rhat_split(stuck), 1.5)
  expect_true(is.na(mfbdfm:::ess_rank(rep(1, 10))))
  expect_true(is.na(mfbdfm:::rhat_split(rep(1, 10))))
})

test_that("mfbdfm_quality() reports the published quantities and can fail", {
  fit <- quality_fit()
  q <- mfbdfm_quality(fit)

  expect_s3_class(q, "mfbdfm_quality")
  expect_true(all(c("latest nowcast: ess", "latest week: mcse", "latest 13 weeks: rhat",
                    "anchor", "rho_fallback", "parameters: smallest ess") %in% q$check))
  expect_identical(attr(q, "pass"), !any(q$pass %in% FALSE))
  expect_output(print(q), "Quality checks")

  # 80 draws cannot reach an ESS of 400
  expect_false(attr(q, "pass"))
  expect_false(q$pass[q$check == "latest nowcast: ess"])

  easy <- mfbdfm_quality(fit, ess_min = 1, mcse_max = 1e6, rhat_max = 1e6, param_ess_min = 0)
  expect_true(attr(easy, "pass"))
})

test_that("the anchor and the unexplained revision are checked", {
  fit <- quality_fit()
  q <- mfbdfm_quality(fit, unexplained = 0.2)
  expect_true(q$pass[q$check == "unexplained revision"])
  q <- mfbdfm_quality(fit, unexplained = -2)
  expect_false(q$pass[q$check == "unexplained revision"])

  broken <- fit
  broken$nowcast[1] <- broken$nowcast[1] + 1
  q <- mfbdfm_quality(broken)
  expect_false(q$pass[q$check == "anchor"])
})

test_that("mfbdfm_quality() compares with the exact estimate", {
  fit <- quality_fit()
  ex <- mfbdfm_exact(fit, n_draws = 3, paths = 2, seed = 1)
  q <- mfbdfm_quality(fit, exact = ex)
  expect_true("chain vs exact: |z|" %in% q$check)
  expect_error(mfbdfm_quality(fit, exact = 1), "mfbdfm_exact")
  expect_error(mfbdfm_quality(1), "fitted model")
  no_draws <- fit
  no_draws$draws <- NULL
  expect_error(mfbdfm_quality(no_draws), "carries no draws")
})

test_that("identified columns are the right functions of the draws", {
  fit <- quality_fit()
  d <- fit$draws
  gaps <- mfbdfm:::low_frequency_gaps(fit$inventory, exclude = fit$target)
  k <- names(gaps)[1]; g <- gaps[[1]]
  r <- d$parameters[, paste0("rho[", k, "]")]
  v <- d$parameters[, paste0("sigma[", k, "]")]
  expect_equal(unname(d$parameters[, paste0("rho_obs[", k, "]")]), unname(r^g))
  expect_equal(unname(d$parameters[, paste0("innovation[", k, "]")]),
               unname(v * (1 - r^(2*g))/(1 - r^2)))

  dg <- as.data.frame(mfbdfm_diagnostics(fit))
  row <- dg[dg$parameter == paste0("rho[", k, "]"), ]
  expect_true(is.na(row$ok))
  expect_match(row$note, "sign not identified")
  expect_false(is.na(dg$ok[dg$parameter == paste0("rho_obs[", k, "]")]))
})

test_that("the plug-in reproduces the identified moments, not the mean of rho", {
  fit <- quality_fit()
  pl <- mfbdfm:::low_frequency_plugin(fit$draws, fit$inventory$key)
  gaps <- mfbdfm:::low_frequency_gaps(fit$inventory, exclude = fit$target)
  expect_setequal(names(pl$rho), names(gaps))
  k <- names(pl$rho)[1]; g <- gaps[[k]]
  expect_gte(pl$rho[[k]], 0)
  expect_equal(pl$rho[[k]]^g, mean(fit$draws$parameters[, paste0("rho_obs[", k, "]")]))
  w <- (1 - pl$rho[[k]]^(2*g))/(1 - pl$rho[[k]]^2)
  expect_equal(pl$sigma[[k]]*w, mean(fit$draws$parameters[, paste0("innovation[", k, "]")]))
  expect_length(mfbdfm:::low_frequency_plugin(NULL, fit$inventory$key)$rho, 0)
})

test_that("standardised loadings use the weights, with the target at 1 and R-squared", {
  fit <- quality_fit()
  tab <- mfbdfm_table_loadings(fit)
  w <- mfbdfm:::fit_weight_sums(fit$inventory)
  tgt <- fit$inventory$key == fit$target
  expect_equal(tab$weight_sum, w)
  expect_equal(tab$loading_std, tab$mean * w / w[tgt])
  expect_equal(tab$loading_std[tab$series == fit$target], 1)
  expect_true(all(tab$std_lower <= tab$loading_std & tab$loading_std <= tab$std_upper, na.rm = TRUE))
  r2 <- summary(fit)$r_squared
  expect_equal(tab$r_squared, r2$r_squared[match(tab$series, r2$series)])
  expect_output(print(summary(fit)), "standardised by its aggregation weights")
})
