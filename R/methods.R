# S3 methods for the two fit classes.
#
# Both classes get the same set, per the parity rule in CLAUDE.md. There is
# deliberately no predict() method: the models do not forecast in the usual
# sense - nowcasts are computed during fitting and stored - so a predict()
# returning stored values would advertise a capability that does not exist.

# Both classes store the prepared matrix as `$data` and the series as supplied
# as `$data_raw` (#50), so the methods below read `$data` directly. The
# accessor that used to reconcile the two names is gone with the discrepancy.

#' Model dimensions, whatever the class calls them
#'
#' @noRd
fit_dims <- function(object){
  if(inherits(object, "fcast_dfm")){
    list(n = object$pars$n, q = object$pars$q, p = object$pars$p, t = object$pars$t)
  } else {
    list(n = nrow(object$inventory), q = 1L, p = NA_integer_,
         t = nrow(object$data))
  }
}


#' Methods for single-factor model fits
#'
#' The generics supported by an [ind_dfm()] fit. [fcast_dfm()] fits support
#' the same set -- see [fcast_dfm_methods].
#'
#' \describe{
#'   \item{`print()`}{Model dimensions and the most recent target nowcasts.}
#'   \item{`summary()`}{Dimensions, posterior mean parameters, residual fit and
#'     a per-series R-squared; returns an object with its own `print()` method.
#'     The R-squared is `1 - Var(residual)/Var(observed)` over the periods where
#'     that series was observed, with the fitted value taken to be the **common
#'     component** -- loadings times factors, temporally aggregated -- so it
#'     measures what the factor explains and not the idiosyncratic AR part. It
#'     is therefore not `1 - Var(residuals(fit))/Var(observed)`: `fitted()`
#'     returns the augmented dataset, whose observed entries are pinned to the
#'     observed values by the sampler. For [ind_dfm()] the target's R-squared is
#'     ~1 by construction, since its loading is fixed to 1 and its measurement
#'     error shrunk towards zero to identify the factor. Read the **ranking**
#'     across the other series rather than the level: the common component is
#'     built from posterior *mean* parameters, which attenuates it, and in
#'     `ind_dfm()` the factor's scale is pinned to the target, so a
#'     high-frequency series' common component is necessarily a small fraction
#'     of its variance.}
#'   \item{`plot()`}{The factor with a 95% band.}
#'   \item{`coef()`}{The posterior mean factor loadings, named by series. The
#'     other parameter blocks (`phi`, `sigma`, `rho`, `h`) remain in
#'     `object$pars`.}
#'   \item{`fitted()`}{The augmented dataset: observed values where a series
#'     was observed, the model's latent estimate where it was not, on the
#'     standardized scale the model works in.}
#'   \item{`residuals()`}{Observed minus fitted. **Unobserved periods are
#'     `NA`, not zero** -- the prepared data encodes a missing observation as
#'     `0`, so differencing directly would report a spurious residual wherever
#'     a series was not observed, which in a mixed-frequency model is most of
#'     the matrix for the low-frequency series.}
#'   \item{`as.data.frame()`}{The factor with 95% bands, one row per period,
#'     so downstream code need not reach into the list structure.}
#' }
#'
#' There is deliberately no `predict()` method: the model does not forecast in
#' the usual sense -- nowcasts are computed during fitting and stored -- so a
#' `predict()` returning stored values would advertise a capability that does
#' not exist.
#'
#' @param object,x A fit from [ind_dfm()].
#' @param n_show Integer, how many of the most recent periods `print()` shows.
#' @param row.names,optional Ignored, present for compatibility with the
#'   [as.data.frame()] generic.
#' @param ... Ignored, present for compatibility with the generics.
#'
#' @return `coef()` a named numeric vector; `fitted()` and `residuals()` `ts`
#'   matrices with one column per series; `as.data.frame()` a data frame with
#'   `time` and the factor with bands; `summary()` an object of class
#'   `"summary.mfbdfm_fit"`, whose `$r_squared` element is a data frame with
#'   columns `series`, `freq`, `n_obs` and `r_squared`, sorted by fit;
#'   `print()` and `plot()` return their input invisibly.
#'
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' fit <- ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                               stats::window, start = 2021),
#'                stocks = lapply(data_ch_dataset_test$stocks[1:2],
#'                                stats::window, start = 2021),
#'                target = target, length_sample = 20, burn_in = 5)
#' fit
#' coef(fit)
#' head(as.data.frame(fit))
#' }
#'
#' @seealso [ind_dfm()], [fcast_dfm_methods]
#' @name ind_dfm_methods
NULL


