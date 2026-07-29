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


#' Extract the nowcast from a fit object
#'
#' @param fit A fit object from [run_ar()] or [run_wai_adj()].
#' @param model Character, `"ar"` or `"wai"`.
#'
#' @return The nowcast value.
#' @examples
#' fit <- list(nowcast = stats::ts(c(0.3, 0.5), start = 2024, frequency = 4))
#' retrieve_nowcast(fit, model = "wai")
#' @export
retrieve_nowcast <- function(fit, model){
  if(model == "ar") ncst <- fit$nowcast
  if(model == "wai") ncst <- tail(fit$nowcast,1)

  return(ncst)

}

#' Extract the nowcast variance from a fit object
#'
#' @inheritParams retrieve_nowcast
#'
#' @return The nowcast variance.
#' @examples
#' fit <- list(nowcast_var = stats::ts(c(0.02, 0.04), start = 2024, frequency = 4))
#' retrieve_nowcast_var(fit, model = "wai")
#' @export
retrieve_nowcast_var <- function(fit, model){
  if(model == "ar") ncst <- fit$nowcast_var
  if(model == "wai") ncst <- tail(fit$nowcast_var,1)

  return(ncst)

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
