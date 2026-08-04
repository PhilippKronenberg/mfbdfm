# Helpers for the multi-factor model of Eckert et al. (2025), used by
# fcast_dfm(). Draws are stored packed into a single numeric vector per
# retained iteration ("theta") so that a rotation matrix can be applied to a
# whole draw with one matrix multiplication (see create_h_fcast() in rotation.R).
# All functions here are internal.

#' Pack one draw of the model parameters into a single vector
#'
#' The packing order is fixed and must match [theta2list_fcast()]:
#' `lambda` (`n*q`), `phi` (`p*q^2`), `sigma` (`n`), `rho` (`n`),
#' `Xmat` (`n*t`), `h` (`t+s`).
#'
#' @noRd
list2theta_fcast <- function(lambda, phi, sigma, rho, Xmat, h){

  rbind(matrix(lambda),
        do.call(rbind, lapply(phi, function(x) matrix(x))),
        matrix(sigma),
        matrix(rho),
        matrix(Xmat),
        matrix(h))

}


#' Unpack a draw vector back into named model parameters
#'
#' Inverse of [list2theta_fcast()].
#'
#' @details
#' `phi` is read back **column-major, block by block**, which is how
#' [list2theta_fcast()] writes it (`matrix(x)` on each `q x q` block). It
#' previously used `matrix(..., byrow = TRUE)` across the whole `phi` region,
#' which returned each block transposed for `q > 1` -- and that transposed copy
#' was then handed to [draw_factors_fcast()] by [run_evaluation_fcast()], while
#' the sampler itself passes the untransposed one. See #66 and the note in
#' CLAUDE.md. `q = 1` was unaffected, a 1x1 block being its own transpose.
#'
#' @noRd
theta2list_fcast <- function(theta, n, p, q, t){

  list(lambda = matrix(theta[c(1:(n*q)),], ncol = q),
       phi =  lapply(1:p, function(px){
         matrix(theta[(n*q + (px-1)*q^2 + 1):(n*q + px*q^2), ], nrow = q, ncol = q)}),
       sigma = theta[c((n*q+p*q^2+1):(n*q+p*q^2+n)),],
       rho = theta[c((n*q+p*q^2+n+1):(n*q+p*q^2+2*n)),],
       Xmat = matrix(theta[c((n*q+p*q^2+2*n+1):(n*q+p*q^2+2*n+n*t)),], ncol = n),
       h = theta[c((n*q+p*q^2+2*n+n*t+1):nrow(theta)),])

}


#' Convert a stacked VAR coefficient vector into a list of lag matrices
#'
#' @noRd
vec2list_fcast <- function(x, p, q){

  x_adj <- x
  dim(x_adj) <- c(p*q,q)
  lapply(seq(from = 1, to = p*q, by = q), function(ix) t(x_adj)[,c(ix:(ix+q-1))])

}


#' Convert a list of VAR lag matrices into a stacked coefficient vector
#'
#' Inverse of [vec2list_fcast()].
#'
#' @noRd
list2vec_fcast <- function(x){

  matrix(t(do.call(cbind,x)))

}


#' Companion-form matrix of a VAR(p) coefficient list
#'
#' Used for the stationarity check in [draw_phi_fcast()]: the VAR is stationary
#' when all eigenvalues of this matrix lie inside the unit circle.
#'
#' @noRd
companion_fcast <- function(phi, p, q){

  rbind(do.call(cbind,phi),cbind(diag(1,(p-1)*q),matrix(0,(p-1)*q,q)))

}


#' Posterior mean and variance of the rotated factors
#'
#' @noRd
#' @importFrom stats ts time frequency var
get_factors_fcast <- function(Ymat, f_draws, inventory, n, q, p, s, t){

  list("mean" =  ts(Reduce("+",f_draws)/length(f_draws),
                    start = time(Ymat)[1]-(s/frequency(Ymat)),
                    frequency = frequency(Ymat)),
       "var" = ts(do.call(cbind,
                          lapply(1:q, function(qx){

                            f_qx <- do.call(cbind, lapply(f_draws, function(rx) rx[,qx]))
                            apply(f_qx,1,var)

                          })),
                  start = time(Ymat)[1]-(s/frequency(Ymat)),
                  frequency = frequency(Ymat)))

}


