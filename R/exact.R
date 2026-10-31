# Exact conditional estimates over stored parameter draws (#171).
#
# Given the parameters and the volatility path the whole system is one sparse
# Gaussian, the same one contributions.R and news.R use at the posterior mean. So
# the factor and the nowcast do not have to be averaged from sampled paths: their
# conditional mean is a linear solve. The chain only has to supply the parameters.


#' Exact estimate of the factor and the nowcast over stored parameter draws
#'
#' Replaces the sampled factor and nowcast paths in a posterior average by exact
#' conditional calculations at a set of the chain's retained parameter draws. The
#' parameter draws still come from the chain, so this removes the simulation noise
#' of the latent paths and not any error in the distribution of the parameters.
#'
#' @details
#' For each selected draw of the parameters and the volatility path, the latent
#' data and the factor given the observations are jointly Gaussian with a sparse
#' precision matrix. The nowcast is linear in them, so its conditional mean comes
#' from one solve, with no simulation. The published factor is a nonlinear function
#' of the standardised one, so its mean and variance use `paths` draws from that
#' Gaussian, in antithetic pairs.
#'
#' Total variances combine the two parts:
#' `Var = E[Var(. | parameters)] + Var(E[. | parameters])`. The first is what a
#' chain has to simulate and the second is what is left to estimate from
#' parameter draws. `mcse_nowcast` is the Monte Carlo error of the nowcast from the
#' second part alone, treating the selected draws as independent, which the even
#' spacing along the chain makes roughly true for a chain that mixes.
#'
#' Applies to [ind_dfm()] only. A [fcast_dfm()] fit identifies its factors after
#' sampling, so its draws are not comparable before that step.
#'
#' Takes about 1 to 2 seconds per selected draw on a 46-series weekly panel.
#'
#' @param fit A fitted [ind_dfm()] model carrying its draws, the default. A fit
#'   made before this function existed holds no volatility paths and is refused.
#' @param n_draws Whole number, how many parameter draws to use, evenly spaced
#'   along the chain. At most the 200 stored.
#' @param paths Even whole number, simulated factor paths per parameter draw.
#' @param seed Optional whole number, for reproducible simulated paths. The caller's
#'   random stream is restored afterwards.
#'
#' @return An object of class `"mfbdfm_exact"`, a list with `factor`, `factor_var`,
#'   `index`, `nowcast` and `nowcast_var`, on the scales and date axes of the same
#'   components of `fit`, and `nowcast_between` (the conditional means, one row per
#'   selected draw), `mcse_nowcast`, `n_draws` and `paths`.
#'
#' @seealso [ind_dfm()], [mfbdfm_contributions()].
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#' set.seed(1)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 100, burn_in = 20)
#' ex <- mfbdfm_exact(fit, n_draws = 5, paths = 4)
#' ex
#' utils::tail(ex$nowcast, 2)
#' }
#'
#' @family model functions
#' @importFrom stats rnorm var sd ts tsp frequency time
#' @export
mfbdfm_exact <- function(fit, n_draws = 100, paths = 20, seed = NULL){

  if(!inherits(fit, "ind_dfm")){
    stop("`fit` must be a fitted model from ind_dfm(), not an object of class ",
         paste(class(fit), collapse = "/"), ".", call. = FALSE)
  }
  d <- fit$draws
  if(is.null(d) || is.null(d$h_paths)){
    stop("`fit` holds no stored volatility paths. Refit it with this version of ",
         "the package and `keep_draws = TRUE`, the default.", call. = FALSE)
  }
  if(!is_count(n_draws) || n_draws < 1){
    stop("`n_draws` must be a positive whole number, not ", deparse(n_draws), ".",
         call. = FALSE)
  }
  if(!is_count(paths) || paths < 2 || paths %% 2 != 0){
    stop("`paths` must be a positive even whole number, not ", deparse(paths), ".",
         call. = FALSE)
  }
  if(!is.null(seed)){
    if(!is_count(seed)) stop("`seed` must be a single whole number or NULL.", call. = FALSE)
    old <- if(exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv())
    on.exit(if(is.null(old)) rm(".Random.seed", envir = globalenv()) else
      assign(".Random.seed", old, envir = globalenv()), add = TRUE)
    set.seed(seed)
  }

  n_stored <- length(d$h_rows)
  picks <- unique(round(seq(1, n_stored, length.out = min(n_draws, n_stored))))
  rows <- d$h_rows[picks] + d$info$n_burn_in
  pars <- d$parameters[rows, , drop = FALSE]
  h_paths <- d$h_paths[picks, , drop = FALSE]

  inv <- fit$inventory
  keys <- inv$key
  Y <- as.matrix(fit$data)
  n <- ncol(Y); t <- nrow(Y)
  s <- ncol(h_paths) - t
  tx <- which(keys == fit$target)
  sd_t <- inv$sd[tx]; mean_t <- inv$mean[tx]
  fq <- max(inv$freq)
  k <- fq/min(inv$freq)

  nc_rows <- target_period_rows(tt = stats::time(fit$data), freq_max = fq, freq = inv$freq[tx])
  n_nc <- length(fit$nowcast)
  nc_rows <- nc_rows[seq_len(n_nc)]
  n_f <- length(fit$factor)
  phi_cols <- grep("^phi[0-9]+$", colnames(pars))

  obj <- fit
  obj$draws <- NULL

  K <- length(picks)
  nc_mean <- matrix(NA_real_, K, n_nc)
  nc_var <- numeric(n_nc)
  f_sum <- numeric(n_f); f_sq <- numeric(n_f)
  i_sum <- numeric(n_f)

  for(i in seq_len(K)){

    obj$pars$lambda <- Matrix(pars[i, paste0("lambda[", keys, "]")], n, 1)
    obj$pars$sigma <- pars[i, paste0("sigma[", keys, "]")]
    obj$pars$rho <- pars[i, paste0("rho[", keys, "]")]
    obj$pars$phi <- pars[i, phi_cols]
    obj$internal$h_full <- h_paths[i,]

    J <- dfm_joint_precision(obj)
    ch <- Cholesky(forceSymmetric(J$Q[J$ix_lat, J$ix_lat]), LDL = FALSE, perm = TRUE)
    m <- as.numeric(solve(ch, -J$Q[J$ix_lat, J$ix_obs] %*% J$y, system = "A"))

    z <- numeric(t + s + n*t)
    z[J$ix_obs] <- J$y

    target_x <- function(zz) zz[t + s + (nc_rows - 1L)*n + tx]*sd_t + mean_t
    z[J$ix_lat] <- m
    nc_m <- target_x(z)
    nc_mean[i,] <- nc_m

    for(px in seq_len(paths/2)){
      dev <- as.numeric(solve(ch, solve(ch, rnorm(length(m)), system = "Lt"), system = "Pt"))
      for(sgn in c(-1, 1)){
        z[J$ix_lat] <- m + sgn*dev
        nc_var <- nc_var + (target_x(z) - nc_m)^2
        r <- z[(s + 1):(t + s)][seq_len(n_f)]*sd_t + mean_t/k
        f_i <- ((1 + r)^fq - 1)*100
        f_sum <- f_sum + f_i
        f_sq <- f_sq + f_i^2
        i_sum <- i_sum + cumprod(1 + r)
      }
    }

  }

  n_paths <- K*paths
  f_mean <- f_sum/n_paths
  nc_within <- nc_var/n_paths
  nc_between <- if(K > 1) apply(nc_mean, 2, var) else rep(0, n_nc)

  like <- function(x, template) ts(x, start = stats::start(template), frequency = frequency(template))

  structure(list(factor = like(f_mean, fit$factor),
                 factor_var = like(f_sq/n_paths - f_mean^2, fit$factor),
                 index = like(i_sum/n_paths*100, fit$factor),
                 nowcast = like(colMeans(nc_mean), fit$nowcast),
                 nowcast_var = like(nc_within + nc_between, fit$nowcast),
                 nowcast_between = nc_mean,
                 mcse_nowcast = like(sqrt(nc_between/K), fit$nowcast),
                 n_draws = K, paths = paths),
            class = "mfbdfm_exact")

}


