#' Numerical and algorithmic settings for the samplers
#'
#' Bundles the numerical and algorithmic knobs that were previously hard-coded
#' inside the samplers: the rotation stopping rule, the stability bounds that
#' reject or cap a draw, and two numerical guards. Passing a control object is
#' **optional** -- omit it and the defaults reproduce the published behaviour
#' exactly.
#'
#' @details
#' # What is and is not here
#'
#' This holds settings that affect *how* the sampler searches, not *what model*
#' it fits. Priors live in [dfm_priors()]; model structure is in the arguments
#' of [ind_dfm()] and [fcast_dfm()].
#'
#' Deliberately absent: initial values, and the numerical conditioning constants
#' that are not choices (the `1e-9` ridge that encodes "effectively zero"
#' autocorrelation when `serial_correlation = FALSE`, and the `pi - 1e-16` domain
#' guard on the Givens angles).
#'
#' # The rotation stopping rule
#'
#' Only [fcast_dfm()] rotates, so `rotation_*` is ignored by [ind_dfm()].
#'
#' Appendix E of the online appendix to Eckert et al. (2025), following Aßmann,
#' Boysen-Hogrefe & Pape (2016), specifies convergence when the **sum** of
#' squared deviations between successive `theta*` falls below `1e-9`. The
#' implementation has always tested the **mean**, which over a packed vector of
#' several thousand elements is a much weaker requirement, and additionally
#' capped the loop at five iterations. `rotation_criterion = "sum"` restores the
#' published rule.
#'
#' Measured on a small two-factor fit, convergence is geometric at roughly an
#' order of magnitude per iteration: the mean criterion converged at iteration 5
#' and the sum criterion at iteration 6. Matching the paper therefore costs
#' about one extra iteration, not the blow-up the difference in thresholds
#' suggests. Note also that the default cap of 5 sits *exactly* on that
#' convergence point, so on other data it can bind and truncate the loop -- which
#' is why a binding cap warns.
#'
#' `rotation_max_iter` and `rotation_init_max_iter` are safety valves, not
#' targets. They default high enough not to bind in practice (100 against 5-7
#' observed) while still guaranteeing the loop terminates. `Inf` is not accepted:
#' an unbounded loop has no termination guarantee, and a non-converging rotation
#' should stop and complain rather than run forever.
#'
#' # Stability bounds
#'
#' `rho_max` bounds the measurement-error autocorrelation. A draw outside it is
#' redrawn up to `rho_max_tries` times, after which `rho_fallback` is used. The
#' others cap or reject a draw for numerical stability: `phi_sum_max` and
#' `sigma_max` in [ind_dfm()], `omega_max` in [fcast_dfm()].
#'
#' @param model Character, which model the settings are for: `"ind_dfm"` or
#'   `"fcast_dfm"`. Determines which knobs are present, since the two samplers
#'   do not share all of them.
#' @param strict Logical. If `TRUE`, sets the rotation to the published
#'   algorithm -- `rotation_criterion = "sum"`, `rotation_max_iter` raised, and
#'   failure to converge becomes an **error** rather than a warning. A single
#'   switch for "run it the way the paper specifies". Ignored by [ind_dfm()].
#' @param ... Named overrides for individual settings, e.g.
#'   `rotation_criterion = "sum"` or `sigma_max = 10`. Naming a setting the
#'   chosen model does not have is an error, so a typo surfaces immediately.
#'
#' @return An object of class `"dfm_control"`: a named list of settings plus
#'   `model` and `strict`.
#'
#' @examples
#' dfm_control("fcast_dfm")
#'
#' # the published rotation rule
#' dfm_control("fcast_dfm", strict = TRUE)
#'
#' # or one setting at a time
#' dfm_control("fcast_dfm", rotation_criterion = "sum", rotation_tol = 1e-10)
#' dfm_control("ind_dfm", sigma_max = 10)
#'
#' @references
#' Aßmann, C., Boysen-Hogrefe, J., & Pape, M. (2016). Bayesian analysis of
#' static and dynamic factor models with an unknown number of factors, and
#' structural instability. *Journal of Applied Econometrics*, 31(8), 1518-1533.
#'
#' Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
#' Tracking economic activity with alternative high-frequency data.
#' *Journal of Applied Econometrics*, 40(3), 270-290.
#'
#' @seealso [ind_dfm()], [fcast_dfm()], [dfm_priors()]
#' @family model specification
#' @export
dfm_control <- function(model = c("ind_dfm", "fcast_dfm"),
                        strict = FALSE, ...){

  model <- match.arg(model)

  if(!is.logical(strict) || length(strict) != 1 || is.na(strict)){
    stop("`strict` must be TRUE or FALSE.", call. = FALSE)
  }

  out <- control_defaults(model)

  if(strict){
    if(model == "ind_dfm"){
      warning("`strict` only affects the rotation, which `ind_dfm()` does not ",
              "use; it is ignored here.", call. = FALSE)
    } else {
      out$rotation_criterion <- "sum"
      out$rotation_max_iter <- ROTATION_MAX_ITER_STRICT
      out$rotation_on_failure <- "error"
    }
  }

  overrides <- list(...)
  if(length(overrides)){
    if(is.null(names(overrides)) || any(!nzchar(names(overrides)))){
      stop("Overrides in `...` must all be named, e.g. ",
           "`dfm_control(\"fcast_dfm\", rotation_tol = 1e-10)`.", call. = FALSE)
    }
    unknown <- setdiff(names(overrides), names(out))
    if(length(unknown)){
      stop("Unknown control setting", if(length(unknown) > 1) "s" else "", " for ",
           model, "(): ", paste(sQuote(unknown), collapse = ", "), ".\n",
           "  Available: ", paste(names(out), collapse = ", "), ".", call. = FALSE)
    }
    out[names(overrides)] <- overrides
  }

  ctrl <- structure(c(out, list(model = model, strict = strict)),
                    class = "dfm_control")

  validate_control(ctrl)

  ctrl

}


