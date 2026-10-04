# The package's plotting layer (#112).
#
# Two things live here, deliberately together:
#
#   1. ONE shared visual style - a palette, a theme and a credible-band layer -
#      used by every ggplot the package draws from a fit object. Any plot method
#      added later (contributions, news decomposition, convergence diagnostics,
#      factor-count selection) should build on these three rather than inventing
#      its own colours and theme, which is the whole point of collecting them in
#      one file.
#   2. The views behind `plot(fit, type = ...)`. The S3 methods themselves stay
#      in methods.R with the rest of the generics; they are one-line delegations
#      to fit_plot() below.
#
# Every view returns a ggplot object rather than drawing directly, so callers
# can modify it. Returning it *visibly* is what makes `plot(fit)` still draw at
# the console: R auto-prints the returned object.


# ------------------------------------------------------------- style ----

#' The package's plot palette
#'
#' Roles, not a ramp: which colour a mark gets is decided by what the mark
#' *means*, so the same quantity keeps the same colour across every view.
#'
#' @noRd
mfbdfm_pal <- function(){
  c(estimate  = "#1b4f72",   # anything the model produces
    band      = "#5dade2",   # credible interval around an estimate
    observed  = "#c0392b",   # data as supplied
    reference = "grey45")    # zero lines, axes furniture
}


#' Qualitative colours for plots that separate more than two roles
#'
#' Deliberately short and fixed. Views that need more categories than this
#' should facet instead of recycling colours.
#'
#' @noRd
mfbdfm_pal_discrete <- function(n){
  base <- c("#1b4f72", "#c0392b", "#117a65", "#b9770e", "#6c3483", "#5d6d7e")
  if(n > length(base)) base <- rep(base, length.out = n)
  base[seq_len(n)]
}


#' The package's plot theme
#'
#' @noRd
#' @importFrom ggplot2 theme_minimal theme element_text element_blank rel
theme_mfbdfm <- function(base_size = 11){

  theme_minimal(base_size = base_size) +
    theme(plot.title      = element_text(face = "bold", size = rel(1.05)),
          plot.subtitle   = element_text(colour = "grey35", size = rel(0.9)),
          legend.title    = element_blank(),
          legend.position = "bottom",
          panel.grid.minor = element_blank(),
          strip.text      = element_text(face = "bold", size = rel(0.85)))

}


#' The shared credible-band layer
#'
#' Expects `lower`/`upper` columns in the plot data and inherits `x`.
#'
#' @noRd
#' @importFrom ggplot2 geom_ribbon aes
#' @importFrom rlang .data
mfbdfm_band <- function(alpha = 0.3, fill = unname(mfbdfm_pal()["band"])){

  geom_ribbon(aes(ymin = .data$lower, ymax = .data$upper),
              fill = fill, alpha = alpha, colour = NA)

}


#' "95% credible band", from a coverage level
#'
#' @noRd
band_label <- function(level){
  paste0(format(100*level, trim = TRUE), "% credible band")
}


# -------------------------------------------------------- shared prep ----

#' Mean and symmetric Gaussian band of a (possibly multi-column) `ts`
#'
#' The fits store posterior means and variances, not draws, so every band in
#' the package is a normal approximation at the posterior mean - the same one
#' `as.data.frame()` and `print.fcast_dfm()` already use.
#'
#' @noRd
#' @importFrom stats qnorm time
band_frame <- function(mean_ts, var_ts, level, labels = NULL){

  z <- qnorm(1 - (1 - level)/2)
  # unclass(): a column of a `ts` matrix is itself a `ts`, and rbind()-ing
  # data frames whose columns carry a tsp attribute is an error
  m <- unclass(as.matrix(mean_ts))
  s <- sqrt(unclass(as.matrix(var_ts)))

  if(is.null(labels)){
    labels <- if(ncol(m) == 1) "factor" else paste("factor", seq_len(ncol(m)))
  }

  tt <- as.numeric(time(mean_ts))

  do.call(rbind, lapply(seq_len(ncol(m)), function(j){

    data.frame(time = tt,
               series = factor(labels[j], levels = labels),
               mean = m[, j],
               lower = m[, j] - z*s[, j],
               upper = m[, j] + z*s[, j],
               stringsAsFactors = FALSE)

  }))

}


