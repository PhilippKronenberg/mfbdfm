# Checks on a fit's published quantities, for use before publishing (#172).
#
# mfbdfm_diagnostics() judges parameters. This judges what a reader sees. A clean
# parameter table does not certify a nowcast: on the real panel, a fit with most
# parameters clean had a nowcast effective sample size below 10.


#' Rank-normalise a chain (Vehtari et al. 2021)
#'
#' @noRd
rank_normal <- function(x){
  stats::qnorm((rank(x, ties.method = "average") - 3/8)/(length(x) + 1/4))
}


#' Effective sample size of a rank-normalised chain
#'
#' @noRd
ess_rank <- function(x){
  if(stats::sd(x) < 1e-12) return(NA_real_)
  as.numeric(coda::effectiveSize(coda::mcmc(rank_normal(x))))
}


#' Split R-hat of a rank-normalised chain
#'
#' One chain cut in half, so it detects drift within the chain and not two chains
#' settling in different places.
#'
#' @noRd
rhat_split <- function(x){
  if(stats::sd(x) < 1e-12) return(NA_real_)
  z <- rank_normal(x)
  n <- floor(length(z)/2)
  a <- z[seq_len(n)]
  b <- z[length(z) - n + seq_len(n)]
  W <- (stats::var(a) + stats::var(b))/2
  B <- n*stats::var(c(mean(a), mean(b)))
  sqrt(((n - 1)/n*W + B/n)/W)
}


