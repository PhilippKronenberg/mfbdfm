# Input validation shared by the exported model entry points.
#
# Kept in one place deliberately: the parity rule in CLAUDE.md says anything
# true of one model entry point must be true of the other, and duplicated
# validation is exactly the thing that drifts. Validation lives here and in the
# exported functions only - never inside the draw_*() samplers, which run once
# per MCMC iteration and would pay the cost for nothing.

#' Unpack an mfbdfm_data object into flows/stocks, if one was given
#'
#' Lets both model entry points accept either
#' `model(mfbdfm_data(...), target = )` or the original
#' `model(flows = , stocks = , target = )`, without either path knowing about
#' the other. Returns the resolved arguments as a list.
#'
#' @noRd
resolve_data_arg <- function(flows, stocks, target){

  if(inherits(flows, "mfbdfm_data")){
    if(!is.null(stocks)){
      stop("When the first argument is an `mfbdfm_data` object, `stocks` must ",
           "not also be supplied - the object already carries both.",
           call. = FALSE)
    }
    d <- flows
    # a target given here wins over one stored on the object, so the call site
    # stays authoritative
    if(is.null(target) || (is.character(target) && !length(target))) target <- d$target
    return(list(flows = d$flows, stocks = d$stocks, target = target))
  }

  list(flows = flows, stocks = stocks, target = target)

}


#' Validate the arguments common to ind_dfm() and fcast_dfm()
#'
#' Errors name the offending argument and what was expected.
#'
#' @param q Integer or `NULL`. Only `fcast_dfm()` takes a factor count; pass
#'   `NULL` to skip that check.
#' @param call Character, the name of the calling function, used in messages.
#'
#' @noRd
validate_model_inputs <- function(flows, stocks, target,
                                  p, length_sample, burn_in, thinning,
                                  q = NULL, call = "ind_dfm"){

  if(is.null(flows) && is.null(stocks)){
    stop("At least one of `flows` and `stocks` must be supplied.", call. = FALSE)
  }

  for(nm in c("flows", "stocks")){
    x <- get(nm)
    if(!is.null(x)){
      if(!is.list(x)){
        stop("`", nm, "` must be a named list of `ts` objects, not a ",
             class(x)[1], ".", call. = FALSE)
      }
      if(is.null(names(x)) || any(names(x) == "")){
        stop("Every element of `", nm, "` must be named.", call. = FALSE)
      }
      bad <- names(x)[!vapply(x, stats::is.ts, logical(1))]
      if(length(bad)){
        stop("`", nm, "` must contain only `ts` objects; these are not: ",
             paste(sQuote(bad), collapse = ", "), ".", call. = FALSE)
      }
    }
  }

  if(missing(target) || is.null(target) || !is.character(target) || length(target) != 1){
    stop("`target` must be a single series name (character).", call. = FALSE)
  }
  available <- c(names(flows), names(stocks))
  if(!target %in% available){
    stop("`target` (\"", target, "\") is not among the supplied series.\n",
         "  Available: ", paste(utils::head(available, 10), collapse = ", "),
         if(length(available) > 10) ", ..." else "", ".", call. = FALSE)
  }

  n_series <- length(flows) + length(stocks)
  if(!is.null(q)){
    if(!is_count(q) || q < 1){
      stop("`q` must be a single positive whole number, not ",
           deparse(q), ".", call. = FALSE)
    }
    if(n_series < q){
      stop("`q` (", q, ") must be smaller than the number of input series (",
           n_series, ").", call. = FALSE)
    }
  }

  for(nm in c("p", "length_sample", "burn_in", "thinning")){
    v <- get(nm)
    if(!is_count(v) || v < 1){
      stop("`", nm, "` must be a single positive whole number, not ",
           deparse(v), ".", call. = FALSE)
    }
  }

  # Collinearity screen (BS3.1). Raised here rather than in each entry point
  # because this is the one funnel both of them pass through, which is what
  # keeps the parity rule from drifting. It warns and does not stop - see
  # warn_collinear_series() for why.
  warn_collinear_series(c(flows, stocks))

  invisible(TRUE)

}


#' Align a list of mixed-frequency `ts` on the highest-frequency grid, keeping NAs
#'
#' The shift-and-match arithmetic is [prepare_data()]'s: a low-frequency
#' observation is moved to the end of its period by
#' `(max(freq)/frequency(x) - 1)/max(freq)` and then matched onto the
#' `1/max(freq)` grid by an exact join. It is reproduced here rather than reused
#' because `prepare_data()` overwrites missing with `0`, and telling a missing
#' observation apart from an observed zero is the whole point of this matrix.
#'
#' Observations that do not land on the grid are dropped, exactly as the join in
#' `prepare_data()` drops them (see the "Weekly and daily series" section of
#' [mfbdfm_data()] for when that happens). All-missing rows are trimmed, so the
#' result is the size of the actual sample rather than of the 1900-2100 grid.
#'
#' @return A numeric matrix, one column per series, `NA` where unobserved.
#'
#' @noRd
align_series_on_grid <- function(series){

  freqs <- vapply(series, stats::frequency, numeric(1))
  freq_max <- max(freqs)

  grid <- round(seq(1900, 2100, 1/freq_max), 5)

  out <- matrix(NA_real_, length(grid), length(series),
                dimnames = list(NULL, names(series)))

  for(j in seq_along(series)){
    x <- series[[j]]
    tim <- round(as.numeric(stats::time(x)) +
                   (freq_max/stats::frequency(x) - 1)/freq_max, 5)
    row <- match(tim, grid)
    ok <- !is.na(row)
    out[row[ok], j] <- as.numeric(x)[ok]
  }

  out[rowSums(!is.na(out)) > 0, , drop = FALSE]

}


