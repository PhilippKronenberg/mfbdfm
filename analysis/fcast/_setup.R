# -----------------------------------------------------------------------------
# _setup.R - shared setup for the multi-factor (fcast_dfm) analysis scripts
# -----------------------------------------------------------------------------
# Sourced from the repository root by everything in analysis/fcast/.
#
# The multi-factor counterpart of analysis/5_plots/_setup.R, kept separate
# because the two workflows differ in what they configure: the WAI setup is
# built around a single target series and its real-time GDP vintages, whereas
# this one is built around a factor count. Same conventions though - no
# setwd(), no per-script library() piles, outputs under the gitignored root via
# the existing path helpers.
# -----------------------------------------------------------------------------

library(mfbdfm)

Sys.setlocale("LC_TIME", "English")
library(ggplot2)
library(dplyr)
library(tidyr)
library(tibble)
library(zoo)
library(scales)
library(purrr)

# A driver script may pre-set `fcast_config` before sourcing this file;
# otherwise the default below is used.
if (!exists("fcast_config") || is.null(fcast_config)) {
  fcast_config <- list(
    sample_id = "fcast_default",
    output_root = file.path("analysis", "outputs", "fcast", "fcast_default"),
    fit_root = file.path("fits", "fcast")
  )
}

# Reuse wai_sample_config() for the output-path layout rather than inventing a
# second convention - it is what write_table_output(), save_result_output() and
# output_figure_path() expect. Only the arguments it actually has are passed.
fcast_sample_config <- do.call(
  wai_sample_config,
  fcast_config[intersect(names(fcast_config), names(formals(wai_sample_config)))]
)

sample_id <- fcast_sample_config$sample_id
output_root <- fcast_sample_config$output_root
figures_dir <- fcast_sample_config$figures_dir
tables_dir <- fcast_sample_config$tables_dir
results_dir <- fcast_sample_config$results_dir

# Where the multi-factor fits are written. Deliberately separate from
# fits/updated/, which holds the single-factor WAI fits - mixing the two under
# one root is exactly what made fits/ hard to reason about in #32.
fcast_fit_root <- fcast_config$fit_root

target <- "ch.seco.gdp.real.gdp.ssa"
