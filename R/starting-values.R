# Where a chain starts: the random seed, the sampler's initial parameter state,
# and continuing a previous chain (#117).
#
# All three are [dfm_control()] settings rather than arguments of ind_dfm()/
# fcast_dfm(), so the two entry points stay the same shape and the parity rule
# is satisfied by construction. Nothing here consumes the random stream itself -
# it only reads, sets and restores it - and with the defaults
# (`seed = NULL`, `starting_values = NULL`) every function below is a no-op, so
# a fit that does not ask for any of this is bit-identical to one from before.


# RNG STATE ------------------------------------------------------------------

#' The current state of the global random stream
#'
#' `.Random.seed` does not exist until something has drawn from the stream, so
#' a fit in a fresh session would have nothing to record. `set.seed(NULL)`
#' initialises it from the same entropy source R would have used on the first
#' draw, **without consuming a draw**, so recording the state does not move the
#' chain. It is called only when the seed is genuinely absent: on an existing
#' stream it would discard the caller's position.
#'
#' @noRd
rng_state <- function(){

  if(!exists(".Random.seed", envir = globalenv(), inherits = FALSE)){
    set.seed(NULL)
  }

  get(".Random.seed", envir = globalenv(), inherits = FALSE)

}


#' Put a recorded state back
#'
#' `.Random.seed[1]` encodes `RNGkind()` as well as the position, so assigning
#' the whole vector restores the generator kind too.
#'
#' @noRd
rng_set_state <- function(state){

  assign(".Random.seed", state, envir = globalenv())
  invisible(state)

}


#' Take control of the random stream for the duration of a fit
#'
#' Returns the bookkeeping a fit needs: what the caller's state was (so it can
#' be handed back), what state the fit actually starts from (so the fit is
#' reproducible even when no seed was given), and whether the fit took the
#' stream over at all.
#'
#' @param seed `NULL`, or a single whole number to `set.seed()`.
#' @param continue_from `NULL`, or a `.Random.seed` vector from a previous fit,
#'   whose stream this fit continues.
#'
#' @noRd
rng_begin <- function(seed = NULL, continue_from = NULL){

  caller <- rng_state()

  if(!is.null(seed) && !is.null(continue_from)){
    warning("dfm_control() got both a `seed` and a `starting_values` fit, ",
            "which set the random stream to two different places. `seed` ",
            "wins, so this fit does NOT continue the previous chain's random ",
            "stream and the two legs are not a single chain. Drop `seed` to ",
            "continue it.", call. = FALSE)
  }

  if(!is.null(seed)){
    set.seed(as.integer(seed))
  } else if(!is.null(continue_from)){
    rng_set_state(continue_from)
  }

  list(seed = if(is.null(seed)) NULL else as.integer(seed),
       kind = RNGkind(),
       start = rng_state(),
       caller = caller,
       # only a fit that moved the stream itself owes the caller a restore; a
       # default fit advances it, exactly as it always has
       restore = !is.null(seed) || !is.null(continue_from))

}


#' Hand the caller's stream position back
#'
#' Registered with `on.exit()` by the entry points, so it runs however the fit
#' leaves - including on an error.
#'
#' @noRd
rng_restore_caller <- function(rng){

  if(isTRUE(rng$restore) && !is.null(rng$caller)) rng_set_state(rng$caller)
  invisible(NULL)

}


#' The RNG record that goes on the fit
#'
#' Called immediately after the sampling loop, **not** at the end of the fit:
#' `fcast_dfm()`'s evaluation phase redraws the factors from each retained draw
#' and so consumes the stream further, and the state a continuation has to
#' resume from is the one the sampler left behind.
#'
#' @noRd
rng_finish <- function(rng){

  list(seed = rng$seed,
       kind = rng$kind,
       start = rng$start,
       end = rng_state())

}


# STARTING VALUES ------------------------------------------------------------

#' The parameter blocks a chain can be started from
#'
#' The sampler's own names, so a `starting_values` list and a stored
#' `$final_state` are the same object in the same layout.
#'
#' @noRd
starting_value_names <- function(){

  c("f", "lambda", "phi", "sigma", "rho", "h", "omega", "Xmat", "indicators")

}


#' The dimensions and switches a state belongs to
#'
#' Stored as an attribute on `$final_state` and compared when a fit is handed
#' back as `starting_values`, so continuing a chain on different data, a
#' different lag order or a different model switch is an error that names the
#' thing that moved rather than a silent nonsense fit. Normalised to double so
#' `p = 1` and `p = 1L` are the same specification.
#'
#' @noRd
fit_spec <- function(model, n, t, s, p, q, stochastic_volatility,
                     serial_correlation){

  list(model = model,
       n = as.numeric(n), t = as.numeric(t), s = as.numeric(s),
       p = as.numeric(p), q = as.numeric(q),
       stochastic_volatility = isTRUE(stochastic_volatility),
       serial_correlation = isTRUE(serial_correlation))

}


