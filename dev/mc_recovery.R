# Simulation-recovery validation for fcast_dfm()  (#52)
#
# Everything else in this package is verified against a reference: the
# pre-change code, compared with identical(). fcast_dfm() has no such
# reference - it is a fresh implementation of a published model - so the only
# way to establish that it *estimates the model* rather than merely *runs* is
# to generate data from a known DGP and check the estimates recover it.
#
# Because factors and loadings are identified only up to a q x q rotation, the
# comparison is the rotation-invariant trace R-squared used by the paper
# (Eckert et al. 2025, Equation 17):
#
#     Trace( F' Fhat (Fhat' Fhat)^-1 Fhat' F ) / Trace( F' F )
#
# The DGP below follows old_code_fcast_dfm/mc_simulation.R so the results are
# comparable with the paper's Table 1, whose columns (6)-(8) report exactly
# this quantity for the EKMN model:
#
#   q_f = 1, q_hat = 1, phi = 0.7, rho = 0, n = 25, T = 120 ->  0.68 0.70 0.71
#   q_f = 2, q_hat = 2, phi = 0.7, rho = 0, n = 25, T = 120 ->  0.84 0.84 0.84
#   q_f = 2, q_hat = 1  (misspecified)                      ->  0.39 0.40 0.40
#
# The third row matters as much as the first two: it is a negative control. A
# correct implementation should score ~0.4 there, so scoring high everywhere
# would indicate a bug just as clearly as scoring low everywhere.
#
#   source("dev/mc_recovery.R")
#   mc_one()                 # a single replication, to gauge cost
#   mc_recovery(n_rep = 20)  # a grid


