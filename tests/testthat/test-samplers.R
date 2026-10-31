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
