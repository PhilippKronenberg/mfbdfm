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
      # G5.8a: checked before is.ts(), because stats::is.ts() is
      # `inherits(x, "ts") && length(x) > 0L` -- so a zero-length series that
      # carries the class would otherwise be reported as "not a `ts` object",
      # which names the series but misstates the reason.
      empty <- names(x)[vapply(x, function(s) length(s) == 0L, logical(1))]
      if(length(empty)){
        stop("`", nm, "` must contain only non-empty series; these have length ",
             "zero: ", paste(sQuote(empty), collapse = ", "), ".", call. = FALSE)
      }
      bad <- names(x)[!vapply(x, stats::is.ts, logical(1))]
      if(length(bad)){
        stop("`", nm, "` must contain only `ts` objects; these are not: ",
             paste(sQuote(bad), collapse = ", "), ".", call. = FALSE)
      }
      # G5.8b: `ts` constrains the time attributes, not the storage mode, so a
      # character or complex series is a valid `ts` and an invalid input here.
      modes <- vapply(x, function(s) typeof(as.vector(s)), character(1))
      wrong <- !modes %in% c("double", "integer")
      if(any(wrong)){
        stop("`", nm, "` must contain only numeric series; these are not: ",
             paste(paste0(sQuote(names(x)[wrong]), " (", modes[wrong], ")"),
                   collapse = ", "), ".", call. = FALSE)
      }
      # G2.16: Inf and NaN are neither data nor missing data, and both would be
      # taken for one or the other. `prepare_data()` standardizes each series by
      # its own mean and standard deviation, so a single Inf turns both into NaN
      # and the whole column leaves the standardization as NaN - the fit then
      # returns NaN nowcasts rather than failing. NaN is worse, because it passes
      # is.na() and would therefore be imputed by the data augmentation as if it
      # were a genuine unobserved period. Refused by name instead.
      why <- vapply(x, nonfinite_reason, character(1))
      if (any(nzchar(why))){
        stop("`", nm, "` must contain only finite observations (`NA` for ",
             "missing); these do not: ",
             paste(paste0(sQuote(names(x)[nzchar(why)]), " ", why[nzchar(why)]),
                   collapse = ", "), ".", call. = FALSE)
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

  for(nm in c("p", "length_sample", "thinning")){
    v <- get(nm)
    if(!is_count(v) || v < 1){
      stop("`", nm, "` must be a single positive whole number, not ",
           deparse(v), ".", call. = FALSE)
    }
  }

  # burn_in alone may be 0: the second leg of a continued chain starts from the
  # first leg's final state, which has already burned in, so demanding at least
  # one discarded draw there would throw away a draw of the same chain (#117).
  if(!is_count(burn_in) || burn_in < 0){
    stop("`burn_in` must be a single whole number >= 0, not ",
         deparse(burn_in), ".", call. = FALSE)
  }

  # Collinearity screen (BS3.1). Raised here rather than in each entry point
  # because this is the one funnel both of them pass through, which is what
  # keeps the parity rule from drifting. It warns and does not stop - see
  # warn_collinear_series() for why.
  warn_collinear_series(c(flows, stocks))

  invisible(TRUE)

}


