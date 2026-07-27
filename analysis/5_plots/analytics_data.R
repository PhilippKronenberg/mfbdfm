# -----------------------------------------------------------------------------
# analytics_data.R
# -----------------------------------------------------------------------------
# Purpose:
# This file builds the full input dataset used by the analytics workflow. It
# imports benchmark indicators, historical GDP series, and the latest fitted
# WAI objects, then transforms them into the shared data frames consumed by the
# in-sample and out-of-sample scripts.
#
# How to use:
# Run this file directly when you want to prepare the common data objects only.
# It can also be sourced automatically by the in-sample and out-of-sample
# scripts when those objects are not yet available.
# -----------------------------------------------------------------------------

source("analysis/5_plots/_setup.R")


# -----------------------------------------------------------------------------
# Shared Dependencies
# -----------------------------------------------------------------------------
# Backcasting and time-conversion helpers come from the mfbdfm package.


# -----------------------------------------------------------------------------
# Benchmark Indicator Inputs
# -----------------------------------------------------------------------------
# Import the external benchmark series and construct weekly or monthly working
# tables for the comparison indicators.

raw_data <- read_excel("analysis/benchmarks/archive_data_benchmarks/wwa.xlsx", sheet = "data", skip = 4, col_names = TRUE)
data_wwa <- raw_data %>%
  rename(Year = 1, Week = 2, "SECO-WWA" = 3, wwa_2019diff = 4) %>%
  mutate(
    # Rebuild a weekly date index from year/week notation in the source file.
    Week_num = as.numeric(gsub("W", "", Week)),
    ISOweek_str = sprintf("%d-W%02d-7", Year, Week_num),
    Date = ISOweek::ISOweek2date(ISOweek_str)
  ) %>%
  arrange(Date) %>%
  mutate(
    # Fill isolated missing growth observations and derive a simple weekly index.
    `SECO-WWA` = ifelse(is.na(`SECO-WWA`), mean(`SECO-WWA`, na.rm = TRUE), `SECO-WWA`),
    weekly_growth_factor = (1 + `SECO-WWA` / 100)^(1/52),
    wwa_index = 100 * cumprod(weekly_growth_factor),
    wwa_qoq = (wwa_index / lag(wwa_index, 13) - 1) * 100
  )

# Convert the cleaned WWA source into zoo and data-frame objects that match the
# structures expected later by the plotting and comparison code.
wwa_yoy_zoo       <- zoo(data_wwa$`SECO-WWA`, order.by = as.Date(data_wwa$Date, format = "%Y-%m-%d"))
wwa_index_zoo     <- zoo(data_wwa$wwa_index, order.by = as.Date(data_wwa$Date, format = "%Y-%m-%d"))
wwa_qoq_zoo       <- zoo(data_wwa$wwa_qoq, order.by = as.Date(data_wwa$Date, format = "%Y-%m-%d"))
wwa_2019diff_zoo  <- zoo(data_wwa$wwa_2019diff, order.by = as.Date(data_wwa$Date, format = "%Y-%m-%d"))
wwa_gr_df <- data.frame("value" = as.numeric(wwa_yoy_zoo),
                           "time" = time(wwa_yoy_zoo))
wwa_gr_df_yoy_full <- wwa_gr_df
wwa_gr_df <- wwa_gr_df %>% 
  filter(time >= as.Date("2005-01-01")) %>%
  filter(time <= sample_end_date)
wwa_gr_df <- wwa_gr_df %>% pivot_longer(-c(time))
wwa_qoq_zoo_trim <- na.trim(wwa_qoq_zoo)
wwa_gr_df_qoq <- data.frame("value" = as.numeric(wwa_qoq_zoo_trim),
                        "time" = time(wwa_qoq_zoo_trim))
wwa_gr_df_qoq_full <- wwa_gr_df_qoq
wwa_gr_df_qoq <- wwa_gr_df_qoq %>%
  filter(time >= as.Date("2005-01-01")) %>%
  filter(time <= sample_end_date)
wwa_gr_df_qoq <- wwa_gr_df_qoq %>% pivot_longer(-c(time))

# Import and clean the SNB business cycle index into a monthly zoo series.
raw_snb <- read_excel("analysis/benchmarks/archive_data_benchmarks/snb-chart-data-snbbcich-de-all-20250326_1500.xlsx", skip = 15, col_names = TRUE)
names(raw_snb)[1] <- "Date"
raw_snb <- raw_snb %>%
  mutate(Date = as.Date(paste0(Date, "-01"))) %>%
  arrange(Date)
