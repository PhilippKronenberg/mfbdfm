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