#' Near-collinear pairs among the input series (BS3.1)
#'
#' In an indicator panel a duplicated series is not hypothetical: the same
#' underlying quantity often enters twice, as a level and as an index, or as a
#' total alongside its own components. A factor model does not fail on that --
#' it splits the loading between the duplicates and reports a fit -- so the
#' screen exists to make it visible before the fit rather than after.
#'
#' The statistic is the correlation of each pair **on its overlapping observed
#' span only**, which is why this works from [align_series_on_grid()] rather
#' than from the prepared matrix: the zeros there encode missing, and a plain
#' correlation over them measures the padding as much as the data. Pairs with
#' fewer than `min_overlap` overlapping observations are skipped, since a
#' correlation off a handful of points is noise rather than evidence of
#' duplication.
#'
#' Correlation is invariant to the affine standardization `prepare_data()`
#' applies, so the aligned values are used directly -- the number is identical
#' to the one the standardized matrix would give, without recomputing the
#' moments here.
#'
#' @param series A named list of `ts` objects (`c(flows, stocks)`).
#' @param threshold Flag pairs with `abs(correlation) > threshold`.
#' @param min_overlap Skip pairs with fewer overlapping observations than this.
#'
#' @return A data frame with columns `series1`, `series2`, `correlation` and
#'   `n_overlap`, ordered by decreasing `abs(correlation)`; zero rows when
#'   nothing is flagged.
#'
#' @noRd
collinear_pairs <- function(series, threshold = 0.99, min_overlap = 24){

  empty <- data.frame(series1 = character(), series2 = character(),
                      correlation = numeric(), n_overlap = integer(),
                      stringsAsFactors = FALSE)

  if(!is.list(series) || length(series) < 2L) return(empty)
  if(is.null(names(series)) || anyNA(names(series))) return(empty)
  if(!all(vapply(series, stats::is.ts, logical(1)))) return(empty)

  X <- align_series_on_grid(series)
  if(!nrow(X)) return(empty)

  # A constant column makes cor() return NA with a warning; NA simply fails the
  # flag test below, so the warning is noise and is suppressed.
  R <- suppressWarnings(stats::cor(X, use = "pairwise.complete.obs"))
  overlap <- crossprod(1 * !is.na(X))

  flag <- upper.tri(R) & !is.na(R) & abs(R) > threshold & overlap >= min_overlap
  if(!any(flag)) return(empty)

  ij <- which(flag, arr.ind = TRUE)
  out <- data.frame(series1 = colnames(X)[ij[, "row"]],
                    series2 = colnames(X)[ij[, "col"]],
                    correlation = R[flag],
                    n_overlap = as.integer(overlap[flag]),
                    stringsAsFactors = FALSE)

  out <- out[order(-abs(out$correlation)), , drop = FALSE]
  row.names(out) <- NULL
  out

}


#' One line per flagged pair, for a warning or a print method
#'
#' @noRd
format_collinear_pairs <- function(pairs, max_show = 5L){

  show <- utils::head(pairs, max_show)
  txt <- sprintf("%s ~ %s  (r = %+.3f, n = %d)",
                 show$series1, show$series2, show$correlation, show$n_overlap)

  rest <- nrow(pairs) - nrow(show)
  if(rest > 0){
    txt <- c(txt, paste0("... and ", rest, " more pair",
                         if(rest > 1) "s" else ""))
  }

  txt

}


#' Warn about near-collinear input series (BS3.1, BS3.2)
#'
#' **BS3.2: no separate code path for exactly collinear data, deliberately.**
#' The model does not break on it -- the likelihood is still proper and the
#' sampler still converges -- so there is no degenerate branch to take. What
#' happens instead is that the shared loading is split between the duplicates,
#' which overweights that signal in the factor without anything downstream
#' noticing. Which of the two series to drop is a question about the data, not
#' about the numerics, so the useful stopping point is a warning that names the
#' pair and leaves the choice to the user.
#'
#' Classed `mfbdfm_warning_collinear` so a caller who has decided the
#' duplication is intended can muffle it; see [dfm_control()].
#'
#' @noRd
warn_collinear_series <- function(series, threshold = 0.99, min_overlap = 24){

  pairs <- collinear_pairs(series, threshold = threshold,
                           min_overlap = min_overlap)
  if(!nrow(pairs)) return(invisible(pairs))

  n <- nrow(pairs)
  mfbdfm_warn(
    paste0(n, " pair", if(n > 1) "s" else "", " of input series ",
           if(n > 1) "are" else "is", " near-perfectly correlated (|r| > ",
           threshold, ") on their overlapping observed span:\n  ",
           paste(format_collinear_pairs(pairs), collapse = "\n  "),
           "\n  A factor model does not fail on collinear inputs: it splits ",
           "the loading between the duplicated series, so the signal is ",
           "silently overweighted rather than reported as an error. Drop one ",
           "series of each pair unless the duplication is intended."),
    "mfbdfm_warning_collinear")

  invisible(pairs)

}


#' Is x a single, finite, whole number?
#'
#' @noRd
is_count <- function(x){
  is.numeric(x) && length(x) == 1 && is.finite(x) && x == round(x)
}
