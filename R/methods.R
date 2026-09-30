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
#'   \item{`logLik()`}{A plug-in Gaussian log-likelihood of the observed data,
#'     with `df` and `nobs` attributes so that [AIC()] and [BIC()] work. Read
#'     the definition below before using it.}
#'   \item{`screeplot()`}{An **error**, deliberately. This model has exactly one
#'     factor by construction, so a scree plot would be a single bar conveying
#'     nothing while implying a choice the model does not offer. The message
#'     points to [select_factors()] and [fcast_dfm()]. See
#'     [fcast_dfm_methods] for the version that does plot something.}
#' }
#'
#' There is deliberately no `predict()` method: the model does not forecast in
#' the usual sense -- nowcasts are computed during fitting and stored -- so a
#' `predict()` returning stored values would advertise a capability that does
#' not exist.
#'
#' @section What `logLik()` means here:
#'
#' Neither model computes a likelihood while sampling -- the factors are drawn
#' jointly from a stacked, precision-based conditional, and there is no Kalman
#' filter anywhere in the package. So the value has to be *defined*, and the
#' definition adopted is:
#'
#' > the Gaussian log density of the **observed** entries of the prepared data,
#' > evaluated at the posterior mean parameters and the posterior mean
#' > volatility path, with the factors and the unobserved data entries
#' > marginalised out.
#'
#' It is computed exactly (not by simulation) from the stacked Gaussian form
#' the samplers already use, so nothing is approximated in the *arithmetic*.
#' What is approximate is the statistics, in three specific ways:
#'
#' \itemize{
#'   \item It is a **plug-in** likelihood at a single parameter value, not the
#'     marginal likelihood of the data under the posterior, and not an average
#'     of the likelihood over draws. Posterior uncertainty in the parameters is
#'     ignored.
#'   \item It is **conditional on the posterior mean volatility path**, which is
#'     itself a latent state, rather than integrated over it.
#'   \item `df` counts the parameters of the measurement and state equations
#'     only -- loadings (net of the identifying restriction), autoregressive
#'     coefficients, measurement error variances, measurement error
#'     autocorrelations, and the volatility process. The latent states are not
#'     counted, and neither is the shrinkage imposed by the priors.
#' }
#'
#' Consequently **`AIC()` and `BIC()` are approximate for this model class, and
#' should be read as rough comparisons rather than as model selection
#' criteria.** Both models are hierarchical and Bayesian, and [ind_dfm()]'s
#' identification is carried by informative priors (see [dfm_priors()]), so the
#' effective number of parameters is not the raw count that `df` reports. For a
#' criterion that respects the posterior, prefer DIC or WAIC computed from the
#' retained draws.
#'
#' Missing observations are encoded as `0` in the prepared data and are
#' **excluded** -- they enter as latent quantities to be marginalised out, not
#' as observed zeros. `nobs` is therefore the number of genuinely observed
#' values, which for a mixed-frequency model is far fewer than `nrow * ncol`.
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
#'   `"summary.mfbdfm_fit"`; `logLik()` an object of class `"logLik"` with `df`
#'   and `nobs` attributes; `print()` and `plot()` return their input
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
#' logLik(fit)
#' AIC(fit)              # approximate here - see "What logLik() means"
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
#' `screeplot()` shows the share of the standardized panel's variance explained
#' by each factor, computed from the posterior mean loadings and factors: the
#' factor's own variance times the sum of squared loadings on it, over the total
#' variance of the observed entries of the prepared data. **The rotated factors
#' are not ordered by variance the way principal components are** -- the
#' post-hoc rotation has no such convention -- so the bars are sorted for the
#' plot and labelled `f1`, `f2`, ... by their position in the fit, not by their
#' position in the plot. It is a description of a fitted model, not a selection
#' criterion; for choosing `q` before fitting, use [select_factors()].
#'
#' `logLik()` uses the same definition as it does for [ind_dfm()] -- see
#' "What `logLik()` means here" in [ind_dfm_methods], including why `AIC()` and
#' `BIC()` are only approximate. The `df` count differs: the loadings are
#' unrestricted in sampling and identified post hoc by rotation, so
#' `n*q - q*(q-1)/2` of them are counted as free, and the volatility
#' contributes a parameter only when `stochastic_volatility = TRUE` (with it
#' off the factor innovation variance is *fixed* at one and carries the
#' identification, where [ind_dfm()] still estimates a constant).
#'
#' @param object,x A fit from [fcast_dfm()].
#' @param n_show Integer, how many of the most recent periods `print()` shows.
#' @param npcs Integer, how many factors `screeplot()` shows, or `NULL` for all
#'   of them.
#' @param type `"barplot"` or `"lines"`, as for [stats::screeplot()].
#' @param main Plot title, or `NULL` for the default.
#' @param row.names,optional Ignored, present for compatibility with the
#'   [as.data.frame()] generic.
#' @param ... Ignored, present for compatibility with the generics.
#'
#' @return As [ind_dfm_methods], except that `coef()` returns a matrix and
#'   `screeplot()` invisibly returns the sorted variance shares.
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
#' screeplot(fit)     # share of panel variance per rotated factor
#' head(as.data.frame(fit))
#' logLik(fit)
#' BIC(fit)           # approximate here - see ?ind_dfm_methods
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


