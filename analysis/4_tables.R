
# Run from the repository root.

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Tables for Swiss Weekly GDP Indicator
# Authors: Florian Eckert, Philipp Kronenberg, Heiner Mikosch, Stefan Neuwirth 
# Last Update: 09/02/2022
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% 

# PACKAGES AND FUNCTIONS --------------------------------------------------

library(ggplot2)
library(tibble)
library(tidyr)
library(dplyr)
library(xtable)
library(Matrix)
library(zoo)      # for as.yearmon, as.yearqtr

# IMPORT DATA -------------------------------------------------------------

library(mfbdfm)
source("analysis/5_plots/_setup.R")  # figures_dir / tables_dir / results_dir

fit_root <- "fits"  # root of the model fits (git-ignored)

# Inputs, checked up front rather than failing at whichever load() first needs
# them. All of them are produced by other scripts here and none is tracked, so a
# clean checkout has none of them; naming the producer is the point (#59, #63).
inputs <- c(
  "analysis/Rda/data_ch_dataset_test.Rda"           = "analysis/1_data_prep_dataset.R",
  "analysis/out/data_ch_dataset_raw_start_end.csv"  = "analysis/1_data_prep_dataset.R",
  "fits/updated/full_RT/fit_2025.979.Rda"           = "analysis/real_time_backcast.R",
  "fits/updated/full_RT/fit_2008.833.Rda"           = "analysis/real_time_backcast.R",
  "fits/updated/full_RT/fit_2009.771.Rda"           = "analysis/real_time_backcast.R",
  "fits/updated/full_RT/fit_2020.Rda"               = "analysis/real_time_backcast.R",
  "fits/updated/full_no_sv/fit_2025.979.Rda"        = "analysis/2_backcast.R",
  "fits/updated/only_monthly_no_sv/fit_2025.979.Rda" = "analysis/2_backcast.R",
  "fits/updated/only_monthly/fit_2025.979.Rda"      = "analysis/2_backcast.R",
  "fits/updated/no_financial/fit_2025.979.Rda"      = "analysis/2_backcast.R"
)
missing_inputs <- names(inputs)[!file.exists(names(inputs))]
if (length(missing_inputs)) {
  stop("4_tables.R is missing ", length(missing_inputs), " input(s):\n",
       paste0("  ", missing_inputs, "\n    produced by ", inputs[missing_inputs],
              collapse = "\n"),
       call. = FALSE)
}

load("analysis/Rda/data_ch_dataset_test.Rda")

# Metadata Table ------------------------------------------------------------------

# Get Metadata & Keys
metadata <- utils::read.csv("data-raw/data_meta.csv")

# Rename Columns
names(metadata)[names(metadata) == "Flow"] <- "Type"
names(metadata)[names(metadata) == "keys"] <- "Keys"

# Add End Date From Raw Data Availability File
date_ranges <- read.csv("analysis/out/data_ch_dataset_raw_start_end.csv", stringsAsFactors = FALSE)
if (!"Keys" %in% names(date_ranges) && "series" %in% names(date_ranges)) {
  names(date_ranges)[names(date_ranges) == "series"] <- "Keys"
}

# Keep backwards compatibility with the legacy LIBOR key used in data_meta.csv.
if ("ch.snb.zimoma.3m0" %in% metadata$Keys &&
    !"ch.snb.zimoma.3m0" %in% date_ranges$Keys &&
    "se.macrobond.chrate0006" %in% date_ranges$Keys) {
  libor_row <- date_ranges[date_ranges$Keys == "se.macrobond.chrate0006", ]
  libor_row$Keys <- "ch.snb.zimoma.3m0"
  date_ranges <- rbind(date_ranges, libor_row)
}

date_ranges <- unique(date_ranges[, c("Keys", "end_date")])
names(date_ranges)[names(date_ranges) == "end_date"] <- "End Date"
metadata <- merge(metadata, date_ranges, by = "Keys", all.x = TRUE, sort = FALSE)

# Add Start Date
data_vec <- c(dat$stocks,dat$flows)
names(data_vec) <- c(names(dat$stocks),names(dat$flows))
dates_vec <- c()
for (i in metadata$Keys){
  dates_vec[i] <- time(data_vec[[i]])[1]
}
metadata$`Start.Date` <- dates_vec
names(metadata)[names(metadata) == "Start.Date"] <- "Start Date"

# Rename Stock and Flow
metadata$Type[metadata$Type == "1"] <- "Flow"
metadata$Type[metadata$Type == "0"] <- "Stock"

# Add Summary Statistics From Inventory
inventory <- create_inventory(flows = dat$flows, stocks = dat$stocks)
names(inventory)[names(inventory) == "key"] <- "Keys"
metadata <- merge(metadata,inventory[,c("Keys","mean","sd")], by = "Keys")

# Sort Columns by Frequency and Type
metadata <- metadata[with(metadata, order(Category, `Start Date`, Frequency, Name, decreasing=FALSE)),]

