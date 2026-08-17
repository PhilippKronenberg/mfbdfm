# -----------------------------------------------------------------------------
# _setup.R — shared setup for the analytics plotting scripts
# -----------------------------------------------------------------------------
# Sourced (from the repository root) by analytics_data.R,
# analytics_in_sample.R, analytics_out-of-sample.R and plots_analytics.R.
# Replaces the former load_analytics_packages() and
# initialize_plots_insample_context() from the pre-package code.
# -----------------------------------------------------------------------------

library(mfbdfm)

Sys.setlocale("LC_TIME", "English")
library(ggplot2)
library(tibble)
library(tidyr)
library(dplyr)
library(scales)
library(forecast)
library(zoo)
library(ggpubr)
library(readxl)
library(lubridate)
library(ISOweek)
library(purrr)
has_ggsci <- requireNamespace("ggsci", quietly = TRUE)

# run_plots_analytics_samples.R may pre-set `sample_config`; otherwise the
# default sample below is used. Extra elements (e.g. from a previous
# wai_sample_config() call) are ignored.
if (!exists("sample_config") || is.null(sample_config)) {
  sample_config <- list(
    sample_id = "sample_2025Q4",
    sample_end_date = as.Date("2026-03-07"),
    output_root = file.path("analysis", "outputs", "plots_insample", "sample_2025Q4"),
    fit_root = "fits",
    fit_rt_dir = file.path("fits", "updated", "full_RT")
  )
}
sample_config <- do.call(
  wai_sample_config,
  sample_config[intersect(names(sample_config), names(formals(wai_sample_config)))]
)

sample_end_date <- sample_config$sample_end_date
sample_id <- sample_config$sample_id
output_root <- sample_config$output_root
figures_dir <- sample_config$figures_dir
tables_dir <- sample_config$tables_dir
results_dir <- sample_config$results_dir
sample_end_decimal <- sample_config$sample_end_decimal
sample_end_fit_decimal <- sample_config$sample_end_fit_decimal

# Create the output tree here rather than in wai_sample_config(), which is a pure
# query and creates nothing. Many scripts downstream write directly - ggsave(),
# xtable(file = ), write_csv() - instead of going through write_table_output() /
# output_figure_path(), so they need the directories to exist up front. Preparing
# the output tree is the analysis prelude's job; a package function that creates
# directories just for being called is not.
for (d in c(figures_dir, tables_dir, results_dir)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}