# Cap for the strict rotation. Measured convergence is 5-7 iterations at roughly
# an order of magnitude per iteration, so this is >10x headroom: high enough not
# to bind, finite so the loop is guaranteed to terminate.
ROTATION_MAX_ITER_STRICT <- 100


#' Default settings per model
#'
#' Every value here is the literal that was previously hard-coded at the
#' corresponding call site, so omitting `control` reproduces the published
#' behaviour exactly. Do not "improve" a default without regenerating
#' dev/baseline.rds and saying why.
#'
#' @noRd
control_defaults <- function(model){

  shared <- list(
    # draw_rho / draw_rho_fcast stationarity screen
    rho_max = 0.99,
    rho_max_tries = 10,
    rho_fallback = 0.98,
    # jitter added after gamma/normal draws to avoid exact zeros and singular
    # matrices; the "+ 1e-9" at the draw sites
    jitter = 1e-9,
    # offset in log(err^2 + offset) for the Kim-Shephard-Chib mixture step
    sv_offset = 0.001
  )

  if(model == "ind_dfm"){
    c(shared,
      list(phi_sum_max = 0.9,     # draw_phi rejects and keeps the previous draw
           sigma_max = 5))        # draw_sigma cap
  } else {
    c(shared,
      list(omega_max = 1,         # draw_omega_fcast cap
           rotation_criterion = "mean",
           rotation_tol = 1e-9,
           rotation_max_iter = 5,
           rotation_init_tol = 1e-9,
           # the init loop was previously uncapped and so had no termination
           # guarantee; 100 against 7 observed leaves it effectively unbounded
           rotation_init_max_iter = 100,
           rotation_on_failure = "warning"))
  }

}


