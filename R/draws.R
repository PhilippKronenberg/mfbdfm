# Retained posterior draws (#110).
#
# Both samplers already hold every retained draw in memory for the whole fit -
# `run_sampling()` builds `par_save`, `run_sampling_fcast()` the packed
# `theta_out` - and until now both were averaged and dropped when the sampler
# returned. Keeping them is therefore a matter of NOT DISCARDING, not of
# changing the loop, which is what makes the "sampling must be untouched"
# requirement easy rather than delicate: nothing here consumes RNG, nothing here
# runs inside the chain, and `dev/baseline.R`'s snapshot is unaffected.
#
# Two things live here: the `mfbdfm_draws` container (built once per fit, from
# draws the sampler already produced) and the trace/density plots over it.
# `mfbdfm_diagnostics()` in diagnostics.R is the statistical companion.
#
# Column naming is the contract between this file, diagnostics.R and the plots:
# one column per scalar parameter, named `block[label]`, so that a column name
# alone says which block a number came from.


# ------------------------------------------------------------- building ----

#' Name the columns of a parameter block
#'
#' @noRd
draws_block_names <- function(block, labels){
  if(is.null(labels)) return(block)
  paste0(block, "[", labels, "]")
}


#' Assemble the draws container
#'
#' @param parameters Iterations x parameters matrix of post-burn-in draws.
#' @param burn Optional iterations x parameters matrix of burn-in draws, with
#'   the same columns as `parameters`.
#' @param nowcast,factor Optional draw matrices, post-burn-in only.
#'
#' @noRd
new_mfbdfm_draws <- function(parameters, burn = NULL, nowcast = NULL,
                             factor = NULL, blocks, model, target,
                             length_sample, burn_in, thinning){

  # the sampler's own iteration number for each retained row, so a trace plot
  # has a meaningful x axis and the burn-in phase can be shaded rather than
  # silently prepended
  it_kept <- burn_in + thinning*seq_len(length_sample)
  n_burn <- if(is.null(burn)) 0L else nrow(burn)

  if(n_burn){
    parameters <- rbind(burn, parameters)
    it_pars <- c(seq_len(n_burn), it_kept)
  } else {
    it_pars <- it_kept
  }

  structure(list(parameters = parameters,
                 nowcast = nowcast,
                 factor = factor,
                 info = list(model = model,
                             target = target,
                             blocks = blocks,
                             length_sample = length_sample,
                             burn_in = burn_in,
                             thinning = thinning,
                             n_burn_in = n_burn,
                             iteration = it_pars,
                             iteration_kept = it_kept)),
            class = "mfbdfm_draws")

}