#' Resolve the `series` argument to a vector of series keys
#'
#' Accepts keys or column positions, and names the offending value rather than
#' failing later inside a subset.
#'
#' @noRd
resolve_plot_series <- function(x, series){

  keys <- x$inventory$key

  if(is.null(series)) return(keys)

  if(is.numeric(series)){

    ok <- !is.na(series) & series == as.integer(series) &
      series >= 1 & series <= length(keys)
    if(!all(ok)){
      stop("`series` must index the fit's ", length(keys),
           " series; out of range: ",
           paste(series[!ok], collapse = ", "), ".", call. = FALSE)
    }

    return(keys[as.integer(series)])

  }

  if(!is.character(series)){
    stop("`series` must be a character vector of series names or a numeric ",
         "vector of column positions.", call. = FALSE)
  }

  bad <- setdiff(series, keys)
  if(length(bad)){
    stop("`series` names series not in the fit: ", paste(bad, collapse = ", "),
         ". Available: ", paste(utils::head(keys, 10), collapse = ", "),
         if(length(keys) > 10) ", ..." else "", ".", call. = FALSE)
  }

  series

}


#' A `ts` matrix from a fit, with the inventory's keys as column names
#'
#' `$data` carries them, `$data_augmented` does not in an `ind_dfm()` fit, so
#' they are (re)attached here rather than relied on.
#'
#' @noRd
#' @importFrom stats time
fit_matrix_long <- function(mat, keys, kind){

  # unclass(), as in band_frame(): a column of a `ts` matrix is still a `ts`
  m <- unclass(as.matrix(mat))
  colnames(m) <- keys
  tt <- as.numeric(time(mat))

  do.call(rbind, lapply(seq_along(keys), function(j){

    data.frame(time = tt, series = keys[j], kind = kind,
               value = m[, j], stringsAsFactors = FALSE)

  }))

}


# -------------------------------------------------------------- views ----

#' Dispatch for `plot()` on either fit class
#'
#' @noRd
fit_plot <- function(x,
                     type = c("factor", "nowcast", "loadings", "residuals",
                              "volatility", "fit"),
                     series = NULL, level = 0.95, ...){

  type <- match.arg(type)

  if(!is.numeric(level) || length(level) != 1L || is.na(level) ||
     level <= 0 || level >= 1){
    stop("`level` must be a single number strictly between 0 and 1, not ",
         deparse(level), ".", call. = FALSE)
  }

  switch(type,
         factor     = plot_view_factor(x, level),
         nowcast    = plot_view_nowcast(x, level),
         loadings   = plot_view_loadings(x),
         residuals  = plot_view_residuals(x, series),
         volatility = plot_view_volatility(x),
         fit        = plot_view_fit(x, series))

}


#' @noRd
#' @importFrom ggplot2 ggplot aes geom_line facet_wrap vars labs
#' @importFrom rlang .data
plot_view_factor <- function(x, level){

  pal <- mfbdfm_pal()
  df <- band_frame(x$factor, x$factor_var, level)

  p <- ggplot(df, aes(x = .data$time, y = .data$mean)) +
    mfbdfm_band() +
    geom_line(colour = unname(pal["estimate"])) +
    labs(x = NULL, y = "factor",
         title = if(nlevels(df$series) > 1) "Estimated factors" else "Estimated factor",
         subtitle = band_label(level)) +
    theme_mfbdfm()

  if(nlevels(df$series) > 1){
    p <- p + facet_wrap(vars(.data$series), ncol = 1, scales = "free_y")
  }

  p

}


