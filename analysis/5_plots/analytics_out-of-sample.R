# -----------------------------------------------------------------------------
# analytics_out-of-sample.R
# -----------------------------------------------------------------------------
# Purpose:
# This file creates the pseudo out-of-sample and real-time out-of-sample
# analytics outputs. It builds GDP and indicator vintages, runs the forecast
# evaluation loops, and writes the OOS error summary tables.
#
# How to use:
# Run this file directly after sourcing analytics_functions.R, or simply source
# it on its own. If the shared data objects are missing, it will automatically
# source analytics_data.R first.
# -----------------------------------------------------------------------------

source("analysis/5_plots/_setup.R")

library(dplyr)
library(lubridate)
library(purrr)
library(tidyr)
library(zoo)
library(tibble)
library(forecast)

if (!exists("plots_insample_data_ready", inherits = FALSE)) {
  source("analysis/5_plots/analytics_data.R")
}
build_truncated_vintage_columns <- function(ref_values, ref_dates, new_dates) {
  new_cols <- lapply(new_dates, function(vintage_date) {
    vals <- ref_values
    vals[ref_dates > vintage_date] <- NA
    vals
  })

  new_cols_df <- as.data.frame(new_cols)
  colnames(new_cols_df) <- format(new_dates, "%Y-%m-%d")

  new_cols_df
}

filter_vintage_columns_by_date <- function(tbl, cutoff_date) {
  vintage_col_names <- colnames(tbl)[-1]
  vintage_dates <- suppressWarnings(ymd(vintage_col_names))
  keep_cols <- is.na(vintage_dates) | vintage_dates >= cutoff_date

  tbl %>% select(time, all_of(vintage_col_names[keep_cols]))
}

filter_numeric_vintage_window <- function(tbl, lower_bound, upper_bound) {
  keep_cols <- names(tbl)[
    names(tbl) == "time" |
      (suppressWarnings(!is.na(as.numeric(names(tbl)))) &
         as.numeric(names(tbl)) >= lower_bound &
         as.numeric(names(tbl)) <= upper_bound)
  ]

  tbl[, keep_cols]
}

decimal_year_to_quarter_start <- function(vintage_names) {
  vintage_values <- as.numeric(vintage_names)
  years <- floor(vintage_values)
  fractions <- vintage_values - years
  quarter_index <- as.integer(cut(
    fractions,
    breaks = c(-Inf, 0.25, 0.50, 0.75, Inf),
    labels = 1:4,
    right = TRUE
  ))
  month_start <- c(1, 4, 7, 10)[quarter_index]

  as.character(as.Date(sprintf("%04d-%02d-01", years, month_start)))
}

create_lagged_gdp_vintages <- function(tbl, vintage_names) {
  lagged_tbl <- tbl %>%
    mutate(across(-time, ~ dplyr::lag(.x, 1)))
  colnames(lagged_tbl)[-1] <- vintage_names

  lagged_tbl
}

trim_indicator_vintages <- function(tbl, latest_indicator_vintage_date) {
  keep_cols <- vapply(names(tbl), function(col_name) {
    if (col_name == "time") {
      return(TRUE)
    }

    date_val <- suppressWarnings(as.Date(col_name, format = "%Y-%m-%d"))
    !is.na(date_val) && date_val <= latest_indicator_vintage_date
  }, logical(1))

  tbl[, keep_cols]
}

build_gdp_target_cache <- function(current_gdp, vintage_names) {
  cache <- setNames(vector("list", length(vintage_names)), vintage_names)

  for (vintage_name in vintage_names) {
    target_series <- current_gdp[, c("time", vintage_name)]
    colnames(target_series)[2] <- "target_value"
    target_series$yearqtr <- as.yearqtr(target_series$time)
    target_series <- na.trim(target_series[, c("yearqtr", "target_value")])
    latest_observation <- if (nrow(target_series) > 0) max(target_series$yearqtr) else NA
    cache[[vintage_name]] <- target_series
    attr(cache[[vintage_name]], "latest_observation") <- latest_observation
  }

  cache
}

get_latest_available_gdp_vintage <- function(pred_vintage, target_vintages) {
  valid_targets <- target_vintages[target_vintages <= pred_vintage]
  if (length(valid_targets) == 0) return(NA_real_)
  max(valid_targets)
}

get_next_extending_gdp_vintage <- function(current_vintage, target_vintages, gdp_target_cache) {
  if (is.na(current_vintage)) {
    return(NA_real_)
  }

  current_series <- gdp_target_cache[[as.character(current_vintage)]]
  current_latest_observation <- attr(current_series, "latest_observation")

  if (is.null(current_latest_observation) || is.na(current_latest_observation)) {
    return(NA_real_)
  }

  later_targets <- target_vintages[target_vintages > current_vintage]

  for (candidate_vintage in later_targets) {
    candidate_series <- gdp_target_cache[[as.character(candidate_vintage)]]
    candidate_latest_observation <- attr(candidate_series, "latest_observation")

    if (!is.null(candidate_latest_observation) &&
        !is.na(candidate_latest_observation) &&
        candidate_latest_observation >= current_latest_observation + 0.25) {
      return(candidate_vintage)
    }
  }

  NA_real_
}

