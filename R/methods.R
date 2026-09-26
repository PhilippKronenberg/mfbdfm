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
#'   \item{`summary()`}{Dimensions, posterior mean parameters and residual fit;
#'     returns an object with its own `print()` method.}
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
#' not exist. Use [mfbdfm_nowcast()] to get at those stored nowcasts; it is
#' the accessor the missing `predict()` would otherwise be mistaken for.
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
#'   `"summary.mfbdfm_fit"`; `print()` and `plot()` return their input
#'   invisibly.
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
#' mfbdfm_nowcast(fit, last = TRUE)
#' }
#'
#' @seealso [ind_dfm()], [fcast_dfm_methods], [mfbdfm_nowcast()] for the
#'   nowcasts
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
#' As for [ind_dfm()] fits, the stored nowcasts are reached with
#' [mfbdfm_nowcast()].
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
#' mfbdfm_nowcast(fit, last = TRUE)
#' }
#'
#' @seealso [fcast_dfm()], [ind_dfm_methods], [mfbdfm_nowcast()] for the
#'   nowcasts
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


# ------------------------------------------------------ mfbdfm_nowcast ----

#' Extract the nowcasts from a model fit
#'
#' The accessor for the nowcasts of the target series, for fits from either
#' [ind_dfm()] or [fcast_dfm()]. The nowcasts are computed while the model is
#' fitted and stored in the fit object; this returns them as a data frame,
#' with the posterior standard deviation and a credible band where the fit
#' records the nowcast variance.
#'
#' This is deliberately **not** a `predict()` method. These models do not
#' forecast in the usual sense -- there is no separate prediction step to run
#' on new data -- so a `predict()` returning stored values would advertise a
#' capability that does not exist. The name is prefixed rather than a bare
#' `nowcast()` to avoid masking the same verb in other packages.
#'
#' @param object A fit from [ind_dfm()] or [fcast_dfm()].
#' @param last Logical. If `TRUE`, only the most recent period is returned
#'   (one row) -- the usual real-time query. Defaults to `FALSE`, the whole
#'   path.
#' @param level Numeric in `(0, 1)`, the width of the credible interval
#'   reported in `lower`/`upper`. Defaults to `0.95`.
#' @param ... Ignored, present for compatibility with the generic.
#'
#' @return A data frame with one row per period of the target series'
#'   frequency and columns
#'   \describe{
#'     \item{time}{Numeric (decimal) time of the period.}
#'     \item{nowcast}{Posterior mean nowcast, the values in `object$nowcast`.}
#'     \item{sd}{Posterior standard deviation, `sqrt(object$nowcast_var)`.}
#'     \item{lower, upper}{The `level` credible bounds, normal-approximated
#'       from `nowcast` and `sd`.}
#'   }
#'   The last three columns are present only when the fit stores
#'   `nowcast_var`, which both model entry points currently do.
#'
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                 stats::window, start = 2021)
#' stocks <- lapply(data_ch_dataset_test$stocks[1:2],
#'                  stats::window, start = 2021)
#' set.seed(1)
#' fit <- ind_dfm(flows = flows, stocks = stocks, target = target,
#'                length_sample = 20, burn_in = 5)
#'
#' head(mfbdfm_nowcast(fit))
#' mfbdfm_nowcast(fit, last = TRUE)          # just the current quarter
#' mfbdfm_nowcast(fit, last = TRUE, level = 0.68)
#' }
#'
#' @seealso [ind_dfm()], [fcast_dfm()], [ind_dfm_methods] and
#'   [fcast_dfm_methods] for the other accessors, and [retrieve_nowcast()]
#'   for the backcast-workflow helper it replaces for ordinary fits.
#' @export
mfbdfm_nowcast <- function(object, last = FALSE, level = 0.95, ...){
  UseMethod("mfbdfm_nowcast")
}

#' @rdname mfbdfm_nowcast
#' @method mfbdfm_nowcast ind_dfm
#' @export
mfbdfm_nowcast.ind_dfm <- function(object, last = FALSE, level = 0.95, ...){
  fit_nowcast(object, last = last, level = level)
}

#' @rdname mfbdfm_nowcast
#' @method mfbdfm_nowcast fcast_dfm
#' @export
mfbdfm_nowcast.fcast_dfm <- function(object, last = FALSE, level = 0.95, ...){
  fit_nowcast(object, last = last, level = level)
}

#' @noRd
#' @importFrom stats time qnorm
fit_nowcast <- function(object, last = FALSE, level = 0.95){

  if(!(is.logical(last) && length(last) == 1L && !is.na(last)))
    stop("`last` must be a single TRUE or FALSE.", call. = FALSE)
  if(!(is.numeric(level) && length(level) == 1L && !is.na(level) &&
       level > 0 && level < 1))
    stop("`level` must be a single number strictly between 0 and 1.",
         call. = FALSE)

  nc <- object$nowcast
  if(is.null(nc))
    stop("this fit has no `$nowcast` component to extract.", call. = FALSE)

  out <- data.frame(time = as.numeric(time(nc)),
                    nowcast = as.numeric(nc))

  vr <- object$nowcast_var
  if(!is.null(vr)){
    s <- sqrt(as.numeric(vr))
    z <- qnorm(1 - (1 - level) / 2)
    out$sd <- s
    out$lower <- out$nowcast - z * s
    out$upper <- out$nowcast + z * s
  }

  if(last) out <- out[nrow(out), , drop = FALSE]
  rownames(out) <- NULL

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
                 rmse = sqrt(mean(res^2, na.rm = TRUE))),
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

  invisible(x)

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

  cat("\nFull results: $factor, $nowcast, $index, $pars; mfbdfm_nowcast(),\n")
  cat("summary(), plot(), as.data.frame(), coef(), fitted(), residuals()\n")

  invisible(x)

}
