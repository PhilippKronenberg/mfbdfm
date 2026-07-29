# Input validation shared by the exported model entry points.
#
# Kept in one place deliberately: the parity rule in CLAUDE.md says anything
# true of one model entry point must be true of the other, and duplicated
# validation is exactly the thing that drifts. Validation lives here and in the
# exported functions only - never inside the draw_*() samplers, which run once
# per MCMC iteration and would pay the cost for nothing.

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

  invisible(TRUE)

}


#' Is x a single, finite, whole number?
#'
#' @noRd
is_count <- function(x){
  is.numeric(x) && length(x) == 1 && is.finite(x) && x == round(x)
}