create_pseudo_gdp_vintages <- function(source_tbl, lower_bound, upper_bound) {
  vintage_names <- names(source_tbl)[-1]
  vintage_values <- suppressWarnings(as.numeric(vintage_names))
  valid_vintages <- vintage_values[!is.na(vintage_values) & vintage_values >= lower_bound & vintage_values <= upper_bound]
  gdp_target_cache <- build_gdp_target_cache(source_tbl, vintage_names)

  pseudo_tbl <- source_tbl

  for (vintage_name in vintage_names) {
    vintage_value <- suppressWarnings(as.numeric(vintage_name))

    if (is.na(vintage_value) || vintage_value < lower_bound || vintage_value > upper_bound) {
      pseudo_tbl[[vintage_name]] <- NA_real_
      next
    }

    next_vintage <- get_next_extending_gdp_vintage(vintage_value, valid_vintages, gdp_target_cache)

    if (is.na(next_vintage)) {
      pseudo_tbl[[vintage_name]] <- NA_real_
    } else {
      pseudo_tbl[[vintage_name]] <- source_tbl[[as.character(next_vintage)]]
    }
  }

  pseudo_tbl
}

prepare_indicator_table <- function(tbl, sample_end_date) {
  tbl <- tbl[tbl$time >= as.Date("1990-01-01") & tbl$time <= sample_end_date, , drop = FALSE]
  vintage_dates <- as.Date(colnames(tbl)[-1])
  date_vec_names <- plyr::round_any(
    x = as.numeric(format(vintage_dates, "%Y")) +
      (as.numeric(format(vintage_dates, "%m")) - 1) / 12 +
      as.numeric(format(vintage_dates, "%d")) / 365,
    accuracy = 1 / 365,
    f = ceiling
  )
  colnames(tbl) <- c("time", round(as.numeric(date_vec_names), 3))

  tbl
}

build_predictor_series_cache <- function(tbl, pred_vintages) {
  cache <- vector("list", length(pred_vintages))
  names(cache) <- as.character(pred_vintages)
  time_values <- tbl$time

  for (pred_v in pred_vintages) {
    pred_col <- as.character(pred_v)
    predictor_values <- tbl[[pred_col]]
    keep_idx <- !is.na(predictor_values)
    predictor_series <- data.frame(
      time = time_values[keep_idx],
      value = predictor_values[keep_idx]
    )
    cache[[pred_col]] <- list(
      predictor_series = predictor_series,
      cut_off_month_pos = ((as.integer(format(max(predictor_series$time), "%m")) - 1) %% 3) + 1
    )
  }

  cache
}

lag_numeric_vector <- function(x, lag_number) {
  if (lag_number == 0) {
    return(x)
  }

  c(rep(NA_real_, lag_number), head(x, -lag_number))
}

run_oos_forecast_block <- function(current_gdp, filtered_tables, anchor_vintages, all_target_vintages, sample_end_date, GDP_type) {
  current_gdp_vintage_names <- colnames(current_gdp)[-1]
  gdp_target_cache <- build_gdp_target_cache(current_gdp, current_gdp_vintage_names)

  all_results <- list()
  result_idx <- 1

  for (ii in names(filtered_tables)) {
    print(ii)

    my_table <- prepare_indicator_table(filtered_tables[[ii]], sample_end_date)
    pred_vintages <- as.numeric(colnames(my_table)[-1])
    predictor_series_cache <- build_predictor_series_cache(my_table, pred_vintages)

    predictor_quarterly_cache <- lapply(c("last_month", "mean", "last"), function(method_name) {
      method_cache <- vector("list", length(pred_vintages))
      names(method_cache) <- as.character(pred_vintages)

      for (pred_v in pred_vintages) {
        pred_key <- as.character(pred_v)
        predictor_info <- predictor_series_cache[[pred_key]]
        method_cache[[pred_key]] <- aggregate_predictor_to_quarterly(
          predictor_info$predictor_series,
          cut_off_month_pos = predictor_info$cut_off_month_pos,
          method = method_name
        ) %>%
          arrange(yearqtr)
      }

      method_cache
    })
    names(predictor_quarterly_cache) <- c("last_month", "mean", "last")

    for (method in names(predictor_quarterly_cache)) {
      print(method)
      method_cache <- predictor_quarterly_cache[[method]]

      for (lag_number in 0:4) {
        print(lag_number)

        results_by_vintage <- lapply(pred_vintages, function(pred_v) {
          pred_key <- as.character(pred_v)
          base_v <- get_latest_available_gdp_vintage(pred_v, anchor_vintages)

          if (is.na(base_v)) {
            return(NULL)
          }

          predictor_quarterly <- method_cache[[pred_key]]
          predictor_values_lagged <- lag_numeric_vector(predictor_quarterly$value, lag_number)
          valid_predictor_idx <- !is.na(predictor_values_lagged)

          if (!any(valid_predictor_idx)) {
            return(NULL)
          }

          predictor_yearqtr <- predictor_quarterly$yearqtr[valid_predictor_idx]
          predictor_values_lagged <- predictor_values_lagged[valid_predictor_idx]

          if (grepl("pseudo", GDP_type, fixed = TRUE)) {
            target_v <- get_next_extending_gdp_vintage(base_v, all_target_vintages, gdp_target_cache)

            if (is.na(target_v)) {
              return(NULL)
            }

            target_series_full <- gdp_target_cache[[as.character(target_v)]]

            if (nrow(target_series_full) < 2) {
              return(NULL)
            }

            target_series <- target_series_full[-nrow(target_series_full), , drop = FALSE]
            next_qtr <- target_series_full$yearqtr[nrow(target_series_full)]
            actual_value <- target_series_full$target_value[nrow(target_series_full)]
            next_target_v <- target_v
          } else {
            target_v <- base_v
            target_series_full <- gdp_target_cache[[as.character(target_v)]]
            next_target_v <- get_next_extending_gdp_vintage(target_v, all_target_vintages, gdp_target_cache)

            if (is.na(next_target_v)) {
              return(NULL)
            }

            target_series <- target_series_full
          }

          matched_idx <- match(target_series$yearqtr, predictor_yearqtr)
          valid_match <- !is.na(matched_idx)

          if (sum(valid_match) < 5) {
            return(NULL)
          }

          merged_yearqtr <- target_series$yearqtr[valid_match]
          merged_target <- target_series$target_value[valid_match]
          merged_predictor <- predictor_values_lagged[matched_idx[valid_match]]

          model <- lm(merged_target ~ merged_predictor)
          if (!grepl("pseudo", GDP_type, fixed = TRUE)) {
            next_qtr <- max(merged_yearqtr) + 0.25
          }
          next_predictor_idx <- match(next_qtr, predictor_yearqtr)

          if (is.na(next_predictor_idx) || is.na(predictor_values_lagged[next_predictor_idx])) {
            return(NULL)
          }

          next_predictor_value <- predictor_values_lagged[next_predictor_idx]

          forecast_value <- unname(coef(model)[1] + coef(model)[2] * next_predictor_value)
          if (!grepl("pseudo", GDP_type, fixed = TRUE)) {
            next_target_series <- gdp_target_cache[[as.character(next_target_v)]]
            next_target_idx <- match(next_qtr, next_target_series$yearqtr)

            if (is.na(next_target_idx)) {
              return(NULL)
            }

            actual_value <- next_target_series$target_value[next_target_idx]
          }

          tibble(
            pred_vintage = pred_v,
            target_vintage = target_v,
            next_target_vintage = next_target_v,
            forecast_period = as.Date(as.yearqtr(next_qtr)),
            forecast_value = forecast_value,
            actual_value = actual_value,
            error = actual_value - forecast_value
          )
        })

        results <- bind_rows(results_by_vintage)

        if (nrow(results) > 0) {
          all_results[[result_idx]] <- results %>%
            mutate(model = ii, method = method, lag_number = lag_number, GDP_type = GDP_type)
          result_idx <- result_idx + 1
        }
      }
    }
  }

  bind_rows(all_results)
}


