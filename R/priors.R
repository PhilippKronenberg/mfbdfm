#' Specify the prior distributions for a dynamic factor model
#'
#' Builds the prior specification passed to [ind_dfm()] or [fcast_dfm()]. The
#' defaults reproduce each model's published prior exactly, so
#' `dfm_priors(model)` changes nothing; the object exists so that priors can be
#' inspected and varied deliberately rather than edited in the sampler source.
#'
#' @details
#' # Structural versus tunable priors
#'
#' Some priors are not tuning knobs -- they *are* the model's identification,
#' and changing them changes what the estimates mean:
#'
#' \describe{
#'   \item{`ind_dfm`}{The target series' measurement-error variance
#'     (`sigma_target`, prior sample size `t` and scale `t * 1e-3`) and its
#'     serial correlation (`rho_target`, prior variance `1e-9`) are what force
#'     the augmented target to reproduce the observed series, which is what
#'     makes the factor interpretable as the target's growth rate. Loosening
#'     them dissolves that anchoring.}
#'   \item{`fcast_dfm`}{The loading prior (`lambda`) must stay diffuse
#'     (`B0 = 1e9`); restricting it conflicts with the post-hoc rotation that
#'     identifies the model.}
#' }
#'
#' `type` therefore moves **tunable priors only**. Structural priors can still
#' be set, by naming them explicitly in `...`, but doing so emits a warning:
#' the resulting fit is a different model from the published one.
#'
#' # Priors that depend on the data
#'
#' Several defaults scale with the sample length `t` or the number of lags
#' `p`, which are not known until the data have been prepared. Those entries
#' are stored as `NULL`, meaning "use the model's rule", and are resolved
#' inside the sampler. Supplying a number instead overrides the rule with a
#' literal value.
#'
#' # Interpreting the inverse-gamma priors
#'
#' Variance priors are inverse-gamma, written so that the posterior update is
#' `c1 = c0 + t` and `d1 = d0 + sum(residuals^2)`. So `c0` is a prior sample
#' size in pseudo-observations, `d0` is the sum of squares they carry, and
#' `d0 / c0` is roughly the prior's guess at the variance.
#'
#' @param model Character, which model the priors are for: `"ind_dfm"` or
#'   `"fcast_dfm"`. The two models take different priors, and passing a set
#'   built for one to the other is an error.
#' @param type Character, the overall strength of the tunable priors:
#'   `"default"` (the published values), `"uninformative"` (minimal prior
#'   information, letting the data dominate) or `"informative"` (more
#'   shrinkage). Does not affect structural priors -- see Details.
#' @param ... Named overrides for individual priors, each a list of the
#'   entries shown by printing the returned object, e.g.
#'   `sigma_other = list(c0 = 3, d0 = 1e-3)`. Naming a structural prior is
#'   allowed but warns.
#'
#' @return An object of class `"dfm_priors"`: a named list with an entry per
#'   prior, plus `model`, `type`, and a `structural_modified` flag recording
#'   whether any identifying prior was overridden.
#'
#' @examples
#' # the defaults reproduce the published priors
#' dfm_priors("ind_dfm")
#'
#' # let the data speak more
#' dfm_priors("ind_dfm", type = "uninformative")
#'
#' # override one tunable prior
#' dfm_priors("fcast_dfm", sigma = list(c0 = 3, d0 = 1e-6))
#'
#' @seealso [ind_dfm()], [fcast_dfm()]
#' @family model specification
#' @export
dfm_priors <- function(model = c("ind_dfm", "fcast_dfm"),
                       type = c("default", "uninformative", "informative"),
                       ...){

  model <- match.arg(model)
  type <- match.arg(type)

  spec <- switch(model,
                 ind_dfm = priors_ind_dfm(type),
                 fcast_dfm = priors_fcast_dfm(type))

  structural <- structural_priors(model)

  overrides <- list(...)
  if(length(overrides)){

    unknown <- setdiff(names(overrides), names(spec))
    if(length(unknown)){
      stop("Unknown prior", if(length(unknown) > 1) "s" else "", " for model \"",
           model, "\": ", paste(sQuote(unknown), collapse = ", "), ".\n",
           "  Available: ", paste(names(spec), collapse = ", "), ".",
           call. = FALSE)
    }

    touched <- intersect(names(overrides), structural)
    if(length(touched)){
      warning("Overriding the structural prior",
              if(length(touched) > 1) "s " else " ",
              paste(sQuote(touched), collapse = ", "),
              " changes how `", model, "` is identified.\n",
              "  ", structural_warning(model), "\n",
              "  The result is no longer the published model.",
              call. = FALSE)
    }

    for(nm in names(overrides)) spec[[nm]][names(overrides[[nm]])] <- overrides[[nm]]
  }

  structure(c(spec,
              list(model = model,
                   type = type,
                   structural = structural,
                   structural_modified = any(names(overrides) %in% structural))),
            class = "dfm_priors")

}


