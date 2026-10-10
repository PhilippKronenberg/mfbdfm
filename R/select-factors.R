#' Choose the number of factors with the Bai-Ng information criteria
#'
#' Computes the Bai & Ng (2002) information criteria IC1, IC2 and IC3 for
#' factor counts `1:max_q`, together with the principal-component eigenvalues
#' and the share of panel variance each component explains. It answers the
#' question [fcast_dfm()]'s `q` argument poses and that the model itself gives
#' no guidance on.
#'
#' @details
#' # What is actually computed, and on which data
#'
#' The criteria are defined for a **balanced panel of one frequency**, so the
#' mixed-frequency input has to be reduced to one before they can be applied.
#' The reduction is deliberate and is reported by `print()`:
#'
#' \enumerate{
#'   \item The series are standardized and aligned by [prepare_data()], exactly
#'     as they are for a model fit.
#'   \item **Only the series observed at the highest frequency are kept.** In a
#'     weekly WAI-style dataset that is the weekly block; the quarterly target
#'     and any monthly series are excluded. They are excluded rather than
#'     interpolated because in this model the low-frequency series are observed
#'     on a small fraction of the periods, so filling them in would put imputed
#'     values in most of their column and let an imputation rule, rather than
#'     the data, drive the criteria.
#'   \item Missing values in that block -- the ragged edge, mostly -- are
#'     removed by listwise deletion (`na_action = "omit"`, the default) or
#'     filled by linear interpolation within each series, carrying the nearest
#'     observed value outward at the ends (`na_action = "interpolate"`).
#'   \item The retained block is re-standardized column by column over the
#'     retained periods, and the criteria are computed from the singular values
#'     of the result.
#' }
#'
#' A constant or all-missing series cannot be standardized at step 1 and is
#' **dropped before the criteria are computed**, with a warning naming every
#' series dropped (condition class `mfbdfm_warning_dropped_series`, as in
#' [ind_dfm()] and [fcast_dfm()] -- see [dfm_control()] on muffling it). It
#' carries no information about the factors, so dropping it loses nothing; the
#' "at least two series at the highest frequency" requirement is then checked
#' on the survivors.
#'
#' With \eqn{V(k)} the mean squared residual of the \eqn{k}-factor principal
#' component approximation of the \eqn{T \times N} panel, the criteria are
#'
#' \deqn{IC_1(k) = \log V(k) + k \frac{N+T}{NT} \log\frac{NT}{N+T}}
#' \deqn{IC_2(k) = \log V(k) + k \frac{N+T}{NT} \log \min(N,T)}
#' \deqn{IC_3(k) = \log V(k) + k \frac{\log \min(N,T)}{\min(N,T)}}
#'
#' and the chosen `q` is the minimizer over `1:max_q`. The three differ only in
#' how hard they penalize an extra factor, IC3 most and IC1 least, so they need
#' not agree; when they do not, the disagreement is itself the result and
#' `print()` shows all three.
#'
#' A minimum that sits on `max_q` is **not** a chosen factor count -- the
#' criteria simply ran out of range -- so it warns and `print()` says so.
#' Raising `max_q` is the first thing to try. If the minimum stays on the
#' boundary however high `max_q` goes, the panel is too narrow: the penalties
#' are calibrated for \eqn{N} and \eqn{T} both large, and with \eqn{N} in the
#' dozens the fall in \eqn{\log V(k)} can outrun them all the way to
#' \eqn{\min(N,T)}. That happens on the weekly block of the shipped
#' `data_ch_dataset_test`, which is why its example warns. Read the scree plot
#' and the share of variance explained instead.
#'
#' # How much weight to put on the answer
#'
#' These are **frequentist, principal-component criteria for an approximate
#' factor model**. [fcast_dfm()] is a Bayesian mixed-frequency state-space
#' model whose factors are identified by a post-hoc rotation, and it is fitted
#' on data the criteria never see -- the lower-frequency series, and the
#' periods dropped at the ragged edge. So the criteria **inform** `q`; they do
#' not determine it. Treat a disagreement between IC1 and IC3, or a scree plot
#' with no clear elbow, as a reason to fit more than one `q` and compare, not
#' as a defect in the criteria.
#'
#' @inheritParams fcast_dfm
#' @param target Character, name of the series of interest, or `NULL` (the
#'   default). Accepted so that the same data specification works here and in
#'   [fcast_dfm()], and validated if supplied, but it does **not** enter the
#'   criteria -- no series is treated specially by a principal-component
#'   decomposition. Being validated includes the degenerate-series screen: a
#'   supplied `target` that is constant or all-missing errors, exactly as it
#'   would in [fcast_dfm()], rather than being dropped. With `target = NULL`
#'   nothing is treated as a target and no series is protected from the
#'   screen.
#' @param max_q Integer, the largest factor count to evaluate. Must be smaller
#'   than both the number of series and the number of periods in the panel
#'   actually used.
#' @param na_action How to handle missing values in the retained
#'   highest-frequency block. `"omit"` (default) drops every period that is not
#'   fully observed; `"interpolate"` fills gaps within each series linearly and
#'   carries the nearest observed value outward at the ends.
#'
#' @return An object of class `"select_factors"`: a list with components
#'   \describe{
#'     \item{ic}{Data frame with one row per evaluated factor count: `q`,
#'       `IC1`, `IC2`, `IC3`.}
#'     \item{q_hat}{Named integer vector of length 3, the minimizer of each
#'       criterion.}
#'     \item{at_boundary}{Character, the criteria whose minimum is `max_q` and
#'       which therefore did not settle. Empty when all three did.}
#'     \item{eigenvalues}{Numeric, the eigenvalues of the panel's second-moment
#'       matrix, in decreasing order.}
#'     \item{var_explained, cum_var_explained}{Numeric, the share of panel
#'       variance explained by each component and its cumulative sum.}
#'     \item{max_q}{The `max_q` used.}
#'     \item{series}{Character, the series the criteria were computed on.}
#'     \item{excluded}{Character, the series dropped for being observed below
#'       the highest frequency.}
#'     \item{frequency}{Numeric, the frequency of the retained block.}
#'     \item{n_series, n_obs}{Panel dimensions after the reduction.}
#'     \item{n_dropped}{Number of periods removed by `na_action = "omit"`.}
#'     \item{na_action}{The `na_action` used.}
#'     \item{call}{The matched call.}
#'   }
#'
#' @examples
#' data(data_ch_dataset_test)
#'
#' # The shipped weekly block is 27 series, which is small for these criteria:
#' # all three are minimised at max_q, so this warns rather than reporting a
#' # settled factor count. That is the intended behaviour, not a failure.
#' sel <- select_factors(flows = data_ch_dataset_test$flows,
#'                       stocks = data_ch_dataset_test$stocks,
#'                       max_q = 8, na_action = "interpolate")
#' sel
#' sel$q_hat
#' sel$at_boundary
#' round(head(sel$cum_var_explained, 5), 3)
#'
#' @references
#' Bai, J., & Ng, S. (2002). Determining the number of factors in approximate
#' factor models. *Econometrica*, 70(1), 191-221.
#' \doi{10.1111/1468-0262.00273}
#'
#' @seealso [select_factors_methods] for `print()`, `plot()` and
#'   `screeplot()`; [fcast_dfm()], whose `q` this is for.
#'
#' @family model fitting functions
#' @importFrom stats sd
#' @importFrom zoo na.approx na.locf
#' @export
select_factors <- function(flows = NULL,
                           stocks = NULL,
                           target = NULL,
                           max_q = 10,
                           na_action = c("omit", "interpolate")){

  na_action <- match.arg(na_action)

  # accept either an mfbdfm_data object as the first argument, or the original
  # flows/stocks pair, exactly as the two model entry points do
  .d <- resolve_data_arg(flows, stocks, target)
  flows <- .d$flows; stocks <- .d$stocks; target <- .d$target

  # `target` plays no role here, but a supplied one is still checked, so that a
  # typo is caught at the same place it would be by fcast_dfm(). When none is
  # given, stand in the first series purely to satisfy the shared validator.
  target_given <- !is.null(target)
  if(!target_given) target <- c(names(flows), names(stocks))[1L]

  validate_model_inputs(flows = flows, stocks = stocks, target = target,
                        p = 1, length_sample = 1, burn_in = 1, thinning = 1,
                        q = NULL, call = "select_factors")

  if(!is_count(max_q) || max_q < 1){
    stop("`max_q` must be a single positive whole number, not ",
         deparse(max_q), ".", call. = FALSE)
  }

  # A constant or all-missing series standardizes to a column of NaN, which
  # listwise deletion below then turns into an empty panel - an error blaming
  # missing data for something else entirely (#146). Dropped here instead,
  # with the entry points' own classed warning. A degenerate `target` errors,
  # but only when the user actually asked for that series: the stand-in above
  # is an arbitrary first series and must not be able to stop the call.
  .s <- screen_degenerate_series(flows, stocks,
                                 target = if(target_given) target else NULL,
                                 context = "before computing the criteria")
  flows <- .s$flows; stocks <- .s$stocks
  if(!target_given) target <- c(names(flows), names(stocks))[1L]

  inventory <- create_inventory(flows = flows, stocks = stocks)

  # fill = NA keeps the missingness mask, which the model fit does not need
  # (it encodes missing as 0) but na_action here does
  Ymat <- prepare_data(flows = flows, stocks = stocks,
                       inventory = inventory, target = target, fill = NA)

  freq_max <- max(inventory$freq)
  keep     <- inventory$key[inventory$freq == freq_max]
  excluded <- inventory$key[inventory$freq != freq_max]

  if(length(keep) < 2){
    stop("Factor selection needs at least two series at the highest frequency ",
         "(", freq_max, "); the data has ", length(keep), ".\n",
         "  Lower-frequency series are excluded by design; see ",
         "`?select_factors`.", call. = FALSE)
  }

  X <- as.matrix(Ymat[, keep, drop = FALSE])
  n_periods_in <- nrow(X)

  if(na_action == "interpolate"){
    X <- apply(X, 2, function(col){
      if(all(is.na(col))) return(col)
      col <- na.approx(col, na.rm = FALSE)
      na.locf(na.locf(col, na.rm = FALSE), fromLast = TRUE, na.rm = FALSE)
    })
  }
  X <- X[stats::complete.cases(X), , drop = FALSE]
  n_dropped <- n_periods_in - nrow(X)

  if(nrow(X) < 2){
    hint <- if(na_action == "omit")
      ": every period has at least one unobserved series. Try `na_action = \"interpolate\"`."
    else "."
    stop("No usable periods remain after removing missing values", hint,
         call. = FALSE)
  }

  # re-standardize over the retained periods: the Bai-Ng criteria are stated
  # for a standardized panel, and prepare_data() standardized on the full raw
  # series rather than on this subsample
  centre <- colMeans(X)
  scale  <- apply(X, 2, sd)
  flat   <- names(scale)[!is.finite(scale) | scale <= 0]
  if(length(flat)){
    stop("These series are constant over the retained periods and carry no ",
         "information: ", paste(sQuote(flat), collapse = ", "), ".",
         call. = FALSE)
  }
  X <- sweep(sweep(X, 2, centre, "-"), 2, scale, "/")

  n_obs <- nrow(X); n_series <- ncol(X)
  k_max_possible <- min(n_obs, n_series) - 1L
  if(max_q > k_max_possible){
    stop("`max_q` (", max_q, ") must be smaller than both the number of ",
         "series (", n_series, ") and the number of periods (", n_obs,
         ") in the panel used, i.e. at most ", k_max_possible, ".",
         call. = FALSE)
  }

  d   <- svd(X, nu = 0, nv = 0)$d
  eig <- d^2 / (n_obs * n_series)              # eigenvalues of X'X/(TN)
  var_explained <- d^2 / sum(d^2)

  # V(k): mean squared residual of the k-factor principal component
  # approximation, which is the sum of the discarded eigenvalues
  v_k <- vapply(seq_len(max_q), function(k) sum(eig[-seq_len(k)]), numeric(1))

  nt <- n_obs * n_series
  ns <- n_obs + n_series
  mn <- min(n_obs, n_series)
  k  <- seq_len(max_q)

  ic <- data.frame(q   = k,
                   IC1 = log(v_k) + k * (ns / nt) * log(nt / ns),
                   IC2 = log(v_k) + k * (ns / nt) * log(mn),
                   IC3 = log(v_k) + k * log(mn) / mn)

  q_hat <- vapply(c("IC1", "IC2", "IC3"),
                  function(nm) ic$q[which.min(ic[[nm]])], integer(1))

  # a minimum sitting on the boundary is not a chosen factor count - the
  # criteria simply had nowhere further to go. Saying so is the difference
  # between a result and a number.
  at_boundary <- names(q_hat)[q_hat == max_q]
  if(length(at_boundary)){
    warning(paste(at_boundary, collapse = "/"),
            if(length(at_boundary) > 1) " are" else " is",
            " minimised at `max_q` (", max_q, "), so the minimum may lie ",
            "beyond the range evaluated. Raise `max_q`; if the minimum stays ",
            "on the boundary, the panel is too narrow for these criteria to ",
            "settle - see `?select_factors`.", call. = FALSE)
  }

  structure(list(ic                = ic,
                 at_boundary       = at_boundary,
                 q_hat             = q_hat,
                 eigenvalues       = eig,
                 var_explained     = var_explained,
                 cum_var_explained = cumsum(var_explained),
                 max_q             = as.integer(max_q),
                 series            = keep,
                 excluded          = excluded,
                 frequency         = freq_max,
                 n_series          = n_series,
                 n_obs             = n_obs,
                 n_dropped         = n_dropped,
                 na_action         = na_action,
                 call              = match.call()),
            class = "select_factors")

}