# -----------------------------------------------------------------------------
# GDP Vintage Construction
# -----------------------------------------------------------------------------
# Import the GDP real-time vintages and prepare both real-time and pseudo
# vintages for the subsequent forecast evaluation.

GDP_gr_vintages_quarterly <- get_real_time_gdp_vintages("quarterly")
GDP_gr_vintages_annual <- get_real_time_gdp_vintages("annual")
sample_end_gdp_vintage <- get_latest_numeric_vintage(GDP_gr_vintages_quarterly, lower_bound = 2005.438, upper_bound = sample_end_decimal)
GDP_gr_vintages_quarterly <- GDP_gr_vintages_quarterly %>%
  mutate(across(-time, ~ (1 + .x)^4 - 1))
GDP_gr_vintages_quarterly_pseudo <- create_pseudo_gdp_vintages(
  GDP_gr_vintages_quarterly,
  lower_bound = 2005.438,
  upper_bound = sample_end_gdp_vintage
)
GDP_gr_vintages_annual_pseudo <- create_pseudo_gdp_vintages(
  GDP_gr_vintages_annual,
  lower_bound = 2005.438,
  upper_bound = sample_end_gdp_vintage
)

# Import the KOF barometer real-time export and convert the vintage names into
# standard date columns.
file_path <- "analysis/benchmarks/archive_data_benchmarks/kof_data_export_2025-06-23_09_05_05_real_time_vintages.xlsx"
data_barro_vintages <- read_excel(file_path, col_names = TRUE, col_types = "numeric")
data_barro_vintages[,1] <- read_excel(file_path, range = cell_cols(1))
col_names <- colnames(data_barro_vintages)[-1]
date_vector <- as.Date(sub("baro_(\\d{4})m(\\d{2})", "\\1-\\2-01", col_names))
date_vector <- as.Date(as.yearmon(date_vector))
colnames(data_barro_vintages)[-1] <- as.character(date_vector)
data_barro_vintages$time <- as.Date(paste0(data_barro_vintages$date, "-01"))
data_barro_vintages <- data_barro_vintages %>% select(-date)
data_barro_vintages <- data_barro_vintages %>%
  select(time, everything())
# Create synthetic early KOF vintages by truncating the first available path.
new_dates <- seq(as.Date("2005-01-01"), as.Date("2014-03-01"), by = "month")
ref_col_name <- colnames(data_barro_vintages)[2]
ref_values <- data_barro_vintages[[ref_col_name]]
ref_dates <- as.Date(data_barro_vintages$time)
new_cols_df <- build_truncated_vintage_columns(ref_values, ref_dates, new_dates)
data_barro_vintages <- bind_cols(
  data_barro_vintages[, 1],  # Keep date column
  new_cols_df,
  data_barro_vintages[, -1]  # Rest of original columns
)
# Determine which GDP vintages are available by the sample end date and which
# later vintages remain eligible as future targets.
all_target_vintages <- as.numeric(colnames(GDP_gr_vintages_quarterly)[-1])
all_target_vintages <- all_target_vintages[all_target_vintages >= 2005.438]
anchor_vintages <- all_target_vintages[all_target_vintages <= sample_end_gdp_vintage]
fcurve_gr_full = na.approx(fcurve_gr_full, na.rm = FALSE)
fcurve_gr_df_full2 <- daily2weekly(fcurve_gr_full)
dates_fcurve_full <- dec2week(time(fcurve_gr_df_full2))
fcurve_gr_df_full <- data.frame("value" = as.numeric(fcurve_gr_df_full2),
                                "time" = as.Date(dates_fcurve_full))