#' Priors for the single-factor, target-anchored model
#'
#' `NULL` entries scale with the data and are resolved by
#' [resolve_priors()]; see [dfm_priors()].
#'
#' @noRd
priors_ind_dfm <- function(type){

  base <- list(
    # STRUCTURAL: these two are the target anchoring
    sigma_target = list(c0 = NULL, d0 = NULL),   # NULL -> t and t * 1e-3
    rho_target   = list(r0 = 0, R0 = 1e-9),
    # tunable
    sigma_other  = list(c0 = 3, d0 = 5e-2),
    rho_other    = list(r0 = 0, R0 = 5),
    lambda       = list(b0 = 0, B0 = 1),
    phi          = list(a0 = 0, A0 = NULL),      # NULL -> 0.12 / (1:p)^2
    omega        = list(k0 = NULL, l0 = NULL),   # NULL -> t and t * 1e-2
    factor_var   = list(c0 = 3, d0 = 1e-2)       # used when SV is off
  )

  switch(type,
         default = base,
         uninformative = utils::modifyList(base, list(
           sigma_other = list(c0 = 3, d0 = 1e-9),
           rho_other   = list(r0 = 0, R0 = 1e3),
           lambda      = list(b0 = 0, B0 = 1e3),
           phi         = list(a0 = 0, A0 = 1e3),
           omega       = list(k0 = 3, l0 = 1e-9),
           factor_var  = list(c0 = 3, d0 = 1e-9))),
         informative = utils::modifyList(base, list(
           sigma_other = list(c0 = 10, d0 = 5e-1),
           rho_other   = list(r0 = 0, R0 = 1),
           lambda      = list(b0 = 0, B0 = 0.1),
           phi         = list(a0 = 0, A0 = 0.01),
           factor_var  = list(c0 = 10, d0 = 1e-1))))

}


#' Priors for the multi-factor, rotation-identified model
#'
#' @noRd
priors_fcast_dfm <- function(type){

  base <- list(
    # STRUCTURAL: diffuseness is required by the post-hoc rotation
    lambda = list(b0 = 0, B0 = 1e9),
    # tunable
    sigma  = list(c0 = 3, d0 = 1e-9),
    rho    = list(r0 = 0, R0 = NULL),   # NULL -> 1 / t
    omega  = list(c0 = 3, d0 = 1)
  )

  switch(type,
         default = base,
         uninformative = utils::modifyList(base, list(
           sigma = list(c0 = 3, d0 = 1e-12),
           rho   = list(r0 = 0, R0 = 1e3),
           omega = list(c0 = 3, d0 = 1e-9))),
         informative = utils::modifyList(base, list(
           sigma = list(c0 = 10, d0 = 1e-3),
           rho   = list(r0 = 0, R0 = 0.1),
           omega = list(c0 = 10, d0 = 10))))

}


#' Which priors carry each model's identification
#'
#' @noRd
structural_priors <- function(model){
  switch(model,
         ind_dfm = c("sigma_target", "rho_target"),
         fcast_dfm = "lambda")
}


#' @noRd
structural_warning <- function(model){
  switch(model,
         ind_dfm = paste("The factor is anchored to `target` by shrinking that",
                         "series' measurement error and serial correlation toward",
                         "zero; loosening these means the factor no longer tracks it."),
         fcast_dfm = paste("The loadings must stay diffuse for the post-hoc",
                           "rotation to identify the model."))
}


#' Resolve data-dependent priors to numbers
#'
#' Fills in the entries stored as `NULL` -- those whose published default is a
#' rule in terms of the sample length `t` or the number of lags `p` -- and
#' leaves any value the user supplied untouched.
#'
#' @noRd
resolve_priors <- function(priors, t, p){

  fill <- function(x, value) if(is.null(x)) value else x

  if(priors$model == "ind_dfm"){

    priors$sigma_target$c0 <- fill(priors$sigma_target$c0, t)
    priors$sigma_target$d0 <- fill(priors$sigma_target$d0, t * 1e-3)
    priors$omega$k0 <- fill(priors$omega$k0, t)
    priors$omega$l0 <- fill(priors$omega$l0, t * 1e-2)
    # a scalar keeps the 1/(lag^2) decay of the published prior
    a0 <- fill(priors$phi$A0, 0.12)
    priors$phi$A0 <- if(length(a0) == 1) a0 / ((1:p)^2) else a0

  } else {

    priors$rho$R0 <- fill(priors$rho$R0, 1 / t)

  }

  priors

}


#' Check that a prior specification matches the model being fitted
#'
#' @noRd
check_priors <- function(priors, model){

  if(!inherits(priors, "dfm_priors")){
    stop("`priors` must be built with `dfm_priors()`, not a plain ",
         class(priors)[1], ".", call. = FALSE)
  }
  if(!identical(priors$model, model)){
    stop("`priors` was built for model \"", priors$model,
         "\" but was passed to `", model, "()`.\n",
         "  Use `dfm_priors(\"", model, "\", ...)` instead.", call. = FALSE)
  }

  invisible(priors)

}


#' Print a prior specification
#'
#' @param x An object of class `"dfm_priors"` from [dfm_priors()].
#' @param ... Ignored, present for compatibility with the [print()] generic.
#'
#' @return `x`, invisibly.
#'
#' @examples
#' dfm_priors("ind_dfm")
#'
#' @method print dfm_priors
#' @export
print.dfm_priors <- function(x, ...){

  cat("Priors for ", x$model, "()  [type: ", x$type, "]\n\n", sep = "")

  meta <- c("model", "type", "structural", "structural_modified")
  for(nm in setdiff(names(x), meta)){

    tag <- if(nm %in% x$structural) "  [structural]" else ""
    vals <- vapply(names(x[[nm]]), function(k){
      v <- x[[nm]][[k]]
      if(is.null(v)) paste0(k, " = <from data>") else paste0(k, " = ", format(v, digits = 4))
    }, character(1))
    cat(sprintf("  %-13s %s%s\n", nm, paste(vals, collapse = ", "), tag))

  }

  if(isTRUE(x$structural_modified)){
    cat("\n  ! A structural prior has been overridden - this is no longer the\n",
        "    published model. See ?dfm_priors.\n", sep = "")
  }

  cat("\n<from data> entries follow the model's published rule in terms of t or p.\n")

  invisible(x)

}