#' Methods for factor-count selection
#'
#' The generics a [select_factors()] result supports.
#'
#' \describe{
#'   \item{`print()`}{The panel the criteria were computed on, the criteria
#'     themselves with each minimum marked, and the chosen factor count.}
#'   \item{`plot()`}{The three criteria against the factor count, with their
#'     minima marked.}
#'   \item{`screeplot()`}{The eigenvalues, or the share of panel variance each
#'     component explains.}
#' }
#'
#' @param x A `"select_factors"` object.
#' @param npcs Integer, how many components to show in the scree plot.
#' @param type `"barplot"` or `"lines"`, as for [stats::screeplot()].
#' @param value `"share"` (default) plots the share of panel variance each
#'   component explains, `"eigenvalue"` the eigenvalues themselves.
#' @param main Plot title, or `NULL` for the default.
#' @param ... Further arguments passed to the underlying plotting functions.
#'
#' @return `print()` returns `x` invisibly. `plot()` and `screeplot()` are
#'   called for their side effect and return the plotted values invisibly.
#'
#' @examples
#' data(data_ch_dataset_test)
#' sel <- suppressWarnings(
#'   select_factors(flows = data_ch_dataset_test$flows,
#'                  stocks = data_ch_dataset_test$stocks,
#'                  max_q = 8, na_action = "interpolate"))
#' print(sel)
#' plot(sel)
#' screeplot(sel)
#'
#' @name select_factors_methods
NULL

