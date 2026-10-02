# Table-ready summaries of a fitted model (#113).
#
# These turn the posterior means already stored in `fit$pars` and the posterior
# spread stored in `fit$pars_dist` into plain tidy data frames, so that reports
# and papers do not have to reach into the list structure and build LaTeX by
# hand.
#
# Where the uncertainty comes from. The fits store posterior MEANS only - the
# retained draws are discarded when the sampler returns. Rather than keep every
# draw, both entry points now summarise the parameter blocks at fit time into a
# `$pars_dist` component holding the posterior `sd` and the 2.5%/97.5%
# quantiles. That is a few numbers per parameter, consumes no RNG, and changes
# no existing computation, so `dev/baseline.R`'s snapshot is unaffected (it is
# a NEW component, and `baseline_digest()` walks a fixed list of names).
#
# The posterior MEAN is deliberately NOT stored in `$pars_dist`: it already
# lives in `$pars`, and keeping one copy is what makes it impossible for a
# table to disagree with `coef()` in the last bit - `ind_dfm()` averages with
# `Reduce("+")/N`, which does not accumulate in long double the way
# `rowMeans()` does. The one exception is the `factor_var` block, which has no
# counterpart in `$pars` and therefore carries its own `mean`.


# -------------------------------------------------- posterior summaries ----

PARS_DIST_PROBS <- c(0.025, 0.975)

#' Posterior sd and interval of each row of a draws matrix
#'
#' @param m A `parameters x draws` numeric matrix, or a plain vector for a
#'   scalar parameter.
#'
#' @noRd
#' @importFrom stats sd quantile
summarise_draw_matrix <- function(m, probs = PARS_DIST_PROBS){

  if(is.null(dim(m))) m <- matrix(m, nrow = 1L)

  qs <- apply(m, 1, quantile, probs = probs, names = FALSE, na.rm = TRUE)

  list(sd = apply(m, 1, sd),
       lower = qs[1, ],
       upper = qs[2, ])

}


#' Posterior spread of the single-factor model's parameter blocks
#'
#' Built from the draws `run_sampling()` retains, so nothing is re-simulated.
#' `h` is trimmed to the same `(s+1):(t+s)` window as `pars$h`, so the two are
#' aligned period for period.
#'
#' With `stochastic_volatility = FALSE` there is no volatility path and `omega`
#' is never drawn - it keeps its start value - so reporting it would be a silent
#' wrong answer. The constant factor-innovation variance `exp(2*h)` is reported
#' as `factor_var` instead, and it carries its own `mean` because `pars` has no
#' entry for it.
#'
#' @noRd
pars_dist_ind <- function(par_save, stochastic_volatility, s, t){

  dm <- function(lst, len) vapply(lst, function(x) as.numeric(x), numeric(len))

  n <- length(as.numeric(par_save$lambda[[1]]))
  p <- length(as.numeric(par_save$phi[[1]]))

  h_draws <- dm(par_save$h, t + s)

  out <- list(lambda = summarise_draw_matrix(dm(par_save$lambda, n)),
              phi    = summarise_draw_matrix(dm(par_save$phi, p)),
              sigma  = summarise_draw_matrix(dm(par_save$sigma, n)),
              rho    = summarise_draw_matrix(dm(par_save$rho, n)),
              h      = summarise_draw_matrix(h_draws[(s + 1):(t + s), , drop = FALSE]))

  if(stochastic_volatility){

    out$omega <- summarise_draw_matrix(dm(par_save$omega, 1L))

  } else {

    # h is constant within a draw here (draw_factor_variance() repeats one
    # value over every period), so any row gives the draw's variance.
    #
    # The `mean` below is the posterior mean of the VARIANCE, mean(exp(2h)) -
    # not exp(2*mean(h)), which is what reading it off `pars$h` would give.
    # exp is convex, so the two differ by Jensen's inequality and the second is
    # strictly smaller. The posterior mean of the quantity being reported is
    # the one that belongs in a column headed `mean`.
    fv <- exp(2 * h_draws[s + 1L, ])
    out$factor_var <- c(summarise_draw_matrix(fv),
                        list(mean = mean(fv), fixed = FALSE))

  }

  out$probs <- PARS_DIST_PROBS
  out

}