#' Per-series nowcasts from the augmented dataset
#'
#' Unlike [get_nowcast()] (which extracts the single target series for
#' `ind_dfm()`), this returns the mean and variance of the fitted value for
#' *every* series, each at that series' own frequency.
#'
#' @noRd
#' @importFrom stats ts time var
get_nowcast_fcast <- function(Xmat, Ymat, rlist, inventory, n, q, p, s, t){

  Xmat_list <- lapply(rlist, function(x) {
    Xm <- theta2list_fcast(theta = x, n, p, q, t)$Xmat
    colnames(Xm) <- inventory$key
    Xm

  })

  Xmat_draws <- lapply(inventory$key, function(x){

    # get the entry where the data is usually recorded
    resid <- (time(Ymat) + 1/max(inventory$freq)) %% (1/inventory[which(inventory$key == x),"freq"])
    idx <- round(resid,3) == 0 | round(resid,3) == round(1/inventory[which(inventory$key == x),"freq"],3)

    # extract and rescale all draws
    do.call(cbind, lapply(Xmat_list, function(Xm){

      (Xm[idx, x] * inventory[which(inventory$key == x),"sd"]) +
        inventory[which(inventory$key == x),"mean"]

    }))

  }); names(Xmat_draws) <- inventory$key

  out_mean <- lapply(names(Xmat_draws), function(x){

    ts(apply(Xmat_draws[[x]],1,mean),
       start = time(Ymat)[1],
       frequency = inventory[which(inventory$key == x),"freq"])

  }); names(out_mean) <- names(Xmat_draws)


  out_var <- lapply(names(Xmat_draws), function(x){

    ts(apply(Xmat_draws[[x]],1,var),
       start = time(Ymat)[1],
       frequency = inventory[which(inventory$key == x),"freq"])

  }); names(out_var) <- names(Xmat_draws)


  list("mean" = out_mean, "var" = out_var)

}


#' High-frequency growth-rate estimates for every series
#'
#' Projects each series onto the factor space using its own loadings, then
#' de-standardizes and annualizes, giving a high-frequency counterpart of
#' each (possibly low-frequency) input series.
#'
#' @noRd
#' @importFrom stats ts time frequency var
get_hfts_fcast <- function(Ymat, f_draws, th_mean, inventory, n, q, p, s, t, k){

  # get weekly growth rates for each time series
  out_draws <- lapply(inventory$key, function(ix){

    k <- max(inventory$freq)/min(inventory$freq) # Fraction of high-frequency periods in lowest frequency
    s <- 2*(k - 1) # Number of periods for aggregation rule in formula (3)

    lapply(f_draws, function(fx){

      f_cut <- ts(apply(fx %*% diag(x = th_mean$lambda[which(inventory$key == ix),], nrow = q),1,sum),
                  start = time(Ymat)[1],
                  frequency = frequency(Ymat))

      # de-standardize data using mean and variance from original series
      f_rescaled <- (f_cut * inventory[which(inventory$key == ix),"sd"]) +
        inventory[which(inventory$key == ix),"mean"]/(q*(2*k-1))

      # annualize
      ((1+f_rescaled)^frequency(Ymat)-1)*100

    })

  }); names(out_draws) <- inventory$key


  out_mean <- lapply(out_draws, function(ix){

    ts(data = apply(do.call(cbind, ix), 1, mean),
       start = time(Ymat)[1]-(s/frequency(Ymat)),
       frequency = frequency(Ymat))

  })

  out_var <- lapply(out_draws, function(ix){

    ts(data = apply(do.call(cbind, ix), 1, var),
       start = time(Ymat)[1]-(s/frequency(Ymat)),
       frequency = frequency(Ymat))

  })


  list("mean" = out_mean, "var" = out_var)

}