# Format End Date Like Start Date
format_end_date <- function(date_string, freq) {
  if (is.na(date_string) || date_string == "") {
    return(NA_character_)
  }

  end_date <- as.Date(date_string)
  if (is.na(end_date)) {
    return(NA_character_)
  }

  if (freq == 4) {
    quarter <- ((as.integer(format(end_date, "%m")) - 1) %/% 3) + 1
    return(paste0(format(end_date, "%Y"), "Q", quarter))
  }

  if (freq == 12) {
    return(paste0(format(end_date, "%Y"), "M", as.integer(format(end_date, "%m"))))
  }

  if (freq == 48) {
    return(paste0(format(end_date, "%G"), "W", as.integer(format(end_date, "%V"))))
  }

  NA_character_
}

# Convert Start Date to Readable Format
metadata$Year <- floor(metadata$`Start Date`)
metadata$Temp <- round(metadata$`Start Date` - floor(metadata$`Start Date`),digits=3)
metadata$Subperiod[metadata$Temp == 0 & metadata$Frequency==4] <- "Q1"
for (ix in 1:3){
  metadata$Subperiod[metadata$Temp == round(ix/4,digits=3) & metadata$Frequency==4] <- paste0("Q",ix+1,sep="")
}
metadata$Subperiod[metadata$Temp == 0 & metadata$Frequency==12] <- "M1"
for (ix in 1:11){
  metadata$Subperiod[metadata$Temp == round(ix/12,digits=3) & metadata$Frequency==12] <- paste0("M",ix+1,sep="")
}
metadata$Subperiod[metadata$Temp == 0 & metadata$Frequency==48] <- "W1"
for (ix in 1:47){
  metadata$Subperiod[metadata$Temp == round(ix/48,digits=3) & metadata$Frequency==48] <- paste0("W",ix+1,sep="")
}
metadata$`Start Date` <- paste0(metadata$Year,metadata$Subperiod,sep="")
metadata$`End Date` <- mapply(format_end_date, metadata$`End Date`, metadata$Frequency)
  
# Adjust Frequency Entries
metadata$Frequency[metadata$Frequency==4] <- "Quarterly"
metadata$Frequency[metadata$Frequency==12] <- "Monthly"
metadata$Frequency[metadata$Frequency==48] <- "Daily"
metadata$Frequency[metadata$Name=="Credit Card Transactions, Swiss-Wide Frequency"] <- "Weekly"

# Add Release Lag of Variables
 # Note: These release lags are not fully coherent with the release lags chosen 
 # for the out-of-sample evaluation in functions_backcast.R, function cut_data_helper (lines 91ff).
 # In a updated version of the code, set the release dates in data_meta.csv both as input
 # for the function cut_data_helper and for creation of the data table in here.

metadata <- metadata %>%
  mutate('Release Lag' = case_when(Frequency == 'Monthly' ~ '5W',
         (Category == 'Retail' | Frequency == 'Quarterly')  ~ '9W',
         TRUE ~ '1W'))

metadata <- metadata %>%
  mutate('Release Lag' = case_when(((Category == 'Retail' & Frequency == 'Monthly') | Frequency == 'Quarterly') ~'9W',
         (Frequency =='Monthly' & Category !='Retail') ~ '5W',
         TRUE ~'1W'))
metadata_small <- metadata  
# Select Columns and Change Column Order
metadata <- subset(metadata, select = c("Name","Category","Frequency","Release Lag","Start Date","End Date","Unit","Transformation","Type","Source"))

# Table as Latex Output
print(xtable(metadata), include.rownames=FALSE, type = "latex", file = file.path(tables_dir, "datatable.tex"))


# Lambda Table ------------------------------------------------------------


# The five extract_wai_data() calls that used to sit here were dead: nothing in
# this script read result_wai, result_wai_no_sv, result_wai_only_monthly_no_sv,
# result_wai_no_hf or result_wai_no_financial. The lambda table below is built
# from the `mod` objects loaded immediately after, which are the same fits. The
# block is a stale copy of analysis/5_plots/analytics_in_sample.R:360-368, where
# those objects *are* used; it also carried the only other broken path in this
# file, fits/full/testlauf5_20_04_2026.Rda, a directory that has not existed
# since the fits/updated/ reorganisation (#63).

load(file.path(fit_root, "updated/full_RT/fit_2025.979.Rda"))
dat_last <- mod
var_names_last <- dat_last$inventory$key
load(file.path(fit_root, "updated/full_no_sv/fit_2025.979.Rda"))
dat_full_No_SV <- mod
var_names_full_No_SV <- dat_full_No_SV$inventory$key
load(file.path(fit_root, "updated/only_monthly_no_sv/fit_2025.979.Rda"))
dat_only_monthly_No_SV <- mod
var_names_only_monthly_No_SV <- dat_only_monthly_No_SV$inventory$key
load(file.path(fit_root, "updated/only_monthly/fit_2025.979.Rda"))
dat_only_monthly <- mod
var_names_only_monthly <- dat_only_monthly$inventory$key
load(file.path(fit_root, "updated/no_financial/fit_2025.979.Rda"))
dat_no_financial <- mod
var_names_no_financial <- dat_no_financial$inventory$key
# load(file.path(fit_root, "only_total_retail/fit_2025.979.Rda"))
# dat_only_total_retail <- out
# var_names_only_total_retail <- dat_only_total_retail$inventory$key