data_snb <- raw_snb %>%
  rename("SNB-BCI" = SNB_BCI) %>%
  mutate(Date = as.Date(paste0(Date, "-01")))
snb_zoo <- zoo(data_snb$`SNB-BCI`, order.by = as.Date(data_snb$Date, format = "%Y-%m-%d"))

# Import and clean the SECO-SEC labor-market indicator into a monthly zoo series.
raw_seco_kss <- read_excel("analysis/benchmarks/archive_data_benchmarks/kss.xlsx", sheet = "data", skip = 4, col_names = TRUE)
data_kss <- raw_seco_kss %>%
  rename(Year = 1, Month = 2, "SECO-SEC" = 3, lower = 4, upper = 5) %>%
  mutate(
    Year = as.integer(Year),
    Month = as.integer(Month),
    Date = as.Date(sprintf("%04d-%02d-01", Year, Month))
  ) %>% select(Date, "SECO-SEC")
kss_zoo <- zoo(data_kss$`SECO-SEC`, order.by = as.Date(data_kss$Date, format = "%Y-%m-%d"))

# Import and clean the KOF Barometer into a monthly zoo series.
raw_kof_baro <- read_excel("analysis/benchmarks/archive_data_benchmarks/kof_barometer.xlsx", col_names = TRUE)
data_barro <- raw_kof_baro %>%
  rename(Date = date, "KOF-BARO" = kofbarometer) %>%
  mutate(Date = as.Date(paste0(Date, "-01")))
baro_zoo <- zoo(data_barro$`KOF-BARO`, order.by = as.Date(data_barro$Date, format = "%Y-%m-%d"))

# Import the F-Curve and convert it into the same weekly-style value/time layout.
fcurve <- read.csv("analysis/benchmarks/archive_data_benchmarks/f-curve-data.csv")
fcurve_norm = na.approx(fcurve$f.curve)#sd(x_hist_gr_short)
fcurve_gr <- zoo(x = cbind(-fcurve_norm),
                 order.by = as.Date(fcurve$X, format = "%Y-%m-%d"))
fcurve_gr_full <- fcurve_gr
fcurve_gr_df <- data.frame("value" = as.numeric(fcurve_gr),
                           "time" = time(fcurve_gr))
fcurve_gr_df <- fcurve_gr_df %>%
  filter(time >= as.Date("2005-01-01")) %>%
  filter(time <= sample_end_date)
fcurve_gr_df <- fcurve_gr_df %>% pivot_longer(-c(time))


# -----------------------------------------------------------------------------
# Historical GDP Reference Series
# -----------------------------------------------------------------------------
# Build the quarterly and yearly historical GDP growth series that are used for
# plotting, rescaling, and correlation analysis.
#load("analysis/Rda/data_ch.Rda")
load("analysis/Rda/data_ch_dataset_test.Rda")

# Build the quarter-on-quarter GDP growth series from the latest real-time
# GDP vintage available up to the configured sample-end vintage date, then
# annualize it for downstream comparisons.
target <- "ch.seco.gdp.real.gdp.ssa"
sample_end_gdp_vintage_date <- as.Date("2026-03-07")
sample_end_gdp_vintage_decimal <- round(decimal_date_local(sample_end_gdp_vintage_date), 3)
GDP_gr_vintages_quarterly <- get_real_time_gdp_vintages("quarterly")
sample_end_gdp_vintage <- get_latest_numeric_vintage(
  GDP_gr_vintages_quarterly,
  lower_bound = 2005.438,
  upper_bound = sample_end_gdp_vintage_decimal
)
GDP_gr_vintages_quarterly <- GDP_gr_vintages_quarterly #%>%
#mutate(across(-time, ~ (1 + .x)^4 - 1))
x_hist_gr <- ts(
  GDP_gr_vintages_quarterly[[as.character(sample_end_gdp_vintage)]]*100,
  start = c(1990, 1),
  frequency = 4
)
x_hist_gr <- na.trim(x_hist_gr)
dat$flows[[target]] <- x_hist_gr

x_hist_gr_ann <- ts(
  ((1 + x_hist_gr / 100)^4 - 1) * 100,
  start = start(x_hist_gr),
  frequency = frequency(x_hist_gr)
)