#' Check an analytics `inputs` bundle and bind what it carries (G5.2a)
#'
#' The three analytics table builders -- [get_insample_fit_table()],
#' [create_error_summary_tables()] and [get_combined_cor_table()] -- each take an
#' explicit `inputs` list rather than reading the caller's environment, and each
#' opened with the same four lines: diff the required names against
#' `names(inputs)`, raise the same `"Missing required inputs: "`, then
#' `list2env()` the bundle into the function's own environment. One message at
#' three call sites is the duplication G5.2a is about, so both halves live here.
#'
#' Binding into `envir` is the point rather than an afterthought: the builders'
#' bodies refer to the input objects by bare name, so the helper has to put them
#' where its *caller* can see them, which is why `envir` defaults to
#' [parent.frame()].
#'
#' @param inputs Named list of data objects, as supplied by the user.
#' @param required Character vector of names `inputs` must carry.
#' @param envir Environment the required objects are bound into.
#'
#' @return `envir`, invisibly.
#'
#' @noRd
require_analysis_inputs <- function(inputs, required, envir = parent.frame()){

  if(!is.list(inputs)){
    stop("`inputs` must be a named list of the data objects the table is built ",
         "from, not a ", class(inputs)[1], ". See mfbdfm_example_inputs() for ",
         "the expected shape.", call. = FALSE)
  }

  missing_inputs <- setdiff(required, names(inputs))
  if(length(missing_inputs) > 0){
    stop("Missing required inputs: ", paste(missing_inputs, collapse = ", "),
         call. = FALSE)
  }

  list2env(inputs[required], envir = envir)
  invisible(envir)

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


#' Does this series carry Inf or NaN, and how much of each? (G2.16)
#'
#' Returns a phrase completing "series 'x' <...>", or `""` when every
#' observation is either finite or `NA`. `NaN` is counted separately from
#' `+-Inf` because the two arrive for different reasons - a NaN is usually
#' `0/0` somewhere upstream, an Inf a division by zero or an overflowing
#' exponential - and because `is.na(NaN)` is `TRUE`, which is exactly why a NaN
#' cannot be left to the missing-value machinery.
#'
#' @noRd
nonfinite_reason <- function(s){

  v <- as.numeric(s)
  n_nan <- sum(is.nan(v))
  n_inf <- sum(!is.na(v) & !is.finite(v))   # is.na() is TRUE for NaN already

  if (!n_nan && !n_inf) return("")

  parts <- c(if (n_inf) paste(n_inf, if (n_inf > 1) "Inf values" else "Inf value"),
             if (n_nan) paste(n_nan, if (n_nan > 1) "NaN values" else "NaN value"))
  paste("carries", paste(parts, collapse = " and "))

}


#' Is x a single, finite, whole number?
#'
#' @noRd
is_count <- function(x){
  is.numeric(x) && length(x) == 1 && is.finite(x) && x == round(x)
}


#' Why is this series degenerate, if it is?
#'
#' Returns a phrase completing "series 'x' <...>", or `NULL` when the series is
#' usable. Constancy is tested on the distinct non-missing values rather than
#' through `sd()`, so that a single-observation series (whose `sd()` is `NA`,
#' not `0`) lands in the same bucket, and so that a series carrying `Inf`
#' (whose `sd()` is `NaN`) is *not* mislabelled as constant -- `Inf`/`NaN`
#' screening is G2.16's job and lives elsewhere.
#'
#' @noRd
degenerate_reason <- function(x){

  v <- x[!is.na(x)]
  if(!length(v)) return("has no non-missing observations")
  if(length(unique(v)) == 1L){
    return(paste0("is constant (every observation is ", format(v[1]), ")"))
  }
  NULL

}


#' Drop degenerate series, or error if the target is one of them
#'
#' G5.8c. `create_inventory()` standardizes each series by its own standard
#' deviation, so a constant or all-missing series divides by zero or by `NA`
#' and the fit fails later with a message that names neither the series nor the
#' cause. Such a series carries no information about the factor, so dropping it
#' loses nothing -- but doing so silently would be a wrong answer quietly
#' given, hence the warning naming every series dropped.
#'
#' The `target` is the exception: in `ind_dfm()` the factor is anchored to it,
#' and in `fcast_dfm()` it selects the surfaced nowcast, so there is no model
#' left to fit without it. That errors instead.
#'
#' Called from the entry points *after* [validate_model_inputs()], so that a
#' zero-length or non-numeric series still errors (G5.8a/G5.8b) instead of
#' being quietly dropped here. `q` is re-checked against the surviving count,
#' since dropping can leave fewer series than factors.
#'
#' [select_factors()] calls it too (#146), passing `target = NULL` when the
#' user supplied none -- there the target is a stand-in for the shared
#' validator and must not be able to stop the call -- and a `context` phrase,
#' since nothing is being fitted there.
#'
#' @param context Phrase completing "Dropped n degenerate series <context>:".
#'
#' @return A list with the surviving `flows` and `stocks`.
#'
#' @noRd
screen_degenerate_series <- function(flows, stocks, target, q = NULL,
                                     context = "before fitting"){

  reasons <- character(0)

  for(nm in c("flows", "stocks")){
    x <- get(nm)
    if(!is.list(x) || !length(x)) next
    if(is.null(names(x)) || any(names(x) == "")) next
    if(!all(vapply(x, stats::is.ts, logical(1)))) next
    r <- vapply(x, function(s){
      why <- degenerate_reason(s)
      if(is.null(why)) "" else why
    }, character(1))
    reasons <- c(reasons, r[nzchar(r)])
  }

  if(!length(reasons)) return(list(flows = flows, stocks = stocks))

  if(is.character(target) && length(target) == 1L && target %in% names(reasons)){
    stop("`target` (\"", target, "\") ", reasons[[target]], ", so there is ",
         "nothing for the factor to track. Supply a target series that varies.",
         call. = FALSE)
  }

  keep <- function(x) if(is.null(x)) NULL else x[!names(x) %in% names(reasons)]
  flows <- keep(flows)
  stocks <- keep(stocks)

  mfbdfm_warn(
    paste0("Dropped ", length(reasons), " degenerate series ", context, ": ",
           paste(paste0(sQuote(names(reasons)), " ", reasons), collapse = "; "),
           ". Standardizing such a series divides by zero or by NA, so it ",
           "cannot enter the model; it carries no information about the factor."),
    "mfbdfm_warning_dropped_series")

  n_series <- length(flows) + length(stocks)
  if(n_series < 1L){
    stop("Every supplied series was degenerate, so there is nothing to fit.",
         call. = FALSE)
  }
  if(!is.null(q) && n_series < q){
    stop("`q` (", q, ") must be smaller than the number of input series, and ",
         "only ", n_series, " survived the degenerate-series screen above.",
         call. = FALSE)
  }

  list(flows = if(length(flows)) flows else NULL,
       stocks = if(length(stocks)) stocks else NULL)

}
