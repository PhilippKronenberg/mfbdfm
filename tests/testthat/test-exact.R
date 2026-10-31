exact_fit <- local({
  fit <- NULL
  function(){
    if(is.null(fit)){
      data(mfbdfm_example_data, envir = environment())
      set.seed(11)
      fit <<- suppressMessages(suppressWarnings(
        ind_dfm(mfbdfm_example_data, length_sample = 60, burn_in = 20,
                control = dfm_control("ind_dfm", verbose = FALSE))))
    }
    fit
  }
})

test_that("mfbdfm_exact() validates its arguments", {
  fit <- exact_fit()
  expect_error(mfbdfm_exact(1), "fitted model from ind_dfm")
  expect_error(mfbdfm_exact(fit, n_draws = 0), "n_draws")
  expect_error(mfbdfm_exact(fit, paths = 3), "paths")
  no_h <- fit
  no_h$draws$h_paths <- NULL
  expect_error(mfbdfm_exact(no_h), "volatility paths")
})

test_that("mfbdfm_exact() matches the fit's axes and the observed target", {
  fit <- exact_fit()
  ex <- mfbdfm_exact(fit, n_draws = 3, paths = 4, seed = 1)

  expect_s3_class(ex, "mfbdfm_exact")
  expect_equal(stats::tsp(ex$factor), stats::tsp(fit$factor))
  expect_equal(stats::tsp(ex$nowcast), stats::tsp(fit$nowcast))
  expect_true(all(ex$factor_var >= 0))
  expect_true(all(ex$nowcast_var >= 0))

  # observed quarters are data, not estimates
  gdp <- stats::na.omit(mfbdfm_example_data$flows[[fit$target]])
  n_obs <- min(length(gdp), length(ex$nowcast))
  expect_equal(as.numeric(ex$nowcast)[seq_len(n_obs)], as.numeric(gdp)[seq_len(n_obs)],
               tolerance = 1e-8)

  expect_identical(mfbdfm_exact(fit, n_draws = 3, paths = 4, seed = 1)$factor, ex$factor)
  expect_output(print(ex), "Exact estimate over 3 parameter draws")
})

test_that("its conditional mean and variance are those of the joint Gaussian", {
  # At one parameter draw the nowcast of an unobserved quarter has an exact mean
  # and variance from the precision matrix. The simulated part must reproduce the
  # variance, and the solve the mean.
  fit <- exact_fit()
  ex <- mfbdfm_exact(fit, n_draws = 1, paths = 2000, seed = 2)

  d <- fit$draws
  row <- d$h_rows[1] + d$info$n_burn_in
  keys <- fit$inventory$key
  n <- length(keys); t <- nrow(fit$data)
  P <- d$parameters[row, , drop = FALSE]
  obj <- fit
  obj$draws <- NULL
  obj$pars$lambda <- Matrix::Matrix(P[, paste0("lambda[", keys, "]")], n, 1)
  obj$pars$sigma <- P[, paste0("sigma[", keys, "]")]
  obj$pars$rho <- P[, paste0("rho[", keys, "]")]
  obj$pars$phi <- P[, grep("^phi[0-9]+$", colnames(P))]
  obj$internal$h_full <- d$h_paths[1, ]
  J <- mfbdfm:::dfm_joint_precision(obj)

  tx <- which(keys == fit$target)
  rows <- mfbdfm:::target_period_rows(stats::time(fit$data), max(fit$inventory$freq),
                                      fit$inventory$freq[tx])
  last <- rows[length(fit$nowcast)]
  idx <- J$q*(t + J$s) + (last - 1L)*n + tx
  pos <- match(idx, J$ix_lat)
  skip_if(is.na(pos), "the last quarter is observed in this panel")

  Qll <- Matrix::forceSymmetric(J$Q[J$ix_lat, J$ix_lat])
  e <- numeric(length(J$ix_lat)); e[pos] <- 1
  var_exact <- Matrix::solve(Qll, e)[pos] * fit$inventory$sd[tx]^2
  mean_exact <- Matrix::solve(Qll, -J$Q[J$ix_lat, J$ix_obs] %*% J$y)[pos]*fit$inventory$sd[tx] +
    fit$inventory$mean[tx]

  m <- length(ex$nowcast)
  expect_equal(as.numeric(ex$nowcast[m]), as.numeric(mean_exact), tolerance = 1e-8)
  # 1000 antithetic pairs: 5 standard errors of a variance
  expect_lt(abs(as.numeric(ex$nowcast_var[m])/var_exact - 1), 5*sqrt(2/1000))
})

test_that("fit_with_exact() replaces only the estimates", {
  fit <- exact_fit()
  ex <- mfbdfm_exact(fit, n_draws = 2, paths = 2, seed = 3)
  out <- mfbdfm:::fit_with_exact(fit, ex)
  expect_identical(out$factor, ex$factor)
  expect_identical(out$nowcast, ex$nowcast)
  expect_identical(out$pars, fit$pars)
  expect_equal(out$exact$n_draws, 2)
})
