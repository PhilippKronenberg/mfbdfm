
# PRELIM ------------------------------------------------------------------

# Run from the repository root.

library(Matrix)
library(zoo)
library(dplyr)
library(tidyr)
library(foreach)
library(readxl)

library(mfbdfm)

sample_config <- wai_sample_config(sample_id = "0_test",
                                    output_root = file.path("analysis", "outputs", "0_test"))
results_dir <- sample_config$results_dir


# IMPORT DATA -------------------------------------------------------------

# for Switzerland
#load("analysis/Rda/data_ch.Rda")
#load("analysis/Rda/data_ch_dataset.Rda")
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




# SETTINGS ---------------------------------------------------------

# truncate_to_q3_2021 <- function(x) {
#   if (!is.ts(x)) {
#     return(x)
#   }
# 
#   if (frequency(x) == 4) {
#     return(window(x, end = c(2021, 3)))
#   }
# 
#   if (frequency(x) == 12) {
#     return(window(x, end = c(2021, 11)))
#   }
# 
#   if (frequency(x) == 48) {
#     return(window(x, end = c(2021, 47)))
#   }
# 
#   x
# }
# 
# dat$flows <- lapply(dat$flows, truncate_to_q3_2021)
# dat$stocks <- lapply(dat$stocks, truncate_to_q3_2021)
tail(time(dat$flows$ch.seco.gdp.real.gdp.ssa),1)[1]

out <- hfdfm(flows = dat$flows,
             stocks = dat$stocks,
             burn_in = 1000,
             length_sample = 10000,
             thinning = 1,
             p = 1, # Number of factor lags in factor state equation. 
             q = 1, # Number of factors
             extend_to = tail(time(dat$flows$ch.seco.gdp.real.gdp.ssa),1),# + 0.25,
             plots = TRUE, 
             stochastic_volatility = TRUE, 
             serial_correlation = TRUE,
             target = target)


save_result_output(out, "final_20_04_2026.rda", results_dir)


# CHECK FORECAST DISTRIBUTION ---------------------------------------------

# plot(cbind(out$ncst$mean$ch.seco.gdp.real.gdp.ssa, 
#            out$ncst$mean$ch.seco.gdp.real.gdp.ssa  - 1.96 * sqrt(out$ncst$var$ch.seco.gdp.real.gdp.ssa),
#            out$ncst$mean$ch.seco.gdp.real.gdp.ssa  + 1.96 * sqrt(out$ncst$var$ch.seco.gdp.real.gdp.ssa)), 
#      plot.type="single", col = c(2,1,1))





plot(cbind(out$nowcast,
     out$nowcast - 1.96 * sqrt(out$nowcast_var),
     out$nowcast + 1.96 * sqrt(out$nowcast_var)),
     plot.type="single", col = c(2,1,1)
)







