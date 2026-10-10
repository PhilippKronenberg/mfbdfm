# MCMC convergence diagnostics over the retained draws (#110).
#
# The statistics themselves come from coda - effectiveSize(), geweke.diag() and
# heidel.diag() all need a spectral density at frequency zero, which is not a
# quantity to reimplement by hand. What this file adds is the part coda cannot
# know: which columns of a draw matrix are parameters that were actually drawn,
# and which are pinned by the identification or never drawn at all.
#
# That distinction is the reason this is not a thin wrapper. In this package a
# zero-variance chain is a NORMAL outcome, not a failure:
#
#   * lambda[target] is fixed at 1 in ind_dfm() - it IS the identification;
#   * rho is held at exactly 1e-9 under serial_correlation = FALSE;
#   * omega and h do not exist under fcast_dfm(stochastic_volatility = FALSE).
#
# Handing such a column to effectiveSize() gives NaN and to geweke.diag() a
# divide-by-zero. Reporting that as "failed to converge" would be a wrong
# answer, so those rows are marked `constant` and excluded from the pass/fail
# count rather than counted as failures.

#' MCMC convergence diagnostics for a fitted model
#'
#' Effective sample size, the Geweke (1992) convergence z-score and -- on
#' request -- the Heidelberger & Welch (1983) stationarity test, for every
#' retained parameter draw of an [ind_dfm()] or [fcast_dfm()] fit.
#'
#' @details
#' Requires the fit to carry its draws, which it does by default; see
#' [dfm_control()]'s `keep_draws` and [mfbdfm_draws] for the container.
#'
#' # The statistics
#'
#' \describe{
#'   \item{`ess`}{Effective sample size, [coda::effectiveSize()]: the number of
#'     independent draws the autocorrelated chain is worth. Small relative to
#'     the number of draws means slow mixing, not necessarily non-convergence.}
#'   \item{`geweke_z`}{[coda::geweke.diag()]: a z-test that the mean of the
#'     first 10% of the chain equals the mean of the last 50%. Large absolute
#'     values indicate the chain was still moving.}
#'   \item{`heidel_*`}{[coda::heidel.diag()]'s stationarity test and
#'     half-width accuracy test, under `heidel = TRUE`.}
#' }
#'
#' A row fails -- `ok` is `FALSE` -- when `abs(geweke_z) > geweke_crit` or
#' `ess < ess_min`. Both thresholds are arguments: the defaults are the usual
#' rules of thumb, not properties of this model.
#'
#' # Single chain
#'
#' Both samplers run **one** chain, so there is no R-hat here: the
#' between-chain variance it is built from does not exist. The diagnostics
#' offered are the single-chain ones. Running several chains from different
#' seeds and comparing them is possible today -- fit twice and compare -- but
#' is not something the fit object represents, so R-hat is deliberately absent
#' rather than computed from one chain and quietly meaningless.
#'
#' # Constant chains are reported, not failed
#'
#' A parameter that was never drawn has zero variance, and no convergence
#' statistic is defined for it. Those rows carry `NA` statistics,
#' `note = "constant"` and `ok = NA`, and are left out of the failure count.
#' This is a normal outcome here rather than an edge case: `lambda[target]` is
#' fixed at 1 by [ind_dfm()]'s identifying restriction, `rho` is held at
#' `1e-9` when `serial_correlation = FALSE`, and the volatility parameters do
#' not exist when `stochastic_volatility = FALSE`.
#'
#' @param x A fitted model from [ind_dfm()] or [fcast_dfm()], or the
#'   `fit$draws` object itself.
#' @param which Columns to diagnose. Defaults to `"parameters"`, every
#'   parameter column; see [mfbdfm_draws] for the accepted forms. `"all"` adds
#'   the nowcast (and, if kept, factor) draws, which can be hundreds of
#'   columns.
#' @param heidel Logical, add the Heidelberger-Welch columns.
#' @param ess_min Numeric, effective sample size below which a parameter is
#'   flagged.
#' @param geweke_crit Numeric, absolute Geweke z-score above which a parameter
#'   is flagged.
#'
#' @return A data frame of class `"mfbdfm_diagnostics"`, one row per parameter,
#'   with columns `parameter`, `block`, `mean`, `sd`, `ess`, `geweke_z`,
#'   `geweke_p`, (optionally `heidel_stationary`, `heidel_p`,
#'   `heidel_halfwidth`), `ok` and `note`. The draws it was computed from are
#'   attached, so `plot()` on the result draws the traces of whatever failed.
#'
#' @references
#' Geweke, J. (1992). Evaluating the accuracy of sampling-based approaches to
#' the calculation of posterior moments. In *Bayesian Statistics 4*, 169-193.
#' Oxford University Press.
#'
#' Heidelberger, P., & Welch, P. D. (1983). Simulation run length control in
#' the presence of an initial transient. *Operations Research*, 31(6),
#' 1109-1144. \doi{10.1287/opre.31.6.1109}
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#' set.seed(1)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 120, burn_in = 30)
#'
#' d <- mfbdfm_diagnostics(fit)
#' d
#' head(as.data.frame(d))
#'
#' # the target's loading is fixed at 1 by the identification, so it is
#' # reported as constant rather than as a convergence failure
#' subset(as.data.frame(d), note == "constant")
#' }
#'
#' @seealso [mfbdfm_draws] for the draws themselves and their trace/density
#'   plots, [dfm_control()] for `keep_draws`, [ind_dfm()], [fcast_dfm()].
#'
#' @family model functions
#' @importFrom stats sd pnorm
#' @export
mfbdfm_diagnostics <- function(x, which = "parameters", heidel = FALSE,
                               ess_min = 100, geweke_crit = 1.96){

  draws <- as_mfbdfm_draws(x)

  if(!is.logical(heidel) || length(heidel) != 1L || is.na(heidel)){
    stop("`heidel` must be TRUE or FALSE.", call. = FALSE)
  }
  for(nm in c("ess_min", "geweke_crit")){
    v <- get(nm)
    if(!is.numeric(v) || length(v) != 1L || is.na(v) || v < 0){
      stop("`", nm, "` must be a single non-negative number.", call. = FALSE)
    }
  }

  m <- draws_matrix(draws, which)
  cols <- draws_columns(draws)
  n_iter <- nrow(m)

  stats_of <- lapply(seq_len(ncol(m)), function(j)
    chain_diagnostics(m[, j], heidel = heidel, n_iter = n_iter))

  out <- data.frame(parameter = colnames(m),
                    block = unname(cols[colnames(m)]),
                    mean = vapply(stats_of, function(z) z$mean, numeric(1)),
                    sd = vapply(stats_of, function(z) z$sd, numeric(1)),
                    ess = vapply(stats_of, function(z) z$ess, numeric(1)),
                    geweke_z = vapply(stats_of, function(z) z$geweke_z, numeric(1)),
                    geweke_p = vapply(stats_of, function(z) z$geweke_p, numeric(1)),
                    stringsAsFactors = FALSE)

  if(heidel){
    out$heidel_stationary <- vapply(stats_of, function(z) z$heidel_stationary,
                                    logical(1))
    out$heidel_p <- vapply(stats_of, function(z) z$heidel_p, numeric(1))
    out$heidel_halfwidth <- vapply(stats_of, function(z) z$heidel_halfwidth,
                                   logical(1))
  }

  out$note <- vapply(stats_of, function(z) z$note, character(1))

  flagged <- (!is.na(out$geweke_z) & abs(out$geweke_z) > geweke_crit) |
    (!is.na(out$ess) & out$ess < ess_min)
  # a row carrying a note has no statistics to judge, so it is neither a pass
  # nor a failure - `ok = TRUE` there would report "converged" for a parameter
  # that was never tested
  out$ok <- ifelse(nzchar(out$note), NA, !flagged)

  # keep ok/note last, in that order, whatever heidel added above
  out <- out[, c(setdiff(names(out), c("ok", "note")), "ok", "note")]
  rownames(out) <- NULL

  structure(out,
            class = c("mfbdfm_diagnostics", "data.frame"),
            draws = draws,
            n_iter = n_iter,
            ess_min = ess_min,
            geweke_crit = geweke_crit,
            heidel = heidel,
            model = draws$info$model)

}