#' Retained draws of the single-factor model
#'
#' Built from the draws [run_sampling()] has already produced, after the
#' posterior means have been taken, so nothing is re-simulated and no RNG is
#' consumed.
#'
#' `flist` is the list of rescaled, annualized factor paths `ind_dfm()` builds
#' anyway; passing it in rather than `par_save$f` is what makes
#' `colMeans(draws$factor)` reproduce `fit$factor` instead of a quantity on the
#' sampler's internal scale.
#'
#' @noRd
build_draws_ind <- function(par_save, flist, inventory, target, s, t,
                            stochastic_volatility, control,
                            length_sample, burn_in, thinning){

  keys <- inventory$key
  n <- length(keys)
  p <- length(as.numeric(par_save$phi[[1]]))

  # one row per draw, columns in block order
  pars_of <- function(lambda, phi, sigma, rho, omega, h){
    c(as.numeric(lambda), as.numeric(phi), as.numeric(sigma), as.numeric(rho),
      if(stochastic_volatility){
        c(as.numeric(omega),
          mean(as.numeric(h)[(s + 1):(t + s)]),
          as.numeric(h)[t + s])
      } else {
        # h is constant within a draw when the volatility path is switched off
        # (draw_factor_variance() repeats one value over every period), so the
        # free parameter is the single constant variance exp(2h) - and omega is
        # never drawn at all, which is why reporting it would be a silent wrong
        # answer. Same choice as pars_dist_ind() in tables.R.
        exp(2*as.numeric(h)[s + 1])
      })
  }

  nms <- c(draws_block_names("lambda", keys),
           paste0("phi", seq_len(p)),
           draws_block_names("sigma", keys),
           draws_block_names("rho", keys),
           if(stochastic_volatility) c("omega", "h_mean", "h_last") else "factor_var")

  blocks <- c(rep("lambda", n), rep("phi", p), rep("sigma", n), rep("rho", n),
              if(stochastic_volatility) c("omega", "h", "h") else "factor_var")
  names(blocks) <- nms

  M <- t(vapply(seq_along(par_save$lambda), function(i){
    pars_of(par_save$lambda[[i]], par_save$phi[[i]], par_save$sigma[[i]],
            par_save$rho[[i]], par_save$omega[[i]], par_save$h[[i]])
  }, numeric(length(nms))))
  colnames(M) <- nms

  B <- NULL
  if(!is.null(par_save$burn)){
    B <- t(vapply(seq_along(par_save$burn$lambda), function(i){
      pars_of(par_save$burn$lambda[[i]], par_save$burn$phi[[i]],
              par_save$burn$sigma[[i]], par_save$burn$rho[[i]],
              par_save$burn$omega[[i]], par_save$burn$h[[i]])
    }, numeric(length(nms))))
    colnames(B) <- nms
  }

  # nowcast draws, at the target's own frequency
  NC <- t(vapply(par_save$ncast, as.numeric, numeric(length(par_save$ncast[[1]]))))
  colnames(NC) <- draws_block_names("nowcast",
                                    format_draw_time(stats::time(par_save$ncast[[1]])))

  FD <- NULL
  if(isTRUE(control$keep_factor_draws)){
    FD <- t(vapply(flist, as.numeric, numeric(length(flist[[1]]))))
    colnames(FD) <- draws_block_names("factor",
                                      format_draw_time(stats::time(flist[[1]])))
  }

  new_mfbdfm_draws(parameters = M, burn = B, nowcast = NC, factor = FD,
                   blocks = blocks, model = "ind_dfm", target = target,
                   length_sample = length_sample, burn_in = burn_in,
                   thinning = thinning)

}


#' Retained draws of the multi-factor model
#'
#' Read out of `rlist`, i.e. **after** [run_rotation_fcast()] and
#' [run_identification_fcast()]. An unrotated draw is only determined up to a
#' `q x q` rotation, so a trace plot of one would show the rotation wandering
#' rather than the chain mixing.
#'
#' `omega` is not packed into `theta`, so [run_sampling_fcast()] returns its
#' draws alongside; it sits outside the rotational indeterminacy
#' (`apply_rotation_fcast()` touches only the `lambda` and `phi` blocks), so it
#' is comparable across iterations exactly as stored.
#'
#' @noRd
build_draws_fcast <- function(rlist, omega_draws, f_draws, nowcast_draws,
                              nowcast_time, factor_time, inventory, target,
                              n, q, p, s, t,
                              stochastic_volatility, control,
                              length_sample, burn_in, thinning){

  keys <- inventory$key

  # omega rides along from the sampler; NA rather than an error if a caller
  # evaluates draws it did not produce
  if(is.null(omega_draws)) omega_draws <- rep(NA_real_, length(rlist))

  npar <- n*q + p*q^2 + 2*n
  ix_h <- npar + n*t + seq_len(t + s)

  lam_lab <- paste0(rep(keys, times = q), ",f", rep(seq_len(q), each = n))
  phi_lab <- unlist(lapply(seq_len(p), function(px)
    paste0("phi", px, "[", rep(seq_len(q), times = q), ",",
           rep(seq_len(q), each = q), "]")))

  nms <- c(draws_block_names("lambda", lam_lab),
           phi_lab,
           draws_block_names("sigma", keys),
           draws_block_names("rho", keys),
           if(stochastic_volatility) c("omega", "h_mean", "h_last") else NULL)

  blocks <- c(rep("lambda", n*q), rep("phi", p*q^2), rep("sigma", n),
              rep("rho", n),
              if(stochastic_volatility) c("omega", "h", "h") else NULL)
  names(blocks) <- nms

  M <- t(vapply(seq_along(rlist), function(i){
    rx <- rlist[[i]]
    hx <- as.numeric(rx[ix_h, ])
    c(as.numeric(rx[seq_len(npar), ]),
      if(stochastic_volatility) c(omega_draws[i], mean(hx), hx[t + s]) else NULL)
  }, numeric(length(nms))))
  colnames(M) <- nms

  NC <- t(nowcast_draws)
  colnames(NC) <- draws_block_names("nowcast", format_draw_time(nowcast_time))

  FD <- NULL
  if(isTRUE(control$keep_factor_draws)){
    FD <- t(vapply(f_draws, function(fx) as.numeric(as.matrix(fx)),
                   numeric((t + s)*q)))
    ftime <- format_draw_time(factor_time)
    colnames(FD) <- paste0("factor", rep(seq_len(q), each = t + s),
                           "[", rep(ftime, times = q), "]")
  }

  new_mfbdfm_draws(parameters = M, burn = NULL, nowcast = NC, factor = FD,
                   blocks = blocks, model = "fcast_dfm", target = target,
                   length_sample = length_sample, burn_in = burn_in,
                   thinning = thinning)

}