#' Assemble the fcast_dfm() output object from rotated draws
#'
#' @noRd
#' @importFrom stats ts time frequency var
run_evaluation_fcast <- function(rlist, Ymat, Gmat_prealloc, k, n, q, p, s, t, inventory,
                           flows, stocks, target){

  # gather factor draws
  f_draws <- lapply(rlist, function(rx){

    th_rx <- theta2list_fcast(theta = rx, n, p, q, t)

    Gmat <- get_gmat(Gmat_prealloc,
                     Llist = get_distributed_lags(inventory),
                     rho = Diagonal(x = th_rx$rho),
                     lambda = th_rx$lambda,
                     s = s,
                     t = t,
                     n = n)

    draw_factors_fcast(Xmat = th_rx$Xmat,
                    Gmat = Gmat,
                    n = n,
                    q = q,
                    p = p,
                    s = s,
                    t = t,
                    lambda = th_rx$lambda,
                    phi = th_rx$phi,
                    sigma = Diagonal(x = th_rx$sigma),
                    h = th_rx$h,
                    rho = Diagonal(x = th_rx$rho))

  })

  # retrieve mean and variance of the estimated factors
  fcts <- get_factors_fcast(Ymat = Ymat, f_draws = f_draws, inventory = inventory,
                      n = n, q = q, p = p, s = s, t = t)

  # get average of all parameter draws
  th_mean <- theta2list_fcast(theta = Reduce("+",rlist)/length(rlist), n, p, q, t)

  # get mean and variance of nowcasts
  ncst <- get_nowcast_fcast(Xmat = th_mean$Xmat,
                         Ymat = Ymat,
                         rlist = rlist,
                         inventory = inventory,
                         n = n, q = q, p = p, s = s, t = t)

  # get mean and variance of high frequency data
  hfts <- get_hfts_fcast(Ymat = Ymat, f_draws = f_draws, th_mean = th_mean, inventory = inventory,
                   n = n, q = q, p = p, s = s, t = t, k = k)

  # get distribution of parameters
  rho_var <- apply(do.call(cbind, lapply(rlist, function(rx){

    theta2list_fcast(rx, n, p, q, t)$rho

  })),1, var)

  # gather output
  out <- list("factor" = fcts$mean,
              "factor_var" = fcts$var,
              "target" = target,
              "nowcast" = ncst$mean[[target]],
              "nowcast_var" = ncst$var[[target]],
              "pars" =  list("lambda" = th_mean$lambda,
                             "phi" = th_mean$phi,
                             "sigma" = th_mean$sigma,
                             "rho" = th_mean$rho,
                             "rho_var" = rho_var,
                             "h" = ts(th_mean$h,
                                      start = time(fcts$mean)[1],
                                      frequency = frequency(fcts$mean)),
                             "n" = n,
                             "q" = q,
                             "p" = p,
                             "s" = s,
                             "t" = t,
                             "k" = k),
              "ncst" = ncst,
              # `data` is the prepared matrix in BOTH fit classes and
              # `data_raw` the series as supplied (#50). This used to be the
              # other way round here, so `fit$data` meant a matrix for
              # ind_dfm and a list for fcast_dfm.
              "data" = Ymat,
              "data_raw" = c(stocks,flows),
              "data_hf" = hfts,
              "data_augmented" = ts(th_mean$Xmat,
                                    start = time(Ymat)[1],
                                    frequency = frequency(Ymat)),
              "inventory" = inventory)

  colnames(out$data_augmented) <- colnames(Ymat)

  # Get rescaled augmented data series
  out$data_augmented_rescaled <- lapply(inventory$key, function(ix){

    (out$data_augmented[,which(inventory$key == ix)] * inventory[which(inventory$key == ix),"sd"]) +
      inventory[which(inventory$key == ix),"mean"]

  }); names(out$data_augmented_rescaled) <- inventory$key

  # collect everything about the target series in one place for inspection
  out$target_series <- get_target_series_fcast(out, target)

  return(out)

}


#' Collect the target series' observed, nowcast and high-frequency estimates
#'
#' Gathers, in one place, everything the model says about the series named by
#' `target`: the observed input data, the nowcast at the target's own
#' frequency, and the high-frequency estimate, each with 95% bands. This is
#' purely for inspection - it re-packages values already present elsewhere in
#' the fit object and does not enter the estimation.
#'
#' @noRd
#' @importFrom stats time qnorm
get_target_series_fcast <- function(out, target){

  z <- qnorm(0.975)

  # nowcast at the target's own frequency
  ncst_mean <- out$ncst$mean[[target]]
  ncst_sd <- sqrt(out$ncst$var[[target]])
  nowcast <- data.frame(time = as.numeric(time(ncst_mean)),
                        mean = as.numeric(ncst_mean),
                        lower = as.numeric(ncst_mean - z * ncst_sd),
                        upper = as.numeric(ncst_mean + z * ncst_sd))

  # observed input values, aligned onto the same time axis where they exist
  observed <- out$data_raw[[target]]
  if(!is.null(observed)){
    obs_df <- data.frame(time = round(as.numeric(time(observed)), 5),
                         observed = as.numeric(observed))
    nowcast$observed <- obs_df$observed[match(round(nowcast$time, 5), obs_df$time)]
  } else {
    nowcast$observed <- NA_real_
  }
  nowcast <- nowcast[, c("time", "observed", "mean", "lower", "upper")]

  # high-frequency growth-rate estimate
  hf_mean <- out$data_hf$mean[[target]]
  hf_sd <- sqrt(out$data_hf$var[[target]])
  high_frequency <- data.frame(time = as.numeric(time(hf_mean)),
                               mean = as.numeric(hf_mean),
                               lower = as.numeric(hf_mean - z * hf_sd),
                               upper = as.numeric(hf_mean + z * hf_sd))

  list(name = target, nowcast = nowcast, high_frequency = high_frequency)

}