#' Methods for multi-factor model fits
#'
#' The generics supported by a [fcast_dfm()] fit. These mirror the
#' single-factor methods exactly -- see [ind_dfm_methods] for what each one
#' does and for why there is no `predict()` method.
#'
#' `coef()` returns an `n x q` loading matrix here rather than a vector, and
#' `as.data.frame()` returns one mean/lower/upper triple per factor.
#'
#' @param object,x A fit from [fcast_dfm()].
#' @param n_show Integer, how many of the most recent periods `print()` shows.
#' @param row.names,optional Ignored, present for compatibility with the
#'   [as.data.frame()] generic.
#' @param ... Ignored, present for compatibility with the generics.
#'
#' @return As [ind_dfm_methods], except that `coef()` returns a matrix.
#'
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' fit <- fcast_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                                 stats::window, start = 2021),
#'                  stocks = lapply(data_ch_dataset_test$stocks[1:2],
#'                                  stats::window, start = 2021),
#'                  target = target, q = 2, length_sample = 20, burn_in = 5)
#' fit
#' coef(fit)          # a q-column matrix here, a vector for ind_dfm()
#' head(as.data.frame(fit))
#' }
#'
#' @seealso [fcast_dfm()], [ind_dfm_methods]
#' @name fcast_dfm_methods
NULL


# ---------------------------------------------------------------- coef ----

#' @rdname ind_dfm_methods
#' @method coef ind_dfm
#' @export
coef.ind_dfm <- function(object, ...){
  out <- as.numeric(object$pars$lambda)
  names(out) <- object$inventory$key
  out
}

#' @rdname fcast_dfm_methods
#' @method coef fcast_dfm
#' @export
coef.fcast_dfm <- function(object, ...){
  out <- as.matrix(object$pars$lambda)
  rownames(out) <- object$inventory$key
  colnames(out) <- paste0("factor", seq_len(ncol(out)))
  out
}


# -------------------------------------------------------------- fitted ----

#' @rdname ind_dfm_methods
#' @method fitted ind_dfm
#' @export
fitted.ind_dfm <- function(object, ...) object$data_augmented

#' @rdname fcast_dfm_methods
#' @method fitted fcast_dfm
#' @export
fitted.fcast_dfm <- function(object, ...) object$data_augmented


# ----------------------------------------------------------- residuals ----

#' @rdname ind_dfm_methods
#' @method residuals ind_dfm
#' @export
residuals.ind_dfm <- function(object, ...) fit_residuals(object)

#' @rdname fcast_dfm_methods
#' @method residuals fcast_dfm
#' @export
residuals.fcast_dfm <- function(object, ...) fit_residuals(object)

#' @noRd
fit_residuals <- function(object){

  obs <- object$data
  fit <- object$data_augmented

  res <- obs - fit
  # 0 encodes "not observed" in the prepared data; a residual there is
  # meaningless rather than zero
  res[obs == 0] <- NA_real_
  res

}


# ------------------------------------------------------- per-series fit ----

