test_that("the collapsed regression is the exact marginal of a series' observations (#169)", {
  # X = M f + K^-1 v with M = K^-1 Gext, so y = X[tau] is N(M[tau,] f, Sigma[tau,tau]).
  # The likelihood of f has to be identical to the skip-sampled form, however the
  # gaps fall and whatever rho is, including the first observation.
  inv <- data.frame(key = c("wk", "gdp"), type = c("flow", "flow"), freq = c(48, 12),
                    stringsAsFactors = FALSE)
  n <- 2L; t <- 24L; s <- 6L
  Llist <- mfbdfm:::get_distributed_lags(inv)
  ix <- 2L

  for(tau in list(seq(4, t, by = 4), c(1L, 5L, 9L, 17L, 21L), c(6L, 7L, 15L))){
    for(rho_i in c(0.6, -0.45, 1e-9)){

      Y <- matrix(0, t, n)
      Y[, 1] <- 1
      set.seed(169)
      Y[tau, ix] <- rnorm(length(tau))
      obs <- mfbdfm:::series_obs(Y, ix, Llist, t, s)

      lam <- 1.7; sig <- 0.4
      rho <- Matrix::Diagonal(x = c(0.3, rho_i))
      G <- as.matrix(mfbdfm:::get_gmat(mfbdfm:::get_gmat_prealloc(n = n, q = 1, s = s, t = t),
                                       Llist, rho, Matrix::Matrix(c(0.5, lam), n, 1), s, t, n))
      Gi <- rbind(0, G[seq(ix, by = n, length.out = t - 1), ])

      K <- diag(t)
      K[cbind(2:t, 1:(t - 1))] <- -rho_i
      M <- solve(K, Gi)
      Sigma <- sig * solve(crossprod(K))
      Sti <- solve(Sigma[tau, tau, drop = FALSE])
      M_tau <- M[tau, , drop = FALSE]

      reg <- mfbdfm:::collapsed_regression(obs, rho_i)
      A <- as.matrix(reg$A)
      D <- diag(1/(sig * reg$w), length(tau))

      expect_equal(lam^2 * t(A) %*% D %*% A, t(M_tau) %*% Sti %*% M_tau, tolerance = 1e-8)
      expect_equal(as.numeric(lam * t(A) %*% D %*% reg$r),
                   as.numeric(t(M_tau) %*% Sti %*% Y[tau, ix]), tolerance = 1e-8)
    }
  }
})