#' Validate a control object
#'
#' @noRd
validate_control <- function(ctrl){

  pos_num <- function(nm, upper = Inf){
    v <- ctrl[[nm]]
    if(is.null(v)) return(invisible())
    if(!is.numeric(v) || length(v) != 1 || is.na(v) || v <= 0 || v > upper){
      stop("`", nm, "` must be a single number in (0, ",
           if(is.infinite(upper)) "Inf" else upper, "], not ",
           deparse(v), ".", call. = FALSE)
    }
  }
  count <- function(nm){
    v <- ctrl[[nm]]
    if(is.null(v)) return(invisible())
    if(!is.numeric(v) || length(v) != 1 || !is.finite(v) || v < 1 || v != round(v)){
      stop("`", nm, "` must be a single finite whole number >= 1, not ",
           deparse(v), ".\n",
           "  `Inf` is not accepted: an unbounded loop has no termination ",
           "guarantee. Use a high finite value instead.", call. = FALSE)
    }
  }

  pos_num("rho_max", upper = 1)
  pos_num("rho_fallback", upper = 1)
  pos_num("jitter")
  pos_num("sv_offset")
  pos_num("phi_sum_max")
  pos_num("sigma_max")
  pos_num("omega_max")
  pos_num("rotation_tol")
  pos_num("rotation_init_tol")
  count("rho_max_tries")
  count("rotation_max_iter")
  count("rotation_init_max_iter")

  if(!is.null(ctrl$rho_fallback) && ctrl$rho_fallback >= ctrl$rho_max){
    stop("`rho_fallback` (", ctrl$rho_fallback, ") must be smaller than ",
         "`rho_max` (", ctrl$rho_max, "), or the fallback draw would itself ",
         "fail the stationarity screen and the loop would never exit.",
         call. = FALSE)
  }

  if(!is.null(ctrl$rotation_criterion) &&
     !identical(ctrl$rotation_criterion, "mean") &&
     !identical(ctrl$rotation_criterion, "sum")){
    stop("`rotation_criterion` must be \"mean\" or \"sum\", not ",
         deparse(ctrl$rotation_criterion), ".", call. = FALSE)
  }

  if(!is.null(ctrl$rotation_on_failure) &&
     !ctrl$rotation_on_failure %in% c("warning", "error", "ignore")){
    stop("`rotation_on_failure` must be \"warning\", \"error\" or \"ignore\", ",
         "not ", deparse(ctrl$rotation_on_failure), ".", call. = FALSE)
  }

  invisible(TRUE)

}


#' Accept a control object, a plain list, or NULL
#'
#' Called by the exported entry points so `control` can be omitted entirely.
#'
#' @noRd
resolve_control <- function(control, model){

  if(is.null(control)) return(dfm_control(model))

  if(inherits(control, "dfm_control")){
    if(!identical(control$model, model)){
      stop("`control` was built for ", control$model, "() but passed to ",
           model, "(). Use dfm_control(\"", model, "\", ...).", call. = FALSE)
    }
    validate_control(control)
    return(control)
  }

  if(is.list(control)) return(do.call(dfm_control, c(list(model), control)))

  stop("`control` must be a `dfm_control` object from dfm_control(), a named ",
       "list of settings, or NULL, not a ", class(control)[1], ".",
       call. = FALSE)

}


#' Print a dfm_control object
#'
#' @param x An object of class `"dfm_control"` from [dfm_control()].
#' @param ... Ignored, present for compatibility with the [print()] generic.
#'
#' @return `x`, invisibly.
#'
#' @examples
#' dfm_control("fcast_dfm", strict = TRUE)
#'
#' @method print dfm_control
#' @export
print.dfm_control <- function(x, ...){

  defaults <- control_defaults(x$model)
  meta <- c("model", "strict")
  nms <- setdiff(names(x), meta)

  cat("Control settings for ", x$model, "()",
      if(isTRUE(x$strict)) "  [strict: published rotation rule]" else "", "\n\n",
      sep = "")

  for(nm in nms){
    v <- x[[nm]]
    changed <- !identical(v, defaults[[nm]])
    cat(sprintf("  %-24s %-10s%s\n", nm,
                if(is.character(v)) paste0("\"", v, "\"") else format(v),
                if(changed) sprintf("  (default %s)",
                                    if(is.character(defaults[[nm]]))
                                      paste0("\"", defaults[[nm]], "\"")
                                    else format(defaults[[nm]])) else ""))
  }

  if(identical(x$rotation_criterion, "mean")){
    cat("\n  Note: rotation_criterion \"mean\" is weaker than the published rule.\n",
        "  dfm_control(\"fcast_dfm\", strict = TRUE) matches Eckert et al. (2025).\n",
        sep = "")
  }

  invisible(x)

}
