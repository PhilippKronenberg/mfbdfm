# -----------------------------------------------------------------------------
# _internals.R - bind the package internals the analysis scripts depend on
# -----------------------------------------------------------------------------
# Sourced (from the repository root) by analysis/5_plots/_setup.R,
# analysis/fcast/_setup.R, and by the few scripts that use neither prelude
# (0_test.R, 2_backcast.R, update_wai_web.R).
#
# Issue #102 un-exported 18 analysis-script helpers. They are plumbing for the
# scripts in this directory, not package API: a user of library(mfbdfm) has no
# reason to call write_table_output() or rescale_to_gdp(), and keeping them
# exported made the package promise stability for 18 functions whose only
# callers live in this repository. They stayed in R/ (so they stay covered by
# tests/testthat/) but lost their @export.
#
# Rather than rewrite ~100 call sites as mfbdfm:::fn(), the names are bound once
# here. The list below is therefore also the record of exactly which internals
# the analysis workflow depends on - if something is added to it, that is a
# decision worth seeing in a diff.
#
# Note the direction of the obligation: an internal has no stability promise, so
# a change to one of these can break a script here without warning. That is the
# price of the smaller export surface, and it is the right way round - the
# scripts are in the same repository as the function.
#
# SOURCE THIS WITH `local = TRUE`. The assignments below land in whatever
# environment this file is evaluated in, and source()'s default (local = FALSE)
# evaluates in the GLOBAL environment regardless of where the call sits. Sourced
# that way from inside a prelude that is itself being read into some other
# environment, the bindings go to globalenv() and the scripts never see them -
# which is exactly the "could not find function" failure #23 was about, moved
# one level out. With local = TRUE it works both at top level and under
# sys.source(envir = ).
# -----------------------------------------------------------------------------

mfbdfm_internals <- c(
  # analytics-config.R: output paths and the vintage pickers
  "write_table_output",
  "save_result_output",
  "output_figure_path",
  "filter_to_sample",
  "latest_fit_file",
  "get_latest_numeric_vintage",
  "get_next_extending_numeric_vintage",
  # analytics-cor.R: WAI series preparation and plot scaling
  "rescale_to_gdp",
  "build_wai_qoq_mean_series",
  "prepare_wai_qoq_series",
  "suffix_cols",
  # analytics-tables.R: relative-error and LaTeX table steps
  "calculate_relative_errors",
  "annotate_relative_errors",
  "create_combined_latex_table",
  "print_evaluation_periods",
  # date-utils.R
  "get_next_target_vintage",
  # web-export.R: the WAI dashboard files
  "export_wai_web",
  "gdp_web_series"
)

for (.f in mfbdfm_internals) {
  assign(.f, get(.f, envir = asNamespace("mfbdfm")))
}
rm(.f)
