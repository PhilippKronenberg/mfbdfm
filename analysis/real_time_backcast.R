
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

# WHAT TO FIT -------------------------------------------------------------
#
# `full_RT` is the baseline and is always fitted; name any of the others to fit
# them alongside it. Same arrangement as analysis/2_backcast.R.
#
#   full_RT              every series, real-time vintages   <- the baseline
#   aggr_weekly          weekly series aggregated to monthly
#   only_monthly         weekly indicators dropped
#   no_financial         financial indicators dropped
#   only_total_retail    retail series reduced to the total
variants <- "full_RT"
# variants <- c("full_RT", "aggr_weekly", "only_monthly", "no_financial",
#               "only_total_retail")

# 1 runs the date loop serially; >1 starts that many workers and uses them.
n_workers <- 1

variant_spec <- list(
  full_RT           = function(d) d,
  aggr_weekly       = function(d) week2mon(d),
  only_monthly      = function(d) drop_weekly(d),
  no_financial      = function(d) drop_financial(d),
  only_total_retail = function(d) drop_retail(d)
)

variants <- unique(c("full_RT", variants))       # the baseline is not optional
unknown <- setdiff(variants, names(variant_spec))
if (length(unknown)) {
  stop("Unknown dataset variant(s): ", paste(unknown, collapse = ", "), ".\n",
       "  Available: ", paste(names(variant_spec), collapse = ", "), ".",
       call. = FALSE)
}

datasets <- lapply(variant_spec[variants], function(f) f(dat))

models <- list(#"ar" = run_ar#,
  "wai" = run_wai_adj
  )

message(length(datasets), " dataset variant(s): ",
        paste(names(datasets), collapse = ", "))

# Define start and end dates of out-of-sample evaluation range  
start_date <- 2025 + 41/48 # NOTE: Important to start in the first week of a quarter for the evaluation, i.e. 0/48, 12/48, 24/48 or 36/48!
end_date <- 2025 + 41/48
date_vec <- seq(start_date, end_date, 1/48)


# BACKDATING --------------------------------------------------------------

if (n_workers > 1) {
  cl <- makeCluster(n_workers)
  registerDoParallel(cl)
  message("running ", length(date_vec), " date(s) on ", n_workers, " workers")
} else {
  registerDoSEQ()
  message("running ", length(date_vec), " date(s) serially")
}

 foreach(ix = date_vec,
         .packages = c("mfbdfm", "Matrix", "zoo","dplyr",
                       "tidyr", "forecast")) %dopar% {

                        for(dataset_name in names(datasets)){
                          xdat <- datasets[[dataset_name]]
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
                            
                            # The loop carries the name now. It used to recover it
                            # by all.equal()-ing the data object against every
                            # entry of `datasets` - a deep comparison of the whole
                            # dataset per fit, and one that returns a VECTOR, not a
                            # name, if two variants ever compare equal (a variant
                            # whose transform happens to be a no-op would do it).
                            dataset_used <- dataset_name

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

# stop the cluster if one was started. Guarded, because n_workers = 1 registers
# doSEQ and creates no `cl`. Not on.exit(): at a script's top level that does not
# defer to the end of the script - under Rscript it never fires at all.
if (exists("cl")) stopCluster(cl)




