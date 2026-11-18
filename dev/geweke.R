# Geweke (2004) joint-distribution test of ind_dfm()'s sampler.
#
# Two ways of simulating (parameters, factor, data) must give the same joint
# distribution if every conditional in the sampler is right:
#
#   marginal-conditional    parameters and factor from the prior, then the data
#   successive-conditional  one gibbs_sweep(), then new data given the state,
#                           and repeat
#
# It catches a wrong conditional, a wrong order of draws and a wrong prior, which
# no comparison of fits can: dev/baseline.R only says that results did not move.
#
#   source("dev/geweke.R")
#   res <- geweke_run()          # about 10 minutes on 4 cores
#   res                          # one z-score per moment
#
# Scope. Runs gibbs_sweep() itself on a small panel with a weekly series, a
# monthly series and a monthly target. phi and the factor variance are held
# nearly fixed through tight priors, because draw_phi() clips at zero and
# draw_factor_variance() leaves out the first period, neither of which is a
# conjugate draw. stochastic volatility is off, because its prior on h is
# improper and the marginal-conditional simulator needs a proper one. So this
# tests f, the latent data, lambda, sigma and rho, not the volatility block.
#
# Fat tails (#180): geweke_run(fat = TRUE) runs the same test with Student-t
# measurement errors, nu = 5, and adds moments of the multipliers kappa. The
# weekly series has one per week, the monthly one per observation period, the
# target none. Compared through log(kappa) and 1/kappa, whose moments are finite
# for any nu.

GEWEKE_T <- 32L

geweke_load <- function(){
  if(!"package:mfbdfm" %in% search()) devtools::load_all(".", quiet = TRUE)
  invisible()
}

geweke_priors <- function(){
  list(sigma_target = list(c0 = 8, d0 = 2),
       sigma_other = list(c0 = 8, d0 = 4),
       rho_target = list(r0 = 0, R0 = 0.04),
       rho_other = list(r0 = 0, R0 = 0.25),
       lambda = list(b0 = 0, B0 = 1),
       phi = list(a0 = 0.6, A0 = 1e-10),
       omega = list(k0 = 3, l0 = 0.03),
       factor_var = list(c0 = 2e6, d0 = 5e5),
       kappa = list(nu = 5))
}

geweke_setup <- function(t = GEWEKE_T, fat = FALSE){
  inventory <- data.frame(key = c("wk", "mo", "gdp"), type = c("flow", "stock", "flow"),
                          freq = c(48, 12, 12), stringsAsFactors = FALSE)
  n <- 3L; s <- 2L*(4L - 1L); p <- 1L
  list(inventory = inventory, n = n, t = t, s = s, p = p, target = "gdp",
       Llist = mfbdfm:::get_distributed_lags(inventory),
       Gmat_prealloc = mfbdfm:::get_gmat_prealloc(n = n, q = 1, s = s, t = t),
       priors = geweke_priors(),
       # sigma is no longer capped (#176). With the old cap at 5, which this prior's
       # tail exceeds, the clipped chain had another stationary distribution:
       # seed 2026 gave sigma_wk z = -5.5, and -1.6 without it.
       control = dfm_control("ind_dfm"),
       # weekly series every week, the monthly ones every fourth
       observed = cbind(rep(TRUE, t), seq_len(t) %% 4L == 0L, seq_len(t) %% 4L == 0L),
       fat = fat)
}

# The multipliers from their prior: one per week for the weekly series, one per
# observation period for the monthly one (weeks 1-4 are period 1, and so on, so
# that week t's period ends at the next observed week), 1 for the target.
geweke_prior_kappa <- function(g){
  nu <- g$priors$kappa$nu
  ig <- function(k) 1/stats::rgamma(k, nu/2, rate = nu/2)
  per <- (seq_len(g$t) - 1L) %/% 4L + 1L
  cbind(ig(g$t), ig(max(per))[per], rep(1, g$t))
}

# Parameters and factor from the prior
geweke_prior_draw <- function(g){
  pr <- g$priors; n <- g$n
  ig <- function(a) 1/stats::rgamma(1, a$c0/2, rate = a$d0/2)
  tn <- function(a){
    repeat{
      r <- stats::rnorm(1, a$r0, sqrt(a$R0))
      if(abs(r) < g$control$rho_max) return(r)
    }
  }
  lambda <- Matrix::Matrix(c(stats::rnorm(2, pr$lambda$b0, sqrt(pr$lambda$B0)), 1), n, 1)
  sigma <- Matrix::Diagonal(x = c(ig(pr$sigma_other), ig(pr$sigma_other), ig(pr$sigma_target)))
  rho <- Matrix::Diagonal(x = c(tn(pr$rho_other), tn(pr$rho_other), tn(pr$rho_target)))
  phi <- pr$phi$a0
  var_f <- ig(pr$factor_var)
  tt <- g$t + g$s
  f <- numeric(tt)
  f[1] <- stats::rnorm(1, 0, sqrt(var_f))
  for(i in 2:tt) f[i] <- phi*f[i - 1] + stats::rnorm(1, 0, sqrt(var_f))
  out <- list(f = matrix(f, tt, 1), lambda = lambda, phi = phi, sigma = sigma, rho = rho,
              h = matrix(0.5*log(var_f), tt, 1), omega = 0.01,
              Xmat = matrix(0, g$t, n), indicators = rep(1L, tt))
  if(isTRUE(g$fat)) out$kappa <- geweke_prior_kappa(g)
  out
}