if (!exists("tab_kss", inherits = FALSE)) {
  tab_kss <- data.frame("mean" = as.numeric(kss_zoo[, 1]), "time" = time(kss_zoo)) %>%
    pivot_longer(-c(time))
}
if (!exists("tab_snb", inherits = FALSE)) {
  tab_snb <- data.frame("mean" = as.numeric(snb_zoo[, 1]), "time" = time(snb_zoo)) %>%
    pivot_longer(-c(time))
}
if (!exists("tab_baro", inherits = FALSE)) {
  baro_zoo <- zoo(baro_zoo, order.by = index(baro_zoo))
  tab_baro <- data.frame("mean" = as.numeric(baro_zoo[, 1]), "time" = time(baro_zoo)) %>%
    pivot_longer(-c(time))
}
if (!exists("tab_kss_full", inherits = FALSE)) {
  tab_kss_full <- tab_kss
}
if (!exists("tab_snb_full", inherits = FALSE)) {
  tab_snb_full <- tab_snb
}
if (!exists("tab_baro_full", inherits = FALSE)) {
  tab_baro_full <- tab_baro
}
tab_gr_full_qoq <- tab_gr_full %>% select(value, time)
tab_gr_full_yoy <- tab_wai_yoy_full %>% select(value, time)
plot_df_qoq <- bind_rows(
  tab_gr_full_qoq      %>% mutate(Series = "WAI"),
  tab_gr_full_yoy     %>% mutate(Series = "WAI_yoy"),
  #wwa_gr_df_qoq_full   %>% mutate(Series = "SECO-WWA"),
  wwa_gr_df_yoy_full   %>% mutate(Series = "SECO-WWA"),
  fcurve_gr_df_full    %>% mutate(Series = "F-CURVE"),
  tab_kss_full         %>% mutate(Series = "SECO-SEC"),
  tab_snb_full         %>% mutate(Series = "SNB-BCI"),
  tab_baro_full        %>% mutate(Series = "KOF-BARO")
)
# Convert each full indicator history into a vintage-style wide table where each
# column keeps only the information available up to that date.
list_of_tables <- split(plot_df_qoq, plot_df_qoq$Series) %>%
  map(function(df) {
    dates <- df$time
    
    # Create matrix where each column j contains values up to row j
    wide_mat <- map_dfc(seq_along(dates), function(j) {
      col <- rep(NA, nrow(df))
      col[1:j] <- df$value[1:j]
      tibble(!!as.character(dates[j]) := col)
    })
    
    # Combine time column and wide matrix
    bind_cols(tibble(time = df$time), wide_mat)
  })
source("analysis/5_plots/run_plots_analytics_samples.R")
folder_path <- sample_config$fit_rt_dir
files <- list.files(folder_path, pattern = "\\.Rda$", full.names = TRUE)
list_of_qoq_tables <- list()
list_of_yoy_tables <- list()
# Rebuild weekly real-time WAI vintages from the stored real-time fit files.
for (file in files) {
  load(file)  # loads 'mod' object
  
  ryear <- floor(time(mod$factor))
  rmon <- as.numeric(format(as.yearmon(time(mod$factor)), "%m"))
  rday <- (round((time(mod$factor) %% 1) * 48) %% 4 + 1) * 7
  
  res_gr <- zoo(x = cbind(mod$factor,
                          mod$factor + 1.96 * sqrt(mod$factor_var),
                          mod$factor - 1.96 * sqrt(mod$factor_var)),
                order.by = as.Date(paste0(ryear, "-", sprintf("%02d", rmon), "-", sprintf("%02d", rday)), format = "%Y-%m-%d"))
  
  tab_gr <- data.frame("mean" = as.numeric(res_gr[, 1]),
                       "max" = as.numeric(res_gr[, 2]),
                       "min" = as.numeric(res_gr[, 3]),
                       "time" = time(res_gr))
  
  tab_gr <- tab_gr %>% pivot_longer(-c(time, min, max))
  
  
  # transform to level index series - FOR TESTING PURPOSE
  gr <- (1+mod$factor/100)^(1/48)-1
  gr <- window(gr,start=time(mod$factor)[[1]],end=time(mod$factor)[length(mod$factor)])
  
  # Time aggregation
  lev <- 100
  idx <- rep(NA,length(gr))
  for(jx in 1:length(gr)){
    # Reconstruct the WAI level index from the fitted weekly growth factor.
    # (1 + gr), not exp(gr): gr is a NET per-period rate, so the gross growth
    # factor is 1 + gr. exp(x) > 1 + x for every x != 0, so the old form was
    # one-signed - it could only push the level up - and it compounded, at
    # ~gr^2/2 per period. Invisible while rates are small, not invisible in
    # 2020. See mfbdfm issue #92.
    idx[jx]<- (1 + gr[jx]) * lev
    lev <- idx[jx]
  }
  
  # Get time series from index
  idx_ts <- ts(idx, start = time(mod$factor)[1], frequency = frequency(mod$factor))
  
  # Calculate the expected decimal time values for the last 12 weeks of 2019
  expected_times <- 2019 + (36:47) / 48
  
  # Find indices of the closest matches in time(idx_ts)
  indices <- findInterval(expected_times, time(idx_ts))
  
  # Check if we got valid indices
  valid_indices <- indices[indices > 0 & indices <= length(idx_ts)]
  
  # Compute the average of the selected time series values
  idx_ts_2020 <- mean(idx_ts[valid_indices])
  
  # Normalize index with Q4 2019 as base == 100
  idx_ts <- 100*idx_ts/idx_ts_2020
  
  wai_yoy <- ts(100 * (idx_ts - stats::lag(idx_ts, k = -48)) / stats::lag(idx_ts, k = -48), start = c(1991,1), frequency = 48)
  
  res_wai_yoy <- zoo(x = wai_yoy,
                     order.by = as.Date(paste0(ryear[-(1:48)],"-",sprintf("%02d", rmon[-(1:48)]),"-",sprintf("%02d", rday[-(1:48)])), format = "%Y-%m-%d"))
  
  tab_wai_yoy <- data.frame("mean" = as.numeric(res_wai_yoy[,1]),
                            "time" = time(res_wai_yoy))
  tab_wai_yoy <- tab_wai_yoy %>% pivot_longer(-c(time))
  
  
  tab_gr_full_qoq <- tab_gr %>% select(value, time)
  tab_gr_full_yoy <- tab_wai_yoy %>% select(value, time)
  
  file_name <- tools::file_path_sans_ext(basename(file))
  file_name <- gsub("^fit_", "", file_name)  # Remove "fits_"
  
  list_of_qoq_tables[[file_name]] <- tab_gr_full_qoq
  list_of_yoy_tables[[file_name]] <- tab_gr_full_yoy
}
list_of_qoq_tables <- list_of_qoq_tables[order(as.numeric(names(list_of_qoq_tables)))]
WAI_RT <- reduce(list_of_qoq_tables, full_join, by = "time")
WAI_RT <- WAI_RT %>% select(time, everything())
colnames(WAI_RT) <- c("time", names(list_of_qoq_tables))
dates <- dec2week(as.numeric(colnames(WAI_RT)[-1]))
colnames(WAI_RT) <- c("time", as.character(dates))
list_of_tables[["WAI-RT"]] <- WAI_RT
list_of_yoy_tables <- list_of_yoy_tables[order(as.numeric(names(list_of_yoy_tables)))]
WAI_yoy_RT <- reduce(list_of_yoy_tables, full_join, by = "time")
WAI_yoy_RT <- WAI_yoy_RT %>% select(time, everything())
colnames(WAI_yoy_RT) <- c("time", names(list_of_yoy_tables))
dates <- dec2week(as.numeric(colnames(WAI_yoy_RT)[-1]))
colnames(WAI_yoy_RT) <- c("time", as.character(dates))
list_of_tables[["WAI-yoy-RT"]] <- WAI_yoy_RT
list_of_tables[["KOF-BARO-RT"]] <- data_barro_vintages
# Convert KOF vintage column names into the same decimal-week naming convention
# used across the rest of the real-time evaluation.
data_barro_vintages <- data_barro_vintages[data_barro_vintages$time >= as.Date("1990-01-01") & 
                                             data_barro_vintages$time <= sample_end_date, ]
