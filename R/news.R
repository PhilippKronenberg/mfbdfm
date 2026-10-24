# Decomposition of a nowcast revision into the news in each newly released
# observation (Banbura & Modugno 2014), in this package's stacked notation.
#
# The one thing worth knowing before reading on is why this is not the textbook
# Kalman-filter derivation. There is no Kalman filter in this package: the
# factors are drawn by a stacked, precision-based sampler. What takes its place
# is that conditional on the parameters, the whole system is one big Gaussian
# with a sparse precision Q (dfm_joint_precision(), R/contributions.R), so
# "the expectation of a not-yet-released observation" and "the weight that
# release carries on the target" are both just blocks of Q^-1. Conditioning a
# Gaussian on more of its own entries is exactly what a vintage update does,
# which is what makes the decomposition exact rather than approximate.
#
# Contributions (R/contributions.R) and news share that machinery deliberately:
# contributions are W %*% y, news is W' %*% (new - expected) for the new
# entries. Both come out of one Cholesky factorization of Q_LL.


#' Plug-in posterior mean of the target, by target period
#'
#' @details
#' `E[x_target | y, theta-hat]` at every period the target is observed on,
#' de-standardised with the inventory's own moments -- the fit's nowcast with
#' the posterior mean parameters plugged in rather than averaged over. Where the
#' target is actually observed this is the observation itself.
#'
#' Not the same number as `fit$nowcast`, which averages the nowcast over the
#' posterior of theta instead of plugging in its mean. The gap is parameter
#' uncertainty and is reported rather than hidden; see [mfbdfm_news()].
#'
#' @param jp Output of [dfm_joint_precision()].
#' @param target Character, the target series name.
#'
#' @return A list with `time`, `value` and `observed`, one entry per target
#'   period.
#'
#' @noRd
#' @importFrom stats time
dfm_target_plugin <- function(jp, target){

  inv <- jp$inventory
  j <- which(inv$key == target)
  n <- jp$n; t <- jp$t; q <- jp$q; s <- jp$s

  QLL <- forceSymmetric(jp$Q[jp$ix_lat, jp$ix_lat, drop = FALSE])
  QLO <- jp$Q[jp$ix_lat, jp$ix_obs, drop = FALSE]
  mlat <- as.numeric(solve(QLL, -(QLO %*% jp$y)))

  tt <- as.numeric(time(jp$Ymat))
  freq_max <- max(inv$freq)
  fq <- inv[j, "freq"]
  idx <- target_period_rows(tt = tt, freq_max = freq_max, freq = fq)

  pos <- (idx - 1L)*n + j
  is_obs <- pos %in% jp$obs

  val <- numeric(length(pos))
  val[is_obs] <- jp$y[match(pos[is_obs], jp$obs)]
  if(any(!is_obs))
    val[!is_obs] <- mlat[match(q*(t + s) + pos[!is_obs], jp$ix_lat)]

  list(time = tt[idx] - (freq_max/fq - 1)/freq_max,
       value = val*inv[j, "sd"] + inv[j, "mean"],
       observed = is_obs)

}


#' Re-prepare a new data vintage on the fit's own grid and moments
#'
#' @details
#' Two things are held fixed, and both matter. The **inventory** is the fit's,
#' so each series is standardised with the old vintage's mean and standard
#' deviation; recomputing them from the new vintage would make the nowcast a
#' nonlinear function of the data and the decomposition would stop adding up.
#' The **time grid** is the union of the two vintages' grids, so a vintage that
#' runs further than the fit's sample simply has periods in which the old
#' vintage observed nothing.
#'
#' @return A list of two `ts` matrices, `old` and `new`, on one common grid.
#'
#' @noRd
#' @importFrom stats time frequency ts
dfm_news_panels <- function(fit, new_series){

  inv <- fit$inventory
  keys <- inv$key

  Ynew <- prepare_data(flows = new_series[keys], stocks = NULL,
                       inventory = inv, target = fit$target)

  Yold <- fit$data[, keys, drop = FALSE]
  Ynew <- Ynew[, keys, drop = FALSE]

  freq <- frequency(Yold)
  if(frequency(Ynew) != freq)
    stop("`new_data` prepares to frequency ", frequency(Ynew), ", but the fit's ",
         "panel is at frequency ", freq, ".", call. = FALSE)

  t_old <- as.numeric(time(Yold))
  t_new <- as.numeric(time(Ynew))
  g_start <- min(t_old[1], t_new[1])
  nper <- round((max(t_old[length(t_old)], t_new[length(t_new)]) - g_start)*freq) + 1L

  # placed by integer offset rather than window(..., extend = TRUE): both
  # panels come off prepare_data()'s own grid, so the offset is exact, whereas
  # asking window() to match a decimal start on a weekly series invites an
  # off-by-one that would silently shift one vintage against the other
  pad <- function(Y){

    off <- round((as.numeric(time(Y))[1] - g_start)*freq)
    M <- matrix(0, nper, ncol(Y))
    M[off + seq_len(nrow(Y)), ] <- as.matrix(Y)
    colnames(M) <- colnames(Y)
    ts(M, start = g_start, frequency = freq)

  }

  list(old = pad(Yold), new = pad(Ynew))

}


