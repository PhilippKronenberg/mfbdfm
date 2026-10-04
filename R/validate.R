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

  invisible(TRUE)

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
#' @return A list with the surviving `flows` and `stocks`.
#'
#' @noRd
screen_degenerate_series <- function(flows, stocks, target, q = NULL){

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
    paste0("Dropped ", length(reasons), " degenerate series before fitting: ",
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