dates <- as.Date(colnames(data_barro_vintages)[-1])
date_vec_names <- plyr::round_any(
  x = as.numeric(format(dates, "%Y")) +
    (as.numeric(format(dates, "%m")) - 1) / 12 +
    as.numeric(format(dates, "%d")) / 365,
  accuracy = 1/48,
  f = ceiling
)
date_vec_names <- round(as.numeric(date_vec_names), 3)
colnames(data_barro_vintages) <- c("time", date_vec_names)
pred_vintages <- as.numeric(colnames(data_barro_vintages)[-1])
cutoff_date <- as.Date("2004-11-16")
list_of_tables <- map(list_of_tables, filter_vintage_columns_by_date, cutoff_date = cutoff_date)
list_of_tables <- lapply(list_of_tables, function(df) {
  df %>%
    filter(#time >= as.Date("2004-11-26"),
           time <= sample_end_date)
})
# Keep only the GDP vintages that belong to the configured evaluation window.
GDP_gr_vintages_quarterly_pseudo <- filter_numeric_vintage_window(GDP_gr_vintages_quarterly_pseudo, 2005.438, sample_end_gdp_vintage)
GDP_gr_vintages_annual_pseudo <- filter_numeric_vintage_window(GDP_gr_vintages_annual_pseudo, 2005.438, sample_end_gdp_vintage)
GDP_gr_vintages_quarterly <- filter_numeric_vintage_window(GDP_gr_vintages_quarterly, 2005.438, sample_end_gdp_vintage)
GDP_gr_vintages_annual <- filter_numeric_vintage_window(GDP_gr_vintages_annual, 2005.438, sample_end_gdp_vintage)


# -----------------------------------------------------------------------------
# Indicator Vintage Construction
# -----------------------------------------------------------------------------
# Prepare the benchmark and WAI real-time vintage tables so they can be aligned
# with the GDP vintages in the forecasting exercises.

cols <- colnames(GDP_gr_vintages_quarterly_pseudo)[-1]
# Translate decimal-year GDP vintage names into quarter-start dates so the AR
# benchmark vintages line up with the indicator vintages.
a_qstart <- decimal_year_to_quarter_start(cols)
cols <- colnames(GDP_gr_vintages_annual_pseudo)[-1]
a_ystart <- decimal_year_to_quarter_start(cols)
GDP_gr_vintages_quarterly_pseudo_lagged <- create_lagged_gdp_vintages(GDP_gr_vintages_quarterly_pseudo, a_qstart)
GDP_gr_vintages_annual_pseudo_lagged <- create_lagged_gdp_vintages(GDP_gr_vintages_annual_pseudo, a_qstart)
GDP_gr_vintages_annual_lagged <- create_lagged_gdp_vintages(GDP_gr_vintages_annual, a_ystart)
GDP_gr_vintages_quarterly_lagged <- create_lagged_gdp_vintages(GDP_gr_vintages_quarterly, a_ystart)
# Add lagged GDP vintages as simple AR benchmarks for both pseudo and RT setups.
list_of_tables[["AR1-qoq"]] <- GDP_gr_vintages_quarterly_pseudo_lagged
list_of_tables[["AR1-yoy"]] <- GDP_gr_vintages_annual_pseudo_lagged
list_of_tables[["AR1-yoy-RT"]] <- GDP_gr_vintages_annual_lagged
list_of_tables[["AR1-qoq-RT"]] <- GDP_gr_vintages_quarterly_lagged
latest_indicator_vintage_date <- as.Date("31-12-2025", format = "%d-%m-%Y")
# Trim all indicator vintage tables to the fixed indicator vintage cutoff date.
list_of_tables <- lapply(list_of_tables, trim_indicator_vintages, latest_indicator_vintage_date = latest_indicator_vintage_date)