#' Accept a fit or a draws object
#'
#' @noRd
as_mfbdfm_draws <- function(x){

  if(inherits(x, "mfbdfm_draws")) return(x)

  if(!inherits(x, c("ind_dfm", "fcast_dfm"))){
    stop("`x` must be a fitted model from ind_dfm() or fcast_dfm(), or its ",
         "`$draws` component, not an object of class ",
         paste(class(x), collapse = "/"), ".", call. = FALSE)
  }

  if(is.null(x$draws)){
    stop("This fit carries no retained draws, so no convergence diagnostic ",
         "can be computed from it.\n",
         "  Refit with `control = dfm_control(\"",
         if(inherits(x, "fcast_dfm")) "fcast_dfm" else "ind_dfm",
         "\", keep_draws = TRUE)`.", call. = FALSE)
  }

  x$draws

}


#' Diagnostics of one chain
#'
#' Non-finite results from coda are converted to `NA` with a note rather than
#' propagated: a short chain can make the Geweke windows degenerate, and an
#' `NaN` in a column headed `geweke_z` reads as a failure.
#'
#' @noRd
chain_diagnostics <- function(v, heidel, n_iter){

  out <- list(mean = mean(v), sd = stats::sd(v),
              ess = NA_real_, geweke_z = NA_real_, geweke_p = NA_real_,
              heidel_stationary = NA, heidel_p = NA_real_,
              heidel_halfwidth = NA, note = "")

  if(!is.finite(out$sd) || out$sd == 0){
    out$note <- "constant"
    return(out)
  }

  if(n_iter < MIN_DIAGNOSTIC_DRAWS){
    out$note <- "too few draws"
    return(out)
  }

  ch <- coda::mcmc(v)

  ess <- try_numeric(coda::effectiveSize(ch))
  if(is.finite(ess)) out$ess <- unname(ess)

  z <- try_numeric(suppressWarnings(coda::geweke.diag(ch)$z))
  if(is.finite(z)){
    out$geweke_z <- unname(z)
    out$geweke_p <- 2*stats::pnorm(-abs(z))
  }

  if(heidel){
    hd <- try(suppressWarnings(coda::heidel.diag(ch)), silent = TRUE)
    if(!inherits(hd, "try-error") && is.matrix(hd)){
      out$heidel_stationary <- isTRUE(hd[1, "stest"] == 1)
      out$heidel_p <- unname(hd[1, "pvalue"])
      out$heidel_halfwidth <- isTRUE(hd[1, "htest"] == 1)
    }
  }

  out

}