#' @rdname select_factors_methods
#' @method print select_factors
#' @export
print.select_factors <- function(x, ...){

  cat("Bai-Ng factor-count selection\n\n")
  cat("Panel: ", x$n_series, " series at frequency ", x$frequency, ", ",
      x$n_obs, " periods\n", sep = "")
  if(length(x$excluded)){
    cat("       ", length(x$excluded),
        " lower-frequency series excluded: ",
        paste(utils::head(x$excluded, 4), collapse = ", "),
        if(length(x$excluded) > 4) ", ..." else "", "\n", sep = "")
  }
  cat("       missing values: ", x$na_action,
      if(x$na_action == "omit")
        paste0(" (", x$n_dropped, " periods dropped)") else "",
      "\n\n", sep = "")

  tab <- data.frame(q   = x$ic$q,
                    IC1 = format(round(x$ic$IC1, 4), nsmall = 4),
                    IC2 = format(round(x$ic$IC2, 4), nsmall = 4),
                    IC3 = format(round(x$ic$IC3, 4), nsmall = 4),
                    `var %` = round(100 * x$var_explained[x$ic$q], 1),
                    `cum %` = round(100 * x$cum_var_explained[x$ic$q], 1),
                    check.names = FALSE)
  # mark each criterion's minimum, so the table can be read without the plot
  for(nm in c("IC1", "IC2", "IC3")){
    tab[[nm]] <- paste0(tab[[nm]], ifelse(x$ic$q == x$q_hat[[nm]], " *", "  "))
  }
  print(tab, row.names = FALSE)

  cat("\nChosen q:  IC1 = ", x$q_hat[["IC1"]],
      ",  IC2 = ", x$q_hat[["IC2"]],
      ",  IC3 = ", x$q_hat[["IC3"]], "\n", sep = "")
  if(length(unique(x$q_hat)) > 1){
    cat("The criteria disagree; that disagreement is the result. See ",
        "`?select_factors`.\n", sep = "")
  }
  if(length(x$at_boundary)){
    cat(paste(x$at_boundary, collapse = "/"),
        if(length(x$at_boundary) > 1) " are" else " is",
        " minimised at max_q = ", x$max_q,
        ", so the minimum may lie beyond\nthe range evaluated. Raise `max_q`.\n",
        sep = "")
  }
  cat("These are frequentist, principal-component criteria. They inform ",
      "fcast_dfm()'s\n`q`; they do not determine it.\n", sep = "")

  invisible(x)

}