# -----------------------------------------------------------------------------
# Forecast Evaluation Loops
# -----------------------------------------------------------------------------
# Run the pseudo and real-time forecast experiments across indicators,
# aggregation methods, and lag structures.

gdp_types_to_run <- c(
  "GDP_gr_vintages_annual_pseudo",
  "GDP_gr_vintages_annual",
  "GDP_gr_vintages_quarterly",
  "GDP_gr_vintages_quarterly_pseudo"
)

for (GDP_type in gdp_types_to_run) {
  current_GDP <- if (GDP_type == "GDP_gr_vintages_quarterly_pseudo") {
    GDP_gr_vintages_quarterly
  } else if (GDP_type == "GDP_gr_vintages_annual_pseudo") {
    GDP_gr_vintages_annual
  } else {
    get(GDP_type)
  }
  print(GDP_type)
  # Keep only the models that match the frequency and real-time setup of the
  # current GDP target block.
  filtered_tables <- list_of_tables
  if (GDP_type == "GDP_gr_vintages_quarterly_pseudo") {
    filtered_tables[c("WAI_yoy", "WAI-yoy-RT", "WAI-RT", "KOF-BARO-RT", "AR1-yoy", "AR1-yoy-RT", "AR1-qoq-RT")] <- NULL
  } else if (GDP_type == "GDP_gr_vintages_quarterly") {
    filtered_tables[c("WAI_yoy", "WAI-yoy-RT", "WAI", "KOF-BARO", "AR1-yoy", "AR1-yoy-RT", "AR1-qoq")] <- NULL
  } else if (GDP_type == "GDP_gr_vintages_annual") {
    filtered_tables[c("WAI", "WAI_yoy", "WAI-RT", "KOF-BARO", "AR1-yoy", "AR1-qoq", "AR1-qoq-RT")] <- NULL
  } else if (GDP_type == "GDP_gr_vintages_annual_pseudo") {
    filtered_tables[c("WAI", "WAI-yoy-RT", "WAI-RT", "KOF-BARO-RT", "AR1-yoy-RT", "AR1-qoq", "AR1-qoq-RT")] <- NULL
  }

  final_results <- run_oos_forecast_block(
    current_gdp = current_GDP,
    filtered_tables = filtered_tables,
    anchor_vintages = anchor_vintages,
    all_target_vintages = all_target_vintages,
    sample_end_date = sample_end_date,
    GDP_type = GDP_type
  )

  results_object_name <- paste0("results_", GDP_type)
  assign(results_object_name, final_results, envir = .GlobalEnv)
  save(
    list = results_object_name,
    file = file.path(results_dir, paste0(results_object_name, "3.rda"))
  )
}


# -----------------------------------------------------------------------------
# Out-of-Sample Summary Tables
# -----------------------------------------------------------------------------
# Combine stored forecast results, compute relative and absolute error metrics,
# split by crisis regime where needed, and write the LaTeX tables.

load(file.path(results_dir, "results_GDP_gr_vintages_annual_pseudo3.rda"))   # loads 'results_GDP_gr_vintages_annual_pseudo'
load(file.path(results_dir, "results_GDP_gr_vintages_annual3.rda"))          # loads 'results_GDP_gr_vintages_annual'
load(file.path(results_dir, "results_GDP_gr_vintages_quarterly3.rda"))       # loads 'results_GDP_gr_vintages_quarterly'
load(file.path(results_dir, "results_GDP_gr_vintages_quarterly_pseudo3.rda"))# loads 'results_GDP_gr_vintages_quarterly_pseudo'
# Drop the duplicate RT WAI row before stacking all result files together.
results_GDP_gr_vintages_quarterly_pseudo <- results_GDP_gr_vintages_quarterly_pseudo %>%
  filter(model != "WAI-RT")
combined_results <- bind_rows(
  results_GDP_gr_vintages_annual_pseudo,
  results_GDP_gr_vintages_annual,
  results_GDP_gr_vintages_quarterly,
  results_GDP_gr_vintages_quarterly_pseudo
)
# Harmonize model labels so the downstream tables compare common names only.
combined_results$model[combined_results$model == "WAI-RT"] <- "WAI"
combined_results$model[combined_results$model == "KOF-BARO-RT"] <- "KOF-BARO"
#combined_results$model[combined_results$model == "SECO-WWA_yoy"] <- "SECO-WWA"
combined_results$model[combined_results$model == "WAI-yoy-RT"] <- "WAI" 
combined_results$model[combined_results$model == "WAI_yoy"] <- "WAI"
combined_results$model[combined_results$model == "AR1-qoq-RT"] <- "AR"
combined_results$model[combined_results$model == "AR1-yoy-RT"] <- "AR"
combined_results$model[combined_results$model == "AR1-yoy"] <- "AR"
combined_results$model[combined_results$model == "AR1-qoq"] <- "AR"
combined_results <- combined_results %>%
  mutate(
    frequency = case_when(
      GDP_type %in% c("GDP_gr_vintages_annual_pseudo", "GDP_gr_vintages_annual") ~ "YoY",
      GDP_type %in% c("GDP_gr_vintages_quarterly", "GDP_gr_vintages_quarterly_pseudo") ~ "QoQ",
      TRUE ~ NA_character_
    ) 
  )