# -------------------------------------------------------------- logLik ----

#' @rdname ind_dfm_methods
#' @method logLik ind_dfm
#' @export
logLik.ind_dfm <- function(object, ...) fit_loglik(object)

#' @rdname fcast_dfm_methods
#' @method logLik fcast_dfm
#' @export
logLik.fcast_dfm <- function(object, ...) fit_loglik(object)

#' Gaussian log-likelihood of the observed data at the posterior mean
#'
#' @details
#' Neither sampler computes a likelihood, and there is no Kalman filter in the
#' package, so the quantity returned here has to be *defined* rather than read
#' off a fit. The definition is: the Gaussian log density of the **observed**
#' entries of the prepared data, evaluated at the posterior mean parameters and
#' the posterior mean volatility path, with the factors and the unobserved
#' entries of the data marginalised out. It is a plug-in likelihood, not a
#' marginal likelihood over the posterior.
#'
#' It is computed from the model exactly as the samplers implement it, reusing
#' their own matrices, so no filtering code is added. Write `f` for the stacked
#' factor path (`q*(t+s)` long) and `x` for the stacked augmented data
#' (`n*t` long, period-major). [draw_factors()] gives the factor prior as
#' `f ~ N(0, F0^-1)` with `F0 = H' V^-1 H`, and [draw_augmented_data()] gives
#' the measurement block as `K x ~ N(Gext f, I_t %x% sigma)`, where `K` is the
#' quasi-differencing operator and `Gext` is `Gmat` with the first period's
#' block of zero rows prepended. Together these make `z = (f, x)` Gaussian with
#' a sparse precision `Q`, and
#'
#' \deqn{\log\det Q = \log\det F_0 - t \sum_i \log \sigma_i}
#'
#' because `det(H) = det(K) = 1`. The observed entries are taken as exact
#' observations of `x` (the sampler's `1e-9` observation variance is a
#' numerical device, not part of the model), so partitioning `Q` into the
#' observed positions `O` and the latent ones `L` -- the whole factor path plus
#' every unobserved data entry -- gives the marginal density in closed form:
#'
#' \deqn{\log p(y) = -\frac{n_{obs}}{2}\log 2\pi + \frac{1}{2}\log\det Q
#'   - \frac{1}{2}\log\det Q_{LL}
#'   - \frac{1}{2}\left(y'Q_{OO}y - b'Q_{LL}^{-1}b\right),\quad b = Q_{LO}y.}
#'
#' `0` encodes a missing observation in the prepared data, so those entries are
#' latent here rather than being scored as zeros -- the same caveat that makes
#' [residuals()] return `NA` where a series was not observed.
#'
#' `h` covers all `t+s` periods in a [fcast_dfm()] fit. An [ind_dfm()] fit
#' stores only the `t` in-sample periods (see #49), so the `s` pre-sample
#' periods carried by the distributed lags are padded with its first value.
#'
#' @noRd
#' @importFrom stats logLik
fit_loglik <- function(object){

  is_fcast <- inherits(object, "fcast_dfm")

  Ymat <- object$data
  inventory <- object$inventory
  n <- ncol(Ymat)
  t <- nrow(Ymat)
  k <- max(inventory$freq)/min(inventory$freq)
  s <- 2*(k - 1)

  pars <- object$pars
  sigma_d <- as.numeric(pars$sigma)
  rho_d <- as.numeric(pars$rho)
  h <- as.numeric(pars$h)

  if(is_fcast){

    q <- pars$q
    phi <- pars$phi
    lambda <- as.matrix(pars$lambda)

  } else {

    q <- 1L
    phi <- lapply(as.numeric(pars$phi), function(x) matrix(x, 1, 1))
    lambda <- as.matrix(as.numeric(pars$lambda))
    h <- c(rep(h[1], s), h)

  }

  p <- length(phi)
  rho <- Diagonal(x = rho_d)

  # the samplers' own observation matrix, at the posterior mean loadings
  Gmat <- get_gmat(get_gmat_prealloc(n = n, q = q, s = s, t = t),
                   Llist = get_distributed_lags(inventory),
                   rho = rho, lambda = lambda, s = s, t = t, n = n)

  # factor prior precision, as in draw_factors()/draw_factors_fcast()
  H <- Reduce("+", lapply(1:p, function(px){

    cbind(rbind(Matrix(0, q*px, q*(t+s-px)),
                kronecker(Diagonal(t+s-px), -phi[[px]])),
          Matrix(0, q*(t+s), q*px))

  })) + Diagonal(n = q*(t+s))

  # one volatility path shared by all q factors, hence rep(h, each = q)
  Vinv <- Diagonal(x = exp(-2*rep(h, each = q)))
  F0 <- t(H) %*% Vinv %*% H

  # measurement block, as in draw_augmented_data()
  Kmat <- cbind(rbind(Matrix(0, n, n*(t-1)),
                      kronecker(Diagonal(t-1), -rho)),
                Matrix(0, t*n, n)) + Diagonal(n = n*t)
  Gext <- rbind(Matrix(0, n, q*(t+s)), Gmat)
  Sinv <- Diagonal(n = t) %x% Diagonal(x = 1/sigma_d)

  # joint precision of z = (f, x)
  GtS <- t(Gext) %*% Sinv
  KtS <- t(Kmat) %*% Sinv
  Qfx <- -(GtS %*% Kmat)
  Q <- rbind(cbind(F0 + GtS %*% Gext, Qfx),
             cbind(t(Qfx), KtS %*% Kmat))

  # det(H) = det(K) = 1, so the joint determinant is available in closed form
  # rather than from a factorization of the full q*(t+s) + n*t matrix
  logdet_Q <- -2 * q * sum(h) - t * sum(log(sigma_d))

  # x is stacked period-major, so entry (period i, series j) sits at (i-1)*n + j
  yv <- as.numeric(t(as.matrix(Ymat)))
  obs <- which(yv != 0)
  nobs <- length(obs)
  y <- yv[obs]

  ix_obs <- q*(t+s) + obs
  ix_lat <- seq_len(q*(t+s) + n*t)[-ix_obs]

  QLL <- forceSymmetric(Q[ix_lat, ix_lat, drop = FALSE])
  b <- Q[ix_lat, ix_obs, drop = FALSE] %*% y

  logdet_QLL <- as.numeric(determinant(QLL, logarithm = TRUE)$modulus)
  quad <- as.numeric(t(y) %*% Q[ix_obs, ix_obs, drop = FALSE] %*% y) -
    as.numeric(t(b) %*% solve(QLL, b))

  ll <- -0.5*nobs*log(2*pi) + 0.5*logdet_Q - 0.5*logdet_QLL - 0.5*quad

  structure(ll, df = fit_loglik_df(object, is_fcast, n, q, p, h, rho_d),
            nobs = nobs, class = "logLik")

}