#' Period labels for a draw matrix's columns
#'
#' @noRd
format_draw_time <- function(x){
  formatC(as.numeric(x), format = "f", digits = 3)
}


# ------------------------------------------------------------ selection ----

#' Every column a draws object offers, with its block
#'
#' @noRd
draws_columns <- function(x){

  out <- x$info$blocks
  if(!is.null(x$nowcast)){
    nc <- rep("nowcast", ncol(x$nowcast)); names(nc) <- colnames(x$nowcast)
    out <- c(out, nc)
  }
  if(!is.null(x$factor)){
    fc <- rep("factor", ncol(x$factor)); names(fc) <- colnames(x$factor)
    out <- c(out, fc)
  }
  out

}


#' Resolve `which` to a vector of column names
#'
#' Accepts column names, block names (`"lambda"`, `"phi"`, ..., `"nowcast"`,
#' `"factor"`), `"parameters"` for every parameter column, `"all"` for
#' everything, or column positions. Names the offending value rather than
#' failing later inside a subset.
#'
#' @noRd
resolve_draws_which <- function(x, which){

  cols <- draws_columns(x)
  all_nms <- names(cols)
  par_nms <- names(x$info$blocks)

  if(is.null(which)) return(default_draws_which(x))

  if(is.numeric(which)){
    bad <- which[which < 1 | which > length(all_nms) | which != round(which)]
    if(length(bad)){
      stop("`which` must index the available draw columns (1:", length(all_nms),
           "); got ", paste(bad, collapse = ", "), ".", call. = FALSE)
    }
    return(all_nms[which])
  }

  if(!is.character(which)){
    stop("`which` must be a character vector of column or block names, a ",
         "vector of column positions, or NULL, not a ", class(which)[1], ".",
         call. = FALSE)
  }

  if(identical(which, "all")) return(all_nms)
  if(identical(which, "parameters")) return(par_nms)

  out <- unlist(lapply(which, function(w){
    if(w %in% all_nms) return(w)
    hit <- all_nms[cols == w]
    if(length(hit)) return(hit)
    if(identical(w, "parameters")) return(par_nms)
    stop("`which` names \"", w, "\", which is neither a draw column nor a ",
         "block of this fit.\n  Blocks: ",
         paste(unique(cols), collapse = ", "), ".", call. = FALSE)
  }), use.names = FALSE)

  unique(out)

}