#' Check a new vintage against the fit it will be compared with
#'
#' @noRd
#' @importFrom stats frequency is.ts
dfm_news_check_series <- function(fit, new_series){

  inv <- fit$inventory
  keys <- inv$key

  if(!is.list(new_series) || is.null(names(new_series)))
    stop("`new_data` must be an `mfbdfm_data` object or a named list of `ts` ",
         "objects.", call. = FALSE)

  bad <- names(new_series)[!vapply(new_series, is.ts, logical(1))]
  if(length(bad))
    stop("`new_data` must contain only `ts` objects; these are not: ",
         paste(sQuote(bad), collapse = ", "), ".", call. = FALSE)

  gone <- setdiff(keys, names(new_series))
  if(length(gone))
    stop("`new_data` is missing ", length(gone), " of the fit's series: ",
         paste(sQuote(utils::head(gone, 5)), collapse = ", "),
         if(length(gone) > 5) ", ..." else "",
         ". A news decomposition compares two vintages of one model, so the ",
         "new vintage must carry exactly the series the fit was estimated on.",
         call. = FALSE)

  extra <- setdiff(names(new_series), keys)
  if(length(extra))
    stop("`new_data` carries ", length(extra), " series the fit does not: ",
         paste(sQuote(utils::head(extra, 5)), collapse = ", "),
         if(length(extra) > 5) ", ..." else "",
         ". Adding a series changes the model rather than the vintage, so ",
         "there is nothing to compare against -- refit instead.",
         call. = FALSE)

  fq <- vapply(new_series[keys], frequency, numeric(1))
  off <- which(fq != inv$freq)
  if(length(off))
    stop("`new_data` changes the frequency of ",
         paste(sQuote(keys[off]), collapse = ", "),
         ". The temporal aggregation is built from the inventory's ",
         "frequencies, so they must match the fit's.", call. = FALSE)

  invisible(TRUE)

}