#' Free parameters counted by logLik(), for AIC()/BIC()
#'
#' Counts the parameters of the measurement and state equations only. The
#' latent states - the factor path, the augmented data and the volatility path
#' itself - are not parameters and are not counted, which is what makes
#' `AIC()`/`BIC()` approximate for this model class.
#'
#' Both switches are read off the fit rather than stored on it: with
#' `serial_correlation = FALSE` every `rho` is held at exactly `1e-9`, and with
#' `stochastic_volatility = FALSE` the volatility path is constant. The
#' volatility contributes one parameter in either case for [ind_dfm()] (`omega`,
#' or the constant variance, which is still estimated there) but nothing for
#' [fcast_dfm()] with stochastic volatility off, where the variance is *fixed*
#' at one and carries the identification. See CLAUDE.md, "Scale identification".
#'
#' @noRd
fit_loglik_df <- function(object, is_fcast, n, q, p, h, rho_d){

  serial <- any(abs(rho_d) > 1e-6)
  sv <- length(unique(h)) > 1

  if(is_fcast){
    # the loadings are unrestricted in sampling; identification is post-hoc, and
    # an orthogonal q x q rotation has q*(q-1)/2 free angles
    n_lambda <- n*q - q*(q - 1)/2
    n_phi <- p*q^2
    n_vol <- as.integer(sv)
  } else {
    # lambda[target] is fixed at 1 by the identifying restriction
    n_lambda <- n - 1
    n_phi <- p
    n_vol <- 1L
  }

  as.integer(n_lambda + n_phi + n + serial*n + n_vol)

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

  cat("\nFull results: $factor, $nowcast, $index, $pars; summary(), plot(),\n")
  cat("as.data.frame(), coef(), fitted(), residuals(), logLik()\n")

  invisible(x)

}