#' The readable default selection for plots
#'
#' The factor VAR coefficients and the volatility parameter -- the two blocks
#' whose mixing governs everything else -- plus the three largest loadings and
#' the latest nowcast. Deliberately a handful of panels rather than one per
#' series: `which = "lambda"` asks for all of them.
#'
#' Constant columns are skipped, since a trace plot of a parameter that is
#' pinned by the identification (`lambda[target]` in [ind_dfm()]) or never drawn
#' (`rho` under `serial_correlation = FALSE`) is a flat line carrying no
#' information.
#'
#' @noRd
default_draws_which <- function(x){

  cols <- x$info$blocks
  nms <- names(cols)

  vol <- nms[cols %in% c("omega", "h", "factor_var")]

  lam <- nms[cols == "lambda"]
  if(length(lam)){
    m <- x$parameters[, lam, drop = FALSE]
    keep <- apply(m, 2, function(v) stats::sd(v) > 0)
    lam <- lam[keep]
    if(length(lam)){
      sz <- abs(colMeans(x$parameters[, lam, drop = FALSE]))
      lam <- lam[order(sz, decreasing = TRUE)][seq_len(min(3L, length(lam)))]
    }
  }

  out <- c(nms[cols == "phi"], vol, lam)

  if(!is.null(x$nowcast)) out <- c(out, colnames(x$nowcast)[ncol(x$nowcast)])

  unique(out)

}


#' Post-burn-in draws of the selected columns, as a matrix
#'
#' Always rectangular: burn-in rows exist only for the parameter block, so
#' including them would mean padding the nowcast and factor columns with `NA`.
#' This is the matrix the diagnostics are computed on.
#'
#' @noRd
draws_matrix <- function(x, which = NULL){

  sel <- resolve_draws_which(x, which)
  nb <- x$info$n_burn_in
  keep <- seq_len(nrow(x$parameters))
  if(nb) keep <- keep[-seq_len(nb)]

  out <- lapply(sel, function(w){
    if(w %in% colnames(x$parameters)) return(x$parameters[keep, w])
    if(!is.null(x$nowcast) && w %in% colnames(x$nowcast)) return(x$nowcast[, w])
    x$factor[, w]
  })

  m <- do.call(cbind, out)
  colnames(m) <- sel
  m

}


#' Every draw of the selected columns in long form, burn-in included
#'
#' Keeps each column on the sampler's own iteration index, which is what lets a
#' parameter column (which may carry burn-in rows) and a nowcast column (which
#' never does) appear in the same faceted plot without being silently
#' misaligned.
#'
#' @noRd
draws_long <- function(x, which = NULL){

  sel <- resolve_draws_which(x, which)
  it_all <- x$info$iteration
  it_kept <- x$info$iteration_kept
  burn_in <- x$info$burn_in

  do.call(rbind, lapply(sel, function(w){

    if(w %in% colnames(x$parameters)){
      v <- x$parameters[, w]; it <- it_all
    } else if(!is.null(x$nowcast) && w %in% colnames(x$nowcast)){
      v <- x$nowcast[, w]; it <- it_kept
    } else {
      v <- x$factor[, w]; it <- it_kept
    }

    data.frame(parameter = factor(w, levels = sel),
               iteration = it,
               value = as.numeric(v),
               phase = ifelse(it <= burn_in, "burn-in", "sampling"),
               stringsAsFactors = FALSE)

  }))

}


# --------------------------------------------------------------- methods ----

