#' Fit an AR(1) benchmark model and nowcast the target
#'
#' Estimates an AR(1) model on the target series and produces a one-step
#' nowcast with variance. Used as the benchmark model in the
#' out-of-sample evaluation.
#'
#' @param flows Named list of `ts` objects containing `target`.
#' @param stocks Named list of `ts` objects (unused, kept for a uniform
#'   interface with [run_wai_adj()]).
#' @param target Character, name of the target series in `flows`.
#' @param date Numeric (decimal time), evaluation date used in the file
#'   name when saving.
#' @param dataset_used Character, dataset label used as sub-directory
#'   when saving.
#' @param stochastic_volatility Logical, unused; kept for a uniform
#'   interface with [run_wai_adj()].
#' @param output_dir Directory to save the fit to, or `NULL` (default) to
#'   skip saving. When given, the fit is saved as
#'   `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.
#'
#' @return Invisibly, a list with elements `nowcast` and `nowcast_var`.
#'
#' @importFrom stats arima predict
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' fit <- run_ar(flows = data_ch_dataset_test$flows, stocks = NULL,
#'               target = "ch.seco.gdp.real.gdp.ssa",
#'               date = 2024.5, dataset_used = "example")
#' fit$nowcast
#' }
#' @export
run_ar <- function(flows, stocks, target, date, dataset_used, stochastic_volatility = TRUE,
                   output_dir = NULL){

  gdpdta <- flows[[target]]

  # Estimate AR Model
  fit <- arima(gdpdta,order = c(1,0,0))
  mod <- list("nowcast" = predict(fit, h = 1)$pred,
              "nowcast_var" = predict(fit, h = 1)$se^2)

  if(!is.null(output_dir)){
    fit_dir <- file.path(output_dir, dataset_used)
    dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)
    save(mod, file = file.path(fit_dir, paste0("fit_",round(date,3),".Rda")))
  }

  invisible(mod)

}


#' Fit the WAI dynamic factor model at a given evaluation date
#'
#' Runs [ind_dfm()] with the settings used in the WAI out-of-sample
#' evaluation and windows the factor and nowcast output to the
#' evaluation date.
#'
#' @param flows Named list of `ts` objects containing `target`.
#' @param stocks Named list of `ts` objects.
#' @param target Character, name of the target series in `flows`.
#' @param date Numeric (decimal time), evaluation date; the factor is cut
#'   at this date.
#' @param dataset_used Character, dataset label used as sub-directory
#'   when saving.
#' @param stochastic_volatility Logical, passed to [ind_dfm()] (currently
#'   without effect there).
#' @param output_dir Directory to save the fit to, or `NULL` (default) to
#'   skip saving. When given, the fit is saved as
#'   `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.
#'
#' @return Invisibly, the windowed `ind_dfm` fit object.
#'
#' @importFrom stats window time frequency
#' @examples
#' \dontrun{
#' # Full MCMC estimation at one evaluation date, saving the fit:
#' fit <- run_wai_adj(flows = dat$flows, stocks = dat$stocks,
#'                    target = "ch.seco.gdp.real.gdp.ssa",
#'                    date = 2024.5, dataset_used = "full_RT",
#'                    output_dir = "fits/updated")
#' }
#' @export
run_wai_adj <- function(flows, stocks, target, date, dataset_used, stochastic_volatility = TRUE,
                        output_dir = NULL){

  mod <- ind_dfm(flows = flows,
                 stocks = stocks,
                 target = target,
                 burn_in = 1000,
                 length_sample = 5000,
                 thinning = 1,
                 p = 1, # Number of factor lags in factor state equation.
                 plots = FALSE,
                 stochastic_volatility = stochastic_volatility,
                 serial_correlation = TRUE)

  mod$factor <- window(mod$factor, end = date)
  mod$factor_var <- window(mod$factor_var, end = date)
  mod$nowcast <- window(mod$nowcast, end = as.numeric(tail(time(flows[[target]]),1)) + 0.25)
  mod$nowcast_var <- window(mod$nowcast_var, end = as.numeric(tail(time(flows[[target]]),1)) + 0.25)

  if(!is.null(output_dir)){
    fit_dir <- file.path(output_dir, dataset_used)
    dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)
    save(mod, file = file.path(fit_dir, paste0("fit_",round(date,3),".Rda")))
  }

  invisible(mod)

}


