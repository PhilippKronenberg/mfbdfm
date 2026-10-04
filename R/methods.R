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
#'     It carries the [mfbdfm_table_loadings()] and [mfbdfm_table_parameters()]
#'     tables in `loadings_table` and `parameters_table`, and prints from them,
#'     so a printed summary and a tabulated one report the same numbers.
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
#'     `object$pars`, and their posterior spread in `object$pars_dist`; for a
#'     table with uncertainty see [mfbdfm_table_loadings()] and
#'     [mfbdfm_table_parameters()].}
#'   \item{`fitted()`}{The augmented dataset: observed values where a series
#'     was observed, the model's latent estimate where it was not. On the
#'     standardized scale the model works in by default; `scale = "original"`
#'     puts every column back in its own units.}
#'   \item{`residuals()`}{Observed minus fitted. **Unobserved periods are
#'     `NA`, not zero** -- the prepared data encodes a missing observation as
#'     `0`, so differencing directly would report a spurious residual wherever
#'     a series was not observed, which in a mixed-frequency model is most of
#'     the matrix for the low-frequency series. `scale = "original"` rescales by
#'     each series' standard deviation only, the series mean cancelling in a
#'     difference.}
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
#' not exist. Use [mfbdfm_nowcast()] to get at those stored nowcasts; it is
#' the accessor the missing `predict()` would otherwise be mistaken for.
#'
#' @section What `logLik()` means here:
#'
#' Neither model computes a likelihood while sampling -- the factors are drawn
#' jointly from a stacked, precision-based conditional, and there is no Kalman
#' filter anywhere in the package. So the value has to be *defined*, and the
#' definition adopted is: *the Gaussian log density of the **observed** entries
#' of the prepared data, evaluated at the posterior mean parameters and the
#' posterior mean volatility path, with the factors and the unobserved data
#' entries marginalised out.*
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
#' @param scale Character, the scale `fitted()` and `residuals()` report on:
#'   `"standardized"` (the default, the scale the model works in) or
#'   `"original"` (each series back in its own units). See
#'   [mfbdfm_table_loadings()] for the same argument on the loadings.
#' @param row.names,optional Ignored, present for compatibility with the
#'   [as.data.frame()] generic.
#' @param ... Ignored, present for compatibility with the generics.
#'
#' @return `coef()` a named numeric vector; `fitted()` and `residuals()` `ts`
#'   matrices with one column per series; `as.data.frame()` a data frame with
#'   `time` and the factor with bands; `summary()` an object of class
#'   `"summary.mfbdfm_fit"`, whose `$r_squared` element is a data frame with
#'   columns `series`, `freq`, `n_obs` and `r_squared`, sorted by fit;
#'   `logLik()` an object of class `"logLik"` with `df` and `nobs` attributes;
#'   `print()` and `plot()` return their input invisibly.
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 20, burn_in = 5)
#' fit
#' coef(fit)
#' head(as.data.frame(fit))
#' logLik(fit)
#' AIC(fit)              # approximate here - see "What logLik() means"
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
#' As for [ind_dfm()] fits, the stored nowcasts are reached with
#' [mfbdfm_nowcast()].
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
#' @param scale Character, the scale `fitted()` and `residuals()` report on:
#'   `"standardized"` (the default) or `"original"`. As for [ind_dfm()]; see
#'   [ind_dfm_methods].
#' @param row.names,optional Ignored, present for compatibility with the
#'   [as.data.frame()] generic.
#' @param ... Ignored, present for compatibility with the generics.
#'
#' @return As [ind_dfm_methods], except that `coef()` returns a matrix and
#'   `screeplot()` invisibly returns the sorted variance shares.
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#' fit <- fcast_dfm(mfbdfm_example_data, q = 2, length_sample = 20, burn_in = 5)
#' fit
#' coef(fit)          # a q-column matrix here, a vector for ind_dfm()
#' screeplot(fit)     # share of panel variance per rotated factor
#' head(as.data.frame(fit))
#' logLik(fit)
#' BIC(fit)           # approximate here - see ?ind_dfm_methods
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
fitted.ind_dfm <- function(object, scale = c("standardized", "original"), ...){
  fit_fitted(object, scale)
}

#' @rdname fcast_dfm_methods
#' @method fitted fcast_dfm
#' @export
fitted.fcast_dfm <- function(object, scale = c("standardized", "original"), ...){
  fit_fitted(object, scale)
}

#' @noRd
fit_fitted <- function(object, scale){

  out <- object$data_augmented
  if(match_scale(scale) == "standardized") return(out)

  # prepare_data() standardizes as (x - mean)/sd, so the inverse puts both the
  # location and the scale back
  sc <- fit_scaling(object)
  rescale_fit_matrix(out, sd = sc$sd, mean = sc$mean)

}


# ----------------------------------------------------------- residuals ----