#' Resolve `dfm_control(starting_values = )` into a state and an RNG position
#'
#' @return A list with `state` (a named list of parameter blocks in the
#'   sampler's own types, or `NULL`) and `rng` (a `.Random.seed` vector to
#'   continue, or `NULL`).
#'
#' @noRd
resolve_starting_values <- function(starting_values, spec){

  if(is.null(starting_values)) return(list(state = NULL, rng = NULL))

  # a control object read back off a fit, which records that the chain was
  # continued without keeping the state it continued from (#119)
  if(inherits(starting_values, "mfbdfm_elided")){
    stop("`starting_values` here is ", unclass(starting_values),
         ": a fit records that its chain was continued but does not keep the ",
         "state it continued from, since storing it would nest one fit inside ",
         "the next.\n  To continue a chain, pass the previous fit itself: ",
         "dfm_control(\"", spec$model, "\", starting_values = <fit>).",
         call. = FALSE)
  }

  if(inherits(starting_values, "ind_dfm") ||
     inherits(starting_values, "fcast_dfm")){
    return(starting_values_from_fit(starting_values, spec))
  }

  if(!is.list(starting_values)){
    stop("`starting_values` in dfm_control() must be a named list of parameter ",
         "blocks, a previous ", spec$model, "() fit, or NULL, not a ",
         class(starting_values)[1], ".", call. = FALSE)
  }

  nms <- names(starting_values)
  if(length(starting_values) &&
     (is.null(nms) || any(!nzchar(nms)) || anyDuplicated(nms))){
    stop("Every element of `starting_values` must have a distinct name. ",
         "The parameter blocks are: ",
         paste(starting_value_names(), collapse = ", "), ".", call. = FALSE)
  }

  unknown <- setdiff(nms, starting_value_names())
  if(length(unknown)){
    stop("Unknown element", if(length(unknown) > 1) "s" else "",
         " in `starting_values`: ", paste(sQuote(unknown), collapse = ", "),
         ".\n  The parameter blocks are: ",
         paste(starting_value_names(), collapse = ", "), ".", call. = FALSE)
  }

  state <- lapply(nms, function(nm){
    coerce_starting_value(starting_values[[nm]], nm, spec)
  })
  names(state) <- nms

  list(state = state, rng = NULL)

}


#' Continue the chain a previous fit left off
#'
#' @noRd
starting_values_from_fit <- function(fit, spec){

  if(!inherits(fit, spec$model)){
    stop("`starting_values` is a ", class(fit)[1], " fit but was passed to ",
         spec$model, "(). A chain can only be continued by the model that ",
         "produced it; the two samplers do not share a parameter state.",
         call. = FALSE)
  }

  state <- fit$final_state
  if(is.null(state)){
    stop("`starting_values` is a ", spec$model, "() fit that carries no ",
         "`$final_state`, so there is no sampler state to continue from. ",
         "Fits produced before mfbdfm 0.2.0.9000 do not have one - refit to ",
         "continue a chain.", call. = FALSE)
  }

  old <- attr(state, "spec")
  if(!is.null(old)){
    moved <- names(old)[!vapply(names(old), function(k){
      identical(old[[k]], spec[[k]])
    }, logical(1))]
    if(length(moved)){
      stop("`starting_values` is a fit of a different model specification, so ",
           "its state cannot be continued here:\n",
           paste0("  ", moved, ": ", vapply(moved, function(k) fmt_spec(old[[k]]),
                                            character(1)),
                  " -> ", vapply(moved, function(k) fmt_spec(spec[[k]]),
                                 character(1)), collapse = "\n"),
           call. = FALSE)
    }
  }

  # A continuation has to be complete. A missing block would be re-initialised
  # from the stream instead, which would consume draws and silently make the
  # two legs something other than one chain - so refuse rather than approximate.
  missing_blocks <- setdiff(starting_value_names(),
                            names(Filter(Negate(is.null), state)))
  if(length(missing_blocks)){
    stop("`starting_values` is a ", spec$model, "() fit whose `$final_state` ",
         "is incomplete (missing ", paste(missing_blocks, collapse = ", "),
         "), so the chain cannot be continued from it exactly.", call. = FALSE)
  }

  list(state = state[starting_value_names()], rng = fit$rng$end)

}


#' @noRd
fmt_spec <- function(x){

  if(is.logical(x)) return(if(isTRUE(x)) "TRUE" else "FALSE")
  if(is.character(x)) return(x)
  format(x)

}