hist_tab_gr <- data.frame(xmin =  seq.Date(as.Date("1990-01-01"),
                                           by = "3 months",
                                           length.out = length(x_hist_gr_ann)),
                          xmax =  seq.Date(as.Date("1990-04-01"),
                                           by = "3 months",
                                           length.out = length(x_hist_gr_ann)),
                          y = as.numeric(x_hist_gr_ann)) %>% 
  pivot_longer(-y)
hist_tab_gr_full <- hist_tab_gr %>%
  filter(value <= sample_end_date)
hist_tab_gr <- hist_tab_gr %>%
  filter(value >= as.Date("2005-01-01"),
         value <= sample_end_date)


# Build a GDP index first so the YoY transformation can be computed from levels.
growth_factor <- 1 + x_hist_gr / 100
gdp_index <- cumprod(replace_na(growth_factor, 1)) * 100
# Convert the quarterly GDP index into standard YoY percent growth.
yoy_growth <- na.trim(ts(100 * (gdp_index - lag(gdp_index, 4)) / lag(gdp_index, 4), start = c(1990,1), frequency = 4))
x_hist_gr_yoy <- yoy_growth
hist_tab_gr_yoy <- data.frame(xmin =  seq.Date(as.Date("1991-01-01"),
                                           by = "3 months",
                                           length.out = length(x_hist_gr_yoy)),
                          xmax =  seq.Date(as.Date("1991-04-01"),
                                           by = "3 months",
                                           length.out = length(x_hist_gr_yoy)),
                          y = as.numeric(x_hist_gr_yoy)) %>% 
  pivot_longer(-y)
hist_tab_gr_yoy_full <- hist_tab_gr_yoy %>%
  filter(value <= sample_end_date)
hist_tab_gr_yoy <- hist_tab_gr_yoy %>%
  filter(value >= as.Date("2005-01-01"),
         value <= sample_end_date)

# Store lagged GDP reference series that are used later in some comparison and
# alignment diagnostics.
x_hist_gr_lag1 <- stats::lag(x_hist_gr, -1)
x_hist_gr_lag1 <- zoo(x_hist_gr_lag1, order.by = as.Date(time(x_hist_gr_lag1), format = "%Y-%m-%d"))
x_hist_gr_lag1_df <- data.frame("value" = as.numeric(x_hist_gr_lag1), "time" = time(x_hist_gr_lag1))
x_hist_gr_lag1_df <- x_hist_gr_lag1_df %>% pivot_longer(-c(time))
x_hist_gr_yoy_lag1 <- stats::lag(x_hist_gr_yoy, -1)
x_hist_gr_yoy_lag1 <- zoo(x_hist_gr_yoy_lag1, order.by = as.Date(time(x_hist_gr_yoy_lag1), format = "%Y-%m-%d"))
x_hist_gr_yoy_lag1_df <- data.frame("value" = as.numeric(x_hist_gr_yoy_lag1), "time" = time(x_hist_gr_yoy_lag1))
x_hist_gr_yoy_lag1_df <- x_hist_gr_yoy_lag1_df %>% pivot_longer(-c(time))


# -----------------------------------------------------------------------------
# Main WAI Fit Objects
# -----------------------------------------------------------------------------
# Load the fixed baseline WAI fit used for the core data objects in this script.
#load("fits/full/testlauf5_20_04_2026.Rda")
load(file.path(sample_config$fit_rt_dir, "fit_2025.979.Rda"))
#load(file.path(sample_config$fit_root, "full", "fit_2021.979.Rda"))
out <- mod
start_date <- 1990
end_date <- 2025 + 47/48
# Rebuild the weekly calendar that corresponds to the model's internal decimal
# time representation.
date_vec <- seq(start_date, end_date, 1/48)
dates <- dec2week(date_vec)
last(dates)
ryear <- floor(time(out$factor))
rmon <- as.numeric(format(as.yearmon(time(out$factor)), "%m"))
rday <- (round((time(out$factor) %% 1) * 48) %% 4 + 1) * 7
res_gr <- zoo(x = cbind(out$factor,
                        out$factor + 1.96 * sqrt(out$factor_var),
                        out$factor - 1.96 * sqrt(out$factor_var)),
              order.by = as.Date(paste0(ryear,"-",sprintf("%02d", rmon),"-",sprintf("%02d", rday)), format = "%Y-%m-%d"))
