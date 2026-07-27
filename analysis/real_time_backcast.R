
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

# for Switzerland
load("analysis/Rda/data_ch_dataset_test.Rda")

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

GDP_gr_vintages <- get_real_time_gdp_vintages("quarterly") #%>%
  #mutate(across(-time, ~ (1 + .x)^4 - 1))

# SETTINGS ---------------------------------------------------------

datasets <- list("full_RT" = dat#,
                 #"aggr_weekly" = week2mon(dat),
                 #"only_monthly" = drop_weekly(dat),
                 #"no_financial" = drop_financial(dat),
                 #"only_total_retail" = drop_retail(dat)
                 )

models <- list(#"ar" = run_ar#,
  "wai" = run_wai_adj
  )

# Define start and end dates of out-of-sample evaluation range  
start_date <- 2025 + 41/48 # NOTE: Important to start in the first week of a quarter for the evaluation, i.e. 0/48, 12/48, 24/48 or 36/48!
end_date <- 2025 + 41/48
date_vec <- seq(start_date, end_date, 1/48)


# BACKDATING --------------------------------------------------------------

#cl <- makeCluster(6)
#registerDoParallel(cl)


 foreach(ix = date_vec,
         .packages = c("mfbdfm", "Matrix", "zoo","dplyr",
                       "tidyr", "forecast")) %do% { # %dopar% {

                        for(xdat in datasets){
                          for(model_name in names(models)){
                            run_mod <- models[[model_name]]
                            
                            # prepare data
                            dat_realtime <- cut_data_real_time(xdat, ix, GDP_gr_vintages)
                            dat_realtime$flows[["ch.seco.gdp.real.gdp.ssa"]] <- na.trim(
                              ts(
                                select_most_recent_GDP_vintage(ix, GDP_gr_vintages),
                                start = c(1990, 1),
                                frequency = 4
                              )
                            )
                            
                            # get name of dataset used (only in order to save the WAI model appropriately)
                            dataset_used <- names(datasets)[which(sapply(datasets, function(x) isTRUE(all.equal(x,xdat))))]
                            
                            # run model
                            out <- run_mod(flows = dat_realtime$flows,
                                           stocks = dat_realtime$stocks,
                                           target = "ch.seco.gdp.real.gdp.ssa",
                                           date = ix,
                                           dataset_used = dataset_used,
                                           output_dir = if (model_name == "ar") file.path(fit_root, "ar") else fit_root)
                            rm(out, dat_realtime)
                            invisible(gc())
                            
                          }
                        }
                      }

# stop cluster
if (exists("cl")) stopCluster(cl)