# ----------------------------------------------------------- screeplot ----

#' @rdname fcast_dfm_methods
#' @method screeplot fcast_dfm
#' @importFrom stats screeplot var
#' @export
screeplot.fcast_dfm <- function(x, npcs = NULL, type = c("barplot", "lines"),
                                main = NULL, ...){

  type <- match.arg(type)

  lam <- as.matrix(x$pars$lambda)
  fac <- as.matrix(x$factor)

  # variance of the standardized panel attributable to each factor: the factor's
  # own variance times the sum of squared loadings on it
  contrib <- apply(fac, 2, var) * colSums(lam^2)

  # total variance of the observed part of the prepared data. 0 encodes a
  # missing observation there, so it is masked out rather than differenced
  # against, exactly as residuals() does.
  dat <- as.matrix(x$data)
  dat[dat == 0] <- NA_real_
  total <- sum(apply(dat, 2, var, na.rm = TRUE), na.rm = TRUE)

  share <- contrib / total
  # rotated factors are NOT ordered by variance the way principal components
  # are; sorting is a presentational choice, and the names record the original
  # factor each bar belongs to
  ord <- order(share, decreasing = TRUE)
  share <- share[ord]
  names(share) <- paste0("f", ord)

  if(is.null(npcs)) npcs <- length(share)
  if(!is_count(npcs) || npcs < 1 || npcs > length(share)){
    stop("`npcs` must be a single whole number between 1 and ",
         length(share), ".", call. = FALSE)
  }
  share <- share[seq_len(npcs)]

  scree_draw(share, type = type,
             ylab = "share of panel variance",
             xlab = "factor (sorted)",
             main = if(is.null(main)) "Variance explained by each rotated factor" else main,
             ...)

  invisible(share)

}

#' @rdname ind_dfm_methods
#' @method screeplot ind_dfm
#' @importFrom stats screeplot
#' @export
screeplot.ind_dfm <- function(x, ...){

  # deliberately an error rather than a one-bar plot: ind_dfm() has exactly one
  # factor by construction, so a scree plot conveys nothing, and drawing one
  # would imply a choice the model does not offer.
  stop("`screeplot()` is not meaningful for an `ind_dfm` fit: the model has ",
       "exactly one factor by construction, so there is no sequence of ",
       "components to inspect.\n",
       "  To choose a factor count, use `select_factors()`; to fit more than ",
       "one factor, use `fcast_dfm()`.", call. = FALSE)

}