#' Simulate one dataset from the paper's Monte Carlo DGP
#'
#' Follows `mc_simulation.R` lines ~516-680. Note stochastic volatility is
#' switched off by `omega = 0`, matching the paper: "we disable the stochastic
#' volatility block in our model and do not include stochastic volatility in
#' the data-generating process of the Monte Carlo simulation either".
#'
#' @return A list with `flows` (named list of `ts`, ready for `fcast_dfm()`),
#'   `f_true` (a `T_m x q_f` matrix of true factors with a leading time
#'   column) and `target`.
mc_simulate <- function(n = 25, T_m = 120, q_f = 1,
                        phi = 0.7, rho = 0, omega = 0, psi = 0.9,
                        share_q = 0.1, share_m = 0.5, cut_obs = 0.5,
                        burn_in = 500, horizon = 1){

  stopifnot(T_m %% 3 == 0)

  target <- "ch.seco.gdp.real.gdp.ssa"
  nb <- T_m + burn_in

  # --- parameters -------------------------------------------------------
  lambda_true <- matrix(stats::rnorm(n * q_f), q_f, n)   # q_f x n
  phi_mat <- diag(phi, nrow = q_f, ncol = q_f)
  rho_mat <- diag(rho, nrow = n, ncol = n)

  # --- stochastic volatility path (all zeros when omega = 0) ------------
  h <- matrix(0, nb, q_f)
  if(omega > 0){
    for(t in seq_len(nb - 1)) h[t+1, ] <- psi * h[t, ] + stats::rnorm(q_f, 0, omega)
  }

  # --- factors ----------------------------------------------------------
  f <- matrix(0, nb, q_f)
  for(t in seq_len(nb - 1)){
    f[t+1, ] <- phi_mat %*% f[t, ] + exp(h[t, ]) * stats::rnorm(q_f)
  }

  # --- measurement errors  (Sigma = I, the "e" variant in the script) ---
  e <- matrix(0, nb, n)
  for(t in seq_len(nb - 1)){
    e[t+1, ] <- as.numeric(rho_mat %*% e[t, ]) + stats::rnorm(n)
  }

  # --- discard burn-in and build the monthly latent panel ---------------
  f <- matrix(f[(burn_in+1):nb, ], nrow = T_m, ncol = q_f)
  e <- e[(burn_in+1):nb, , drop = FALSE]
  x <- f %*% lambda_true + e

  n_q <- ceiling(n * share_q)
  n_m <- ceiling(n * (share_q + share_m)) - n_q
  colnames(x) <- c(paste0("v", seq_len(n_q), "_q"),
                   if(n_m > 0) paste0("v", n_q + seq_len(n_m), "_m"),
                   paste0("v", seq_len(n - n_q - n_m) + n_q + n_m, "_shortm"))
  colnames(x)[1] <- target

  # --- Mariano-Murasawa temporal aggregation ----------------------------
  x_tam <- matrix(NA_real_, T_m, n)
  for(t in 5:T_m){
    x_tam[t, ] <- 1/3*x[t, ] + 2/3*x[t-1, ] + x[t-2, ] + 2/3*x[t-3, ] + 1/3*x[t-4, ]
  }
  colnames(x_tam) <- colnames(x)

  q_rows <- seq(6, T_m, by = 3)
  x_taq <- x_tam[q_rows, , drop = FALSE]

  # time helper columns, then drop the first two quarters (x_tam only starts
  # in month 5)
  f_true <- cbind(time = seq_len(T_m), f)
  colnames(f_true) <- c("time", paste0("f", seq_len(q_f)))
  x_m_all <- cbind(time = seq_len(T_m), x)
  x_q_all <- cbind(time = q_rows, x_taq)

  f_true <- f_true[7:T_m, , drop = FALSE]
  x_m_all <- x_m_all[7:T_m, , drop = FALSE]
  x_q_all <- x_q_all[3:nrow(x_q_all), , drop = FALSE]

  # --- split into quarterly and monthly blocks --------------------------
  q_cols <- c(grep(target, colnames(x_q_all), fixed = TRUE), grep("_q$", colnames(x_q_all)))
  m_cols <- c(grep("_m$", colnames(x_m_all)), grep("_shortm$", colnames(x_m_all)))

  dta_q <- x_q_all[1:(nrow(x_q_all) - 2), c(1, q_cols), drop = FALSE]
  dta_m <- x_m_all[1:(nrow(x_m_all) - 3 - horizon), c(1, m_cols), drop = FALSE]

  # truncate the history of the "shortm" series
  short <- grep("_shortm$", colnames(dta_m))
  if(length(short) && cut_obs > 0){
    dta_m[seq_len(floor(cut_obs * nrow(dta_m))), short] <- NA
  }

  # --- convert to ts lists ----------------------------------------------
  flows <- list()
  for(nm in setdiff(colnames(dta_q), "time")){
    flows[[nm]] <- stats::ts(dta_q[, nm],
                             start = c(1990, dta_q[1, "time"]/3), frequency = 4)
  }
  for(nm in setdiff(colnames(dta_m), "time")){
    v <- dta_m[, nm]
    ok <- which(!is.na(v))
    flows[[nm]] <- stats::ts(v[ok[1]:ok[length(ok)]],
                             start = c(1990, dta_m[ok[1], "time"]), frequency = 12)
  }

  list(flows = flows, f_true = f_true, target = target)

}


#' Rotation-invariant agreement between true and estimated factors
#'
#' Equation (17) of the paper. Invariant to any rotation of `f_hat`, which is
#' what makes it the right measure when factors are identified only up to one.
trace_r2 <- function(f_true, f_hat){

  f_true <- as.matrix(f_true); f_hat <- as.matrix(f_hat)
  num <- sum(diag(t(f_true) %*% f_hat %*% solve(t(f_hat) %*% f_hat) %*% t(f_hat) %*% f_true))
  den <- sum(diag(t(f_true) %*% f_true))
  num / den

}