test_that("draw_low_frequency() targets the exact marginal of rho, sigma and lambda (#170)", {
  # With f fixed, one series has a small exact posterior. Integrate sigma out of
  # the true Gaussian of the observations, brute force on a grid for rho, and
  # compare with a run of the draw itself.
  inv <- data.frame(key = c("wk", "mo"), type = c("flow", "stock"), freq = c(48, 12),
                    stringsAsFactors = FALSE)
  t <- 40L; s <- 6L; ix <- 2L
  Llist <- mfbdfm:::get_distributed_lags(inv)
  set.seed(170)
  f <- as.numeric(stats::arima.sim(list(ar = 0.6), t + s, sd = 0.5))
  tau <- seq(4, t, by = 4)
  Y <- matrix(0, t, 2)
  Y[, 1] <- 1
  Y[tau, ix] <- rnorm(length(tau))
  obs <- mfbdfm:::series_obs(Y, ix, Llist, t, s)
  lam <- 0.8
  priors <- list(sigma = list(c0 = 6, d0 = 2), rho = list(r0 = 0, R0 = 0.5),
                 lambda = list(b0 = 0, B0 = 1))
  control <- dfm_control("ind_dfm")

  # the mean of X given f, as in the measurement equation: X[1] has mean zero
  a <- as.numeric(rowSums(sapply(0:s, function(j){
    Matrix::diag(Llist[[as.character(j)]])[ix] * f[(1:t) + s - j]
  })))
  log_exact <- function(r){
    K <- diag(t)
    K[cbind(2:t, 1:(t - 1))] <- -r
    m <- solve(K, c(0, lam * (a[-1] - r * a[-t])))
    C <- solve(crossprod(K))[tau, tau]
    e <- Y[tau, ix] - m[tau]
    -r^2/(2 * priors$rho$R0) - 0.5 * as.numeric(determinant(C)$modulus) -
      0.5 * (priors$sigma$c0 + length(tau)) * log(priors$sigma$d0 + sum(e * solve(C, e)))
  }
  grid <- seq(-0.985, 0.985, length.out = 301)
  lp <- vapply(grid, log_exact, numeric(1))
  p <- exp(lp - max(lp))
  p <- p/sum(p)

  n_draw <- 6000L
  out <- matrix(NA_real_, n_draw, 3)
  rho <- 0.3
  for(i in seq_len(n_draw)){
    d <- mfbdfm:::draw_low_frequency(obs, f = f, lambda = lam, rho = rho, draw_rho = TRUE,
                                     prior_sigma = priors$sigma, prior_rho = priors$rho,
                                     prior_lambda = priors$lambda, control = control)
    rho <- d$rho
    out[i,] <- c(d$rho, d$sigma, d$lambda)
  }

  # both are independent-draw standard errors up to the accept rate, which is
  # close to 1, so 5 of them is a real bound
  m2 <- sum(grid^2 * p)
  m4 <- sum(grid^4 * p)
  expect_lt(abs(mean(out[, 1]^2) - m2), 5 * sqrt((m4 - m2^2)/n_draw))
  expect_lt(abs(mean(out[, 1]) - sum(grid * p)), 5 * sqrt(m2/n_draw))
  expect_gt(mean(diff(out[, 1]) != 0), 0.9)
})

test_that("draw_rho() leaves the low-frequency series alone when told to (#170)", {
  n <- 2L; t <- 20L; s <- 6L
  inv <- data.frame(key = c("wk", "mo"), type = c("flow", "stock"), freq = c(48, 12),
                    stringsAsFactors = FALSE)
  Llist <- mfbdfm:::get_distributed_lags(inv)
  set.seed(3)
  r <- mfbdfm:::draw_rho(Xmat = matrix(rnorm(t * n), t, n), f = matrix(rnorm(t + s), t + s, 1),
                         n = n, t = t, s = s, sigma = Matrix::Diagonal(x = c(1, 1)),
                         lambda = Matrix::Matrix(1, n, 1), Llist = Llist, inventory = inv,
                         target = "wk", control = dfm_control("ind_dfm"),
                         prior_target = list(r0 = 0, R0 = 1e-9),
                         prior_other = list(r0 = 0, R0 = 5),
                         skip = 2L, rho_old = c(0.1, -0.77))
  expect_equal(Matrix::diag(r)[2], -0.77)
})

test_that("the target's latent weeks are drawn from their exact conditional (#169)", {
  inv <- data.frame(key = c("wk", "gdp"), type = c("flow", "flow"), freq = c(48, 12),
                    stringsAsFactors = FALSE)
  t <- 16L; s <- 6L
  Llist <- mfbdfm:::get_distributed_lags(inv)
  tau <- seq(4, t, by = 4)
  Y <- matrix(0, t, 2)
  Y[, 1] <- 1
  set.seed(1)
  Y[tau, 2] <- rnorm(length(tau))
  obs <- mfbdfm:::series_obs(Y, 2L, Llist, t, s)
  gf <- rnorm(t - 1)
  rho <- 0.5; sig <- 0.3

  draws <- replicate(4000, mfbdfm:::draw_series_latent(obs, gf, rho, sig, t))

  K <- diag(t)
  K[cbind(2:t, 1:(t - 1))] <- -rho
  m <- solve(K, c(0, gf))
  Sigma <- sig * solve(crossprod(K))
  un <- setdiff(seq_len(t), tau)
  cond <- Sigma[un, tau] %*% solve(Sigma[tau, tau])
  mean_exact <- as.numeric(m[un] + cond %*% (Y[tau, 2] - m[tau]))
  var_exact <- diag(Sigma[un, un] - cond %*% Sigma[tau, un])

  expect_equal(draws[tau, 1], Y[tau, 2], tolerance = 1e-3)
  # 4000 independent draws: 5 standard errors
  expect_true(all(abs(rowMeans(draws[un, ]) - mean_exact) < 5 * sqrt(var_exact / 4000)))
  expect_true(all(abs(apply(draws[un, ], 1, var) / var_exact - 1) < 5 * sqrt(2 / 4000)))
})