#' Retained posterior draws of a fitted model
#'
#' The draws both samplers keep internally, returned with the fit instead of
#' being averaged and discarded. This is what makes convergence diagnostics
#' ([mfbdfm_diagnostics()]) and trace/density plots possible after the fact,
#' and what lets any posterior functional be computed from the chain rather
#' than from the stored summaries.
#'
#' @details
#' A fit carries this in `fit$draws` whenever `keep_draws` is `TRUE`, which is
#' the default -- see [dfm_control()] for `keep_draws`, `keep_factor_draws` and
#' `keep_burn_in`, and for the memory each costs.
#'
#' # Structure
#'
#' \describe{
#'   \item{`$parameters`}{Iterations x parameters matrix. One column per
#'     *scalar* parameter, named `block[label]`: `lambda[<series>]`,
#'     `phi1`...`phip` (`phi<lag>[i,j]` for [fcast_dfm()]), `sigma[<series>]`,
#'     `rho[<series>]`, `omega`, and two summaries of the volatility path,
#'     `h_mean` and `h_last`. The path itself is `t+s` long *per draw* and is a
#'     latent state rather than a parameter, so it is summarised rather than
#'     stored in full.}
#'   \item{`$nowcast`}{Iterations x periods matrix of the target's nowcast
#'     draws, at the target's own frequency.}
#'   \item{`$factor`}{Iterations x periods matrix of the factor path (one block
#'     of columns per factor for [fcast_dfm()]), on the **same scale as
#'     `fit$factor`** -- rescaled and annualized for [ind_dfm()], rotated for
#'     [fcast_dfm()] -- so that `colMeans()` reproduces it. `NULL` unless
#'     `keep_factor_draws = TRUE`, since it is the one large component.}
#'   \item{`$info`}{Chain metadata: `model`, `target`, `blocks`,
#'     `length_sample`, `burn_in`, `thinning`, `n_burn_in` (leading rows of
#'     `$parameters` that are burn-in) and the iteration index of each row.}
#' }
#'
#' With `stochastic_volatility = FALSE` the volatility columns differ, because
#' the two models pin the factor's scale in different places (see
#' [ind_dfm()]'s details and CLAUDE.md, "Scale identification"): [ind_dfm()]
#' reports the single estimated constant variance as `factor_var` and has no
#' `omega`, while [fcast_dfm()] has neither, its variance being *fixed* at one.
#'
#' # Burn-in
#'
#' `keep_burn_in = TRUE` ([ind_dfm()] only) prepends the burn-in draws to
#' `$parameters`, so a trace plot can show the chain settling. They are
#' **parameter draws only**: the nowcast and factor draws are derived quantities
#' that the sampler computes for retained iterations, and computing them for the
#' burn-in as well would change the cost of a fit for a plotting convenience.
#' Each row's sampler iteration is recorded in `$info$iteration`, so the two
#' sets are plotted on a common axis rather than concatenated.
#'
#' # Selecting columns
#'
#' `which` accepts column names, block names (`"lambda"`, `"phi"`, `"sigma"`,
#' `"rho"`, `"omega"`, `"h"`, `"nowcast"`, `"factor"`), `"parameters"` for
#' every parameter column, `"all"`, or column positions. The default is a
#' readable subset: the factor VAR coefficients, the volatility parameter, the
#' three largest loadings and the latest nowcast.
#'
#' @param x An object of class `"mfbdfm_draws"`, i.e. `fit$draws`.
#' @param which Columns to use; see "Selecting columns". `NULL` (the default)
#'   is the readable subset.
#' @param ... Passed on to the underlying plotting calls; ignored otherwise.
#'
#' @return `print()` returns `x` invisibly. `as.data.frame()` returns a long
#'   data frame with columns `parameter`, `iteration`, `value` and `phase`.
#'   `as.mcmc()` returns a \pkg{coda} `mcmc` object with `start`/`thin` set from
#'   the chain. `plot()` returns a \pkg{ggplot} object, or a `ggarrange` grid
#'   when `type = "both"`.
#'
#' @examples
#' \donttest{
#' data(mfbdfm_example_data)
#' set.seed(1)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 60, burn_in = 20)
#'
#' fit$draws
#' dim(fit$draws$parameters)
#'
#' # the stored means are the means of the retained draws
#' max(abs(colMeans(fit$draws$parameters[, 1:8]) -
#'           as.numeric(fit$pars$lambda)[1:8]))
#'
#' head(as.data.frame(fit$draws, which = "phi"))
#' }
#'
#' @seealso [mfbdfm_diagnostics()] for convergence statistics over these draws,
#'   [dfm_control()] for the `keep_*` settings, [ind_dfm()] and [fcast_dfm()].
#'
#' @name mfbdfm_draws
#' @family model functions
NULL