#' Align the estimated factors with the true ones on their common span
#'
#' `fcast_dfm()` reports the factor over `t + s` periods, starting `s` before
#' the data; the true factors carry a month index. Both are put on the same
#' month grid and intersected.
mc_align <- function(fit, f_true){

  tt <- round((as.numeric(stats::time(fit$factor)) - 1990) * 12, 1) + 1
  f_hat <- cbind(time = tt, as.matrix(fit$factor))

  st <- max(min(f_hat[, "time"]), min(f_true[, "time"]))
  en <- min(max(f_hat[, "time"]), max(f_true[, "time"]))

  a <- f_hat[f_hat[, "time"] >= st & f_hat[, "time"] <= en, , drop = FALSE]
  b <- f_true[f_true[, "time"] >= st & f_true[, "time"] <= en, , drop = FALSE]

  # the estimated factor is monthly here, so the two grids should match once
  # intersected; guard against an off-by-one rather than silently recycling
  if(nrow(a) != nrow(b)){
    keep <- intersect(a[, "time"], b[, "time"])
    a <- a[a[, "time"] %in% keep, , drop = FALSE]
    b <- b[b[, "time"] %in% keep, , drop = FALSE]
  }

  list(f_hat = a[, -1, drop = FALSE], f_true = b[, -1, drop = FALSE])

}


#' One replication: simulate, estimate, score
mc_one <- function(q_f = 1, q_hat = q_f, n = 25, T_m = 120, cut_obs = 0.5,
                   phi = 0.7, rho = 0,
                   length_sample = 100, burn_in_mcmc = 1000, seed = NULL,
                   verbose = TRUE){

  if(!is.null(seed)) set.seed(seed)
  sim <- mc_simulate(n = n, T_m = T_m, q_f = q_f, phi = phi, rho = rho,
                     cut_obs = cut_obs)

  t0 <- Sys.time()
  fit <- tryCatch(
    suppressMessages(suppressWarnings(
      fcast_dfm(flows = sim$flows, stocks = NULL, target = sim$target,
                q = q_hat, p = 1,
                length_sample = length_sample, burn_in = burn_in_mcmc,
                plots = FALSE,
                stochastic_volatility = FALSE))),   # matches the paper's MC
    error = function(e){ if(verbose) message("  fit failed: ", conditionMessage(e)); NULL })

  if(is.null(fit)) return(list(trace_r2 = NA_real_, secs = NA_real_))

  al <- mc_align(fit, sim$f_true)
  r2 <- trace_r2(al$f_true, al$f_hat)
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if(verbose) cat(sprintf("  q_f=%d q_hat=%d cut=%.0f%%  trace R2 = %.3f   (%.0fs)\n",
                          q_f, q_hat, 100*cut_obs, r2, secs))

  list(trace_r2 = r2, secs = secs, n_obs = nrow(al$f_true))

}


#' Average the trace R-squared over replications, for one or more cells
mc_recovery <- function(cells = NULL, n_rep = 20, seed0 = 100, ...){

  if(is.null(cells)){
    cells <- list(
      list(q_f = 1, q_hat = 1, cut_obs = 0.5, target_r2 = 0.68),
      list(q_f = 2, q_hat = 2, cut_obs = 0.5, target_r2 = 0.84),
      list(q_f = 2, q_hat = 1, cut_obs = 0.5, target_r2 = 0.39)
    )
  }

  out <- lapply(seq_along(cells), function(i){

    cl <- cells[[i]]
    cat(sprintf("\ncell %d: q_f=%d q_hat=%d cut=%.0f%%  (paper: %.2f)\n",
                i, cl$q_f, cl$q_hat, 100*cl$cut_obs, cl$target_r2))

    r <- vapply(seq_len(n_rep), function(k){
      mc_one(q_f = cl$q_f, q_hat = cl$q_hat, cut_obs = cl$cut_obs,
             seed = seed0 + 1000*i + k, verbose = FALSE, ...)$trace_r2
    }, numeric(1))

    cat(sprintf("  mean %.3f   sd %.3f   se %.3f   n_ok %d/%d   paper %.2f\n",
                mean(r, na.rm = TRUE), stats::sd(r, na.rm = TRUE),
                stats::sd(r, na.rm = TRUE)/sqrt(sum(!is.na(r))),
                sum(!is.na(r)), n_rep, cl$target_r2))

    data.frame(q_f = cl$q_f, q_hat = cl$q_hat, cut_obs = cl$cut_obs,
               mean = mean(r, na.rm = TRUE), sd = stats::sd(r, na.rm = TRUE),
               n_ok = sum(!is.na(r)), paper = cl$target_r2)
  })

  do.call(rbind, out)

}