#' The factor on the scale the observation equation uses
#'
#' The two classes surface this under different names, because `fcast_dfm()`'s
#' `$factor` *is* the standardized factor while `ind_dfm()`'s is the
#' de-standardized, annualized growth rate and the latter cannot be inverted
#' back (see `?ind_dfm`'s `factor_std`).
#'
#' `NULL` for a fit object saved before `factor_std` existed, which is what lets
#' [fit_r_squared()] degrade to "not reported" instead of erroring.
#'
#' @noRd
fit_factor_state <- function(object){

  f <- if(inherits(object, "fcast_dfm")) object$factor else object$factor_std
  if(is.null(f)) return(NULL)
  as.matrix(f)

}

#' The common component: loadings x factors, temporally aggregated
#'
#' The model's fit to series `i` that the factor(s) alone explain, excluding the
#' idiosyncratic AR component. Deliberately not `fitted()`: that returns the
#' augmented dataset, whose observed entries are pinned to the observed values
#' by a 1e-9 measurement prior, so residuals against it are sampling noise of
#' order 1e-5 and every R-squared computed from them would be ~1.
#'
#' Mirrors the `Xfit` accumulation in `draw_rho()` exactly: row `tx` of series
#' `i` is `sum_sx w[i, sx] * lambda[i, ] %*% f[tx + s - sx, ]`.
#'
#' @noRd
#' @importFrom stats ts time frequency
fit_common_component <- function(object){

  f <- fit_factor_state(object)
  if(is.null(f)) return(NULL)

  lambda <- as.matrix(object$pars$lambda)
  Llist <- get_distributed_lags(object$inventory)
  s <- length(Llist) - 1L
  t <- nrow(object$data)

  # a fit whose factor does not span the t + s periods the aggregation needs
  # cannot be evaluated this way; report nothing rather than something wrong
  if(nrow(f) != t + s || ncol(f) != ncol(lambda)) return(NULL)

  out <- matrix(0, t, nrow(lambda))
  for(sx in 0:s){
    w <- diag(Llist[[as.character(sx)]])
    out <- out + f[seq(from = 1 + s - sx, to = t + s - sx), , drop = FALSE] %*%
      t(lambda * w)
  }

  colnames(out) <- object$inventory$key
  ts(out, start = time(object$data)[1], frequency = frequency(object$data))

}

#' Per-series R-squared of the common component
#'
#' `1 - Var(residual_i)/Var(observed_i)` over the periods where series `i` was
#' actually observed, the residual being observed minus common component.
#'
#' @noRd
#' @importFrom stats var
fit_r_squared <- function(object){

  cc <- fit_common_component(object)
  if(is.null(cc)) return(NULL)

  obs <- object$data
  # 0 encodes "not observed", exactly as in fit_residuals()
  obs[obs == 0] <- NA_real_

  r2 <- vapply(seq_len(ncol(obs)), function(j){

    o <- obs[, j]
    keep <- !is.na(o)
    if(sum(keep) < 2L) return(NA_real_)

    vo <- var(o[keep])
    if(!is.finite(vo) || vo == 0) return(NA_real_)
    1 - var(o[keep] - cc[keep, j])/vo

  }, numeric(1))

  out <- data.frame(series = object$inventory$key,
                    freq = object$inventory$freq,
                    n_obs = unname(colSums(!is.na(obs))),
                    r_squared = r2,
                    stringsAsFactors = FALSE,
                    row.names = NULL)

  out <- out[order(out$r_squared, decreasing = TRUE, na.last = TRUE), ]
  row.names(out) <- NULL
  out

}


# ------------------------------------------------------- as.data.frame ----

#' @rdname ind_dfm_methods
#' @method as.data.frame ind_dfm
#' @export
as.data.frame.ind_dfm <- function(x, row.names = NULL, optional = FALSE, ...){
  fit_as_data_frame(x)
}

#' @rdname fcast_dfm_methods
#' @method as.data.frame fcast_dfm
#' @export
as.data.frame.fcast_dfm <- function(x, row.names = NULL, optional = FALSE, ...){
  fit_as_data_frame(x)
}