#' Cut a series at `end`, but only when that actually trims something
#'
#' `window(x, end = e)` warns "'end' value not changed" when `e` is at or past
#' the end of `x`. That is the normal case when an evaluation date sits beyond
#' the available data, and the warning carries no information, so it is avoided
#' rather than suppressed.
#'
#' @noRd
#' @importFrom stats window time
trim_to <- function(x, end){

  if(is.null(x) || !length(x)) return(x)

  last <- as.numeric(tail(time(x), 1))
  if(!is.finite(end) || end >= last) return(x)

  window(x, end = end)

}


#' Fit the multi-factor model at a given evaluation date
#'
#' Runs [fcast_dfm()] at one evaluation date and windows the factor and
#' nowcast output to it. The multi-factor counterpart of [run_wai_adj()],
#' with the same arguments, the same file layout and the same
#' no-side-effects-by-default rule, so the two can be driven by the same
#' backcasting loop.
#'
#' @details
#' Note what `target` does and does not do here. [fcast_dfm()] estimates every
#' series jointly and `target` only selects which nowcast is surfaced at the top
#' level -- unlike [run_wai_adj()], where the target is what identifies the
#' factor. Results for every series remain in `ncst` and `data_hf` on the
#' returned object.
#'
#' `q` is the setting that has no counterpart in [run_wai_adj()]: the
#' single-factor model has exactly one factor by construction, so a
#' multi-factor sweep varies `q` where the WAI sweep varies the dataset.
#'
#' @inheritParams run_wai_adj
#' @inheritParams fcast_dfm
#' @param q Integer, number of factors, passed to [fcast_dfm()].
#' @param ncores Integer or `NULL`, passed to [fcast_dfm()] to parallelise
#'   the rotation step.
#' @param control Optional settings from [dfm_control()], passed to
#'   [fcast_dfm()]. Use `dfm_control("fcast_dfm", strict = TRUE)` to run the
#'   rotation as specified in the online appendix.
#'
#' @return Invisibly, the windowed `fcast_dfm` fit object.
#'
#' @seealso [run_wai_adj()] for the single-factor equivalent, [fcast_dfm()]
#'   for the model itself.
#'
#' @importFrom stats window time
#' @examples
#' \donttest{
#' # Short chain on the shipped data; a real evaluation uses the defaults.
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                 stats::window, start = 2021)
#' stocks <- lapply(data_ch_dataset_test$stocks[1:2],
#'                  stats::window, start = 2021)
#' set.seed(1)
#' fit <- run_fcast(flows = flows, stocks = stocks, target = target,
#'                  date = 2023, dataset_used = "example",
#'                  q = 2, length_sample = 20, burn_in = 5)
#' fit$nowcast
#' }
#'
#' @family model fitting functions
#' @export
run_fcast <- function(flows, stocks, target, date, dataset_used,
                      q = 2, p = 1,
                      length_sample = 1000, burn_in = 1000, thinning = 1,
                      stochastic_volatility = TRUE, serial_correlation = TRUE,
                      ncores = NULL, control = NULL, output_dir = NULL){

  mod <- fcast_dfm(flows = flows,
                   stocks = stocks,
                   target = target,
                   q = q,
                   p = p,
                   burn_in = burn_in,
                   length_sample = length_sample,
                   thinning = thinning,
                   plots = FALSE,
                   stochastic_volatility = stochastic_volatility,
                   serial_correlation = serial_correlation,
                   ncores = ncores,
                   control = control)

  # Window to the evaluation date, as run_wai_adj() does. The factor is a
  # q-column matrix here rather than a single series, but window() handles both.
  #
  # trim_to() rather than window() directly: the requested end often lies beyond
  # the series, in which case window() leaves it untouched but emits
  # "'end' value not changed". That warning carries no information here - there
  # was simply nothing to trim - and a wrapper that warns on ordinary use trains
  # people to ignore its warnings.
  mod$factor <- trim_to(mod$factor, date)
  mod$factor_var <- trim_to(mod$factor_var, date)

  target_end <- as.numeric(tail(time(flows[[target]]), 1)) + 0.25
  mod$nowcast <- trim_to(mod$nowcast, target_end)
  mod$nowcast_var <- trim_to(mod$nowcast_var, target_end)

  if(!is.null(output_dir)){
    fit_dir <- file.path(output_dir, dataset_used)
    dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)
    save(mod, file = file.path(fit_dir, paste0("fit_", round(date, 3), ".Rda")))
  }

  invisible(mod)

}