#' News decomposition of a nowcast revision between two data vintages
#'
#' Answers the question every high-frequency indicator raises: the nowcast moved
#' this week -- which release did that? Between the data vintage a fit was
#' estimated on and a newer one, reports for every newly released observation
#' its *actual* value, the *forecast* the old vintage implied for it, the *news*
#' (actual minus forecast), the *gain* that news carries on the target, and the
#' resulting *impact* on the nowcast. The impacts add up to the revision.
#'
#' @details
#' Conditional on the parameters, the factor path and the unobserved data
#' entries are jointly Gaussian with a sparse precision `Q` (the samplers' own
#' matrices; see [mfbdfm_contributions()], which uses the same construction).
#' Writing `z = (f, x)` and splitting it into the entries an observation pins
#' and the latent rest,
#'
#' \deqn{E[z_L \mid y] = -Q_{LL}^{-1} Q_{LO}\, y,
#'       \qquad \mathrm{Cov}(z_L \mid y) = Q_{LL}^{-1}.}
#'
#' A new vintage observes some of those latent entries. Conditioning the same
#' Gaussian on them gives, for the target entry `k` and the newly released set
#' `N`,
#'
#' \deqn{\mathrm{gain} = \Sigma_{kN}\,\Sigma_{NN}^{-1}, \qquad
#'       \mathrm{impact} = \mathrm{gain} \times (\mathrm{actual} -
#'       \mathrm{forecast}),}
#'
#' with `Sigma = Q_LL^-1`. This is Bańbura and Modugno's (2014) decomposition
#' with the Kalman smoother replaced by the stacked form this package samples
#' in. The orthogonalisation through `Sigma_NN^-1` is what makes the impacts
#' add up: several series are released in the same week and their forecast
#' errors are correlated, so a per-observation weight that ignored that would
#' not sum to the revision.
#'
#' Nothing is refitted and `Q` is never inverted. One sparse Cholesky
#' factorisation of `Q_LL` serves every quantity above, with one solve per newly
#' released observation -- a handful for a weekly vintage update. The cost is
#' linear in how much the new vintage adds, so this is a tool for consecutive
#' vintages; handing it a vintage that adds a year of data asks for a year's
#' worth of solves.
#'
#' Two things are deliberately *not* carried over from the sampler. The factor
#' draw masks the forecast horizon with a selection vector, because
#' it conditions on the sampler's own augmented data and has to stop the
#' extension periods' imputed values from feeding back into the factor. Here
#' only genuine observations are conditioned on and everything else is left
#' latent, which is the correct marginal and needs no mask. And the sampler pins
#' observed entries with a `1e-9` observation variance; this conditions on them
#' exactly, which is the limit that nugget approximates (the two agree to
#' `O(1e-9)`, asserted in `tests/testthat/test-news.R`).
#'
#' ## What is held fixed, and where the rest of the revision goes
#'
#' The decomposition is exact *at fixed parameters*, which is standard practice
#' and is also what makes it exact. Three things are therefore held at the old
#' vintage's values:
#'
#' \itemize{
#'   \item the posterior mean parameters `theta` from `fit`;
#'   \item the volatility path `h`, extended over any periods the new vintage
#'     adds by holding its last value -- the posterior mean extension of a
#'     random walk;
#'   \item **the standardisation.** [prepare_data()] standardises each series
#'     with moments computed from the vintage in hand, so the new vintage is
#'     re-prepared with the *fit's* inventory. Using the new vintage's own
#'     moments would make the nowcast a nonlinear function of the data and
#'     nothing would add up. The consequence is that the change in
#'     standardisation is part of the parameter term below, not of any series'
#'     impact. This looks like a bug later if it is not written down, so it is
#'     written down here.
#' }
#'
#' What is left over is reported rather than folded in:
#'
#' \describe{
#'   \item{`news`}{Per newly released observation, as above. Exact by
#'     construction.}
#'   \item{`revision`}{Per observation present in *both* vintages whose value
#'     changed. Also exact and also additive per observation: at a fixed
#'     observation set the plug-in nowcast is linear in the data, so a revised
#'     value contributes its own weight times its own change. (The plan for this
#'     feature expected only a block total here; it is finer than that.)}
#'   \item{`parameter`}{`nowcast(theta_new) - nowcast(theta_old)`, the part of
#'     the revision that comes from re-estimating the model rather than from new
#'     data. It needs a fit on the new vintage, so it is `NA` unless `new_fit`
#'     is supplied.}
#' }
#'
#' ## The nowcast reported here is the plug-in one
#'
#' `nowcast_old` and `nowcast_new` are `E[x_target | y, theta-hat]`, the
#' nowcast with the posterior mean parameters plugged in. `fit$nowcast` is the
#' mean of the nowcast *over* the posterior of `theta`, which is a different
#' number; it is carried alongside as `posterior_old` so the two can be
#' compared rather than confused. The decomposition adds up to the plug-in
#' revision, which is the only revision it can add up to.
#'
#' ## Which period
#'
#' One target period at a time: the gain is a row of the smoother's weight
#' matrix and that row belongs to one period. `period` defaults to the last
#' target period the old vintage had *not* yet observed -- the nowcast, in other
#' words. Pass a decimal time to pick another. A period whose target value the
#' old vintage already observed is an error: its nowcast is pinned to the
#' observation and no amount of news can move it.
#'
#' ## [fcast_dfm()] is deferred
#'
#' Deliberately, and not for want of algebra -- the same derivation applies. The
#' target is not identified in that model: `fcast_dfm()`'s `target` argument
#' only selects which series' nowcast is surfaced, and the factors are pinned by
#' a post-hoc Procrustes plus varimax rotation rather than during sampling. A
#' gain computed at a fixed `theta` would be a gain in a rotation the new
#' vintage's fit does not reproduce, so "the impact of this release on the
#' factor" needs a rule for aligning rotations across vintages first. That is a
#' second methodological question, tracked separately; an `fcast_dfm` fit is an
#' informative error here rather than a plausible-looking number.
#'
#' @param fit A fitted model from [ind_dfm()], estimated on the **old** vintage.
#' @param new_data The new data vintage: either an [mfbdfm_data()] object or a
#'   named list of `ts` objects, carrying exactly the series `fit` was estimated
#'   on, at the same frequencies. Pass `stocks` alongside to supply the
#'   flow/stock pair instead.
#' @param stocks Named list of `ts` objects treated as stock variables, or
#'   `NULL`. Ignored when `new_data` is an [mfbdfm_data()] object. The
#'   flow/stock split is taken from the fit's inventory in any case; this
#'   argument exists so the same call shape as [ind_dfm()] works.
#' @param period Numeric (decimal time) or `NULL`. The target period whose
#'   nowcast revision is decomposed. Defaults to the last target period the old
#'   vintage had not yet observed.
#' @param by Either `"series"` (default, one component per input series) or
#'   `"group"` (one component per group of series). Governs the aggregation in
#'   `$by_component`, `print()` and `plot()`; the per-observation detail is
#'   retained whichever is chosen.
#' @param groups Optional named character vector or list mapping every series
#'   name to a group name, used when `by = "group"` and the inventory has no
#'   `group` or `category` column.
#' @param new_fit Optional fit from [ind_dfm()] on the new vintage. Supply it to
#'   get the `parameter` term; without it that term is `NA`.
#'
#' @return An object of class `"mfbdfm_news"`, a list with
#'   \describe{
#'     \item{table}{The tidy table `as.data.frame()` returns: one row per newly
#'       released or revised observation with `term`, `series`, `group`, `time`,
#'       `actual`, `forecast`, `news`, `gain` and `impact`, followed by summary
#'       rows for the total revision and the parameter term.}
#'     \item{news, revisions}{The two per-observation blocks on their own.}
#'     \item{by_component}{Impacts aggregated to `by`: the component column,
#'       `news`, `revision` and their sum `impact`.}
#'     \item{totals}{One row: `nowcast_old`, `revision`, `news`, `total`,
#'       `parameter`, `nowcast_new`, `posterior_old`, `posterior_new`.}
#'     \item{period, target, by, components, n_added, n_revised, model, call}{
#'       Metadata.}
#'   }
#'   With `print()`, `as.data.frame()` and `plot()` (a waterfall) methods.
#'
#' @references
#' Bańbura, M., & Modugno, M. (2014). Maximum likelihood estimation of factor
#' models on datasets with arbitrary pattern of missing data.
#' *Journal of Applied Econometrics*, 29(1), 133-160. \doi{10.1002/jae.2306}
#'
#' Kronenberg, P. (2026). A weekly activity index for Switzerland.
#' *Swiss Journal of Economics and Statistics*, 162:10.
#' \doi{10.1186/s41937-026-00157-w}
#'
#' @seealso [mfbdfm_contributions()] for the decomposition of the *level* of the
#'   factor and nowcast (the same weight matrix, applied to the data rather than
#'   to the news), [cut_data_real_time()] to build vintage pairs, and
#'   [ind_dfm()].
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#'
#' # two consecutive vintages of the shipped example data: the old one stops
#' # four weeks earlier, so the new one brings four weeks of releases
#' new <- mfbdfm_example_data
#' old <- new
#' old$flows <- lapply(old$flows, function(x)
#'   if(stats::frequency(x) > 4) stats::window(x, end = stats::time(x)[length(x) - 4])
#'   else x)
#' old$stocks <- lapply(old$stocks, function(x)
#'   stats::window(x, end = stats::time(x)[length(x) - 4]))
#'
#' set.seed(1)
#' fit <- ind_dfm(old, length_sample = 50, burn_in = 10)
#'
#' nw <- mfbdfm_news(fit, new)
#' nw
#' head(as.data.frame(nw))
#'
#' # the impacts add up to the revision, by construction
#' d <- as.data.frame(nw)
#' sum(d$impact[d$term %in% c("news", "revision")]) - nw$totals$total
#' }
#'
#' @family model functions
#' @importFrom stats time frequency
#' @export
mfbdfm_news <- function(fit, new_data, stocks = NULL, period = NULL,
                        by = c("series", "group"), groups = NULL,
                        new_fit = NULL){

  if(inherits(fit, "fcast_dfm"))
    stop("`mfbdfm_news()` is implemented for ind_dfm() fits only. The target ",
         "is not identified in fcast_dfm(), whose factors are rotated after ",
         "sampling, so a gain computed at fixed parameters would belong to a ",
         "rotation the new vintage does not reproduce. See ?mfbdfm_news.",
         call. = FALSE)

  if(!inherits(fit, "ind_dfm"))
    stop("`fit` must be a fitted model from ind_dfm(), not an object of class ",
         paste(class(fit), collapse = "/"), ".", call. = FALSE)

  by <- match.arg(by)

  target <- fit$target
  inv <- fit$inventory
  keys <- inv$key

  .d <- resolve_data_arg(new_data, stocks, target)
  new_series <- c(.d$flows, .d$stocks)
  dfm_news_check_series(fit, new_series)

  if(!is.null(new_fit)){
    if(!inherits(new_fit, "ind_dfm"))
      stop("`new_fit` must be a fitted model from ind_dfm(), not an object of ",
           "class ", paste(class(new_fit), collapse = "/"), ".", call. = FALSE)
    if(!identical(new_fit$target, target))
      stop("`new_fit` has target ", sQuote(new_fit$target), " but `fit` has ",
           sQuote(target), ".", call. = FALSE)
  }

  # ------------------------------------------------- the two vintages, aligned

  pan <- dfm_news_panels(fit, new_series)

  jp <- dfm_joint_precision(fit, Ymat = pan$old)
  n <- jp$n; t <- jp$t; q <- jp$q; s <- jp$s
  nf <- q*(t + s)

  yv_old <- as.numeric(t(as.matrix(pan$old)))
  yv_new <- as.numeric(t(as.matrix(pan$new)))

  obs_old <- jp$obs
  obs_new <- which(yv_new != 0)

  gone <- setdiff(obs_old, obs_new)
  if(length(gone))
    stop(length(gone), " observation(s) present in the fit's vintage are ",
         "missing from `new_data` (first affected series: ",
         sQuote(keys[((gone[1] - 1L) %% n) + 1L]),
         "). A news decomposition needs the new vintage to be a superset of ",
         "the old one -- an observation that disappeared is neither news nor a ",
         "revision, and there is no well-defined weight for it.", call. = FALSE)

  added <- setdiff(obs_new, obs_old)
  revised <- obs_old[yv_new[obs_old] != yv_old[obs_old]]

  # ------------------------------------------------------ the target's own row

  j <- which(keys == target)
  tt <- as.numeric(time(pan$old))
  freq_max <- max(inv$freq)
  fq <- inv[j, "freq"]
  idx <- target_period_rows(tt = tt, freq_max = freq_max, freq = fq)
  tgt_time <- tt[idx] - (freq_max/fq - 1)/freq_max
  pos_tgt <- (idx - 1L)*n + j
  latent <- !(pos_tgt %in% obs_old)

  if(is.null(period)){

    sel <- if(any(latent)) max(which(latent)) else length(idx)

  } else {

    sel <- match(round(as.numeric(period), 5), round(tgt_time, 5))
    if(is.na(sel))
      stop("`period` must be one of the target's periods, between ",
           signif(tgt_time[1], 7), " and ", signif(tgt_time[length(idx)], 7),
           ".", call. = FALSE)

  }

  if(!latent[sel])
    stop("The target is already observed in the fit's vintage at period ",
         signif(tgt_time[sel], 7), ", so its nowcast is pinned to that ",
         "observation and no news can revise it. Pick a period the old ",
         "vintage does not yet cover.", call. = FALSE)

  # ----------------------------------------------------------- the linear maps

  QLL <- forceSymmetric(jp$Q[jp$ix_lat, jp$ix_lat, drop = FALSE])
  QLO <- jp$Q[jp$ix_lat, jp$ix_obs, drop = FALSE]
  chf <- Cholesky(QLL)
  nlat <- length(jp$ix_lat)

  # the latent posterior mean under the old vintage, and under the old vintage's
  # observation set carrying the new vintage's (revised) values
  m0_lat <- as.numeric(as.matrix(solve(chf, -(QLO %*% yv_old[obs_old]))))
  m1_lat <- as.numeric(as.matrix(solve(chf, -(QLO %*% yv_new[obs_old]))))

  k_row <- match(nf + pos_tgt[sel], jp$ix_lat)

  # row k of W = -Q_LL^-1 Q_LO, i.e. the weight every *existing* observation
  # carries on this nowcast. One solve: Sigma[, k] first, then W[k, ] from it.
  uk <- solve(chf, sparseMatrix(i = k_row, j = 1L, x = 1,
                                dims = c(nlat, 1L)))
  wk <- -as.numeric(as.matrix(crossprod(QLO, uk)))

  # gain of the newly released block, orthogonalised within the block
  if(length(added)){

    Nr <- match(nf + added, jp$ix_lat)
    SigN <- as.matrix(solve(chf, sparseMatrix(i = Nr, j = seq_along(Nr), x = 1,
                                              dims = c(nlat, length(Nr)))))
    gain_std <- as.numeric(solve(SigN[Nr, , drop = FALSE], SigN[k_row, ]))
    fcst_std <- m1_lat[Nr]
    impact_std <- gain_std * (yv_new[added] - fcst_std)

  } else {

    gain_std <- numeric(0)
    fcst_std <- numeric(0)
    impact_std <- numeric(0)

  }

  # ---------------------------------------------------------- report, de-scaled

  sd_t <- inv[j, "sd"]; mn_t <- inv[j, "mean"]
  grp <- dfm_resolve_groups(inv, by = by, groups = groups)

  # the group label of every series, when one is available at all: the tidy
  # table carries both columns whatever `by` says
  glab <- if(by == "group"){
    grp$levels[grp$index]
  } else {
    g <- try(dfm_resolve_groups(inv, by = "group", groups = groups),
             silent = TRUE)
    if(inherits(g, "try-error")) NULL else g$levels[g$index]
  }

  mk_rows <- function(term, posv, act_std, fc_std, gainv){

    if(!length(posv)) return(NULL)

    si <- ((posv - 1L) %% n) + 1L
    pidx <- ((posv - 1L) %/% n) + 1L
    sdj <- inv$sd[si]; mnj <- inv$mean[si]

    news_std <- act_std - fc_std

    data.frame(term = term,
               series = keys[si],
               group = if(is.null(glab)) NA_character_ else glab[si],
               # a series is recorded at the last high-frequency slot of its own
               # period, so undo prepare_data()'s shift to report the period a
               # reader would name
               time = tt[pidx] - (freq_max/inv$freq[si] - 1)/freq_max,
               actual = act_std*sdj + mnj,
               forecast = fc_std*sdj + mnj,
               news = news_std*sdj,
               # impact = gain(raw) * news(raw) = gain(std) * news(std) * sd_t,
               # so the series' own scale cancels and the product is the same
               # number on either scale
               gain = gainv * sd_t/sdj,
               impact = gainv * news_std * sd_t,
               stringsAsFactors = FALSE)

  }

  news_rows <- mk_rows("news", added, yv_new[added], fcst_std, gain_std)
  rev_rows <- mk_rows("revision", revised, yv_new[revised], yv_old[revised],
                      wk[match(revised, obs_old)])

  nowcast_old <- m0_lat[k_row]*sd_t + mn_t
  rev_total <- (m1_lat[k_row] - m0_lat[k_row])*sd_t
  news_total <- sum(impact_std)*sd_t
  nowcast_new <- nowcast_old + rev_total + news_total

  # the parameter term needs a fit on the new vintage; without one it is NA
  # rather than quietly absorbed into something else
  parameter <- NA_real_
  if(!is.null(new_fit)){
    pl <- dfm_target_plugin(dfm_joint_precision(new_fit), target)
    m <- match(round(tgt_time[sel], 5), round(pl$time, 5))
    if(!is.na(m)) parameter <- pl$value[m] - nowcast_new
  }

  at <- function(x){
    if(is.null(x)) return(NA_real_)
    m <- match(round(tgt_time[sel], 5), round(as.numeric(time(x)), 5))
    if(is.na(m)) NA_real_ else as.numeric(x)[m]
  }

  totals <- data.frame(nowcast_old = nowcast_old,
                       revision = rev_total,
                       news = news_total,
                       total = rev_total + news_total,
                       parameter = parameter,
                       nowcast_new = nowcast_new,
                       posterior_old = at(fit$nowcast),
                       posterior_new = if(is.null(new_fit)) NA_real_
                                       else at(new_fit$nowcast))

  # aggregation to `by`, every component present even when its impact is zero
  acc <- function(posv, imp){
    out <- numeric(length(grp$levels))
    if(length(posv)){
      ci <- grp$index[((posv - 1L) %% n) + 1L]
      for(i in seq_along(ci)) out[ci[i]] <- out[ci[i]] + imp[i]
    }
    out
  }

  agg_news <- acc(added, if(is.null(news_rows)) numeric(0) else news_rows$impact)
  agg_rev <- acc(revised, if(is.null(rev_rows)) numeric(0) else rev_rows$impact)

  by_component <- data.frame(component = grp$levels,
                             news = agg_news,
                             revision = agg_rev,
                             impact = agg_news + agg_rev,
                             stringsAsFactors = FALSE)
  names(by_component)[1] <- by

  # the tidy table: per-observation rows, then the two summary rows the issue
  # asks for. `term` is what tells them apart, so a reader cannot sum the
  # summary rows into the detail by accident.
  summ <- data.frame(term = c("total", "parameter"),
                     series = NA_character_, group = NA_character_,
                     time = tgt_time[sel],
                     actual = NA_real_, forecast = NA_real_, news = NA_real_,
                     gain = NA_real_,
                     impact = c(rev_total + news_total, parameter),
                     stringsAsFactors = FALSE)

  tab <- rbind(news_rows, rev_rows, summ)
  rownames(tab) <- NULL

  structure(list(table = tab,
                 news = news_rows,
                 revisions = rev_rows,
                 by_component = by_component,
                 totals = totals,
                 period = tgt_time[sel],
                 target = target,
                 by = by,
                 components = grp$levels,
                 n_added = length(added),
                 n_revised = length(revised),
                 model = "ind_dfm",
                 call = match.call()),
            class = "mfbdfm_news")

}