test_that("a rho prior narrower than the grid is honoured, whatever the start (#170)", {

  # The proposal was a histogram on a fixed grid. A prior narrower than a cell
  # fell between the points, and the starting value sat in a cell of zero mass,
  # so every step back had probability zero and rho never moved.
  set.seed(3)
  fit <- suppressMessages(suppressWarnings(
    ind_dfm(mfbdfm_example_data, length_sample = 10, burn_in = 5, plots = FALSE,
            priors = dfm_priors("ind_dfm", rho_other = list(r0 = 0, R0 = 1e-9)))))

  low <- fit$inventory$freq < 48 & fit$inventory$key != fit$target
  expect_true(any(low))
  expect_lt(max(abs(fit$pars$rho[low])), 1e-3)
})

test_that("draw_low_frequency() with every kappa at 1 is the Gaussian draw (#180)", {
  inv <- data.frame(key = c("wk", "mo"), type = c("flow", "stock"), freq = c(48, 12),
                    stringsAsFactors = FALSE)
  t <- 40L; s <- 6L; ix <- 2L
  Llist <- mfbdfm:::get_distributed_lags(inv)
  set.seed(180)
  f <- as.numeric(stats::arima.sim(list(ar = 0.6), t + s, sd = 0.5))
  tau <- seq(4, t, by = 4)
  Y <- matrix(0, t, 2); Y[, 1] <- 1; Y[tau, ix] <- rnorm(length(tau))
  obs <- mfbdfm:::series_obs(Y, ix, Llist, t, s)
  args <- list(obs, f = f, lambda = 0.8, rho = 0.3, draw_rho = TRUE,
               prior_sigma = list(c0 = 6, d0 = 2), prior_rho = list(r0 = 0, R0 = 0.5),
               prior_lambda = list(b0 = 0, B0 = 1), control = dfm_control("ind_dfm"))
  set.seed(1); g <- do.call(mfbdfm:::draw_low_frequency, args)
  set.seed(1); k <- do.call(mfbdfm:::draw_low_frequency,
                            c(args, list(kappa = rep(1, length(tau)), nu = 5)))
  expect_equal(k[c("lambda", "sigma", "rho")], g[c("lambda", "sigma", "rho")])
  expect_length(k$kappa, length(tau))
  expect_true(all(k$kappa > 0))
})

test_that("draw_kappa() draws from the conjugate inverse-gamma, and only the series asked (#180)", {
  n <- 2L; t <- 4001L; nu <- 5; sig <- 0.5
  set.seed(181)
  u <- c(0.1, 2)                                   # a small and a large residual
  X <- rbind(rep(u, length.out = t - 1), 0)           # series 1 alternates small, large
  kappa <- matrix(7, t, n)
  out <- mfbdfm:::draw_kappa(Xvec_tilde = as.numeric(X), Gmat = Matrix::Matrix(0, n*(t - 1), 1),
                             f = matrix(0, 1, 1), n = n, t = t, x1 = c(0.1, 0.1),
                             sigma = Matrix::Diagonal(x = c(sig, 1)), kappa = kappa,
                             ix = 1L, nu = nu)
  expect_equal(out[, 2], rep(7, t))                # not asked: untouched
  r <- X[1, ]                                      # series 1's residuals, weeks 2..t
  w <- 1/out[-1, 1]
  for(v in unique(r)){
    sel <- r == v
    # E[1/kappa] = shape/rate = (nu + 1)/(nu + v^2/sigma)
    expect_equal(mean(w[sel]), (nu + 1)/(nu + v^2/sig), tolerance = 0.05)
  }
  # an outlier gets a smaller weight than an ordinary observation
  expect_lt(mean(w[r == max(r)]), mean(w[r == min(r)]))
})