#' Extract the nowcast from a fit object
#'
#' @param fit A fit object from [run_ar()] or [run_wai_adj()].
#' @param model Character, which kind of fit `fit` is: `"ar"` for the AR
#'   benchmark (whose nowcast is already a single value) or `"wai"` for the
#'   dynamic factor model (whose nowcast is a series, of which the last value
#'   is taken). Matched with [match.arg()].
#'
#' @return The nowcast value.
#' @examples
#' fit <- list(nowcast = stats::ts(c(0.3, 0.5), start = 2024, frequency = 4))
#' retrieve_nowcast(fit, model = "wai")
#' @family backcasting functions
#' @export
retrieve_nowcast <- function(fit, model = c("ar", "wai")){

  # previously an if/if chain with no else: an unmatched `model` left `ncst`
  # undefined and the user got "object 'ncst' not found", naming neither the
  # argument nor the expectation
  model <- match.arg(model)

  switch(model,
         ar  = fit$nowcast,
         wai = tail(fit$nowcast, 1))

}

#' Extract the nowcast variance from a fit object
#'
#' @inheritParams retrieve_nowcast
#'
#' @return The nowcast variance.
#' @examples
#' fit <- list(nowcast_var = stats::ts(c(0.02, 0.04), start = 2024, frequency = 4))
#' retrieve_nowcast_var(fit, model = "wai")
#' @family backcasting functions
#' @export
retrieve_nowcast_var <- function(fit, model = c("ar", "wai")){

  model <- match.arg(model)

  switch(model,
         ar  = fit$nowcast_var,
         wai = tail(fit$nowcast_var, 1))

}