#' Posterior spread of the multi-factor model's parameter blocks
#'
#' Read straight out of the rotated packed draws, using the same offsets as
#' [theta2list_fcast()] - only the parameter region and the volatility path,
#' never the `n*t` augmented-data block, which is the large part.
#'
#' There is deliberately **no `omega` entry**: `omega` is drawn in this model
#' but is not packed into `theta`, so no posterior summary of it exists.
#' With `stochastic_volatility = FALSE` the factor innovation variance is
#' *fixed* at one - it carries the identification here, where `ind_dfm()` still
#' estimates it (see CLAUDE.md, "Scale identification") - so `factor_var` is
#' reported with zero spread and `fixed = TRUE`.
#'
#' @noRd
pars_dist_fcast <- function(rlist, n, q, p, s, t, stochastic_volatility){

  npar <- n*q + p*q^2 + 2*n
  ix_lambda <- seq_len(n*q)
  ix_phi <- n*q + seq_len(p*q^2)
  ix_sigma <- n*q + p*q^2 + seq_len(n)
  ix_rho <- n*q + p*q^2 + n + seq_len(n)
  ix_h <- npar + n*t + seq_len(t + s)

  M <- vapply(rlist, function(rx) as.numeric(rx[seq_len(npar), ]), numeric(npar))
  H <- vapply(rlist, function(rx) as.numeric(rx[ix_h, ]), numeric(t + s))

  out <- list(lambda = summarise_draw_matrix(M[ix_lambda, , drop = FALSE]),
              phi    = summarise_draw_matrix(M[ix_phi, , drop = FALSE]),
              sigma  = summarise_draw_matrix(M[ix_sigma, , drop = FALSE]),
              rho    = summarise_draw_matrix(M[ix_rho, , drop = FALSE]),
              h      = summarise_draw_matrix(H))

  if(!stochastic_volatility){
    out$factor_var <- list(sd = 0, lower = 1, upper = 1, mean = 1, fixed = TRUE)
  }

  out$probs <- PARS_DIST_PROBS
  out

}


#' One parameter block's spread, or NA of the right length
#'
#' A fit produced before `$pars_dist` existed has no spread to report. The
#' tables still build - with `NA` in the `sd`/`lower`/`upper` columns - rather
#' than erroring, which is the difference between an old fit being readable and
#' being useless.
#'
#' @noRd
pars_dist_block <- function(fit, block, len){

  d <- fit$pars_dist[[block]]
  if(is.null(d)) return(list(sd = rep(NA_real_, len),
                             lower = rep(NA_real_, len),
                             upper = rep(NA_real_, len)))

  list(sd = rep_len(as.numeric(d$sd), len),
       lower = rep_len(as.numeric(d$lower), len),
       upper = rep_len(as.numeric(d$upper), len))

}


# ------------------------------------------------------------- rendering ----

#' Render a table in one of the supported output formats
#'
#' The shared \pkg{knitr} wrapper behind the `format` argument of
#' [mfbdfm_table_loadings()], [mfbdfm_table_parameters()] and
#' [mfbdfm_table_nowcast()]. Exported so that a table built by hand, or one of
#' those data frames after further manipulation, can be rendered the same way.
#'
#' @param x A data frame.
#' @param format Character, one of `"latex"`, `"html"` or `"markdown"`.
#' @param digits Integer, significant digits passed to [knitr::kable()].
#' @param caption Character or `NULL`, a table caption.
#'
#' @return A character vector of class `"knitr_kable"`.
#'
#' @examples
#' mfbdfm_kable(data.frame(series = c("a", "b"), mean = c(1.234567, 2)),
#'              format = "markdown")
#'
#' @seealso [mfbdfm_table_loadings()], [mfbdfm_table_parameters()],
#'   [mfbdfm_table_nowcast()]
#' @family model tables
#' @importFrom knitr kable
#' @export
mfbdfm_kable <- function(x, format = c("latex", "html", "markdown"),
                         digits = 4, caption = NULL){

  format <- match.arg(format)

  if(!is.data.frame(x)){
    stop("`x` must be a data frame, not a ", class(x)[1], ".", call. = FALSE)
  }
  if(!is_count(digits)){
    stop("`digits` must be a single non-negative integer.", call. = FALSE)
  }

  kable(x, format = format, digits = digits, caption = caption,
        row.names = FALSE)

}