#metadata <- utils::read.csv("data-raw/data_meta.csv")



lambdas_last <- round(dat_last$pars$lambda,2)
lambdas_full_No_SV <- round(dat_full_No_SV$pars$lambda,2)
lambdas_only_monthly_No_SV <- round(dat_only_monthly_No_SV$pars$lambda,2)
lambdas_only_monthly <- round(dat_only_monthly$pars$lambda,2)
lambdas_no_financial <- round(dat_no_financial$pars$lambda,2)
#lambdas_only_total_retail  <- round(dat_only_total_retail$pars$lambda,2)

# --- 1) Coerce S4 matrices to numeric vectors and name them --- 
lambdas_full_No_SV_vec <- as.numeric(lambdas_full_No_SV)
names(lambdas_full_No_SV_vec) <- var_names_full_No_SV

lambdas_only_monthly_No_SV_vec <- as.numeric(lambdas_only_monthly_No_SV)
names(lambdas_only_monthly_No_SV_vec) <- var_names_only_monthly_No_SV

lambdas_only_monthly_vec <- as.numeric(lambdas_only_monthly)
names(lambdas_only_monthly_vec) <- var_names_only_monthly

lambdas_no_financial_vec <- as.numeric(lambdas_no_financial)
names(lambdas_no_financial_vec) <- var_names_no_financial

# lambdas_only_total_retail_vec <- as.numeric(lambdas_only_total_retail)
# names(lambdas_only_total_retail_vec) <- var_names_only_total_retail

# lambdas_last is already aligned to var_names_last, but ensure it's numeric
lambdas_last_vec <- as.numeric(lambdas_last)
names(lambdas_last_vec) <- var_names_last



# --- 2) Pull out in the order of var_names_last, NAs where missing ---
aligned_full_No_SV <- lambdas_full_No_SV_vec[var_names_last]
aligned_only_monthly_No_SV <- lambdas_only_monthly_No_SV_vec[var_names_last]
aligned_only_monthly <- lambdas_only_monthly_vec[var_names_last]
aligned_no_financial <- lambdas_no_financial_vec[var_names_last]
#aligned_total_retail <- lambdas_only_total_retail_vec[var_names_last]

# --- 3) Replace NAs with 0 ---
aligned_full_No_SV[is.na(aligned_full_No_SV)] <- 0
aligned_only_monthly_No_SV[is.na(aligned_only_monthly_No_SV)] <- 0
aligned_only_monthly[is.na(aligned_only_monthly)] <- 0
aligned_no_financial[is.na(aligned_no_financial)] <- 0
#aligned_total_retail[is.na(aligned_total_retail)] <- 0

# --- 4) (Optional) report which names were missing in each series ---
missing_in_full_No_SV <- setdiff(var_names_last, var_names_full_No_SV)
missing_in_only_monthly_No_SV <- setdiff(var_names_last, var_names_only_monthly_No_SV)
missing_in_only_monthly <- setdiff(var_names_last, var_names_only_monthly)
missing_in_no_financial <- setdiff(var_names_last, var_names_no_financial)
#missing_in_total_retail <- setdiff(var_names_last, var_names_only_total_retail)

if(length(missing_in_full_No_SV)) {
  message("These variables had no full_No_SV λ and were set to 0:\n", paste(missing_in_full_No_SV, collapse = ", "))
}
if(length(missing_in_only_monthly_No_SV)) {
  message("These variables had no nly_monthly_No_SV λ and were set to 0:\n", paste(missing_in_only_monthly_No_SV, collapse = ", "))
}
if(length(missing_in_only_monthly)) {
  message("These variables had no only_monthly λ and were set to 0:\n", paste(missing_in_only_monthly, collapse = ", "))
}
if(length(missing_in_no_financial)) {
  message("These variables had no only_monthly λ and were set to 0:\n", paste(missing_in_no_financial, collapse = ", "))
}
# if(length(missing_in_total_retail)) {
#   message("These variables had no only_monthly λ and were set to 0:\n", paste(missing_in_total_retail, collapse = ", "))
# }


# --- 5) Combine into one data.frame ---
df <- data.frame(
  variable     = var_names_last,
  lambda_last  = lambdas_last_vec,
  lambda_full_No_SV    = aligned_full_No_SV,
  lambda_only_monthly_No_SV    = aligned_only_monthly_No_SV,
  lambda_only_monthly    = aligned_only_monthly,
  lambda_no_financial    = aligned_no_financial,
  #lambda_total_retail    = aligned_total_retail,
  stringsAsFactors = FALSE
)