#' @rdname select_factors_methods
#' @importFrom graphics matplot points legend barplot
#' @method plot select_factors
#' @export
plot.select_factors <- function(x, main = NULL, ...){

  m <- as.matrix(x$ic[, c("IC1", "IC2", "IC3")])
  matplot(x$ic$q, m, type = "b", pch = 16, lty = 1,
          col = c("#1b6ca8", "#e08214", "#4d9221"),
          xlab = "number of factors", ylab = "information criterion",
          main = if(is.null(main)) "Bai-Ng information criteria" else main,
          xaxt = "n", ...)
  graphics::axis(1, at = x$ic$q)
  for(j in seq_len(3L)){
    nm <- colnames(m)[j]
    points(x$q_hat[[nm]], min(m[, j]), pch = 1, cex = 2.4,
           col = c("#1b6ca8", "#e08214", "#4d9221")[j])
  }
  legend("topright", legend = colnames(m), bty = "n", lty = 1, pch = 16,
         col = c("#1b6ca8", "#e08214", "#4d9221"))

  invisible(x$ic)

}

#' @rdname select_factors_methods
#' @importFrom stats screeplot
#' @method screeplot select_factors
#' @export
screeplot.select_factors <- function(x, npcs = min(10, length(x$eigenvalues)),
                                     type = c("barplot", "lines"),
                                     value = c("share", "eigenvalue"),
                                     main = NULL, ...){

  type  <- match.arg(type)
  value <- match.arg(value)
  if(!is_count(npcs) || npcs < 1 || npcs > length(x$eigenvalues)){
    stop("`npcs` must be a single whole number between 1 and ",
         length(x$eigenvalues), ".", call. = FALSE)
  }

  v <- if(value == "share") x$var_explained else x$eigenvalues
  v <- v[seq_len(npcs)]
  names(v) <- seq_len(npcs)
  ylab <- if(value == "share") "share of panel variance" else "eigenvalue"
  if(is.null(main)) main <- "Scree plot"

  scree_draw(v, type = type, ylab = ylab, main = main, ...)

  invisible(v)

}


#' Draw a scree plot from a named vector of component magnitudes
#'
#' Shared by [screeplot.select_factors()] and the fit-class `screeplot()`
#' methods in `methods.R`, so the two look the same.
#'
#' @noRd
#' @importFrom graphics barplot axis
scree_draw <- function(v, type = "barplot", ylab = "", main = "", xlab = "component", ...){

  if(type == "barplot"){
    barplot(v, col = "#1b6ca8", border = NA, ylab = ylab, xlab = xlab,
            main = main, ...)
  } else {
    plot(seq_along(v), v, type = "b", pch = 16, col = "#1b6ca8",
         xlab = xlab, ylab = ylab, main = main, xaxt = "n", ...)
    axis(1, at = seq_along(v), labels = names(v))
  }

  invisible(v)

}