#' @noRd
#' @importFrom stats time qnorm
fit_as_data_frame <- function(x){

  z <- qnorm(0.975)
  fac <- as.matrix(x$factor)
  vr <- as.matrix(x$factor_var)
  sd <- sqrt(vr)

  out <- data.frame(time = as.numeric(time(x$factor)))
  nms <- if(ncol(fac) == 1) "factor" else paste0("factor", seq_len(ncol(fac)))

  for(j in seq_len(ncol(fac))){
    out[[nms[j]]] <- fac[, j]
    out[[paste0(nms[j], "_lower")]] <- fac[, j] - z * sd[, j]
    out[[paste0(nms[j], "_upper")]] <- fac[, j] + z * sd[, j]
  }

  out

}


# ---------------------------------------------------------------- plot ----

#' @rdname ind_dfm_methods
#' @method plot ind_dfm
#' @export
plot.ind_dfm <- function(x, ...) fit_plot(x, ...)

#' @rdname fcast_dfm_methods
#' @method plot fcast_dfm
#' @export
plot.fcast_dfm <- function(x, ...) fit_plot(x, ...)

#' @noRd
#' @importFrom graphics par lines polygon
#' @importFrom stats time qnorm
fit_plot <- function(x, ...){

  z <- qnorm(0.975)
  fac <- as.matrix(x$factor)
  sd <- sqrt(as.matrix(x$factor_var))
  tt <- as.numeric(time(x$factor))

  # restore the caller's graphics state however this exits
  oldpar <- par(no.readonly = TRUE)
  on.exit(par(oldpar), add = TRUE)

  if(ncol(fac) > 1) par(mfrow = c(ncol(fac), 1))

  for(j in seq_len(ncol(fac))){
    lo <- fac[, j] - z * sd[, j]
    hi <- fac[, j] + z * sd[, j]
    plot(tt, fac[, j], type = "n", ylim = range(c(lo, hi), finite = TRUE),
         xlab = "", ylab = if(ncol(fac) == 1) "factor" else paste("factor", j),
         ...)
    polygon(c(tt, rev(tt)), c(lo, rev(hi)), border = NA,
            col = grDevices::adjustcolor("steelblue", alpha.f = 0.25))
    lines(tt, fac[, j], col = "steelblue")
  }

  invisible(x)

}


# ------------------------------------------------------------- summary ----

#' @rdname ind_dfm_methods
#' @method summary ind_dfm
#' @export
summary.ind_dfm <- function(object, ...) fit_summary(object, "ind_dfm")

#' @rdname fcast_dfm_methods
#' @method summary fcast_dfm
#' @export
summary.fcast_dfm <- function(object, ...) fit_summary(object, "fcast_dfm")

#' @noRd
fit_summary <- function(object, model){

  d <- fit_dims(object)
  res <- fit_residuals(object)

  structure(list(model = model,
                 call = object$call,
                 dims = d,
                 target = object$target,
                 loadings = if(model == "ind_dfm") coef.ind_dfm(object) else coef.fcast_dfm(object),
                 phi = object$pars$phi,
                 sigma = object$pars$sigma,
                 rho = object$pars$rho,
                 nowcast = object$nowcast,
                 n_observed = sum(!is.na(res)),
                 rmse = sqrt(mean(res^2, na.rm = TRUE)),
                 r_squared = fit_r_squared(object)),
            class = "summary.mfbdfm_fit")

}