metadata_small <- metadata_small %>%
  select(Keys, Name, Frequency, `Release Lag`, `Start Date`)

df_named <- df %>%
  left_join(metadata_small, by = c(variable = "Keys")) %>%  # bring in Name
  select(variable = Name, Frequency, `Release Lag`, `Start Date`, lambda_last, lambda_full_No_SV, lambda_only_monthly_No_SV, lambda_only_monthly, lambda_no_financial,)%>% # lambda_total_retail, ) %>%
  rename("Variable Name" = variable)# drop the old code, rename

# 2) convert to an xtable object
xt <- xtable(
  df_named,
  caption = "Estimated Lambdas for Different Samples",
  label   = "tab:lambdas"
)



library(dplyr)
library(ISOweek)  # for ISOweek2date

xt_sorted <- xt %>%
  arrange(
    # extract characters 1–4 and turn into integer for proper ordering
    as.integer(substr(`Start Date`, 1, 4)),
    Frequency
  )


# 3) print the LaTeX table
print(
  xt,
  include.rownames    = FALSE,
  booktabs            = TRUE,
  caption.placement   = "top",
  sanitize.text.function = identity,
  floating            = TRUE,              # keeps the table float
  tabular.environment = "tabular*",        # use tabular* instead of tabular
  width               = "\\textwidth"      # stretch to the full text width
)

library(dplyr)
library(xtable)

# 1) Sort by year (first 4 chars of Start Date) and Frequency
xt_sorted <- xt %>%
  arrange(Frequency)
xt_sorted <- xt %>%
  mutate(Frequency = factor(Frequency, levels = c("Quarterly", "Monthly", "Weekly", "Daily"))) %>%
  arrange(Frequency)



short_names <- c(
  "Gross Domestic Product, Adjusted for International Sport Events" = "GDP (sport-adj.)",
  "Consumer Price Index, Total" = "CPI (total)",
  "Producer Prices Index" = "PPI",
  "Consumer Price Index, Excl. Energy, Fresh & Seasonal Products" = "Core CPI (ex energy & fresh)",
  "Retail Sales, Total" = "Retail (total)",
 # "Retail Sales, Food, Beverage and Tobacco" = "Retail: Food & tobacco",
#  "Retail Sales, Non-Food" = "Retail: Non-food",
#  "Retail Sales, Information and Communication Equipment" = "Retail: Info & comm equip",
#  "Retail Sales, Household Equipment" = "Retail: Household equip",
#  "Retail Sales, Culture and Recreation Goods, Constant Prices" = "Retail: Culture & recreation",
#  "Retail Sales, Other Goods" = "Retail: Other goods",
  "Business Situation Assessment, Manufacturing" = "Business Survey: Manufacturing",
  "Business Situation Assessment, Construction" = "Business Survey: Construction",
  "Business Situation Assessment, Finance & Insurance" = "Business Survey: Finance & insurance",
  "Business Situation Assessment, Project Engineering" = "Business Survey: Project engineering",
  "Business Situation Assessment, All Industries" = "Business Survey: All industries",
  "Business Situation Assessment, Manufacturing Investment Goods " = "Business Survey: Invest goods",
  "Business Situation Assessment, Manufacturing Durable Goods" = "Business Survey: Durable goods",
  "Business Situation Assessment, Manufacturing Consumption Goods" = "Business Survey: Consumption goods",
  "Business Situation Assessment, Manufacturing Intermediate Goods, " = "Business Survey: Intermediate goods",
  "Switzerland, Export: Total, Real, SA, Index (1997=100)" = "Real exports (SA)",
  "Switzerland, Import: Total, Real, SA, Index (1997=100)" = "Real imports (SA)",
#  "10-Year Confederation Bond Yield" = "10Y Bond yield",
  "Purchasing Managers Index, Manufacturing Sector" = "PMI: Manufacturing",
  "Purchasing Managers Index, Manufacturing Sector, Backlog of Orders" = "PMI: Backlog",
  "Purchasing Managers Index, Manufacturing Sector, Output" = "PMI: Output",
#  "3-Month CHF LIBOR" = "3Month CHF LIBOR",
  "Credit Card Transactions, Swiss-Wide Frequency" = "Credit cards Transactions",
  "Swiss Stock Market Index, Financials" = "Swiss Stock Market Index: Financials",
  "Swiss Stock Market Index, Industrials" = "Swiss Stock Market Index: Industrials",
  "Swiss Market Index (SMI) " = "Swiss Stock Market Index (headline)",
  "Public Transport Passenger Frequency, Zurich Main Station" = "Public Transport: Zürich HB",
  "Public Transport Passenger Frequency, Zurich Hardbruecke" = "Public Transport: Zürich Hardbrücke",
  "Median Day Distance of Representative Swiss Population Sample" = "Mobility: Mobile Phone",
  "Swiss Debit Card Transactions Abroad, Volume in CHF" = "Debit Card Transaction: abroad (CHF)",
  "Cash Withdrawals, Swiss-Wide Volume in CHF" = "Cash withdrawals (CHF)",
  "Non-Online Retail Sales, Swiss-Wide Volume in CHF" = "Retail Sales (non-online, CHF)",
  "Private Transport Frequency, Important Counting Stations, Zurich" = "Private traffic",
  "Passenger Car Frequency, Counting Stations on Major Swiss Motorways" = "Car traffic",
  "Truck Frequency, Counting Stations on Major Swiss Motorways" = "Truck traffic",
  "Truck-Toll Mileage Index, Germany" = "Germany truck-toll index",
  "Energy Consumed by Swiss End Users" = "Energy use: end users",
  "Energy Production in Switzerland" = "Energy production (CH)",
  "Total Flight Departures, Zurich Airport" = "Flight departures: ZRH",
  "Total Flight Arrivals, Zurich Airport" = "Flight arrivals: ZRH",
  "Google COVID-19 Community Mobility Reports, Retail and Recreation" = "Google Mobility: Retail & recreation",
  "Google COVID-19 Community Mobility Reports, Grocery and Pharmacy" = "Google Mobility: Grocery & pharmacy",
  "Google COVID-19 Community Mobility Reports, Parks" = "Google Mobility: Parks",
  "Google COVID-19 Community Mobility Reports, Transit Stations" = "Google Mobility: Transit stations",
  "Google COVID-19 Community Mobility Reports, Workplaces" = "Google Mobility: Workplaces",
  "Google COVID-19 Community Mobility Reports, Residential" = "Google Mobility: Residential",
  "Google Search Index, Perceived Economic Situation" = "Google search: economy sentiment",
  "Google Search Index, Perceived Labour Market Situation" = "Google search: labour sentiment",
  "Volatility Index (VIX)" = "Volatility Index (VIX)"
)



