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
#   mc_one()          # a single replication, to gauge cost (~40s)
#   mc_recovery()     # the three published cells; reproduces MC_RESULTS_PATH
#   mc_report()       # summarise the stored run without recomputing it
#
# mc_recovery()'s defaults ARE the run reported on #52 - the same cells, the
# same per-cell replication counts and the same seeds - so it reproduces those
# numbers rather than merely similar ones. That costs 40+ minutes; it saves
# incrementally to dev/mc_results.rds after every replication, so it can be
# interrupted and resumed, and mc_report() reads that file back.
#
# Like dev/baseline.R this is deliberately NOT a CI test. MCMC output is not
# bit-identical across platforms and BLAS implementations, the run takes tens of
# minutes, and the quantity being checked is a Monte Carlo mean with a standard
# error - a pass/fail threshold on it would be either vacuous or flaky. The
# result snapshot is committed for the same reason baseline.rds is: so it can be
# compared across commits, and so regenerating it is a visible act in the diff.


MC_RESULTS_PATH <- "dev/mc_results.rds"


#' The cells reported on #52
#'
#' Replication counts differ by cell because the q_f = 1 cell came out 3.3
#' standard errors above the paper's value on the first 10 replications, which
#' needed more data before it could be called signal or noise. It settled at
#' 0.717 with the paper's 0.68 inside the 95% interval.
MC_CELLS <- list(
  list(tag = "qf1_qhat1", q_f = 1, q_hat = 1, cut_obs = 0.5, paper = 0.68, n_rep = 40),
  list(tag = "qf2_qhat2", q_f = 2, q_hat = 2, cut_obs = 0.5, paper = 0.84, n_rep = 20),
  list(tag = "qf2_qhat1", q_f = 2, q_hat = 1, cut_obs = 0.5, paper = 0.39, n_rep = 20)
)


#' Seed for one replication
#'
#' Fixed as a function of the cell and replication index, so the reported run is
#' reproducible and resuming an interrupted run repeats the same draws.
mc_seed <- function(q_f, q_hat, k) 90000 + 1000 * q_f + 100 * q_hat + k


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


#' Run the replications and write the result snapshot
#'
#' Defaults reproduce the run reported on #52. Saves after every replication, so
#' an interrupted run resumes where it stopped rather than starting over; pass
#' `resume = FALSE` to discard what is stored and start clean.
#'
#' @param cells List of cell specifications; see `MC_CELLS`.
#' @param path Where to write the snapshot.
#' @param resume Keep replications already stored in `path`.
#'
#' @return The summary table, invisibly (also printed).
mc_recovery <- function(cells = MC_CELLS, path = MC_RESULTS_PATH,
                        resume = TRUE, ...){

  res <- if(resume && file.exists(path)) readRDS(path) else list()

  for(cl in cells){

    have <- if(is.null(res[[cl$tag]])) numeric(0) else res[[cl$tag]]$r2
    todo <- seq_len(cl$n_rep)[-seq_along(have)]

    cat(sprintf("\n=== %s (paper %.2f, %d reps, %d already stored) ===\n",
                cl$tag, cl$paper, cl$n_rep, length(have)))

    for(k in todo){
      one <- mc_one(q_f = cl$q_f, q_hat = cl$q_hat, cut_obs = cl$cut_obs,
                    seed = mc_seed(cl$q_f, cl$q_hat, k), verbose = FALSE, ...)
      have <- c(have, one$trace_r2)
      # store after each replication: a 40-minute run should not be all-or-nothing
      res[[cl$tag]] <- list(paper = cl$paper, r2 = have)
      saveRDS(res, path)

      if(k %% 5 == 0){
        ok <- have[!is.na(have)]
        cat(sprintf("  %2d reps: mean %.3f  se %.3f  (paper %.2f)\n",
                    length(ok), mean(ok), stats::sd(ok)/sqrt(length(ok)), cl$paper))
      }
    }
  }

  mc_report(path)

}


#' Summarise a stored run, without recomputing it
#'
#' Reports the Monte Carlo mean against the paper's value with a 95% interval,
#' which is the form the comparison has to take: the target is a mean with a
#' standard error, not a fixed number to match.
#'
#' @return A data frame, invisibly (also printed).
mc_report <- function(path = MC_RESULTS_PATH){

  if(!file.exists(path)){
    stop("No stored run at ", path, ". Run mc_recovery() first.", call. = FALSE)
  }
  res <- readRDS(path)

  out <- do.call(rbind, lapply(names(res), function(tag){
    r <- res[[tag]]$r2
    r <- r[!is.na(r)]
    se <- stats::sd(r)/sqrt(length(r))
    ci <- mean(r) + c(-1.96, 1.96)*se
    data.frame(cell = tag, n = length(r), paper = res[[tag]]$paper,
               mean = mean(r), sd = stats::sd(r), se = se,
               lo = ci[1], hi = ci[2],
               paper_inside = res[[tag]]$paper >= ci[1] & res[[tag]]$paper <= ci[2],
               stringsAsFactors = FALSE)
  }))

  cat("\nSimulation recovery, trace R-squared (Eckert et al. 2025, Eq. 17)\n\n")
  cat(sprintf("%-11s %4s %7s %8s %7s   %-18s %s\n",
              "cell", "n", "paper", "mean", "sd", "95% CI for mean", "paper inside?"))
  for(i in seq_len(nrow(out))){
    cat(sprintf("%-11s %4d %7.2f %8.3f %7.3f   [%.3f, %.3f]     %s\n",
                out$cell[i], out$n[i], out$paper[i], out$mean[i], out$sd[i],
                out$lo[i], out$hi[i], if(out$paper_inside[i]) "yes" else "NO"))
  }
  cat("\n", if(all(out$paper_inside)) "All published values inside the 95% interval."
      else "SOME published values fall outside the interval.", "\n", sep = "")

  invisible(out)

}