#' @rdname mfbdfm_draws
#'
#' @param n_show Number of column names to list.
#'
#' @method print mfbdfm_draws
#' @export
print.mfbdfm_draws <- function(x, n_show = 8, ...){

  i <- x$info
  cat("Retained posterior draws of a ", i$model, " fit\n\n", sep = "")
  cat("  draws kept      : ", i$length_sample,
      if(i$thinning > 1) paste0(" (thinning ", i$thinning, ")") else "",
      "\n", sep = "")
  cat("  burn-in         : ", i$burn_in,
      if(i$n_burn_in) paste0(" (", i$n_burn_in, " retained)") else " (discarded)",
      "\n", sep = "")
  cat("  parameters      : ", ncol(x$parameters), "\n", sep = "")
  cat("  nowcast periods : ",
      if(is.null(x$nowcast)) "-" else ncol(x$nowcast), "\n", sep = "")
  cat("  factor draws    : ",
      if(is.null(x$factor)) "not kept (keep_factor_draws = FALSE)"
      else paste0(ncol(x$factor), " columns"), "\n", sep = "")

  nms <- names(i$blocks)
  cat("\nParameter columns:\n\n  ",
      paste(utils::head(nms, n_show), collapse = ", "),
      if(length(nms) > n_show) paste0(", ... (", length(nms) - n_show, " more)"),
      "\n", sep = "")

  cat("\nBlocks: ", paste(unique(i$blocks), collapse = ", "), "\n", sep = "")
  cat("\nmfbdfm_diagnostics() for convergence statistics; plot() for traces\n")
  cat("and posterior densities; as.mcmc() to hand the chain to coda\n")

  invisible(x)

}


#' @rdname mfbdfm_draws
#'
#' @param row.names,optional Ignored, present for consistency with the generic.
#'
#' @method as.data.frame mfbdfm_draws
#' @export
as.data.frame.mfbdfm_draws <- function(x, row.names = NULL, optional = FALSE,
                                       which = NULL, ...){

  out <- draws_long(x, which)
  out$parameter <- as.character(out$parameter)
  if(!is.null(row.names)) rownames(out) <- row.names
  out

}


#' @rdname mfbdfm_draws
#'
#' @method as.mcmc mfbdfm_draws
#' @export
#' @importFrom coda as.mcmc
as.mcmc.mfbdfm_draws <- function(x, which = NULL, ...){

  # burn-in rows are dropped rather than offered: an mcmc object carries one
  # start/thin pair, and the burn-in is kept at thinning 1 while the retained
  # draws are not, so a single regular series cannot describe both
  m <- draws_matrix(x, which)
  coda::mcmc(m,
             start = x$info$burn_in + x$info$thinning,
             thin = x$info$thinning)

}


# ----------------------------------------------------------------- plots ----

#' @rdname mfbdfm_draws
#'
#' @param type `"both"` (default) for trace and density side by side, as in
#'   \pkg{coda}'s `plot.mcmc`, or `"trace"` / `"density"` for one of them.
#' @param level Coverage of the interval marked on the density, as a
#'   probability.
#' @param max_panels Largest number of parameters to draw. A selection larger
#'   than this is truncated with a warning rather than silently producing an
#'   unreadable grid.
#'
#' @method plot mfbdfm_draws
#' @export
plot.mfbdfm_draws <- function(x, which = NULL,
                              type = c("both", "trace", "density"),
                              level = 0.95, max_panels = 12, ...){

  type <- match.arg(type)

  if(!is.numeric(level) || length(level) != 1L || is.na(level) ||
     level <= 0 || level >= 1){
    stop("`level` must be a single number strictly between 0 and 1, not ",
         deparse(level), ".", call. = FALSE)
  }

  sel <- resolve_draws_which(x, which)
  if(length(sel) > max_panels){
    warning("Selected ", length(sel), " parameters; showing the first ",
            max_panels, ". Raise `max_panels` or narrow `which`.",
            call. = FALSE)
    sel <- sel[seq_len(max_panels)]
  }

  df <- draws_long(x, sel)

  switch(type,
         trace   = draws_trace_plot(df, x),
         density = draws_density_plot(df, x, level),
         both    = ggpubr::ggarrange(draws_trace_plot(df, x),
                                     draws_density_plot(df, x, level),
                                     ncol = 2))

}