test_that("h_max bounds the factor log-volatility, and Inf lifts the bound (#182)", {
  fit_h <- function(h_max) {
    ind_dfm(mfbdfm_example_data, length_sample = 60, burn_in = 20,
            control = dfm_control("ind_dfm", seed = 3, verbose = FALSE, h_max = h_max))
  }
  bounded <- fit_h(-2.15)
  free <- fit_h(Inf)
  # the default keeps every draw at or below the bound ...
  expect_lte(max(bounded$draws$h_paths), -2.15)
  # ... and on this panel the bound binds over COVID-19, so lifting it lets h past it
  expect_gt(max(free$draws$h_paths), -2.15)
})


test_that("draw_factor_outliers() draws from the conjugate inverse-gamma (#182)", {
  set.seed(5)
  p <- 1; s <- 0; t <- 4000; nu <- 5
  # f with AR coefficient 0 and alternating residuals 0.1 and 2, h = 0
  f <- matrix(rep(c(0.1, 2), length.out = t), t, 1)
  o <- mfbdfm:::draw_factor_outliers(f = f, phi = 0, h = rep(0, t), p = p, s = s, t = t, nu = nu)
  expect_length(o, t)
  expect_equal(o[1], 1)                               # no residual: kept at 1
  e <- as.numeric(f)[-1]; w <- 1/o[-1]
  for(v in unique(e)){
    # E[1/o] = shape/rate = (nu + 1)/(nu + e^2)
    expect_equal(mean(w[e == v]), (nu + 1)/(nu + v^2), tolerance = 0.05)
  }
})


test_that("draw_sv_ar1() recovers the level and persistence of a simulated path (#182)", {
  set.seed(6)
  m <- 5000; mu <- -2.5; ph <- 0.9; om <- 0.04
  h <- numeric(m); h[1] <- mu + rnorm(1, 0, sqrt(om/(1 - ph^2)))
  for(i in 2:m) h[i] <- mu + ph*(h[i-1] - mu) + rnorm(1, 0, sqrt(om))
  prior <- list(mu0 = 0, M0 = 100, phi0 = 0.5, Phi0 = 1)
  st <- list(mu = 0, phi = 0.5)
  keep <- t(replicate(400, {st <<- mfbdfm:::draw_sv_ar1(h, om, st$mu, st$phi, prior); unlist(st)}))
  post <- colMeans(keep[-(1:100), ])
  expect_equal(unname(post["mu"]), mean(h), tolerance = 0.05)
  expect_equal(unname(post["phi"]), ph, tolerance = 0.02)
  expect_true(all(abs(keep[, "phi"]) < 1))
})


test_that("draw_volatility() under an AR(1) prior is pulled to its level (#182)", {
  # with the data carrying no information (huge mixture variances are not
  # available, so a long flat stretch of zero residuals is used instead), the
  # AR(1) prior keeps h near mu where the random walk lets it sit at the data
  set.seed(7)
  p <- 1; s <- 0; t <- 200
  f <- matrix(rnorm(t, 0, exp(-2.5)), t, 1)
  ctl <- dfm_control("ind_dfm", h_max = Inf)
  ind <- rep(5L, t)
  NtN <- Matrix::crossprod(Matrix::bandSparse(t - 1, t, k = c(0, 1),
                                              diagonals = list(rep(-1, t - 1), rep(1, t - 1))))
  h_ar <- replicate(200, mean(mfbdfm:::draw_volatility(f, 0, 1, p, s, t, omega = 1e-4,
                     indicators = ind, h_old = rep(0, t), NtN = NtN, control = ctl,
                     ar1 = list(mu = 1, phi = 0.5))))
  # the prior at mu = 1 with a tiny omega dominates
  expect_gt(mean(h_ar), 0.5)
})