#' Quality checks on a fit's published quantities
#'
#' Measures the mixing and the precision of what is actually published, which
#' parameter diagnostics do not. Meant as a gate: if a check fails, keep the
#' last publication and investigate, rather than lowering the bar.
#'
#' @details
#' For the latest unobserved nowcast (annualised percentage points), and for an
#' [ind_dfm()] fit also for the latest weekly factor value and the mean of the
#' latest 13 weeks:
#'
#' \describe{
#'   \item{`ess`}{Rank-normalised effective sample size, at least `ess_min`.}
#'   \item{`mcse`}{Monte Carlo error of the mean, `sd / sqrt(ess)`, at most
#'     `mcse_max`.}
#'   \item{`rhat`}{Split R-hat from one chain cut in half, at most `rhat_max`.}
#' }
#'
#' And for the fit as a whole:
#'
#' \describe{
#'   \item{`anchor`}{An [ind_dfm()] nowcast reproduces the observed target, largest
#'     absolute difference at most `anchor_max`.}
#'   \item{`rho_fallback`}{How often `rho` was forced to `rho_fallback` rather than
#'     drawn, at most `fallback_max` of the draws per series. An [ind_dfm()] fit.}
#'   \item{`parameters`}{The smallest effective sample size among the identified
#'     parameters, at least `param_ess_min`.}
#'   \item{`exact`}{With `exact`, the chain's latest nowcast differs from
#'     [mfbdfm_exact()]'s by at most `exact_z` joint Monte Carlo errors.}
#'   \item{`unexplained`}{With `unexplained`, the part of a revision the news
#'     decomposition leaves unexplained is at most `unexplained_max`.}
#' }
#'
#' The default limits follow Vehtari et al. (2021) for ESS and R-hat. The limit on
#' the Monte Carlo error is a judgement about one-decimal communication: `mcse_max`
#' of 0.10 means that two runs differ by about 0.14 (one standard deviation).
#'
#' @param fit A fitted model carrying its draws, the default.
#' @param exact Optional result of [mfbdfm_exact()] on `fit`.
#' @param unexplained Optional single number: the published revision minus the
#'   sum of its news, in annualised points.
#' @param ess_min,mcse_max,rhat_max,anchor_max,fallback_max,param_ess_min,exact_z,unexplained_max
#'   The limits, see Details.
#'
#' @return A data frame of class `"mfbdfm_quality"` with columns `check`, `value`,
#'   `limit`, `pass`. A check that does not apply here is left out. `pass` is `NA`
#'   for one that cannot be judged, such as a constant chain. The attribute `pass`
#'   is `TRUE` only if no row has `pass` of `FALSE`.
#'
#' @references
#' Vehtari, A., Gelman, A., Simpson, D., Carpenter, B., & Burkner, P.-C. (2021).
#' Rank-normalization, folding, and localization: An improved R-hat for assessing
#' convergence of MCMC. *Bayesian Analysis*, 16(2), 667-718.
#' \doi{10.1214/20-BA1221}
#'
#' @seealso [mfbdfm_diagnostics()] for every parameter, [mfbdfm_exact()].
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#' set.seed(1)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 200, burn_in = 50)
#' q <- mfbdfm_quality(fit)
#' q
#' attr(q, "pass")
#' }
#'
#' @family model functions
#' @export
mfbdfm_quality <- function(fit, exact = NULL, unexplained = NULL,
                           ess_min = 400, mcse_max = 0.10, rhat_max = 1.01,
                           anchor_max = 1e-3, fallback_max = 0.01,
                           param_ess_min = 100, exact_z = 3, unexplained_max = 0.5){

  if(!inherits(fit, c("ind_dfm", "fcast_dfm"))){
    stop("`fit` must be a fitted model from ind_dfm() or fcast_dfm(), not an object ",
         "of class ", paste(class(fit), collapse = "/"), ".", call. = FALSE)
  }
  d <- fit$draws
  if(is.null(d)){
    stop("`fit` carries no draws. Refit it with `keep_draws = TRUE`, the default.",
         call. = FALSE)
  }
  if(!is.null(exact) && !inherits(exact, "mfbdfm_exact")){
    stop("`exact` must come from mfbdfm_exact(), not an object of class ",
         paste(class(exact), collapse = "/"), ".", call. = FALSE)
  }
  if(!is.null(unexplained) && (!is.numeric(unexplained) || length(unexplained) != 1L ||
                               is.na(unexplained))){
    stop("`unexplained` must be a single number or NULL.", call. = FALSE)
  }

  rows <- list()
  add <- function(check, value, limit, pass){
    rows[[length(rows) + 1L]] <<- data.frame(check = check, value = as.numeric(value),
                                             limit = as.numeric(limit), pass = pass,
                                             stringsAsFactors = FALSE)
  }
  judge <- function(ok) if(length(ok) != 1L || is.na(ok)) NA else ok

  chain_checks <- function(label, x){
    e <- ess_rank(x)
    m <- if(is.na(e)) NA_real_ else stats::sd(x)/sqrt(e)
    r <- rhat_split(x)
    add(paste0(label, ": ess"), e, ess_min, judge(e >= ess_min))
    add(paste0(label, ": mcse"), m, mcse_max, judge(m <= mcse_max))
    add(paste0(label, ": rhat"), r, rhat_max, judge(r <= rhat_max))
  }

  # the latest quarter the chain actually has to estimate
  NC <- d$nowcast
  latent <- which(apply(NC, 2, stats::sd)*400 > 1e-3)
  nc_col <- if(length(latent)) max(latent) else NA_integer_
  if(!is.na(nc_col)) chain_checks("latest nowcast", NC[, nc_col]*400)

  if(!is.null(d$factor_recent)){
    chain_checks("latest week", d$factor_recent[, ncol(d$factor_recent)])
    chain_checks("latest 13 weeks", rowMeans(d$factor_recent))
  }

  if(inherits(fit, "ind_dfm")){

    target <- stats::na.omit(fit$data_raw[[fit$target]])
    n_obs <- min(length(target), length(fit$nowcast))
    gap <- max(abs(as.numeric(fit$nowcast)[seq_len(n_obs)] - as.numeric(target)[seq_len(n_obs)]))
    add("anchor", gap, anchor_max, judge(gap <= anchor_max))

    if(!is.null(fit$internal$rho_fallback)){
      share <- fit$internal$rho_fallback/(nrow(NC)*nrow(fit$inventory))
      add("rho_fallback", share, fallback_max, judge(share <= fallback_max))
    }

  }

  P <- d$parameters
  if(d$info$n_burn_in > 0) P <- P[-seq_len(d$info$n_burn_in), , drop = FALSE]
  P <- P[, setdiff(colnames(P), d$info$unidentified), drop = FALSE]
  ess_all <- apply(P, 2, ess_rank)
  worst <- suppressWarnings(min(ess_all, na.rm = TRUE))
  add("parameters: smallest ess", worst, param_ess_min, judge(worst >= param_ess_min))

  if(!is.null(exact) && !is.na(nc_col)){
    x <- NC[, nc_col]*400
    e <- ess_rank(x)
    pos <- min(nc_col, length(exact$nowcast))
    se <- sqrt((stats::sd(x)^2/e) + (exact$mcse_nowcast[pos]*400)^2)
    z <- abs(mean(x) - exact$nowcast[pos]*400)/se
    add("chain vs exact: |z|", z, exact_z, judge(z <= exact_z))
  }

  if(!is.null(unexplained)){
    add("unexplained revision", abs(unexplained), unexplained_max,
        judge(abs(unexplained) <= unexplained_max))
  }

  out <- do.call(rbind, rows)
  structure(out, class = c("mfbdfm_quality", "data.frame"),
            pass = !any(out$pass %in% FALSE))

}


#' @rdname mfbdfm_quality
#' @method print mfbdfm_quality
#' @param x An object from `mfbdfm_quality()`.
#' @param ... Ignored.
#' @export
print.mfbdfm_quality <- function(x, ...){

  cat("Quality checks:", if(isTRUE(attr(x, "pass"))) "PASS" else "FAIL", "\n")
  for(i in seq_len(nrow(x))){
    cat(sprintf("  %-4s %-28s %10s   limit %s\n",
                if(is.na(x$pass[i])) "n/a" else if(x$pass[i]) "ok" else "FAIL",
                x$check[i], format(signif(x$value[i], 4)), format(x$limit[i])))
  }
  invisible(x)

}