library(ggplot2)
library(dplyr)

xt_bars <- xt_sorted

# Absolute values
xt_bars$lambda_last <- abs(xt_bars$lambda_last)

# Add short names
xt_bars$short_name <- short_names[xt_bars$`Variable Name`]
xt_bars$short_name[is.na(xt_bars$short_name)] <- xt_bars$`Variable Name`[is.na(xt_bars$short_name)]

# Reorder
xt_bars <- xt_bars %>%
  arrange(desc(lambda_last)) %>%
  mutate(order_id = row_number())

# Split into two roughly equal groups
n <- nrow(xt_bars)
xt_bars$panel <- ifelse(xt_bars$order_id <= ceiling(n/2), "Group 1", "Group 2")

# Color rule
xt_bars$color_group <- ifelse(
  xt_bars$Frequency %in% c("Weekly", "Daily"), "Weekly/Daily",
  "Monthly/Quarterly"
)

# Plot
ggplot(xt_bars, aes(x = reorder(short_name, lambda_last), y = lambda_last, fill = color_group)) +
  geom_bar(stat = "identity") +
  coord_flip(clip = "off") +
  facet_wrap(~panel, ncol = 2, scales = "free_y") +
  labs(
    #title = expression(paste("Estimated ", lambda[last], " (absolute values)")),
    x = NULL,
    y = NULL,
    fill = "Frequency"
  ) +
  scale_fill_manual(
    values = c("Weekly/Daily" = "red", "Monthly/Quarterly" = "blue")
  ) +
  theme_minimal(base_size = 16) +
  theme(
    axis.text.y = element_text(size = 12),
    strip.text = element_blank(),
    legend.position = c(0.985, 0.95),
    legend.justification = c("right", "top"),
    plot.title = element_text(face = "bold")
  )





# 2) Wrap zeros in \textcolor{red}{0}
xt_colored <- xt_sorted %>%
  mutate(across(
    where(is.numeric),
    ~ ifelse(. == 0,
             "\\textcolor{red}{0}",
             as.character(.))
  )) %>%
  # if you have non-numeric columns that might contain "0" as text,
  # you can include them too, e.g. across(everything(), ...)
  mutate(across(
    where(~ is.character(.) && any(. == "0")),
    ~ ifelse(. == "0",
             "\\textcolor{red}{0}",
             .)
  ))

# 3) Turn into an xtable and print
xtab <- xtable(xt_colored,
               caption = "Estimated Lambdas for Different Samples",
               label   = "tab:mytable")

print(
  xtab,
  include.rownames         = FALSE,
  booktabs                 = TRUE,
  caption.placement        = "top",
  sanitize.text.function   = identity,   # so our \textcolor survives
  floating                 = TRUE,
  tabular.environment      = "tabular*",
  width                    = "\\textwidth"
)



# Lambda Table ------------------------------------------------------------

