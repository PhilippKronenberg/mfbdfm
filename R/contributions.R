# Decomposition of the smoothed factor, and of the target's nowcast, into the
# contribution of each input series.
#
# The one non-obvious thing about this file is that "loading x standardised
# series" is NOT a contribution. That product is the series' reconstruction
# *from* the factor -- the reverse direction -- and with missing data, temporal
# aggregation and serially correlated measurement errors it does not add up to
# the factor at all. What does add up is the smoother: conditional on the
# parameters, the posterior mean of the factor path is a linear map of the
# observed data, and grouping the columns of that map by series partitions it
# exactly. dfm_state_weights() below applies that map without ever forming it.

#' Joint precision of the factor path and the augmented data
#'
#' The sparse precision `Q` of `z = (f, x)` implied by the model at the
#' posterior mean parameters, together with the index sets that split `z` into
#' the entries pinned by an observation and the latent rest.
#'
#' @details
#' This is the construction described at length under [fit_loglik()], extracted
#' so that the log-likelihood, this file's contribution decomposition and (when
#' it lands) the news decomposition of issue #101 all build `Q` exactly once, in
#' one place. Nothing here is new: the matrices are the samplers' own, taken
#' from [draw_factors()] (the factor prior `f ~ N(0, F0^-1)`, `F0 = H' V^-1 H`)
#' and [draw_augmented_data()] (the measurement block
#' `K x ~ N(Gext f, I_t %x% sigma)`).
#'
#' `0` encodes a missing observation in the prepared data, so `ix_obs` covers
#' only the nonzero entries and everything else -- the whole factor path plus
#' every unobserved data entry -- is latent. The sampler's `1e-9` observation
#' variance is a numerical device rather than part of the model, so observed
#' entries are treated as exact.
#'
#' `h` covers all `t+s` periods in a [fcast_dfm()] fit. An [ind_dfm()] fit
#' stores only the `t` in-sample periods (see #49), so the `s` pre-sample
#' periods carried by the distributed lags are padded with its first value.
#'
#' @return A list with the precision `Q`, its log determinant in closed form,
#'   the observed/latent index sets and values, the model dimensions, and the
#'   posterior mean parameters and aggregation matrices used to build it.
#'
#' @noRd
dfm_joint_precision <- function(object){

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
  Llist <- get_distributed_lags(inventory)

  # the samplers' own observation matrix, at the posterior mean loadings
  Gmat <- get_gmat(get_gmat_prealloc(n = n, q = q, s = s, t = t),
                   Llist = Llist,
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

  ix_obs <- q*(t+s) + obs
  ix_lat <- seq_len(q*(t+s) + n*t)[-ix_obs]

  list(Q = Q, logdet_Q = logdet_Q,
       obs = obs, y = yv[obs], nobs = length(obs),
       ix_obs = ix_obs, ix_lat = ix_lat,
       n = n, t = t, q = q, p = p, s = s, k = k,
       lambda = lambda, phi = phi, sigma = sigma_d, rho = rho_d, h = h,
       Llist = Llist, inventory = inventory, Ymat = Ymat, is_fcast = is_fcast)

}


#' Smoother weights, applied to the data and aggregated by series group
#'
#' @details
#' Conditional on `z_O = y`, the latent block of a zero-mean Gaussian with
#' precision `Q` has mean
#'
#' \deqn{E[z_L \mid y] = -Q_{LL}^{-1} Q_{LO} y = W y,}
#'
#' so `W` is the weight each observation carries in the smoothed factor path and
#' in every unobserved data entry. Splitting the columns of `W` by series and
#' summing gives an exact decomposition, because the map is linear and every
#' observation belongs to exactly one series.
#'
#' **`W` is never formed.** It has one column per observation, which at the WAI's
#' dimensions is a dense matrix of tens of gigabytes. What is wanted is only the
#' group-aggregated product, so the aggregation is pushed inside the solve:
#' with `A` the `nobs x G` matrix holding `y` scattered into its group's column,
#'
#' \deqn{C = W A = -Q_{LL}^{-1} (Q_{LO} A),}
#'
#' which is one sparse solve against `G` right-hand sides -- a few dozen, not
#' tens of thousands. `rowSums(C)` is `E[z_L | y]` exactly, since the rows of `A`
#' sum to `y`.
#'
#' @param jp Output of [dfm_joint_precision()].
#' @param group_of Integer vector of length `n`, the group index of each series.
#' @param n_groups Number of groups.
#'
#' @return A dense matrix with `length(jp$ix_lat)` rows and `n_groups` columns.
#'   The first `q*(t+s)` rows are the factor path in the samplers' stacking
#'   (factor `qx` of period `m` in row `q*(m-1) + qx`); the remainder are the
#'   unobserved data entries, in increasing order of their position in the
#'   period-major data vector.
#'
#' @noRd
dfm_state_weights <- function(jp, group_of, n_groups){

  QLL <- forceSymmetric(jp$Q[jp$ix_lat, jp$ix_lat, drop = FALSE])
  QLO <- jp$Q[jp$ix_lat, jp$ix_obs, drop = FALSE]

  # observation at period-major position v belongs to series ((v-1) %% n) + 1
  series_of <- ((jp$obs - 1L) %% jp$n) + 1L

  A <- sparseMatrix(i = seq_along(jp$obs), j = group_of[series_of], x = jp$y,
                    dims = c(length(jp$obs), n_groups))

  as.matrix(-solve(QLL, QLO %*% A))

}


#' Resolve the grouping of the input series
#'
#' @noRd
dfm_resolve_groups <- function(inventory, by, groups){

  keys <- inventory$key

  if(by == "series"){
    return(list(levels = keys, index = seq_along(keys)))
  }

  col <- intersect(c("group", "category"), names(inventory))

  if(length(col) > 0){

    g <- as.character(inventory[[col[1]]])

  } else if(!is.null(groups)){

    if(is.null(names(groups)))
      stop("`groups` must be a NAMED character vector or list mapping series ",
           "names to group names.", call. = FALSE)

    groups <- vapply(as.list(groups), as.character, character(1))
    missing <- setdiff(keys, names(groups))
    if(length(missing) > 0)
      stop("`groups` is missing an entry for: ",
           paste(missing, collapse = ", "), ".", call. = FALSE)

    g <- unname(groups[keys])

  } else {

    stop("by = \"group\" needs a grouping: the inventory has no `group` or ",
         "`category` column, so supply one via `groups`.", call. = FALSE)

  }

  lev <- unique(g)
  list(levels = lev, index = match(g, lev))

}


#' Contribution of each input series to the factor and to the nowcast
#'
#' Decomposes the smoothed factor path, and the nowcast of the fit's `target`,
#' into the contribution of each input series (or of each group of series) in
#' every period. Answers "which series drive the factor, and by how much, when?"
#'
#' @details
#' The decomposition is the smoother's own. Conditional on the posterior mean
#' parameters and volatility path, the posterior mean of the factor path is a
#' linear function of the observed data, `E[f | y, theta] = W y`, and summing the
#' columns of `W` that belong to one series gives that series' contribution. It
#' is exact: the contributions sum to `E[f | y, theta]` to numerical tolerance,
#' a series whose loading is zero contributes zero, and an observation carries
#' weight in a period even when the series was not observed in it -- which is
#' the whole point, and is why "loading times standardised series" is not an
#' answer to this question. That product is the series' reconstruction *from*
#' the factor and does not sum to anything.
#'
#' Everything is reported on the **standardised, non-annualised scale the
#' sampler works on**, which is the scale on which the decomposition is linear.
#' `$factor` on an [ind_dfm()] fit is de-standardised and annualised through
#' `((1 + f)^frequency - 1) * 100`; that transformation is not linear, so
#' contributions to it do not exist. `totals$posterior` maps the fit's own
#' posterior mean back to the sampler's scale so that the two are comparable.
#'
#' ## The residual term
#'
#' `E[f | y, theta-hat]` is not the same thing as the MCMC posterior mean factor,
#' which averages over the posterior of `theta` rather than plugging in its mean.
#' The difference is reported rather than hidden: `totals` carries `plugin` (the
#' sum of the contributions), `posterior` (the fit's own posterior mean, mapped
#' to the same scale) and `residual = posterior - plugin`. Read `residual` as
#' parameter uncertainty. It shrinks as the chain lengthens and as the sample
#' grows; on a short chain over a couple of years it is not small, and a
#' decomposition whose residual dominates should not be read as if it explained
#' the factor.
#'
#' ## Contributions to the nowcast
#'
#' The target's value in period `i` is the aggregated factor plus its own
#' measurement error,
#' `x[i] = sum(L[sx] * lambda' f[i - sx]) + u[i]`, so the factor contributions
#' are carried through the target's loading and the model's own distributed-lag
#' aggregation weights `L`. `nowcast_totals` splits the nowcast into
#' `systematic` (the sum of those contributions) and `idiosyncratic`
#' (`E[x | y, theta-hat]` minus the systematic part, i.e. the measurement error
#' the smoother attributes to the target itself). Where the target was actually
#' observed, `E[x | y]` is the observation, and the idiosyncratic term absorbs
#' whatever the factor does not explain.
#'
#' ## Both classes
#'
#' [fcast_dfm()] gets one decomposition per factor. No extra rotation is needed:
#' `run_rotation_fcast()` and `run_identification_fcast()` rotate the draws
#' themselves, so the stored posterior mean `lambda` and `phi` are already in the
#' identified orientation and `W` is built from them.
#'
#' The reported time axis covers all `t+s` periods of the factor path, including
#' the `s` pre-sample periods the distributed lags carry. `totals$posterior` is
#' read from `$factor` for a [fcast_dfm()] fit and from `$factor_std` for an
#' [ind_dfm()] fit, both on the sampler's scale over all `t+s` periods. (An
#' [ind_dfm()] fit saved before `$factor_std` existed falls back to inverting
#' the annualised `$factor`, which leaves the pre-sample periods `NA`.)
#'
#' @param fit A fitted model from [ind_dfm()] or [fcast_dfm()].
#' @param by Either `"series"` (default, one component per input series) or
#'   `"group"` (one component per group of series).
#' @param groups Optional named character vector or list mapping every series
#'   name to a group name, used when `by = "group"` and the inventory has no
#'   `group` or `category` column. Ignored when `by = "series"`.
#'
#' @return An object of class `"mfbdfm_contributions"`, a list with
#'   \describe{
#'     \item{contributions}{Long data frame of contributions to the factor:
#'       `time`, the component column (named `series` or `group` after `by`),
#'       `factor` and `contribution`.}
#'     \item{totals}{Data frame of `time`, `factor`, `plugin`, `posterior` and
#'       `residual`.}
#'     \item{nowcast}{Long data frame of contributions to the target's nowcast,
#'       at the target's own frequency: `time`, the component column,
#'       `contribution`.}
#'     \item{nowcast_totals}{Data frame of `time`, `systematic`,
#'       `idiosyncratic`, `plugin`, `posterior` and `residual`.}
#'     \item{by, components, target, q, model, call}{Metadata.}
#'   }
#'   With `print()`, `as.data.frame()` and `plot()` methods.
#'
#' @references
#' Kronenberg, P. (2026). A weekly activity index for Switzerland.
#' *Swiss Journal of Economics and Statistics*, 162:10.
#' \doi{10.1186/s41937-026-00157-w}
#'
#' @seealso [ind_dfm()], [fcast_dfm()], [ind_dfm_methods]
#'
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' fit <- ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                               stats::window, start = 2021),
#'                stocks = lapply(data_ch_dataset_test$stocks[1:2],
#'                                stats::window, start = 2021),
#'                target = target, length_sample = 20, burn_in = 5,
#'                plots = FALSE)
#'
#' ct <- mfbdfm_contributions(fit)
#' ct
#' head(as.data.frame(ct))
#'
#' # the contributions add up to the smoothed factor, by construction
#' agg <- tapply(as.data.frame(ct)$contribution, as.data.frame(ct)$time, sum)
#' max(abs(agg - ct$totals$plugin))
#'
#' # by group, with a user-supplied mapping
#' grp <- c(rep("real", 2), rep("financial", nrow(fit$inventory) - 2))
#' names(grp) <- fit$inventory$key
#' mfbdfm_contributions(fit, by = "group", groups = grp)
#' }
#'
#' @family model functions
#' @importFrom stats time frequency ts
#' @export
mfbdfm_contributions <- function(fit, by = c("series", "group"), groups = NULL){

  if(!inherits(fit, c("ind_dfm", "fcast_dfm")))
    stop("`fit` must be a fitted model from ind_dfm() or fcast_dfm(), not an ",
         "object of class ", paste(class(fit), collapse = "/"), ".",
         call. = FALSE)

  by <- match.arg(by)

  jp <- dfm_joint_precision(fit)
  grp <- dfm_resolve_groups(jp$inventory, by = by, groups = groups)
  G <- length(grp$levels)

  C <- dfm_state_weights(jp, group_of = grp$index, n_groups = G)

  n <- jp$n; t <- jp$t; q <- jp$q; s <- jp$s; k <- jp$k
  nf <- q*(t + s)
  Cf <- C[seq_len(nf), , drop = FALSE]

  freq <- frequency(jp$Ymat)
  t_start <- as.numeric(time(jp$Ymat))[1]
  # stacked factor period m sits s periods before the data start when m = 1
  f_time <- t_start + (seq_len(t + s) - s - 1)/freq

  flabs <- paste0("factor", seq_len(q))

  # ------------------------------------------------- factor contributions ----

  contrib <- data.frame(
    time = rep(f_time, times = q*G),
    component = rep(rep(grp$levels, each = t + s), times = q),
    factor = rep(flabs, each = (t + s)*G),
    contribution = as.numeric(vapply(seq_len(q), function(qx)
      as.numeric(Cf[seq(from = qx, by = q, length.out = t + s), , drop = FALSE]),
      numeric((t + s)*G))),
    stringsAsFactors = FALSE)
  names(contrib)[2] <- by

  plugin <- vapply(seq_len(q), function(qx)
    rowSums(Cf[seq(from = qx, by = q, length.out = t + s), , drop = FALSE]),
    numeric(t + s))

  post <- dfm_factor_posterior(fit, jp, t, s, q)

  totals <- data.frame(time = rep(f_time, times = q),
                       factor = rep(flabs, each = t + s),
                       plugin = as.numeric(plugin),
                       posterior = as.numeric(post),
                       residual = as.numeric(post) - as.numeric(plugin),
                       stringsAsFactors = FALSE)

  # ------------------------------------------------ nowcast contributions ----

  nc <- dfm_nowcast_contributions(fit, jp, C, Cf, grp, by)

  structure(list(contributions = contrib,
                 totals = totals,
                 nowcast = nc$contributions,
                 nowcast_totals = nc$totals,
                 by = by,
                 components = grp$levels,
                 target = fit$target,
                 q = q,
                 model = if(jp$is_fcast) "fcast_dfm" else "ind_dfm",
                 call = match.call()),
            class = "mfbdfm_contributions")

}


#' The fit's own posterior mean factor, on the sampler's scale
#'
#' `fcast_dfm()` stores the factor untransformed and over all `t+s` periods, so
#' it is returned as is. `ind_dfm()` stores the same quantity as `$factor_std`
#' (#99), which is used when present.
#'
#' A fit saved before `$factor_std` existed has only `$factor`, de-standardised
#' and annualised over the `t` in-sample periods. That transformation is
#' inverted as a fallback, with two caveats: the `s` pre-sample periods are `NA`
#' rather than guessed, and since `$factor` is the mean of the *transformed*
#' draws and the transformation is convex, inverting it does not return the
#' mean of `f` exactly -- the gap then lands in `residual` on top of parameter
#' uncertainty.
#'
#' @noRd
#' @importFrom stats frequency
dfm_factor_posterior <- function(fit, jp, t, s, q){

  # both classes' sampler-scale posterior mean factor over all t+s periods
  fac <- if(jp$is_fcast) fit$factor else fit$factor_std

  if(!is.null(fac)){
    fac <- as.matrix(fac)
    # guard against an unexpected length rather than recycling silently
    if(nrow(fac) != t + s) return(matrix(NA_real_, t + s, q))
    return(unclass(fac))
  }

  if(jp$is_fcast) return(matrix(NA_real_, t + s, q))

  inv <- jp$inventory
  tsd <- inv[which(inv$key == fit$target), "sd"]
  tmn <- inv[which(inv$key == fit$target), "mean"]

  ann <- as.numeric(fit$factor)
  if(length(ann) != t) return(matrix(NA_real_, t + s, 1L))

  f_rescaled <- (ann/100 + 1)^(1/frequency(jp$Ymat)) - 1
  matrix(c(rep(NA_real_, s), (f_rescaled - tmn/jp$k)/tsd), ncol = 1L)

}


#' Carry the factor contributions through to the target's nowcast
#'
#' @noRd
#' @importFrom stats time frequency
dfm_nowcast_contributions <- function(fit, jp, C, Cf, grp, by){

  n <- jp$n; t <- jp$t; q <- jp$q; s <- jp$s
  G <- length(grp$levels)
  inv <- jp$inventory
  j <- which(inv$key == fit$target)

  lam <- jp$lambda[j, ]
  # the target's own row of each distributed-lag matrix
  Lj <- vapply(0:s, function(sx) diag(jp$Llist[[as.character(sx)]])[j],
               numeric(1))

  # fw[m, g] is group g's contribution to the target's loading-weighted factor
  # in stacked period m
  fw <- matrix(0, t + s, G)
  for(qx in seq_len(q))
    fw <- fw + lam[qx] * Cf[seq(from = qx, by = q, length.out = t + s), ,
                            drop = FALSE]

  # sys[i, g]: data period i uses stacked factor periods i+s-sx, sx = 0..s
  sys <- matrix(0, t, G)
  for(sx in 0:s)
    if(Lj[sx + 1] != 0) sys <- sys + Lj[sx + 1] * fw[seq_len(t) + s - sx, ,
                                                     drop = FALSE]

  # E[x_target | y, theta-hat] at every high-frequency period: the observation
  # where there is one, the smoothed value otherwise
  pos <- (seq_len(t) - 1L)*n + j
  xhat <- numeric(t)
  is_obs <- pos %in% jp$obs
  xhat[is_obs] <- jp$y[match(pos[is_obs], jp$obs)]
  if(any(!is_obs)){
    lat <- setdiff(seq_len(n*t), jp$obs)
    row <- q*(t + s) + match(pos[!is_obs], lat)
    xhat[!is_obs] <- rowSums(C[row, , drop = FALSE])
  }

  # the target is observed on its own frequency grid, at the period-end slot
  # prepare_data() shifts it to
  freq_max <- max(inv$freq)
  fq <- inv[j, "freq"]
  tt <- as.numeric(time(jp$Ymat))
  # get_nowcast()'s own rule, so the two pick the same periods
  idx <- which(round(tt + 1/freq_max, 3) %% (1/fq) == 0)
  shift <- (freq_max/fq - 1)/freq_max
  nc_time <- tt[idx] - shift

  systematic <- rowSums(sys[idx, , drop = FALSE])
  idio <- xhat[idx] - systematic

  # the fit's own nowcast is de-standardised; bring it back to this scale, and
  # match it on time rather than on position, the two classes selecting the
  # target's periods by slightly different rules
  nc <- fit$nowcast
  post <- rep(NA_real_, length(idx))
  if(!is.null(nc)){
    m <- match(round(nc_time, 5), round(as.numeric(time(nc)), 5))
    ok <- !is.na(m)
    post[ok] <- (as.numeric(nc)[m[ok]] - inv[j, "mean"])/inv[j, "sd"]
  }

  contributions <- data.frame(
    time = rep(nc_time, times = G),
    component = rep(grp$levels, each = length(idx)),
    contribution = as.numeric(sys[idx, , drop = FALSE]),
    stringsAsFactors = FALSE)
  names(contributions)[2] <- by

  totals <- data.frame(time = nc_time,
                       systematic = systematic,
                       idiosyncratic = idio,
                       plugin = xhat[idx],
                       posterior = post,
                       residual = post - xhat[idx],
                       stringsAsFactors = FALSE)

  list(contributions = contributions, totals = totals)

}


# ----------------------------------------------------------------- print ----

#' @rdname mfbdfm_contributions
#'
#' @param x An object of class `"mfbdfm_contributions"`.
#' @param n_show Number of components to list, ordered by mean absolute
#'   contribution.
#' @param ... Passed on to the underlying plotting calls; ignored by `print()`
#'   and `as.data.frame()`.
#'
#' @method print mfbdfm_contributions
#' @export
print.mfbdfm_contributions <- function(x, n_show = 10, ...){

  cat("Contributions to the factor and nowcast of a ", x$model, " fit\n",
      sep = "")
  if(!is.null(x$call)) cat("Call: ", deparse(x$call, nlines = 2), "\n", sep = "")

  cat("\n  by         : ", x$by, "\n", sep = "")
  cat("  components : ", length(x$components), "\n", sep = "")
  cat("  factors    : ", x$q, "\n", sep = "")
  cat("  periods    : ", length(unique(x$totals$time)), "\n", sep = "")
  cat("  target     : ", x$target, "\n", sep = "")

  d <- x$contributions
  key <- d[[x$by]]
  sizes <- sort(tapply(abs(d$contribution), key, mean), decreasing = TRUE)

  cat("\nMean absolute contribution to the factor (standardized scale):\n\n")
  top <- utils::head(sizes, n_show)
  for(i in seq_along(top))
    cat(sprintf("  %-40s %12s\n", substr(names(top)[i], 1, 40),
                formatC(top[i], format = "f", digits = 5, width = 12)))
  if(length(sizes) > n_show)
    cat("  ... and ", length(sizes) - n_show, " more\n", sep = "")

  res <- x$totals$residual
  if(any(is.finite(res)))
    cat("\nMean |residual| (parameter uncertainty, not explained by any ",
        "series): ", signif(mean(abs(res), na.rm = TRUE), 3), "\n", sep = "")

  cat("\nFull results: $contributions, $totals, $nowcast, $nowcast_totals;\n")
  cat("as.data.frame(), plot()\n")

  invisible(x)

}


# --------------------------------------------------------- as.data.frame ----

#' @rdname mfbdfm_contributions
#'
#' @param row.names,optional Ignored, present for consistency with the generic.
#' @param what Either `"factor"` (default) for contributions to the factor path
#'   or `"nowcast"` for contributions to the target's nowcast.
#'
#' @method as.data.frame mfbdfm_contributions
#' @export
as.data.frame.mfbdfm_contributions <- function(x, row.names = NULL,
                                               optional = FALSE,
                                               what = c("factor", "nowcast"),
                                               ...){

  what <- match.arg(what)
  out <- if(what == "factor") x$contributions else x$nowcast
  if(!is.null(row.names)) rownames(out) <- row.names
  out

}


# ------------------------------------------------------------------ plot ----

#' @rdname mfbdfm_contributions
#'
#' @param factor Which factor to plot, as an index into `1:q`. Only relevant for
#'   a [fcast_dfm()] fit with `q > 1`.
#'
#' @method plot mfbdfm_contributions
#' @export
#' @importFrom graphics abline axis barplot legend lines par plot.new rect title
#' @importFrom grDevices hcl.colors
plot.mfbdfm_contributions <- function(x, what = c("factor", "nowcast"),
                                      factor = 1, ...){

  what <- match.arg(what)

  if(what == "factor"){
    lab <- paste0("factor", factor)
    if(!lab %in% x$totals$factor)
      stop("`factor` must be an index into 1:", x$q, ".", call. = FALSE)
    d <- x$contributions[x$contributions$factor == lab, ]
    tot <- x$totals[x$totals$factor == lab, ]
    ylab <- if(x$q > 1) lab else "factor"
  } else {
    d <- x$nowcast
    tot <- x$nowcast_totals
    ylab <- paste0("nowcast: ", x$target)
  }

  comps <- x$components
  tms <- sort(unique(d$time))
  # one column per component, rows in time order
  mat <- matrix(0, length(tms), length(comps),
                dimnames = list(NULL, comps))
  mat[cbind(match(d$time, tms), match(d[[x$by]], comps))] <- d$contribution

  line <- tot$plugin[match(tms, tot$time)]

  cols <- hcl.colors(length(comps), palette = "Zissou 1")

  # a stacked bar chart that handles both signs: barplot() overlays negative
  # segments on positive ones, so the stacks are drawn directly. Accumulated
  # with an explicit loop rather than apply(, 1, cumsum), which drops to a
  # vector - and so silently transposes - with one component or one period.
  rowcumsum <- function(m){
    for(g in seq_len(ncol(m))[-1]) m[, g] <- m[, g - 1] + m[, g]
    m
  }
  up <- cbind(0, rowcumsum(pmax(mat, 0)))
  dn <- cbind(0, rowcumsum(pmin(mat, 0)))

  w <- if(length(tms) > 1) min(diff(tms)) else 1
  ylim <- range(c(up, dn, line), finite = TRUE)

  oldpar <- par(no.readonly = TRUE)
  on.exit(par(oldpar), add = TRUE)

  plot(range(tms) + c(-w, w)/2, ylim, type = "n", xlab = "", ylab = ylab, ...)
  abline(h = 0, col = "grey60")

  for(g in seq_along(comps)){
    rect(tms - w/2, up[, g], tms + w/2, up[, g + 1], col = cols[g],
         border = NA)
    rect(tms - w/2, dn[, g], tms + w/2, dn[, g + 1], col = cols[g],
         border = NA)
  }

  lines(tms, line, lwd = 2)

  legend("topleft", legend = comps, fill = cols, border = NA, bty = "n",
         cex = 0.7, ncol = max(1, ceiling(length(comps)/8)))

  invisible(x)

}