# geweke.diag() compares the first 10% of the chain with the last 50%; below
# this the leading window is a draw or two and the z-score is noise rather than
# a diagnostic. Reported as "too few draws" instead of as a number.
MIN_DIAGNOSTIC_DRAWS <- 30


#' A single finite number from a coda call, or NA
#'
#' @noRd
try_numeric <- function(expr){

  out <- try(expr, silent = TRUE)
  if(inherits(out, "try-error") || length(out) != 1L || !is.numeric(out)){
    return(NA_real_)
  }
  out

}


# ----------------------------------------------------------------- print ----

#' @rdname mfbdfm_diagnostics
#'
#' @param n_show Number of flagged parameters to list.
#' @param ... Passed on to the underlying plotting calls; ignored by `print()`.
#'
#' @method print mfbdfm_diagnostics
#' @export
print.mfbdfm_diagnostics <- function(x, n_show = 10, ...){

  d <- as.data.frame(x)
  ess_min <- attr(x, "ess_min")
  gc_crit <- attr(x, "geweke_crit")

  cat("MCMC convergence diagnostics for a ", attr(x, "model"), " fit\n",
      sep = "")
  cat("  (single chain: effective sample size and Geweke z, no R-hat)\n\n")

  cat("  draws          : ", attr(x, "n_iter"), "\n", sep = "")
  cat("  parameters     : ", nrow(d), "\n", sep = "")

  n_const <- sum(d$note == "constant")
  n_short <- sum(d$note == "too few draws")
  n_tested <- sum(!is.na(d$ok))
  n_bad <- sum(!is.na(d$ok) & !d$ok)

  skipped <- c(if(n_const) paste0(n_const, " constant, not drawn"),
               if(n_short) paste0(n_short, " chain too short"))

  cat("  tested         : ", n_tested,
      if(length(skipped)) paste0("  (", paste(skipped, collapse = "; "), ")") else "",
      "\n", sep = "")
  cat("  flagged        : ", n_bad, "  (|geweke z| > ", gc_crit,
      " or ESS < ", ess_min, ")\n", sep = "")

  if(n_tested){
    cat("  min ESS        : ",
        formatC(min(d$ess, na.rm = TRUE), format = "f", digits = 1), "\n",
        sep = "")
    cat("  max |geweke z| : ",
        formatC(max(abs(d$geweke_z), na.rm = TRUE), format = "f", digits = 2),
        "\n", sep = "")
  }

  if(n_bad){

    bad <- d[!is.na(d$ok) & !d$ok, , drop = FALSE]
    bad <- bad[order(bad$ess), , drop = FALSE]

    cat("\nFlagged parameters:\n\n")
    cat(sprintf("  %-28s %10s %10s %10s\n",
                "parameter", "ess", "geweke z", "geweke p"))
    for(i in seq_len(min(n_show, nrow(bad)))){
      cat(sprintf("  %-28s %10s %10s %10s\n",
                  substr(bad$parameter[i], 1, 28),
                  formatC(bad$ess[i], format = "f", digits = 1, width = 10),
                  formatC(bad$geweke_z[i], format = "f", digits = 2, width = 10),
                  formatC(bad$geweke_p[i], format = "f", digits = 3, width = 10)))
    }
    if(nrow(bad) > n_show)
      cat("  ... and ", nrow(bad) - n_show, " more\n", sep = "")

    cat("\nA flag is a prompt to look, not a verdict: run a longer chain and\n")
    cat("inspect plot() of this object before trusting the affected block.\n")

  } else if(n_tested){

    cat("\nNo parameter is flagged at these thresholds.\n")

  } else {

    cat("\nNo parameter could be tested: see the `note` column.\n")

  }

  cat("\nas.data.frame() for the full table; plot() for traces and densities\n")

  invisible(x)

}


# ------------------------------------------------------------------ plot ----

#' @rdname mfbdfm_diagnostics
#'
#' @method plot mfbdfm_diagnostics
#' @export
plot.mfbdfm_diagnostics <- function(x, which = NULL, ...){

  draws <- attr(x, "draws")

  if(is.null(which)){
    d <- as.data.frame(x)
    bad <- d$parameter[!is.na(d$ok) & !d$ok]
    # the failures are what one wants to see first; with none, fall back to the
    # draws object's own readable default
    if(length(bad)) which <- bad[order(d$ess[!is.na(d$ok) & !d$ok])]
  }

  plot(draws, which = which, ...)

}