load(file.path(fit_root, "updated/full_RT/fit_2025.979.Rda"))
dat_last <- mod
var_names_last <- dat_last$inventory$key
load(file.path(fit_root, "updated/full_RT/fit_2008.833.Rda"))
dat_PG <- mod
var_names_PG <- dat_PG$inventory$key
load(file.path(fit_root, "updated/full_RT/fit_2009.771.Rda"))
dat_GR <- mod
var_names_GR <- dat_GR$inventory$key
load(file.path(fit_root, "updated/full_RT/fit_2020.Rda"))
dat_PC <- mod
var_names_PC <- dat_PC$inventory$key

#metadata <- utils::read.csv("data-raw/data_meta.csv")



lambdas_last <- round(dat_last$pars$lambda,2)
lambdas_PG <- round(dat_PG$pars$lambda,2)
lambdas_GR <- round(dat_GR$pars$lambda,2)
lambdas_PC <- round(dat_PC$pars$lambda,2)

# --- 1) Coerce S4 matrices to numeric vectors and name them --- 
lambdas_PG_vec <- as.numeric(lambdas_PG)
names(lambdas_PG_vec) <- var_names_PG

lambdas_GR_vec <- as.numeric(lambdas_GR)
names(lambdas_GR_vec) <- var_names_GR

lambdas_PC_vec <- as.numeric(lambdas_PC)
names(lambdas_PC_vec) <- var_names_PC

# lambdas_last is already aligned to var_names_last, but ensure it's numeric
lambdas_last_vec <- as.numeric(lambdas_last)
names(lambdas_last_vec) <- var_names_last

# --- 2) Pull out in the order of var_names_last, NAs where missing ---
aligned_PG <- lambdas_PG_vec[var_names_last]
aligned_GR <- lambdas_GR_vec[var_names_last]
aligned_PC <- lambdas_PC_vec[var_names_last]

# --- 3) Replace NAs with 0 ---
aligned_PG[is.na(aligned_PG)] <- 0
aligned_GR[is.na(aligned_GR)] <- 0
aligned_PC[is.na(aligned_PC)] <- 0

# --- 4) (Optional) report which names were missing in each series ---
missing_in_PG <- setdiff(var_names_last, var_names_PG)
missing_in_GR <- setdiff(var_names_last, var_names_GR)
missing_in_PC <- setdiff(var_names_last, var_names_PC)

if(length(missing_in_PG)) {
  message("These variables had no PG λ and were set to 0:\n", paste(missing_in_PG, collapse = ", "))
}
if(length(missing_in_GR)) {
  message("These variables had no GR λ and were set to 0:\n", paste(missing_in_GR, collapse = ", "))
}
if(length(missing_in_PC)) {
  message("These variables had no PC λ and were set to 0:\n", paste(missing_in_PC, collapse = ", "))
}

# --- 5) Combine into one data.frame ---
df <- data.frame(
  variable     = var_names_last,
  lambda_last  = lambdas_last_vec,
  lambda_PG    = aligned_PG,
  lambda_GR    = aligned_GR,
  lambda_PC    = aligned_PC,
  stringsAsFactors = FALSE
)

metadata_small <- metadata_small %>%
  select(Keys, Name, Frequency, `Release Lag`, `Start Date`)

df_named <- df %>%
  left_join(metadata_small, by = c(variable = "Keys")) %>%  # bring in Name
  select(variable = Name, Frequency, `Release Lag`, `Start Date`, lambda_PG, lambda_GR, lambda_PC, lambda_last) %>%
  rename("Variable Name" = variable)# drop the old code, rename

# 2) convert to an xtable object
xt <- xtable(
  df_named,
  caption = "Estimated Lambdas for Different Samples",
  label   = "tab:lambdas"
)





library(dplyr)
library(zoo)      # for as.yearmon, as.yearqtr
library(ISOweek)  # for ISOweek2date

xt_sorted <- xt %>%
  arrange(
    # extract characters 1–4 and turn into integer for proper ordering
    as.integer(substr(`Start Date`, 1, 4)),
    Frequency
  )


# 3) print the LaTeX table
print(
  xt,
  include.rownames    = FALSE,
  booktabs            = TRUE,
  caption.placement   = "top",
  sanitize.text.function = identity,
  floating            = TRUE,              # keeps the table float
  tabular.environment = "tabular*",        # use tabular* instead of tabular
  width               = "\\textwidth"      # stretch to the full text width
)


library(dplyr)
library(xtable)

# 1) Sort by year (first 4 chars of Start Date) and Frequency
xt_sorted <- xt %>%
  arrange(
    as.integer(substr(`Start Date`, 1, 4)),
    Frequency
  )

# 2) Wrap zeros in \textcolor{red}{0}
xt_colored <- xt_sorted %>%
  mutate(across(
    where(is.numeric),
    ~ ifelse(. == 0,
             "\\textcolor{red}{0}",
             as.character(.))
  )) %>%
  # if you have non-numeric columns that might contain "0" as text,
  # you can include them too, e.g. across(everything(), ...)
  mutate(across(
    where(~ is.character(.) && any(. == "0")),
    ~ ifelse(. == "0",
             "\\textcolor{red}{0}",
             .)
  ))