#' Return a table as a data frame or render it
#'
#' `digits` deliberately affects the **rendered** output only. The data frame is
#' the primary return value and is left unrounded: a table is often the input to
#' further arithmetic, and silently rounding it would make the primary output
#' lossy for the convenience of the secondary one.
#'
#' @noRd
finish_table <- function(x, format, digits, caption){

  format <- match.arg(format, c("data.frame", "latex", "html", "markdown"))

  if(format == "data.frame") return(x)

  mfbdfm_kable(x, format = format, digits = digits, caption = caption)

}


#' Validate the `scale` argument shared by the tables and fitted()/residuals()
#'
#' @noRd
match_scale <- function(scale){
  match.arg(scale, c("standardized", "original"))
}


#' Each series' standardization sd and mean, in inventory order
#'
#' [prepare_data()] standardizes every series as `(x - mean)/sd` using these
#' moments, so they are what maps any standardized quantity back.
#'
#' @noRd
fit_scaling <- function(fit){
  list(sd = as.numeric(fit$inventory$sd),
       mean = as.numeric(fit$inventory$mean))
}


# ------------------------------------------------------- loadings table ----

#' Factor loadings as a table, with posterior uncertainty
#'
#' The posterior mean, standard deviation and 95% interval of every factor
#' loading, as a tidy data frame - one row per series for an [ind_dfm()] fit,
#' one row per series and factor for a [fcast_dfm()] fit.
#'
#' @details
#' # Scale
#'
#' The model works on standardized data: [prepare_data()] replaces each series
#' `x` by `(x - mean(x))/sd(x)`, so the loadings it estimates are loadings on
#' the standardized series. That is the **default** here, `scale =
#' "standardized"` - the model's own numbers, unaltered, and the same values
#' [coef()] returns.
#'
#' `scale = "original"` multiplies each row by that series' standard deviation
#' from the inventory. Writing the measurement equation for series `i` as
#' `(x_i - m_i)/s_i = lambda_i f + e_i` and multiplying through by `s_i` gives
#' `x_i = m_i + (s_i lambda_i) f + s_i e_i`, so `s_i lambda_i` is the loading
#' in the series' own units: the change in `x_i` per unit of the factor. The
#' series mean does not enter, being an intercept rather than a slope.
#'
#' # The fixed loading
#'
#' An [ind_dfm()] fit pins the loading on `target` at exactly one - that
#' restriction is the model's identification, which is what makes the factor
#' interpretable as the target's growth rate (see [ind_dfm()] and [dfm_priors()]).
#' The `fixed` column flags that row, so a value of one is not read as an
#' estimate that happened to land there. Its posterior `sd` is zero for the same
#' reason. On the original scale the fixed row reads `sd(target)`, the target's
#' own standard deviation, which is the correct unit conversion of a loading of
#' one.
#'
#' A [fcast_dfm()] fit has no fixed loading: its loadings are unrestricted
#' during sampling and identified afterwards by rotation. Note that the
#' rotation does not reach uniqueness (see the Maturity section of
#' [fcast_dfm()]), so individual loadings there should not be read as unique
#' across runs even though this table reports a posterior interval for them.
#'
#' @param fit A fit from [ind_dfm()] or [fcast_dfm()].
#' @param scale Character, `"standardized"` (the default, the model's own
#'   loadings) or `"original"` (rescaled into each series' own units). See
#'   Details.
#' @param format Character, `"data.frame"` (the default), `"latex"`, `"html"`
#'   or `"markdown"`. The data frame is the primary output; the other three
#'   render it through [mfbdfm_kable()].
#' @param digits Integer, significant digits for the rendered formats. The data
#'   frame is returned unrounded.
#' @param caption Character or `NULL`, a caption for the rendered formats.
#'
#' @return A data frame with columns `series`, `type` (flow or stock), `freq`,
#'   `factor`, `mean`, `sd`, `lower`, `upper` and `fixed`; or a
#'   `"knitr_kable"` object when `format` is not `"data.frame"`. `sd`, `lower`
#'   and `upper` are `NA` for a fit made before `$pars_dist` existed.
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
#' mfbdfm_table_loadings(fit)
#' mfbdfm_table_loadings(fit, scale = "original")
#' mfbdfm_table_loadings(fit, format = "markdown")
#' }
#'
#' @seealso [mfbdfm_table_parameters()], [mfbdfm_table_nowcast()],
#'   [ind_dfm_methods]
#' @family model tables
#' @export
mfbdfm_table_loadings <- function(fit,
                                  scale = c("standardized", "original"),
                                  format = c("data.frame", "latex", "html", "markdown"),
                                  digits = 4,
                                  caption = NULL){

  check_fit(fit)
  scale <- match_scale(scale)

  inv <- fit$inventory
  n <- nrow(inv)
  lambda <- as.matrix(fit$pars$lambda)
  q <- ncol(lambda)

  # $pars_dist$lambda is stored in the packing order of the loading matrix,
  # which is column-major (factor by factor), so as.numeric(lambda) lines up
  # with it element for element
  d <- pars_dist_block(fit, "lambda", n*q)

  out <- data.frame(
    series = rep(inv$key, times = q),
    type = rep(as.character(inv$type), times = q),
    freq = rep(as.numeric(inv$freq), times = q),
    factor = rep(paste0("factor", seq_len(q)), each = n),
    mean = as.numeric(lambda),
    sd = d$sd,
    lower = d$lower,
    upper = d$upper,
    stringsAsFactors = FALSE)

  # the identifying restriction, flagged rather than left to look like an
  # estimate that happened to come out at exactly 1
  out$fixed <- !inherits(fit, "fcast_dfm") & out$series == fit$target

  if(scale == "original"){
    s <- rep(fit_scaling(fit)$sd, times = q)
    for(col in c("mean", "sd", "lower", "upper")) out[[col]] <- out[[col]] * s
  }

  attr(out, "scale") <- scale
  rownames(out) <- NULL

  finish_table(out, format, digits, caption)

}


