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

# Created here, not by wai_sample_config(), which is a pure query - see the same
# block in analysis/5_plots/_setup.R for why.
for (d in c(figures_dir, tables_dir, results_dir)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# Where the multi-factor fits are written. Deliberately separate from
# fits/updated/, which holds the single-factor WAI fits - mixing the two under
# one root is exactly what made fits/ hard to reason about in #32.
fcast_fit_root <- fcast_config$fit_root

target <- "ch.seco.gdp.real.gdp.ssa"


# BMDFM BENCHMARK ---------------------------------------------------------
#
# The Banbura-Modugno (JAE 2014) mixed-frequency DFM used as the benchmark in
# Eckert et al. (2025), built from functions lifted out of the `nowcasting`
# package (https://github.com/nmecsys/nowcasting) rather than installed: the
# published package errors for the one-factor case, and line 233 of its
# nowcast.R was changed from colnames(factors$dynamic_factors) to
# names(factors$dynamic_factors) to fix it. That local edit is why the files are
# vendored here instead of being a dependency.
#
# The archived driver sourced them from code/lib/functions_package_nowcasting/;
# they now live under analysis/benchmarks/.
bmdfm_functions_dir <- file.path("analysis", "benchmarks",
                                 "functions_package_nowcasting")

#' Source the vendored BMDFM benchmark functions
#'
#' Not sourced on load - it pulls in ~23 files and needs DBI and RCurl, which
#' nothing else in this workflow requires. Call it from a script that actually
#' runs the benchmark.
source_bmdfm_functions <- function(dir = bmdfm_functions_dir) {

  if (!dir.exists(dir)) {
    stop("No BMDFM functions at ", dir, ".", call. = FALSE)
  }

  missing <- c("DBI", "RCurl", "MASS")[
    !vapply(c("DBI", "RCurl", "MASS"), requireNamespace, logical(1),
            quietly = TRUE)]
  if (length(missing)) {
    stop("The BMDFM benchmark needs ", paste(missing, collapse = ", "),
         ", which ", if (length(missing) > 1) "are" else "is",
         " not installed.", call. = FALSE)
  }

  files <- list.files(dir, pattern = "\\.[Rr]$", full.names = TRUE)
  invisible(lapply(files, source))
  message("sourced ", length(files), " BMDFM benchmark functions from ", dir)

  # NOTE for whoever wires run_bmdfm() back in: the archived version calls
  # prepare_data(flows, stocks, inventory, model = model). `model` is not an
  # argument of prepare_data() any more - it takes `target`. The call needs
  # updating before that function will run.
  invisible(files)

}