# 3) Turn into an xtable and print
xtab <- xtable(xt_colored,
               caption = "Estimated Lambdas for Different Samples",
               label   = "tab:mytable")

print(
  xtab,
  include.rownames         = FALSE,
  booktabs                 = TRUE,
  caption.placement        = "top",
  sanitize.text.function   = identity,   # so our \textcolor survives
  floating                 = TRUE,
  tabular.environment      = "tabular*",
  width                    = "\\textwidth"
)

# Serial Correlation Table ---------------------------------------------

# get metadata
metadata <- utils::read.csv("data-raw/data_meta.csv")

# get in-sample results
load(file.path(fit_root, "updated/full_RT/fit_2025.979.Rda"))

# get variable names and sort them according to the in-sample results
# The fit files save their object as `mod`, not `out` -- every other load() in
# this script already reads `mod`. This section still referred to `out` and so
# failed with "object 'out' not found" (#63).
mod_var_names <- colnames(mod$data)
metadata_sorted <- metadata[match(mod_var_names,metadata$keys),]
metadata_sorted[which(metadata_sorted$Name=="Credit Card Transactions, Swiss-Wide Frequency"),"Frequency"] <- 47
var_names <- metadata_sorted$Name
alt <- metadata_sorted$Category
freq <- metadata_sorted$Frequency

# get rhos from model output
sd_rho <- round(sqrt(mod$pars$rho_var),2) #var_rho <- formatC(var_rho, format = "e", digits = 2)
mean_rho <- format(round(mod$pars$rho,2), nsmall = 2)
t_rho <- round(mod$pars$rho/(sqrt(mod$pars$rho_var)),2)
p_rho = round(2*pt(-abs(t_rho), df=4000-1),2)

# create data-frame
table_rho_full <- data.frame(var_names, mean_rho, sd_rho, t_rho, p_rho, alt, freq)

table_rho <- table_rho_full %>%
  mutate(sig_rho = ifelse(abs(t_rho) >2.576,paste0("***"),
                           ifelse(abs(t_rho) >1.96,paste0("**"),
                                  ifelse(abs(t_rho) >1.645,paste0("*"),"")))) %>%
  select(-"t_rho")%>%
  relocate(sig_rho, .after = mean_rho)


colnames(table_rho) <- c("Names","Mean","","Standard Error","P-Value", "Category", "Frequency")
table_rho <- table_rho[order(table_rho$Frequency),]

# Adjust Frequency Entries
table_rho$Frequency[table_rho$Frequency==4] <- "Quarterly"
table_rho$Frequency[table_rho$Frequency==12] <- "Monthly"
table_rho$Frequency[table_rho$Frequency==48] <- "Daily"
table_rho$Frequency[table_rho$Name=="Credit Card Transactions, Swiss-Wide Frequency"] <- "Weekly"

# print table as latex output
print(xtable(table_rho), include.rownames=FALSE, type = "latex", file = file.path(tables_dir, "table_rho.tex"))

# calculate statistics
# number of statistically significant rhos at 99%, 95%, 90%
length(which(abs(table_rho_full$t_rho) >= 2.576))
length(which(abs(table_rho_full$t_rho) >= 1.96))
length(which(abs(table_rho_full$t_rho) >= 1.647)) 

# share of statistically significant rhos at 99%, 95%, 90%
length(which(abs(table_rho_full$t_rho) >= 2.576))/length(table_rho_full$t_rho)*100
length(which(abs(table_rho_full$t_rho) >= 1.96))/length(table_rho_full$t_rho)*100
length(which(abs(table_rho_full$t_rho) >= 1.647))/length(table_rho_full$t_rho)*100




# Structural Breaks Test --------------------------------------------------

# Zeileis A., Leisch F., Hornik K., Kleiber C. (2002), strucchange: An R Package for Testing for Structural Change in Linear Regression Models, Journal of Statistical Software, 7(2), 1-38. URL http://www.jstatsoft.org/v07/i02/
library(strucchange)

# create data vector
data_vec <- c(dat$stocks,dat$flows)
names(data_vec) <- c(names(dat$stocks),names(dat$flows))

# get metadata
metadata <- utils::read.csv("data-raw/data_meta.csv")

# get variable names and sort them according to the in-sample results
mod_var_names <- names(data_vec)
metadata_sorted <- metadata[match(mod_var_names,metadata$keys),]
var_names <- metadata_sorted[,2]

# initialize vectors
supF_p <- c()
aveF_p <- c()
expF_p <- c()
numb_breaks <- c()
time_break <- c()
opt_breaks <- c()
ols_cusum_p <- c()
ols_mosum_p <- c()
score_cusum_p <- c()
re_p <- c()
fluc_p <- c()
rec_cusum_p <- c()
rec_mosum_p <- c()