#' @noRd
#' @importFrom ggplot2 ggplot aes geom_line geom_point scale_colour_manual labs
#' @importFrom stats time
#' @importFrom rlang .data
plot_view_nowcast <- function(x, level){

  pal <- mfbdfm_pal()
  df <- band_frame(x$nowcast, x$nowcast_var, level, labels = x$target)

  p <- ggplot(df, aes(x = .data$time, y = .data$mean)) +
    mfbdfm_band() +
    geom_line(aes(colour = "nowcast"))

  obs <- x$data_raw[[x$target]]
  if(!is.null(obs)){

    obs_df <- data.frame(time = as.numeric(time(obs)),
                         observed = as.numeric(obs))
    obs_df <- obs_df[!is.na(obs_df$observed), , drop = FALSE]

    if(nrow(obs_df)){
      p <- p + geom_point(data = obs_df,
                          aes(x = .data$time, y = .data$observed,
                              colour = "observed"),
                          inherit.aes = FALSE, size = 1.4)
    }

  }

  p +
    scale_colour_manual(values = c(nowcast = unname(pal["estimate"]),
                                   observed = unname(pal["observed"]))) +
    labs(x = NULL, y = x$target,
         title = paste0("Nowcast of ", x$target),
         subtitle = band_label(level)) +
    theme_mfbdfm()

}


#' @noRd
#' @importFrom ggplot2 ggplot aes geom_segment geom_point geom_vline facet_wrap
#'   vars labs
#' @importFrom rlang .data
plot_view_loadings <- function(x){

  pal <- mfbdfm_pal()

  # the same numbers mfbdfm_table_loadings() reports, so the plot and the table
  # cannot disagree; the interval comes from $pars_dist (#113) and is NA on a
  # fit saved before that existed
  tab <- mfbdfm_table_loadings(x)
  flabs <- unique(tab$factor)
  has_interval <- any(is.finite(tab$lower))

  # one common ordering across facets, taken from the first factor - a per-facet
  # ordering would put the same series in a different row of each panel
  first <- tab[tab$factor == flabs[1], ]
  ord <- first$series[order(first$mean)]

  df <- data.frame(series = factor(tab$series, levels = ord),
                   factor = factor(tab$factor, levels = flabs),
                   loading = tab$mean,
                   lower = tab$lower,
                   upper = tab$upper,
                   stringsAsFactors = FALSE)

  p <- ggplot(df, aes(x = .data$loading, y = .data$series)) +
    geom_vline(xintercept = 0, colour = unname(pal["reference"]),
               linewidth = 0.3)

  if(has_interval){
    p <- p + geom_segment(aes(x = .data$lower, xend = .data$upper,
                              y = .data$series, yend = .data$series),
                          colour = unname(pal["band"]), linewidth = 1.2,
                          na.rm = TRUE)
  } else {
    p <- p + geom_segment(aes(x = 0, xend = .data$loading,
                              y = .data$series, yend = .data$series),
                          colour = "grey75")
  }

  p <- p +
    geom_point(colour = unname(pal["estimate"]), size = 2) +
    labs(x = "loading", y = NULL,
         title = "Factor loadings",
         subtitle = if(has_interval) "posterior mean and 95% interval"
                    else "posterior mean (this fit stores no interval)") +
    theme_mfbdfm()

  if(length(flabs) > 1) p <- p + facet_wrap(vars(.data$factor), nrow = 1)

  p

}


#' The common component of a fit, or an error saying why there is none
#'
#' `"residuals"` and `"fit"` are built on [fit_common_component()] rather than
#' on `fitted()`/`residuals()`: `fitted()` is the augmented dataset, whose
#' observed entries the sampler pins to the data with a `1e-9` measurement
#' prior, so residuals against it are noise of order `1e-5` and observed versus
#' fitted is the data drawn twice. An `ind_dfm()` fit saved before
#' `$factor_std` existed has no common component to draw.
#'
#' @noRd
plot_common_component <- function(x, view){

  cc <- fit_common_component(x)
  if(is.null(cc)){
    stop("`plot(type = \"", view, "\")` needs the factor on the model's ",
         "standardized scale, which this fit does not store. Refit with the ",
         "current version of mfbdfm (an ind_dfm() fit gained `$factor_std` in ",
         "0.1.0.9000).", call. = FALSE)
  }
  cc

}