#' A fit whose factor and nowcast are the exact estimates
#'
#' What the publishing scripts read, so that the exports need no second code path.
#'
#' @noRd
fit_with_exact <- function(fit, exact){

  for(nm in c("factor", "factor_var", "index", "nowcast", "nowcast_var")){
    fit[[nm]] <- exact[[nm]]
  }
  fit$exact <- list(n_draws = exact$n_draws, paths = exact$paths,
                    mcse_nowcast = exact$mcse_nowcast)
  fit

}


#' @rdname mfbdfm_exact
#' @method print mfbdfm_exact
#' @param x An object from `mfbdfm_exact()`.
#' @param ... Ignored.
#' @export
print.mfbdfm_exact <- function(x, ...){

  cat("Exact estimate over", x$n_draws, "parameter draws,", x$paths, "factor paths each\n")
  last <- length(x$nowcast)
  cat(sprintf("  latest nowcast : %.5f (sd %.5f, Monte Carlo error %.5f)\n",
              x$nowcast[last], sqrt(x$nowcast_var[last]), x$mcse_nowcast[last]))
  cat(sprintf("  latest factor  : %.3f (sd %.3f)\n",
              x$factor[length(x$factor)], sqrt(x$factor_var[length(x$factor)])))
  invisible(x)

}