combined_results_pseudo <- combined_results %>%
  filter(GDP_type %in% c("GDP_gr_vintages_annual_pseudo", "GDP_gr_vintages_quarterly_pseudo"))
combined_results_RT <- combined_results %>%
  filter(GDP_type %in% c("GDP_gr_vintages_annual", "GDP_gr_vintages_quarterly"))

print_oos_evaluation_periods <- function(data, context_label) {
  if (is.null(data) || nrow(data) == 0) {
    return(invisible(NULL))
  }
  
  period_summary <- data %>%
    filter(!is.na(model), !is.na(method), !is.na(frequency), !is.na(forecast_period)) %>%
    group_by(model, method, frequency) %>%
    summarise(
      start_quarter = as.character(as.yearqtr(min(forecast_period, na.rm = TRUE))),
      end_quarter = as.character(as.yearqtr(max(forecast_period, na.rm = TRUE))),
      .groups = "drop"
    ) %>%
    arrange(frequency, method, model)
  
  message("")
  message(paste0("Evaluation periods: ", context_label))
  print(period_summary, row.names = FALSE)
  
  invisible(period_summary)
}

print_oos_forecast_diagnostics <- function(data, context_label, file_stub) {
  if (is.null(data) || nrow(data) == 0) {
    return(invisible(NULL))
  }
  
  diagnostic_table <- data %>%
    filter(
      !is.na(model),
      !is.na(method),
      !is.na(forecast_value),
      !is.na(actual_value),
      !is.na(error),
      !is.na(forecast_period)
    ) %>%
    transmute(
      model = model,
      measure = method,
      forecast = forecast_value,
      target_gdp = actual_value,
      error = error,
      date = forecast_period,
      frequency = frequency,
      gdp_type = GDP_type
    ) %>%
    arrange(frequency, measure, model, date)
  
  diagnostic_path <- file.path(tables_dir, paste0("table_output_oos_forecast_diagnostics_", file_stub, ".csv"))
  write.csv(diagnostic_table, diagnostic_path, row.names = FALSE)
  
  message("")
  message(paste0("Raw OOS forecast diagnostics: ", context_label))
  print(diagnostic_table, row.names = FALSE)
  message(paste0("Saved raw OOS forecast diagnostics to: ", diagnostic_path))
  
  invisible(diagnostic_table)
}

print_oos_evaluation_periods(combined_results_pseudo, "Out-of-sample pseudo")
print_oos_evaluation_periods(combined_results_RT, "Out-of-sample real-time")
oos_forecast_diagnostics_pseudo <- print_oos_forecast_diagnostics(
  combined_results_pseudo,
  "Out-of-sample pseudo",
  "pseudo"
)
oos_forecast_diagnostics_RT <- print_oos_forecast_diagnostics(
  combined_results_RT,
  "Out-of-sample real-time",
  "real_time"
)

model_order <- c("WAI", "AR","SECO-WWA", "F-CURVE", "SECO-SEC", "SNB-BCI", "KOF-BARO")
# Build summary error tables for standard OOS outputs and for the crisis split.
error_tables_pseudo <- create_error_summary_tables(combined_results_pseudo, model_order, date_col = "forecast_period")
error_tables_RT <- create_error_summary_tables(combined_results_RT, model_order, date_col = "forecast_period")
error_tables_pseudo_period <- create_error_summary_tables(combined_results_pseudo, model_order, date_col = "forecast_period", include_period = TRUE)
error_tables_RT_period <- create_error_summary_tables(combined_results_RT, model_order, date_col = "forecast_period", include_period = TRUE)

build_oos_crisis_tables <- function(total_tables, period_tables, sample_label, file_stub, metric_name = c("RMSE", "MAE")) {
  metric_name <- match.arg(metric_name)
  metric_key <- if (metric_name == "RMSE") "rel_rmse" else "rel_mae"
  metric_caption <- if (metric_name == "RMSE") "relative RMSE" else "relative MAE"
  crisis_methods <- c("mean", "last", "last_month")
  method_labels <- c(
    mean = "mean",
    last = "last",
    last_month = "last month"
  )
  
  results_by_method <- lapply(crisis_methods, function(method_name) {
    crisis_metric_tables <- list(
      total = total_tables[[metric_key]][[method_name]],
      crisis = period_tables[[metric_key]][[method_name]] %>% filter(Period == "Crisis Periods") %>% select(-Period),
      non_crisis = period_tables[[metric_key]][[method_name]] %>% filter(Period == "Non-Crisis Periods") %>% select(-Period)
    )
    
    combined_result <- create_combined_latex_table(
      crisis_metric_tables,
      caption = paste(sample_label, metric_caption, "by lag and sample regime using", method_labels[[method_name]], "aggregation"),
      measure_label_map = c(
        total = "\\textbf{Total}",
        crisis = "\\textbf{Crisis}",
        non_crisis = "\\textbf{Non-Crisis}"
      )
    )
    write_table_output(
      paste0("table_output_", tolower(metric_name), "_", file_stub, "_crisis_", method_name, ".tex"),
      combined_result$table_tex,
      tables_dir
    )
    
    combined_result
  })
  names(results_by_method) <- crisis_methods
  
  results_by_method
}