# Turn the latent factor and uncertainty bands into a tidy plotting table.
tab_gr <- data.frame("mean" = as.numeric(res_gr[,1]),
                     "max" = as.numeric(res_gr[,2]),
                     "min" = as.numeric(res_gr[,3]),
                     "time" = time(res_gr))
tab_gr <- tab_gr %>% pivot_longer(-c(time,min,max))
tab_gr_full <- tab_gr
tab_gr <- tab_gr %>%
  filter(time >= as.Date("2005-01-01"),
         time <= sample_end_date)

# Convert the weekly growth signal into a normalized level index so it can be
# compared with a GDP level path on the same chart.
gr <- (1+out$factor/100)^(1/48)-1
gr <- window(gr,start=time(out$factor)[[1]],end=time(out$factor)[length(out$factor)])
lev <- 100
idx <- rep(NA,length(gr))
for(jx in 1:length(gr)){
  # Convert weekly growth rates into an index level recursively.
  idx[jx]<- exp(gr[jx]) * lev
  lev <- idx[jx]
}
idx_ts <- ts(idx, start = time(out$factor)[1], frequency = frequency(out$factor))
# Normalize the level index so that Q4 2019 averages to 100.
idx_dates <- as.Date(dates)
q4_2019_mask <- idx_dates >= as.Date("2019-10-01") & idx_dates <= as.Date("2019-12-31")
idx_ts_q4_2019 <- mean(idx_ts[q4_2019_mask], na.rm = TRUE)
idx_ts <- 100 * idx_ts / idx_ts_q4_2019
ryear <- floor(time(idx_ts))
rmon <- as.numeric(format(as.yearmon(time(idx_ts)), "%m"))
rday <- (round((time(idx_ts) %% 1) * 48) %% 4 + 1) * 7
merged_max <- merge(zoo(idx_ts, order.by = dates),(1+res_gr[,2]/100)^(1/48), all = FALSE)
merged_min <- merge(zoo(idx_ts, order.by = dates),(1+res_gr[,3]/100)^(1/48), all = FALSE)
lv_max <- ts(merged_max[,1]*merged_max[,2], start = time(out$factor)[1], frequency = frequency(out$factor))
lv_min <- ts(merged_min[,1]*merged_min[,2], start = time(out$factor)[1], frequency = frequency(out$factor))
res_lv <- zoo(x = cbind(idx_ts,
                        lv_max,          #                     out$factor + 1.96 * sqrt(out$factor_var),
                        lv_min           #                     out$factor - 1.96 * sqrt(out$factor_var)
),
order.by = as.Date(paste0(ryear,"-",sprintf("%02d", rmon),"-",sprintf("%02d", rday)), format = "%Y-%m-%d"))
# Build the WAI level table used in the history comparison figure.
tab_gr_lv <- data.frame("mean" = as.numeric(res_lv[,1]),
                      #              "max" = as.numeric(res_lv[,2]),
                      #              "min" = as.numeric(res_lv[,3]),
                  "time" = time(res_lv))
tab_gr_lv <- tab_gr_lv %>% pivot_longer(-c(time))




gr <- x_hist_gr/100
gr <- window(gr,start=time(out$factor)[[1]],end=time(out$factor)[length(out$factor)])
lev <- 100
idx <- rep(NA,length(gr))
for(jx in 1:length(gr)){
  # Build the historical GDP level series on the same normalized index scale.
  idx[jx]<- exp(gr[jx]) * lev
  lev <- idx[jx]
}
hist_ts_lv <- ts(idx, start = time(x_hist_gr)[1], frequency = frequency(x_hist_gr))
# Normalize the GDP level index so that Q4 2019 equals 100.
hist_q4_2019_idx <- which(time(hist_ts_lv) == 2019.75)
hist_ts_lv <- 100 * hist_ts_lv / hist_ts_lv[[hist_q4_2019_idx]]
hist_tab_gr_lv <- data.frame(xmin =  seq.Date(as.Date("1990-01-01"),
                                        by = "3 months",
                                        length.out = length(hist_ts_lv)),
                       xmax =  seq.Date(as.Date("1990-04-01"),
                                        by = "3 months",
                                        length.out = length(hist_ts_lv)),
                       y = as.numeric(hist_ts_lv)) %>% 
  pivot_longer(-y)
tab_gr_lv_full <- tab_gr_lv
hist_tab_gr_lv_full <- hist_tab_gr_lv %>%
  filter(value <= sample_end_date)