# ----------------------------------------------------- parameters table ----

#' Estimated parameters as a table, with posterior uncertainty
#'
#' Every parameter block of a fitted model in one tidy data frame: the factor
#' autoregressive coefficients `phi`, the measurement-error variances `sigma`
#' and autocorrelations `rho`, and the volatility parameter - `omega` where a
#' stochastic volatility path was estimated, the constant `factor_var` where it
#' was not.
#'
#' @details
#' # What is not an estimate
#'
#' Two columns mark values that should not be read as estimates:
#'
#' \describe{
#'   \item{`fixed`}{The value was imposed, not drawn. The only case is a
#'     [fcast_dfm()] fit with `stochastic_volatility = FALSE`, whose factor
#'     innovation variance is fixed at exactly one because it carries the
#'     identification there.}
#'   \item{`structural`}{The value was drawn, but under a prior that *is* the
#'     model's identification rather than a tuning knob - so it is informative
#'     by design and tells you about the restriction as much as about the data.
#'     For [ind_dfm()] these are the target series' own `sigma` and `rho`,
#'     shrunk toward zero to anchor the factor to the target; see
#'     [dfm_priors()], which lists the same two as structural.}
#' }
#'
#' # Blocks that are absent, and why
#'
#' \describe{
#'   \item{`omega` for a [fcast_dfm()] fit}{`omega` is drawn in that model but
#'     is not packed into the retained draw vector, so no posterior summary of
#'     it exists. It is omitted rather than reported from a value that was never
#'     retained.}
#'   \item{`omega` with `stochastic_volatility = FALSE`}{There is no volatility
#'     path for `omega` to be the innovation variance of, and the sampler never
#'     draws it - it keeps its start value. Reporting that number would be a
#'     silent wrong answer, so `factor_var` is reported instead.}
#'   \item{The volatility path itself}{`h` is a latent state, one value per
#'     period, not a parameter. It is in `fit$pars$h`, with its posterior spread
#'     in `fit$pars_dist$h`. Note that the `factor_var` row is the posterior
#'     mean of the *variance*, `mean(exp(2h))` over draws -- not `exp(2h)`
#'     evaluated at the posterior mean of `h`, which is strictly smaller since
#'     `exp` is convex.}
#'   \item{The loadings}{In [mfbdfm_table_loadings()], which also handles the
#'     original-scale conversion they need.}
#' }
#'
#' @param fit A fit from [ind_dfm()] or [fcast_dfm()].
#' @inheritParams mfbdfm_table_loadings
#'
#' @return A data frame with columns `block`, `parameter`, `series` (`NA` for
#'   blocks that are not per-series), `mean`, `sd`, `lower`, `upper`, `fixed`
#'   and `structural`; or a `"knitr_kable"` object when `format` is not
#'   `"data.frame"`.
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
#' mfbdfm_table_parameters(fit)
#' }
#'
#' @seealso [mfbdfm_table_loadings()], [mfbdfm_table_nowcast()],
#'   [dfm_priors()] for which priors are structural
#' @family model tables
#' @export
mfbdfm_table_parameters <- function(fit,
                                    format = c("data.frame", "latex", "html", "markdown"),
                                    digits = 4,
                                    caption = NULL){

  check_fit(fit)

  is_fcast <- inherits(fit, "fcast_dfm")
  inv <- fit$inventory
  n <- nrow(inv)

  blk <- function(block, parameter, series, mean, fixed = FALSE,
                  structural = FALSE){
    len <- length(mean)
    d <- pars_dist_block(fit, block, len)
    data.frame(block = rep(block, len),
               parameter = parameter,
               series = series,
               mean = as.numeric(mean),
               sd = d$sd, lower = d$lower, upper = d$upper,
               fixed = rep_len(fixed, len),
               structural = rep_len(structural, len),
               stringsAsFactors = FALSE)
  }

  # phi: a scalar per lag in ind_dfm, a q x q block per lag in fcast_dfm. The
  # labels follow the packing order of $pars_dist$phi, which is column-major
  # within each block (see list2theta_fcast()).
  phi <- fit$pars$phi
  if(is_fcast){
    q <- fit$pars$q
    lab <- unlist(lapply(seq_along(phi), function(px)
      paste0("phi", px, "[", rep(seq_len(q), times = q), ",",
             rep(seq_len(q), each = q), "]")))
    phi_mean <- unlist(lapply(phi, as.numeric))
  } else {
    lab <- paste0("phi[", seq_along(as.numeric(phi)), "]")
    phi_mean <- as.numeric(phi)
  }

  target_ix <- match(fit$target, inv$key)

  # STRUCTURAL in ind_dfm: structural_priors("ind_dfm") names sigma_target and
  # rho_target, the two priors that anchor the factor to the target
  struct <- rep(FALSE, n)
  if(!is_fcast && !is.na(target_ix)) struct[target_ix] <- TRUE

  rows <- list(
    blk("phi", lab, NA_character_, phi_mean),
    blk("sigma", paste0("sigma[", inv$key, "]"), inv$key,
        as.numeric(fit$pars$sigma), structural = struct),
    blk("rho", paste0("rho[", inv$key, "]"), inv$key,
        as.numeric(fit$pars$rho), structural = struct))

  # the volatility parameter, whichever one this fit actually has. $pars_dist
  # carries a factor_var entry exactly when stochastic volatility was off.
  fv <- fit$pars_dist$factor_var

  if(!is.null(fv)){

    rows <- c(rows, list(blk("factor_var", "factor_var", NA_character_,
                             as.numeric(fv$mean),
                             fixed = isTRUE(fv$fixed),
                             structural = isTRUE(fv$fixed))))

  } else if(!is_fcast && !is.null(fit$pars$omega)){

    rows <- c(rows, list(blk("omega", "omega", NA_character_,
                             as.numeric(fit$pars$omega))))

  }

  out <- do.call(rbind, rows)
  rownames(out) <- NULL

  finish_table(out, format, digits, caption)

}