# All of the latent data given the state, from the measurement equation. The first
# row has mean zero, as in draw_augmented_data().
geweke_simulate_x <- function(state, g){
  n <- g$n; t <- g$t
  G <- mfbdfm:::get_gmat(g$Gmat_prealloc, g$Llist, state$rho, state$lambda, g$s, t, n)
  gf <- as.numeric(G %*% state$f)
  dim(gf) <- c(n, t - 1)
  rd <- Matrix::diag(state$rho)
  sd_v <- sqrt(Matrix::diag(state$sigma))
  k <- if(isTRUE(g$fat)) sqrt(state$kappa) else matrix(1, t, n)
  X <- matrix(0, t, n)
  X[1,] <- sd_v*k[1,]*stats::rnorm(n)
  for(tx in 2:t) X[tx,] <- gf[, tx - 1] + rd*X[tx - 1,] + sd_v*k[tx,]*stats::rnorm(n)
  X
}

geweke_context <- function(X, g){
  Y <- X
  Y[!g$observed] <- 0
  mfbdfm:::sweep_context(Ymat = Y, target = g$target, n = g$n, t = g$t, t2 = g$t, p = g$p,
                         s = g$s, inventory = g$inventory, Gmat_prealloc = g$Gmat_prealloc,
                         priors = g$priors, control = g$control,
                         stochastic_volatility = FALSE, serial_correlation = TRUE,
                         fat_tails = isTRUE(g$fat))
}

# The moments compared. rho only through even powers for the monthly series,
# whose sign the data do not identify.
geweke_moments <- function(state, g){
  l <- as.numeric(state$lambda); v <- Matrix::diag(state$sigma); r <- Matrix::diag(state$rho)
  f <- as.numeric(state$f)
  c(lambda_wk = l[1], lambda_mo = l[2], lambda_wk2 = l[1]^2, lambda_mo2 = l[2]^2,
    sigma_wk = v[1], sigma_mo = v[2], sigma_gdp = v[3],
    rho_wk = r[1], rho_wk2 = r[1]^2, rho_mo2 = r[2]^2, rho_mo4 = r[2]^4, rho_gdp2 = r[3]^2,
    sigmaRho_mo = v[2]*r[2]^2,
    f_mean = mean(f), f_var = mean(f^2), f_last = f[length(f)], f_last2 = f[length(f)]^2,
    lamF_wk = l[1]*f[length(f)], lamF_mo = l[2]*mean(f[(length(f) - 3):length(f)]),
    if(isTRUE(g$fat)){
      k <- state$kappa
      c(lkap_wk = mean(log(k[, 1])), ikap_wk = mean(1/k[, 1]), lkap_wk_last = log(k[g$t, 1]),
        lkap_mo = mean(log(k[, 2])), ikap_mo = mean(1/k[, 2]), lkap_mo_last = log(k[g$t, 2]),
        sigKap_wk = v[1]*mean(1/k[, 1]))
    })
}

geweke_n_moments <- function(g) length(geweke_moments(geweke_prior_draw(g), g))

geweke_marginal <- function(draws, g){
  m <- geweke_n_moments(g)
  t(vapply(seq_len(draws), function(i) geweke_moments(geweke_prior_draw(g), g), numeric(m)))
}

geweke_successive <- function(sweeps, g){
  state <- geweke_prior_draw(g)
  out <- matrix(NA_real_, sweeps, geweke_n_moments(g))
  for(i in seq_len(sweeps)){
    ctx <- geweke_context(geweke_simulate_x(state, g), g)
    state <- mfbdfm:::gibbs_sweep(state, ctx)
    out[i,] <- geweke_moments(state, g)
  }
  colnames(out) <- names(geweke_moments(state, g))
  out
}

# Standard error of a mean from an autocorrelated column: batch means
geweke_se <- function(x, batches = 40L){
  b <- floor(seq_along(x)/(length(x) + 1)*batches)
  stats::sd(tapply(x, b, mean))/sqrt(batches)
}

#' @param patch Called in each worker before sampling, e.g. to swap in a known
#'   wrong function as a negative control.
geweke_run <- function(sweeps = 20000L, draws = 200000L, chains = 4L, burn = 500L,
                       patch = NULL, seed = 2026L, fat = FALSE){

  cl <- parallel::makeCluster(chains)
  on.exit(parallel::stopCluster(cl))
  parallel::clusterSetRNGStream(cl, seed)
  wd <- getwd()
  parallel::clusterExport(cl, c("patch", "wd", "sweeps", "draws", "burn", "fat"), envir = environment())
  parallel::clusterEvalQ(cl, {
    setwd(wd)
    suppressMessages(devtools::load_all(".", quiet = TRUE))
    source("dev/geweke.R")
    if(is.function(patch)) patch()
    NULL
  })
  res <- parallel::parLapply(cl, seq_len(chains), function(i){
    g <- geweke_setup(fat = fat)
    list(succ = geweke_successive(sweeps + burn, g)[-seq_len(burn),],
         marg = geweke_marginal(draws, g))
  })

  se_chain <- sapply(res, function(r) apply(r$succ, 2, geweke_se))
  mean_succ <- rowMeans(sapply(res, function(r) colMeans(r$succ)))
  se_succ <- sqrt(rowSums(se_chain^2))/chains
  marg <- do.call(rbind, lapply(res, `[[`, "marg"))
  mean_marg <- colMeans(marg)
  se_marg <- apply(marg, 2, stats::sd)/sqrt(nrow(marg))
  z <- (mean_succ - mean_marg)/sqrt(se_succ^2 + se_marg^2)

  out <- data.frame(moment = names(z), marginal = round(mean_marg, 4),
                    successive = round(mean_succ, 4), se = round(se_succ, 4),
                    z = round(z, 2), row.names = NULL)
  attr(out, "max_abs_z") <- max(abs(z))
  out

}