build_scaled_abs_oos_tables <- function(summary_df, metric = c("RMSE", "MAE"), factor = 100, model_order) {
  metric <- match.arg(metric)
  expected_cols <- paste0(metric, "_", -4:0)
  
  summary_df %>%
    filter(model %in% model_order) %>%
    split(.$method) %>%
    map(~ {
      .x %>%
        mutate(
          Frequency = factor(frequency, levels = c("QoQ", "YoY")),
          Series = factor(model, levels = model_order),
          lag_number = ifelse(lag_number > 0, -lag_number, lag_number),
          lag_label = paste0(metric, "_", lag_number),
          scaled_value = .data[[metric]] * factor,
          annotated_value = formatC(scaled_value, format = "f", digits = 2)
        ) %>%
        select(Frequency, Series, lag_label, value = annotated_value) %>%
        pivot_wider(names_from = lag_label, values_from = value) %>%
        select(Frequency, Series, all_of(expected_cols)) %>%
        arrange(Frequency, Series)
    })
}

# Write the standard OOS tables first, then the crisis-split relative RMSE tables.
results_rmse_oos_pseudo <- create_combined_latex_table(
  error_tables_pseudo$rel_rmse[c("mean", "last", "last_month")],
  caption = "Pseudo out-of-sample relative RMSE by lag and aggregation method"
)
write_table_output("table_output_rmse_oos_pseudo3.tex", results_rmse_oos_pseudo$table_tex, tables_dir)
results_rmse_oos_RT <- create_combined_latex_table(
  error_tables_RT$rel_rmse[c("mean", "last", "last_month")],
  caption = "Real-time out-of-sample relative RMSE by lag and aggregation method"
)
write_table_output("table_output_rmse_oos_RT3.tex", results_rmse_oos_RT$table_tex, tables_dir)
results_mae_oos_pseudo <- create_combined_latex_table(
  error_tables_pseudo$rel_mae[c("mean", "last", "last_month")],
  caption = "Pseudo out-of-sample relative MAE by lag and aggregation method"
)
write_table_output("table_output_mae_oos_pseudo3.tex", results_mae_oos_pseudo$table_tex, tables_dir)
results_mae_oos_RT <- create_combined_latex_table(
  error_tables_RT$rel_mae[c("mean", "last", "last_month")],
  caption = "Real-time out-of-sample relative MAE by lag and aggregation method"
)
write_table_output("table_output_mae_oos_RT3.tex", results_mae_oos_RT$table_tex, tables_dir)
scaled_abs_rmse_oos_pseudo <- build_scaled_abs_oos_tables(
  error_tables_pseudo$summary,
  metric = "RMSE",
  factor = 100,
  model_order = model_order
)
scaled_abs_rmse_oos_RT <- build_scaled_abs_oos_tables(
  error_tables_RT$summary,
  metric = "RMSE",
  factor = 100,
  model_order = model_order
)
scaled_abs_mae_oos_pseudo <- build_scaled_abs_oos_tables(
  error_tables_pseudo$summary,
  metric = "MAE",
  factor = 100,
  model_order = model_order
)
scaled_abs_mae_oos_RT <- build_scaled_abs_oos_tables(
  error_tables_RT$summary,
  metric = "MAE",
  factor = 100,
  model_order = model_order
)
results_abs_rmse_oos_pseudo <- create_combined_latex_table(
  scaled_abs_rmse_oos_pseudo[c("mean", "last", "last_month")],
  caption = "Pseudo out-of-sample absolute RMSE by lag and aggregation method"
)
write_table_output("table_output_abs_rmse_oos_pseudo3.tex", results_abs_rmse_oos_pseudo$table_tex, tables_dir)
results_abs_rmse_oos_RT <- create_combined_latex_table(
  scaled_abs_rmse_oos_RT[c("mean", "last", "last_month")],
  caption = "Real-time out-of-sample absolute RMSE by lag and aggregation method"
)
write_table_output("table_output_abs_rmse_oos_RT3.tex", results_abs_rmse_oos_RT$table_tex, tables_dir)
results_abs_mae_oos_pseudo <- create_combined_latex_table(
  scaled_abs_mae_oos_pseudo[c("mean", "last", "last_month")],
  caption = "Pseudo out-of-sample absolute MAE by lag and aggregation method"
)
write_table_output("table_output_abs_mae_oos_pseudo3.tex", results_abs_mae_oos_pseudo$table_tex, tables_dir)
results_abs_mae_oos_RT <- create_combined_latex_table(
  scaled_abs_mae_oos_RT[c("mean", "last", "last_month")],
  caption = "Real-time out-of-sample absolute MAE by lag and aggregation method"
)
write_table_output("table_output_abs_mae_oos_RT3.tex", results_abs_mae_oos_RT$table_tex, tables_dir)

results_rmse_oos_pseudo_crisis <- build_oos_crisis_tables(
  total_tables = error_tables_pseudo,
  period_tables = error_tables_pseudo_period,
  sample_label = "Pseudo out-of-sample",
  file_stub = "oos_pseudo",
  metric_name = "RMSE"
)
results_mae_oos_pseudo_crisis <- build_oos_crisis_tables(
  total_tables = error_tables_pseudo,
  period_tables = error_tables_pseudo_period,
  sample_label = "Pseudo out-of-sample",
  file_stub = "oos_pseudo",
  metric_name = "MAE"
)
results_rmse_oos_RT_crisis <- build_oos_crisis_tables(
  total_tables = error_tables_RT,
  period_tables = error_tables_RT_period,
  sample_label = "Real-time out-of-sample",
  file_stub = "oos_RT",
  metric_name = "RMSE"
)
results_mae_oos_RT_crisis <- build_oos_crisis_tables(
  total_tables = error_tables_RT,
  period_tables = error_tables_RT_period,
  sample_label = "Real-time out-of-sample",
  file_stub = "oos_RT",
  metric_name = "MAE"
)