#' Extract WAI growth, level and year-over-year tables from a saved fit
#'
#' Loads a saved `ind_dfm` fit (an `.Rda` file containing an object `mod`)
#' and derives long-format tables of the weekly growth rate (with 95%
#' bands), the cumulated level index (rebased to 2020 = 100), and
#' year-over-year growth, as used by the plotting scripts.
#'
#' @param file_path Path to a fit `.Rda` file containing an object `mod`
#'   with elements `factor` and `factor_var`.
#'
#' @return A list of data frames: `tab_wai_yoy_full`, `tab_wai_yoy`,
#'   `tab_gr_full`, `tab_gr_qoq`, `tab_gr_lv`.
#'
#' @importFrom zoo zoo as.yearmon
#' @importFrom tidyr pivot_longer
#' @importFrom dplyr select %>%
#' @importFrom stats ts time window frequency
#' @examples
#' \dontrun{
#' result_wai <- extract_wai_data("fits/updated/full_RT/fit_2025.979.Rda")
#' head(result_wai$tab_gr_qoq)
#' }
#' @export
extract_wai_data <- function(file_path) {
  # Load model object
  load(file_path)
  if (exists("mod", inherits = FALSE)) {
    out <- mod
  } else {
    stop("File does not contain a fit object named 'mod': ", file_path)
  }

  # Setup
  start_date <- 1990
  end_date <- 2025 + 47/48
  date_vec <- seq(start_date, end_date, 1/48)

  # Construct dates for irregular ts (7th, 14th, 21st, 28th)
  dates <- dec2week(date_vec)

  # Growth rate series
  ryear <- floor(time(out$factor))
  rmon <- as.numeric(format(as.yearmon(time(out$factor)), "%m"))
  rday <- (round((time(out$factor) %% 1) * 48) %% 4 + 1) * 7

  res_gr <- zoo(
    x = cbind(out$factor,
              out$factor + 1.96 * sqrt(out$factor_var),
              out$factor - 1.96 * sqrt(out$factor_var)),
    order.by = as.Date(paste0(ryear, "-", sprintf("%02d", rmon), "-", sprintf("%02d", rday)))
  )

  tab_gr <- data.frame("mean" = as.numeric(res_gr[,1]),
                       "max" = as.numeric(res_gr[,2]),
                       "min" = as.numeric(res_gr[,3]),
                       "time" = time(res_gr)) %>%
    pivot_longer(-c(time, min, max))

  tab_gr_full <- tab_gr
  tab_gr_qoq <- tab_gr %>% select(time, name, value)
  # Level index series
  gr <- (1 + out$factor/100)^(1/48) - 1
  gr <- window(gr, start = time(out$factor)[[1]], end = time(out$factor)[length(out$factor)])

  lev <- 100
  idx <- numeric(length(gr))
  for (jx in 1:length(gr)) {
    idx[jx] <- exp(gr[jx]) * lev
    lev <- idx[jx]
  }

  idx_ts <- ts(idx, start = time(out$factor)[1], frequency = frequency(out$factor))

  expected_times <- 2019 + (36:47) / 48
  indices <- findInterval(expected_times, time(idx_ts))
  valid_indices <- indices[indices > 0 & indices <= length(idx_ts)]
  idx_ts_2020 <- mean(idx_ts[valid_indices])
  idx_ts <- 100 * idx_ts / idx_ts_2020

  # Level bounds
  ryear <- floor(time(idx_ts))
  rmon <- as.numeric(format(as.yearmon(time(idx_ts)), "%m"))
  rday <- (round((time(idx_ts) %% 1) * 48) %% 4 + 1) * 7

  merged_max <- merge(zoo(idx_ts, order.by = dates), (1 + res_gr[,2]/100)^(1/48), all = FALSE)
  merged_min <- merge(zoo(idx_ts, order.by = dates), (1 + res_gr[,3]/100)^(1/48), all = FALSE)

  lv_max <- ts(merged_max[,1] * merged_max[,2], start = time(out$factor)[1], frequency = frequency(out$factor))
  lv_min <- ts(merged_min[,1] * merged_min[,2], start = time(out$factor)[1], frequency = frequency(out$factor))

  res_lv <- zoo(
    x = cbind(idx_ts, lv_max, lv_min),
    order.by = as.Date(paste0(ryear, "-", sprintf("%02d", rmon), "-", sprintf("%02d", rday)))
  )

  tab_gr_lv <- data.frame("mean" = as.numeric(res_lv[,1]),
                          "time" = time(res_lv)) %>%
    pivot_longer(-time)

  # Year-over-year growth
  wai_yoy <- ts(100 * (idx_ts - stats::lag(idx_ts, k = -48)) / stats::lag(idx_ts, k = -48),
                start = c(1991, 1), frequency = 48)

  res_wai_yoy <- zoo(
    x = wai_yoy,
    order.by = as.Date(paste0(ryear[-(1:48)], "-", sprintf("%02d", rmon[-(1:48)]), "-", sprintf("%02d", rday[-(1:48)])))
  )

  tab_wai_yoy <- data.frame("mean" = as.numeric(res_wai_yoy[,1]),
                            "time" = time(res_wai_yoy)) %>%
    pivot_longer(-time)

  tab_wai_yoy_full <- tab_wai_yoy

  return(list(
    tab_wai_yoy_full = tab_wai_yoy_full,
    tab_wai_yoy = tab_wai_yoy,
    tab_gr_full = tab_gr_full,
    tab_gr_qoq = tab_gr_qoq,
    tab_gr_lv = tab_gr_lv
  ))
}