# ----------------------------------------------------------------- print ----

#' @rdname mfbdfm_news
#'
#' @param x An object of class `"mfbdfm_news"`.
#' @param n_show Number of components to list, ordered by absolute impact.
#' @param ... Passed on to the underlying plotting calls; ignored by `print()`
#'   and `as.data.frame()`.
#'
#' @method print mfbdfm_news
#' @export
print.mfbdfm_news <- function(x, n_show = 10, ...){

  cat("News decomposition of a nowcast revision (", x$model, ")\n", sep = "")
  if(!is.null(x$call)) cat("Call: ", deparse(x$call, nlines = 2), "\n", sep = "")

  tt <- x$totals

  cat("\n  target            : ", x$target, "\n", sep = "")
  cat("  period            : ", signif(x$period, 7), "\n", sep = "")
  cat("  new observations  : ", x$n_added, "\n", sep = "")
  cat("  revised           : ", x$n_revised, "\n", sep = "")
  cat("  by                : ", x$by, "\n", sep = "")

  fmt <- function(v) formatC(v, format = "f", digits = 4, width = 10)

  cat("\n  nowcast, old vintage     ", fmt(tt$nowcast_old), "\n", sep = "")
  cat("    + news                 ", fmt(tt$news), "\n", sep = "")
  cat("    + data revisions       ", fmt(tt$revision), "\n", sep = "")
  cat("  nowcast, new vintage     ", fmt(tt$nowcast_new), "\n", sep = "")
  if(is.finite(tt$parameter)){
    cat("    + parameter revision   ", fmt(tt$parameter), "\n", sep = "")
    cat("  refitted on new vintage  ", fmt(tt$nowcast_new + tt$parameter),
        "\n", sep = "")
  } else {
    cat("    parameter revision     ",
        "       not computed (supply `new_fit`)\n", sep = "")
  }

  d <- x$by_component
  d <- d[order(-abs(d$impact)), , drop = FALSE]
  d <- d[abs(d$impact) > 0, , drop = FALSE]

  if(nrow(d)){

    cat("\nImpact on the nowcast, by ", x$by, ":\n\n", sep = "")
    top <- utils::head(d, n_show)
    for(i in seq_len(nrow(top)))
      cat(sprintf("  %-40s %12s\n", substr(top[i, 1], 1, 40),
                  formatC(top$impact[i], format = "f", digits = 5,
                          width = 12)))
    if(nrow(d) > n_show)
      cat("  ... and ", nrow(d) - n_show, " more\n", sep = "")

  } else {

    cat("\nNo series moved the nowcast.\n")

  }

  cat("\nThe nowcasts above plug in the posterior mean parameters rather than\n")
  cat("averaging over them")
  if(is.finite(tt$posterior_old)){
    cat("; the fit's own posterior mean nowcast for this\nperiod was ",
        signif(tt$posterior_old, 6), sep = "")
  } else {
    cat(" (the fit's own nowcast does not reach this period)", sep = "")
  }
  cat(". See ?mfbdfm_news.\n")

  cat("\nFull results: $table, $news, $revisions, $by_component, $totals;\n")
  cat("as.data.frame(), plot()\n")

  invisible(x)

}