#' Validate one starting-value block and put it in the sampler's own type
#'
#' Errors name the offending element and what was expected, per the
#' "validate in exported functions" rule - the caller is still inside
#' `ind_dfm()`/`fcast_dfm()` here, not inside the sampling loop.
#'
#' @noRd
coerce_starting_value <- function(x, nm, spec){

  n <- spec$n; t <- spec$t; s <- spec$s; p <- spec$p; q <- spec$q

  switch(nm,
         f = start_matrix(x, nm, t + s, q),
         lambda = Matrix(start_matrix(x, nm, n, q)),
         h = start_matrix(x, nm, t + s, 1),
         Xmat = start_matrix(x, nm, t, n),
         sigma = start_diag(x, nm, n),
         rho = start_diag(x, nm, n),
         omega = start_scalar(x, nm),
         phi = if(identical(spec$model, "ind_dfm")){
           as.numeric(start_matrix(x, nm, p, 1))
         } else {
           if(!is.list(x) || length(x) != p){
             start_stop(nm, paste0("a list of ", p, " ", q, " x ", q,
                                   " coefficient matrices, one per factor lag"),
                        x)
           }
           lapply(seq_len(p), function(i){
             start_matrix(x[[i]], paste0(nm, "[[", i, "]]"), q, q)
           })
         },
         indicators = start_indicators(x, nm, t + s, q, spec$model),
         stop("Unhandled starting value `", nm, "`.", call. = FALSE))

}


#' @noRd
start_stop <- function(nm, expected, x){

  stop("`starting_values$", nm, "` must be ", expected, ", not ",
       start_shape(x), ".", call. = FALSE)

}


#' A short description of what was actually supplied
#'
#' @noRd
start_shape <- function(x){

  if(is.null(x)) return("NULL")
  d <- dim(x)
  if(!is.null(d)){
    return(paste0("a ", paste(d, collapse = " x "), " ", class(x)[1]))
  }
  if(is.list(x)) return(paste0("a list of ", length(x)))
  paste0(class(x)[1], " of length ", length(x))

}


#' @noRd
start_matrix <- function(x, nm, nr, nc){

  expected <- paste0("a numeric ", nr, " x ", nc, " matrix (or a vector of ",
                     nr * nc, ")")

  if(methods::is(x, "Matrix")) x <- as.matrix(x)
  if(!is.numeric(x) || anyNA(x) || !all(is.finite(x))){
    start_stop(nm, paste0(expected, ", finite and non-missing"), x)
  }

  if(is.null(dim(x))){
    if(length(x) != nr * nc) start_stop(nm, expected, x)
    x <- matrix(as.numeric(x), nr, nc)
  }

  if(length(dim(x)) != 2 || dim(x)[1] != nr || dim(x)[2] != nc){
    start_stop(nm, expected, x)
  }

  storage.mode(x) <- "double"
  x

}


#' @noRd
start_diag <- function(x, nm, n){

  expected <- paste0("a positive numeric vector of ", n,
                     " (or an ", n, " x ", n, " diagonal matrix)")

  if(methods::is(x, "Matrix") || is.matrix(x)){
    if(length(dim(x)) != 2 || dim(x)[1] != n || dim(x)[2] != n){
      start_stop(nm, expected, x)
    }
    d <- as.numeric(diag(as.matrix(x)))
    if(any(as.matrix(x) - diag(d, n, n) != 0)){
      start_stop(nm, paste0(expected, "; the off-diagonal entries must be zero, ",
                            "since this model has no cross-series covariance"), x)
    }
    x <- d
  }

  if(!is.numeric(x) || length(x) != n || anyNA(x) || !all(is.finite(x))){
    start_stop(nm, expected, x)
  }

  # sigma is a variance and rho enters solve()d products; a non-positive
  # starting value is a singular first iteration, not a slow one
  if(identical(nm, "sigma") && any(x <= 0)){
    start_stop(nm, paste0(expected, "; every measurement variance must be > 0"),
               x)
  }

  Diagonal(x = as.numeric(x))

}


#' @noRd
start_scalar <- function(x, nm){

  if(!is.numeric(x) || length(x) != 1 || !is.finite(x) || x <= 0){
    start_stop(nm, "a single positive finite number", x)
  }

  as.numeric(x)

}


#' @noRd
start_indicators <- function(x, nm, nr, q, model){

  nc <- if(identical(model, "ind_dfm")) 1L else q
  expected <- paste0("whole numbers in 1:7, ",
                     if(nc == 1) paste0("of length ", nr)
                     else paste0("as an ", nr, " x ", nc, " matrix"),
                     " (the log chi-squared mixture components)")

  v <- if(is.matrix(x) || methods::is(x, "Matrix")) as.matrix(x) else x
  if(!is.numeric(v) || anyNA(v) || length(v) != nr * nc ||
     any(v != round(v)) || any(v < 1) || any(v > 7)){
    start_stop(nm, expected, x)
  }

  # ind_dfm carries the indicators as a bare vector, fcast_dfm as (t+s) x q
  if(nc == 1) as.numeric(v) else matrix(as.numeric(v), nr, nc)

}