#' Observed values in long form, with the unobserved periods as NA
#'
#' @noRd
plot_observed_long <- function(x){

  obs <- fit_matrix_long(x$data, x$inventory$key, "observed")
  # 0 encodes "not observed" in the prepared data
  obs$value[obs$value == 0] <- NA_real_
  obs

}


#' @noRd
#' @importFrom ggplot2 ggplot aes geom_line geom_point geom_hline facet_wrap
#'   vars labs
#' @importFrom rlang .data
plot_view_residuals <- function(x, series){

  pal <- mfbdfm_pal()
  keys <- resolve_plot_series(x, series)

  cc <- plot_common_component(x, "residuals")
  df <- plot_observed_long(x)
  df$value <- df$value - fit_matrix_long(cc, x$inventory$key, "cc")$value
  df$kind <- "residual"
  df <- df[df$series %in% keys, , drop = FALSE]
  df$series <- factor(df$series, levels = keys)

  ggplot(df, aes(x = .data$time, y = .data$value)) +
    geom_hline(yintercept = 0, colour = unname(pal["reference"]),
               linewidth = 0.3) +
    geom_line(colour = unname(pal["estimate"]), na.rm = TRUE) +
    # the points are not decoration: a quarterly series in a weekly model is
    # observed once every k periods, so every one of its residuals is an
    # isolated non-NA surrounded by NAs and geom_line() alone draws an empty
    # panel for it
    geom_point(colour = unname(pal["estimate"]), size = 0.6, na.rm = TRUE) +
    facet_wrap(vars(.data$series), scales = "free_y") +
    labs(x = NULL, y = "residual",
         title = "Residuals from the common component",
         subtitle = "observed minus loadings x factors, standardized scale; gaps are unobserved periods") +
    theme_mfbdfm()

}


#' @noRd
#' @importFrom ggplot2 ggplot aes geom_line labs
#' @importFrom stats time
#' @importFrom rlang .data
plot_view_volatility <- function(x){

  pal <- mfbdfm_pal()
  h <- x$pars$h
  hv <- as.numeric(h)

  if(diff(range(hv)) < 1e-12){
    message("The volatility path is constant (stochastic_volatility = FALSE), ",
            "so there is nothing to plot. The constant factor innovation ",
            "sd is ", signif(exp(hv[1]), 4), ".")
    return(invisible(NULL))
  }

  df <- data.frame(time = as.numeric(time(h)), value = exp(hv))

  ggplot(df, aes(x = .data$time, y = .data$value)) +
    geom_line(colour = unname(pal["estimate"])) +
    labs(x = NULL, y = "exp(h)",
         title = "Stochastic volatility of the factor innovation",
         subtitle = "posterior mean of exp(h), a standard deviation") +
    theme_mfbdfm()

}


#' @noRd
#' @importFrom ggplot2 ggplot aes geom_line geom_point facet_wrap vars
#'   scale_colour_manual labs
#' @importFrom rlang .data
plot_view_fit <- function(x, series){

  pal <- mfbdfm_pal()
  keys <- resolve_plot_series(x, series)

  cc <- plot_common_component(x, "fit")
  obs <- plot_observed_long(x)
  fit <- fit_matrix_long(cc, x$inventory$key, "common component")

  df <- rbind(obs, fit)
  df <- df[df$series %in% keys, , drop = FALSE]
  df$series <- factor(df$series, levels = keys)

  ggplot(df, aes(x = .data$time, y = .data$value, colour = .data$kind)) +
    geom_line(data = df[df$kind == "common component", , drop = FALSE],
              na.rm = TRUE) +
    geom_point(data = df[df$kind == "observed", , drop = FALSE],
               size = 0.9, na.rm = TRUE) +
    facet_wrap(vars(.data$series), scales = "free_y") +
    scale_colour_manual(values = c(observed = unname(pal["observed"]),
                                   `common component` = unname(pal["estimate"]))) +
    labs(x = NULL, y = NULL,
         title = "Observed values and the common component",
         subtitle = "loadings x factors, standardized scale; observed points are missing where a series was not observed") +
    theme_mfbdfm()

}