tab_gr_lv <- tab_gr_lv %>%
  filter(time >= as.Date("2005-01-01"),
         time <= sample_end_date)
hist_tab_gr_lv <- hist_tab_gr_lv %>%
  filter(value >= as.Date("2005-01-01"),
         value <= sample_end_date)

# Compute the WAI year-over-year growth series from the normalized weekly index.
wai_yoy <- ts(100 * (idx_ts - stats::lag(idx_ts, k = -48)) / stats::lag(idx_ts, k = -48), start = c(1991,1), frequency = 48)
res_wai_yoy <- zoo(x = wai_yoy,
              order.by = as.Date(paste0(ryear[-(1:48)],"-",sprintf("%02d", rmon[-(1:48)]),"-",sprintf("%02d", rday[-(1:48)])), format = "%Y-%m-%d"))
tab_wai_yoy <- data.frame("mean" = as.numeric(res_wai_yoy[,1]),
                     "time" = time(res_wai_yoy))
tab_wai_yoy <- tab_wai_yoy %>% pivot_longer(-c(time))
tab_wai_yoy_full <- tab_wai_yoy
tab_wai_yoy <- tab_wai_yoy %>%
  filter(time >= as.Date("2005-01-01"),
         time <= sample_end_date)

# Extract the stochastic-volatility path from the fitted model for the history panel.
tab_gr_vol <- data.frame("vol" = exp(out$pars$h[1:length(out$factor)]),
                       "time" = time(res_gr))


# -----------------------------------------------------------------------------
# Script Completion Flag
# -----------------------------------------------------------------------------
# Mark the shared data objects as ready so downstream scripts do not rebuild
# them unnecessarily when sourced in the same session.

# Collect the shared data objects in one bundle so they can be reloaded without
# rebuilding the full data-preparation script.
analytics_data_outputs <- list(
  sample_config = sample_config,
  sample_end_date = sample_end_date,
  sample_id = sample_id,
  sample_end_decimal = sample_end_decimal,
  sample_end_fit_decimal = sample_end_fit_decimal,
  wwa_yoy_zoo = wwa_yoy_zoo,
  wwa_index_zoo = wwa_index_zoo,
  wwa_qoq_zoo = wwa_qoq_zoo,
  wwa_2019diff_zoo = wwa_2019diff_zoo,
  wwa_gr_df = wwa_gr_df,
  wwa_gr_df_yoy_full = wwa_gr_df_yoy_full,
  wwa_gr_df_qoq = wwa_gr_df_qoq,
  wwa_gr_df_qoq_full = wwa_gr_df_qoq_full,
  snb_zoo = snb_zoo,
  kss_zoo = kss_zoo,
  baro_zoo = baro_zoo,
  fcurve_gr = fcurve_gr,
  fcurve_gr_full = fcurve_gr_full,
  fcurve_gr_df = fcurve_gr_df,
  x_hist_gr = x_hist_gr,
  hist_tab_gr = hist_tab_gr,
  hist_tab_gr_full = hist_tab_gr_full,
  x_hist_gr_yoy = x_hist_gr_yoy,
  hist_tab_gr_yoy = hist_tab_gr_yoy,
  hist_tab_gr_yoy_full = hist_tab_gr_yoy_full,
  x_hist_gr_lag1 = x_hist_gr_lag1,
  x_hist_gr_lag1_df = x_hist_gr_lag1_df,
  x_hist_gr_yoy_lag1 = x_hist_gr_yoy_lag1,
  x_hist_gr_yoy_lag1_df = x_hist_gr_yoy_lag1_df,
  dates = dates,
  res_gr = res_gr,
  tab_gr = tab_gr,
  tab_gr_full = tab_gr_full,
  res_lv = res_lv,
  tab_gr_lv = tab_gr_lv,
  tab_gr_lv_full = tab_gr_lv_full,
  hist_ts_lv = hist_ts_lv,
  hist_tab_gr_lv = hist_tab_gr_lv,
  hist_tab_gr_lv_full = hist_tab_gr_lv_full,
  wai_yoy = wai_yoy,
  res_wai_yoy = res_wai_yoy,
  tab_wai_yoy = tab_wai_yoy,
  tab_wai_yoy_full = tab_wai_yoy_full,
  tab_gr_vol = tab_gr_vol,
  out = out
)
save_result_output(analytics_data_outputs, "analytics_data_outputs.rda", results_dir)

plots_insample_data_ready <- TRUE