# --------------------------------------------------------- as.data.frame ----

#' @rdname mfbdfm_news
#'
#' @param row.names,optional Ignored, present for consistency with the generic.
#' @param what Either `"observation"` (default) for the per-observation tidy
#'   table with its summary rows, or `"component"` for the impacts aggregated
#'   to `by`.
#'
#' @method as.data.frame mfbdfm_news
#' @export
as.data.frame.mfbdfm_news <- function(x, row.names = NULL, optional = FALSE,
                                      what = c("observation", "component"),
                                      ...){

  what <- match.arg(what)
  out <- if(what == "observation") x$table else x$by_component
  if(!is.null(row.names)) rownames(out) <- row.names
  out

}


# ------------------------------------------------------------------ plot ----

#' @rdname mfbdfm_news
#'
#' @method plot mfbdfm_news
#' @export
#' @importFrom graphics abline axis box par rect segments title
#' @importFrom grDevices hcl.colors
plot.mfbdfm_news <- function(x, n_show = 10, ...){

  d <- x$by_component
  d <- d[abs(d$impact) > 0, , drop = FALSE]
  d <- d[order(-abs(d$impact)), , drop = FALSE]

  # everything beyond n_show collapsed into one bar rather than dropped, so the
  # bars still close the gap between the two nowcasts
  if(nrow(d) > n_show){
    rest <- sum(d$impact[-seq_len(n_show)])
    d <- d[seq_len(n_show), , drop = FALSE]
    other <- d[1, , drop = FALSE]
    other[1, ] <- list("other", NA_real_, NA_real_, rest)
    d <- rbind(d, other)
  }

  steps <- d$impact
  labs <- as.character(d[[1]])

  if(is.finite(x$totals$parameter)){
    steps <- c(steps, x$totals$parameter)
    labs <- c(labs, "parameters")
  }

  start <- x$totals$nowcast_old
  base <- start + c(0, cumsum(steps))
  nb <- length(steps)

  # bar i floats from base[i] to base[i+1]; the two end bars are levels, drawn
  # from zero
  lvl0 <- start
  lvl1 <- base[nb + 1]

  xs <- seq_len(nb + 2)
  lo <- c(min(0, lvl0), pmin(base[-(nb + 1)], base[-1]), min(0, lvl1))
  hi <- c(max(0, lvl0), pmax(base[-(nb + 1)], base[-1]), max(0, lvl1))

  cols <- c("grey40", ifelse(steps >= 0, hcl.colors(2, "Zissou 1")[1],
                             hcl.colors(2, "Zissou 1")[2]), "grey40")

  oldpar <- par(no.readonly = TRUE)
  on.exit(par(oldpar), add = TRUE)
  par(mar = c(7.5, 4.1, 3.1, 1.1))

  plot(range(xs) + c(-0.6, 0.6), range(c(lo, hi, 0)), type = "n",
       xlab = "", ylab = x$target, xaxt = "n", ...)
  abline(h = 0, col = "grey70")

  rect(xs - 0.4, lo, xs + 0.4, hi, col = cols, border = NA)

  # connectors, so the waterfall reads as one chain
  if(nb > 0) segments(xs[-length(xs)] + 0.4, base, xs[-1] - 0.4, base,
                      col = "grey50", lty = 3)

  axis(1, at = xs,
       labels = substr(c("old vintage", labs, "new vintage"), 1, 18),
       las = 2, cex.axis = 0.7)
  box()
  title(main = paste0("Revision of the ", signif(x$period, 7), " nowcast"))

  invisible(x)

}