#' Trace plot with the running mean overlaid
#'
#' @noRd
#' @importFrom ggplot2 ggplot aes geom_line geom_rect facet_wrap vars labs
#'   scale_colour_manual
#' @importFrom rlang .data
draws_trace_plot <- function(df, x){

  pal <- mfbdfm_pal()

  # running mean per parameter, over the draws in iteration order
  df <- df[order(df$parameter, df$iteration), ]
  df$running <- unlist(lapply(split(df$value, df$parameter), function(v)
    cumsum(v)/seq_along(v)), use.names = FALSE)

  p <- ggplot(df, aes(x = .data$iteration))

  nb <- x$info$n_burn_in
  if(nb){
    p <- p + geom_rect(xmin = -Inf, xmax = x$info$burn_in,
                       ymin = -Inf, ymax = Inf,
                       fill = "grey85", colour = NA,
                       data = data.frame(parameter = unique(df$parameter)),
                       inherit.aes = FALSE)
  }

  p +
    geom_line(aes(y = .data$value, colour = "draw"), linewidth = 0.25) +
    geom_line(aes(y = .data$running, colour = "running mean"), linewidth = 0.6) +
    facet_wrap(vars(.data$parameter), scales = "free_y", ncol = 1) +
    scale_colour_manual(values = c(draw = unname(pal["band"]),
                                   `running mean` = unname(pal["estimate"]))) +
    labs(x = "iteration", y = NULL, title = "Trace",
         subtitle = if(nb) "burn-in shaded" else NULL) +
    theme_mfbdfm()

}


#' Posterior density with the mean and the interval marked
#'
#' @noRd
#' @importFrom ggplot2 ggplot aes geom_density geom_vline facet_wrap vars labs
#'   scale_linetype_manual
#' @importFrom stats sd quantile
#' @importFrom rlang .data
draws_density_plot <- function(df, x, level){

  pal <- mfbdfm_pal()

  # densities are over the posterior, so the burn-in draws are excluded even
  # when they are retained for the trace
  d <- df[df$phase == "sampling", , drop = FALSE]

  probs <- c((1 - level)/2, 1 - (1 - level)/2)
  marks <- do.call(rbind, lapply(split(d$value, d$parameter), stats::quantile,
                                 probs = probs, names = FALSE))
  ann <- data.frame(parameter = factor(levels(d$parameter),
                                       levels = levels(d$parameter)),
                    mean = vapply(split(d$value, d$parameter), mean, numeric(1)),
                    lower = marks[, 1],
                    upper = marks[, 2])

  # a constant chain has no density to estimate; geom_density() would error
  const <- vapply(split(d$value, d$parameter),
                  function(v) stats::sd(v) == 0, logical(1))

  p <- ggplot(d[!const[as.character(d$parameter)], , drop = FALSE],
              aes(x = .data$value))

  if(any(!const)){
    p <- p + geom_density(fill = unname(pal["band"]), alpha = 0.35,
                          colour = unname(pal["estimate"]), linewidth = 0.4)
  }

  p +
    geom_vline(data = ann, aes(xintercept = .data$mean, linetype = "mean"),
               colour = unname(pal["estimate"])) +
    geom_vline(data = ann, aes(xintercept = .data$lower, linetype = "interval"),
               colour = unname(pal["reference"])) +
    geom_vline(data = ann, aes(xintercept = .data$upper, linetype = "interval"),
               colour = unname(pal["reference"])) +
    facet_wrap(vars(.data$parameter), scales = "free", ncol = 1) +
    scale_linetype_manual(values = c(mean = "solid", interval = "dashed")) +
    labs(x = NULL, y = NULL, title = "Posterior density",
         subtitle = paste0("mean and ", band_label(level))) +
    theme_mfbdfm()

}
