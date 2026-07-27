
# Run from the repository root.

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Model Run and Fit Generation for Swiss Weekly GDP Indicator
# Authors: Florian Eckert, Philipp Kronenberg, Heiner Mikosch, Stefan Neuwirth
# Last Update: 09/02/2022
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

# NOTES -------------------------------------------------------------------

# Forecast evaluation:

# 2 Models to evaluate:
#       - DFM model
#       - AR-model
#
# 2 data sets to evaluate
#       - full data set
#       - weekly variables aggregated to monthly frequency
#
# 3 Evaluation periods:
#       - Full time span (when should it start?)
#       - First forecast in 2020Q1 (Beginning of Corona-Pandemic)
#       - First forecast in 2015Q1 (CHF Exchange-rate shock)

# Out-of-sample evaluation with expanding window (rolling window not implemented)


# PACKAGES AND FUNCTIONS --------------------------------------------------

library(Matrix)
library(zoo)
library(dplyr)
library(tidyr)
library(forecast)
library(foreach)
library(doParallel)
library(readxl)

library(mfbdfm)

fit_root <- "fits/updated"  # where model fits are written (git-ignored)



# IMPORT DATA -------------------------------------------------------------

load("analysis/Rda/data_ch_dataset_test.Rda")

sample_end_indicator_date <- 2026
dat <- cut_data(dat, current_date = sample_end_indicator_date)
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
  GDP_gr_vintages_quarterly[[as.character(sample_end_gdp_vintage)]],
  start = c(1990, 1),
  frequency = 4
)
x_hist_gr <- na.trim(x_hist_gr)
dat$flows[[target]] <- x_hist_gr


# # for Switzerland
# load("analysis/Rda/data_ch_dataset.Rda")
# 
# sample_end_gdp_vintage_date <- as.Date("2025-12-31")
# GDP_gr_vintages_quarterly <- get_real_time_gdp_vintages("quarterly")
# sample_end_gdp_vintage <- get_next_extending_numeric_vintage(
#   GDP_gr_vintages_quarterly,
#   reference_date = sample_end_gdp_vintage_date,
#   lower_bound = 2005.438
# )
# GDP_gr_vintages_quarterly <- GDP_gr_vintages_quarterly %>%
#   mutate(across(-time, ~ (1 + .x)^4 - 1))
# x_hist_gr <- ts(
#   GDP_gr_vintages_quarterly[[as.character(sample_end_gdp_vintage)]],
#   start = c(1990, 1),
#   frequency = 4
# )
# x_hist_gr <- window(x_hist_gr, end = time(x_hist_gr)[sum(!is.na(x_hist_gr))] - 0.25)
# dat$flows[["ch.seco.gdp.real.gdp.ssa"]] <- x_hist_gr

# # discontinue retail data
# dat$flows[which(grepl(pattern = "rtt", names(dat$flows)))] <- 
#   lapply(dat$flows[which(grepl(pattern = "rtt", names(dat$flows)))], 
#          function(x){window(x, end = 2021)})


# Version to test
# 1.) Only Monthly and Quarterly without SV
# 1.) Full with high-frequency without SV
# 2.) Full with high-frequency with SV
# 3.) Full without Financial Variables
# 4.) Full with only total retail sales
# 5.) Vary number of lags in measurement error
# 6.) Vary number of factors
# SETTINGS ---------------------------------------------------------

datasets <- list(
  #"full" = list(data = dat, stochastic_volatility = TRUE),
  #"full_no_sv" = list(data = dat, stochastic_volatility = FALSE)#,
  #"only_monthly" = list(data = drop_weekly(dat), stochastic_volatility = TRUE)
  #"only_monthly_no_sv" = list(data = drop_weekly(dat), stochastic_volatility = FALSE)#,
  "no_financial" = list(data = drop_financial(dat), stochastic_volatility = TRUE)#,
  #"only_total_retail" = list(data = drop_retail(dat), stochastic_volatility = TRUE)
)

models <- list(#"ar" = run_ar,
               "wai" = run_wai_adj)

# Define start and end dates of out-of-sample evaluation range  
start_date <- 2025 + 47/48 # NOTE: Important to start in the first week of a quarter for the evaluation, i.e. 0/48, 12/48, 24/48 or 36/48!
end_date <- 2025 + 47/48
date_vec <- seq(start_date, end_date, 1/48)


# BACKDATING --------------------------------------------------------------

# cl <- makeCluster(2)
# registerDoParallel(cl)

# loop over datasets
# foreach(ix = date_vec,
#                    xdat = datasets,
foreach(ix = date_vec,
        .packages = c("mfbdfm", "Matrix", "zoo","dplyr",
                      "tidyr", "forecast")) %do% { # %dopar% {

          for(dataset_name in names(datasets)){
            dataset_cfg <- datasets[[dataset_name]]
            xdat <- dataset_cfg$data
            stochastic_volatility <- dataset_cfg$stochastic_volatility

            for(model_name in names(models)){
              run_mod <- models[[model_name]]

              # prepare data
              dat_realtime <- cut_data(xdat, ix)

              # run model; the AR benchmark keeps its own subfolder as before
              out <- run_mod(flows = dat_realtime$flows,
                             stocks = dat_realtime$stocks,
                             target = "ch.seco.gdp.real.gdp.ssa",
                             date = ix,
                             dataset_used = dataset_name,
                             stochastic_volatility = stochastic_volatility,
                             output_dir = if (model_name == "ar") file.path(fit_root, "ar") else fit_root)

            }
          }
        }

# stop cluster
stopCluster(cl)