# -------------------------------------------------------- nowcast table ----

#' The target series' nowcast as a table, with posterior uncertainty
#'
#' The stored nowcast for the fit's `target` series at that series' own
#' frequency, with its posterior standard deviation, a 95% interval, and the
#' observed value where one exists.
#'
#' @details
#' The nowcast is computed *during* fitting and stored, not produced on demand -
#' which is why neither fit class has a `predict()` method (see
#' [ind_dfm_methods]). This function reads `$nowcast` and `$nowcast_var` and
#' lines the observed target series up against them; it does not re-estimate
#' anything.
#'
#' Rows where `observed` is `NA` are the periods the target series does not
#' cover - the genuine nowcasts and backcasts.
#'
#' The nowcast is on the target series' **original scale** already, having been
#' de-standardized inside the sampler, so there is no `scale` argument here.
#'
#' @param fit A fit from [ind_dfm()] or [fcast_dfm()].
#' @inheritParams mfbdfm_table_loadings
#'
#' @return A data frame with columns `time`, `observed`, `nowcast`, `sd`,
#'   `lower` and `upper`; or a `"knitr_kable"` object when `format` is not
#'   `"data.frame"`.
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
#' utils::tail(mfbdfm_table_nowcast(fit))
#' }
#'
#' @seealso [mfbdfm_table_loadings()], [mfbdfm_table_parameters()]
#' @family model tables
#' @export
mfbdfm_table_nowcast <- function(fit,
                                 format = c("data.frame", "latex", "html", "markdown"),
                                 digits = 4,
                                 caption = NULL){

  check_fit(fit)

  out <- fit_nowcast_table(fit)

  finish_table(out, format, digits, caption)

}