#' @rdname ind_dfm_methods
#' @method residuals ind_dfm
#' @export
residuals.ind_dfm <- function(object, scale = c("standardized", "original"), ...){
  fit_residuals(object, scale)
}

#' @rdname fcast_dfm_methods
#' @method residuals fcast_dfm
#' @export
residuals.fcast_dfm <- function(object, scale = c("standardized", "original"), ...){
  fit_residuals(object, scale)
}

#' @noRd
fit_residuals <- function(object, scale = "standardized"){

  obs <- object$data
  fit <- object$data_augmented

  res <- obs - fit
  # 0 encodes "not observed" in the prepared data; a residual there is
  # meaningless rather than zero
  res[obs == 0] <- NA_real_

  if(match_scale(scale) == "standardized") return(res)

  # a residual is a difference, so the series mean cancels: only the scale
  # factor converts it
  rescale_fit_matrix(res, sd = fit_scaling(object)$sd, mean = 0)

}

#' Put a standardized data matrix back on each series' own scale
#'
#' Columns of `$data`/`$data_augmented` are in `inventory$key` order (see
#' [prepare_data()]), so the per-series moments line up column for column.
#' `mean = 0` converts a difference, where the location cancels.
#'
#' @noRd
rescale_fit_matrix <- function(x, sd, mean){

  out <- x
  out[] <- sweep(sweep(as.matrix(x), 2, sd, "*"), 2, mean, "+")
  out

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
#' their own matrices, so no filtering code is added. The precision itself is
#' built by [dfm_joint_precision()], which [mfbdfm_contributions()] also uses.
#' Write `f` for the stacked
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

  jp <- dfm_joint_precision(object)

  Q <- jp$Q
  y <- jp$y
  nobs <- jp$nobs

  QLL <- forceSymmetric(Q[jp$ix_lat, jp$ix_lat, drop = FALSE])
  b <- Q[jp$ix_lat, jp$ix_obs, drop = FALSE] %*% y

  logdet_QLL <- as.numeric(determinant(QLL, logarithm = TRUE)$modulus)
  quad <- as.numeric(t(y) %*% Q[jp$ix_obs, jp$ix_obs, drop = FALSE] %*% y) -
    as.numeric(t(b) %*% solve(QLL, b))

  ll <- -0.5*nobs*log(2*pi) + 0.5*jp$logdet_Q - 0.5*logdet_QLL - 0.5*quad

  structure(ll, df = fit_loglik_df(object, jp$is_fcast, jp$n, jp$q, jp$p,
                                   jp$h, jp$rho),
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
                 # the printed numbers come from these, so a printed summary and
                 # a tabulated one cannot disagree (#113). The bare
                 # $loadings/$phi/$sigma/$rho fields above are kept for
                 # compatibility with code that already reads them.
                 loadings_table = mfbdfm_table_loadings(object),
                 parameters_table = mfbdfm_table_parameters(object),
                 nowcast = object$nowcast,
                 n_observed = sum(!is.na(res)),
                 rmse = sqrt(mean(res^2, na.rm = TRUE)),
                 r_squared = fit_r_squared(object)),
            class = "summary.mfbdfm_fit")

}

#' Select and round the columns of a table for printing
#'
#' `drop_single_factor` removes the `factor` column when there is only one
#' factor to name, which is the `ind_dfm()` case: the column is carried in the
#' table for parity with `fcast_dfm()` but says nothing when constant.
#'
#' @noRd
summary_table_block <- function(tab, cols, drop_single_factor = FALSE){

  if(is.null(tab)) return(NULL)

  if(drop_single_factor && length(unique(tab$factor)) < 2){
    cols <- setdiff(cols, "factor")
  }

  out <- tab[, intersect(cols, names(tab)), drop = FALSE]
  num <- vapply(out, is.numeric, logical(1))
  out[num] <- lapply(out[num], round, digits = 4)

  rownames(out) <- NULL
  out

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
#' data(mfbdfm_example_data)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 20, burn_in = 5)
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

  # printed from the same tables mfbdfm_table_*() returns, so the two views of
  # a fit report the same numbers (#113)
  cat("\nFactor loadings (posterior mean, 95% interval):\n")
  print(summary_table_block(x$loadings_table,
                            c("series", "factor", "mean", "sd", "lower", "upper"),
                            drop_single_factor = TRUE))

  cat("\nMeasurement error variance (posterior mean, 95% interval):\n")
  print(summary_table_block(x$parameters_table[x$parameters_table$block == "sigma", ],
                            c("series", "mean", "sd", "lower", "upper")))
  cat("  (the measurement error sd is the square root of `mean`)\n")

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

  cat("\nFull results: $factor, $nowcast, $index, $pars; mfbdfm_nowcast(),\n")
  cat("summary(), plot(), as.data.frame(), coef(), fitted(), residuals(),\n")
  cat("logLik()\n")
  cat("Tables: mfbdfm_table_loadings(), mfbdfm_table_parameters(),\n")
  cat("mfbdfm_table_nowcast()\n")

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