#' Print a fit summary
#'
#' @param x An object from [summary.ind_dfm()] or [summary.fcast_dfm()].
#' @param ... Ignored.
#'
#' @return `x`, invisibly.
#'
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' fit <- ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                               stats::window, start = 2021),
#'                stocks = lapply(data_ch_dataset_test$stocks[1:2],
#'                                stats::window, start = 2021),
#'                target = target, length_sample = 20, burn_in = 5)
#' summary(fit)          # dispatches here
#' }
#'
#' @method print summary.mfbdfm_fit
#' @export
print.summary.mfbdfm_fit <- function(x, ...){

  cat(if(x$model == "ind_dfm")
        "Single-factor mixed-frequency dynamic factor model (Kronenberg 2026)\n"
      else
        "Multi-factor mixed-frequency dynamic factor model (Eckert et al. 2025)\n")
  if(!is.null(x$call)) cat("Call: ", deparse(x$call, nlines = 2), "\n", sep = "")

  cat("\n  series (n) : ", x$dims$n, "\n", sep = "")
  cat("  factors (q): ", x$dims$q, "\n", sep = "")
  cat("  periods (t): ", x$dims$t, "\n", sep = "")
  cat("  target     : ", x$target, "\n", sep = "")

  cat("\nFactor loadings (posterior mean):\n")
  print(round(x$loadings, 4))

  cat("\nMeasurement error sd (posterior mean):\n")
  print(round(sqrt(as.numeric(x$sigma)), 4))

  cat("\nFit to observed data:\n")
  cat("  observed values: ", x$n_observed, "\n", sep = "")
  cat("  residual RMSE  : ", signif(x$rmse, 4), " (standardized scale)\n", sep = "")

  if(!is.null(x$r_squared)){

    cat("\nR-squared of the common component, by series:\n")
    print_r_squared(x$r_squared)

    if(x$model == "ind_dfm"){
      cat("  Note: the target's loading is fixed to 1 and its measurement error\n")
      cat("  shrunk towards zero to identify the factor, so its R-squared is ~1\n")
      cat("  by construction rather than as a finding.\n")
    }

  }

  invisible(x)

}

#' Print the per-series R-squared table
#'
#' All of it when there are few series, otherwise the best and worst handful:
#' the WAI runs to over fifty series, and a fifty-row block buries the
#' dimensions and parameters printed above it.
#'
#' @noRd
print_r_squared <- function(r2, n_max = 14L, n_ends = 5L){

  rows <- function(d){
    for(i in seq_len(nrow(d))){
      cat(sprintf("  %-38s %5s %6s %9s\n",
                  substr(d$series[i], 1, 38), d$freq[i], d$n_obs[i],
                  formatC(d$r_squared[i], format = "f", digits = 3)))
    }
  }

  cat(sprintf("  %-38s %5s %6s %9s\n", "series", "freq", "n_obs", "R-squared"))

  if(nrow(r2) <= n_max){
    rows(r2)
  } else {
    rows(utils::head(r2, n_ends))
    cat("  ... ", nrow(r2) - 2L*n_ends, " series not shown ...\n", sep = "")
    rows(utils::tail(r2, n_ends))
  }

  invisible(r2)

}


# --------------------------------------------------------------- print ----

#' @rdname ind_dfm_methods
#' @method print ind_dfm
#' @export
print.ind_dfm <- function(x, n_show = 8, ...){

  cat("Single-factor mixed-frequency dynamic factor model (Kronenberg 2026)\n")
  if(!is.null(x$call)) cat("Call: ", deparse(x$call, nlines = 2), "\n", sep = "")

  d <- fit_dims(x)
  cat("\n  series (n) : ", d$n, "\n", sep = "")
  cat("  periods (t): ", d$t, "\n", sep = "")
  cat("  target     : ", x$target, "\n", sep = "")

  cat("\n  Most recent nowcasts for ", x$target, ":\n\n", sep = "")
  nc <- utils::tail(data.frame(time = as.numeric(stats::time(x$nowcast)),
                               nowcast = as.numeric(x$nowcast)), n_show)
  cat(sprintf("  %10s %12s\n", "time", "nowcast"))
  for(i in seq_len(nrow(nc))){
    cat(sprintf("  %10s %12s\n",
                formatC(nc$time[i], format = "f", digits = 3, width = 10),
                formatC(nc$nowcast[i], format = "f", digits = 5, width = 12)))
  }

  cat("\nFull results: $factor, $nowcast, $index, $pars; summary(), plot(),\n")
  cat("as.data.frame(), coef(), fitted(), residuals()\n")

  invisible(x)

}