#' Assemble the nowcast table from the stored nowcast
#'
#' The single place that reads `$nowcast`/`$nowcast_var`, so that when the
#' dedicated nowcast accessor of #104 lands on `main` there is one line to
#' delegate from rather than a second copy of this arithmetic to reconcile.
#'
#' @noRd
#' @importFrom stats time qnorm
fit_nowcast_table <- function(fit){

  z <- qnorm(0.975)

  ncst <- fit$nowcast
  sd <- sqrt(as.numeric(fit$nowcast_var))
  m <- as.numeric(ncst)

  out <- data.frame(time = as.numeric(time(ncst)),
                    observed = NA_real_,
                    nowcast = m,
                    sd = sd,
                    lower = m - z*sd,
                    upper = m + z*sd)

  # the observed target, matched on time. Rounded before matching because the
  # two time axes are both decimal dates built by different routes, and
  # floating-point equality on those is not reliable - the same precaution
  # get_target_series_fcast() takes.
  observed <- fit$data_raw[[fit$target]]
  if(!is.null(observed)){
    obs_t <- round(as.numeric(time(observed)), 5)
    out$observed <- as.numeric(observed)[match(round(out$time, 5), obs_t)]
  }

  out

}


# ---------------------------------------------------------------- shared ----

#' Reject anything that is not one of the two fit classes
#'
#' @noRd
check_fit <- function(fit){

  if(!inherits(fit, c("ind_dfm", "fcast_dfm"))){
    stop("`fit` must be a fit from `ind_dfm()` or `fcast_dfm()`, not a ",
         class(fit)[1], ".", call. = FALSE)
  }

  invisible(fit)

}