# start loop over variables
for (i in names(data_vec)){
  print(i)

  tib <- tibble(y = data_vec[[i]][1:length(data_vec[[i]])-1] , # cut last observation out
                y_lag1 = window(stats::lag(data_vec[[i]]),start = start(data_vec[[i]])), # lag the series
                date = time(data_vec[[i]])[1:length(data_vec[[i]])-1]
  ) %>%
    drop_na()
  
## Test 1: generate the Quandt Likelihood Ratio (QLR) statistic 
# the F tests are designed to test against a single shift alternative
qlr <- Fstats(y ~ y_lag1, data = tib)

# get breakpoints
brp <- breakpoints(qlr)
#plot(qlr)
#lines(breakpoints(qlr))

# get F-statistic and p-values
stats_supF <- sctest(qlr, type = "supF") # takes max value of F statistic
stats_aveF <- sctest(qlr, type = "aveF") # takes mean
stats_expF <- sctest(qlr, type = "expF") # takes mean of exp(0.5*F)

# get date where structural break is located
date_break <- tib %>%
slice(qlr$breakpoint) %>%
  select(date)

# store in vectors
supF_p[i] <- stats_supF$p.value
#numb_breaks[i] <- length(qlr$breakpoint)
#time_break[i] <- date_break

aveF_p[i] <- stats_aveF$p.value
expF_p[i] <- stats_expF$p.value

##Test 2: perform the Bai and Perron (2003) test for multiple structural breaks
bp <- breakpoints(y ~ y_lag1, data = tib, breaks = 5)

# get optimal number of breakpoints according to BIC and RSS
#summary(bp)  # where the breakpoints are
brp <- breakpoints(bp)
#plot(bp, breaks = 5)

# get date where structural break is located
date_break <- tib %>%
  slice(bp$breakpoint) %>%
  select(date)

opt_breaks[i] <- length(brp$breakpoints)

## Test 3: perform CUSUM test (Zeileis et al. (2010, doi:10.1016/j.csda.2009.12.005))
# the null hypothesis of “no structural change” should be rejected when the fluctuation of the empirical process efp(t) gets improbably large compared to the fluctuation of the limiting process

# cumulative sums of standardized residuals.
ols_cusum <- efp(y ~ y_lag1, data = tib, type = "OLS-CUSUM") # OLS based cumulative sums of standardized residuals
plot(ols_cusum)
ols_cusum_p[i] <- sctest(ols_cusum)$p.value

# moving sums of residuals
ols_mosum <- efp(y ~ y_lag1, data = tib, type = "OLS-MOSUM") # OLS based moving sums of residuals
#plot(ols_mosum)
#sctest(ols_mosum)
ols_mosum_p[i] <- sctest(ols_mosum)$p.value

score_cusum <- efp(y ~ y_lag1, data = tib, type = "Score-CUSUM") # score based cumulative sums of standardized residuals
#plot(score_cusum)
sctest(score_cusum)
score_cusum_p[i] <- sctest(score_cusum)$p.value

# moving estimates of the unknown regression coefficients
re <- efp(y ~ y_lag1, data = tib, type = "RE")
#plot(re)
#sctest(re)
re_p[i] <- sctest(re)$p.value

# recursive estimates of the unknown regression coefficients
fluc <- efp(y ~ y_lag1, data = tib, type = "fluctuation") #  based on estimates of the unknown regression coefficients
#plot(fluc)
#sctest(fluc)
fluc_p[i] <- sctest(fluc)$p.value

# Recursive residuals are standardized one-step-ahead prediction errors.
rec_cusum <- efp(y ~ y_lag1, data = tib, type = "Rec-CUSUM") # OLS based cumulative sums of standardized residuals
#plot(rec_cusum)
rec_cusum_p[i] <- sctest(rec_cusum)$p.value

rec_mosum <- efp(y ~ y_lag1, data = tib, type = "Rec-MOSUM") # OLS based moving sums of residuals
#plot(rec_mosum)
#sctest(rec_mosum)
rec_mosum_p[i] <- sctest(rec_mosum)$p.value

}

# create table
table_struc_break <- data.frame(var_names, supF_p, aveF_p, expF_p, opt_breaks, ols_cusum_p, ols_mosum_p, score_cusum_p, re_p, fluc_p, rec_cusum_p, rec_mosum_p)
table_struc_break <- table_struc_break %>% mutate(nb_supF = ifelse(supF_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_aveF = ifelse(aveF_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_expF = ifelse(expF_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_ols_cusum = ifelse(ols_cusum_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_ols_mosum = ifelse(ols_mosum_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_score_cusum = ifelse(score_cusum_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_cusum_re = ifelse(re_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_fluc = ifelse(fluc_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_rec_mosum = ifelse(rec_mosum_p >= 0.05, 0,1))
table_struc_break <- table_struc_break %>% mutate(nb_rec_cusum = ifelse(rec_cusum_p >= 0.05, 0,1))

table_struc_break[is.na(table_struc_break)] <- 0

colSums(table_struc_break[,-(1:12)])

