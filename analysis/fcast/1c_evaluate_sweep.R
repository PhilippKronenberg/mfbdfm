# Run from the repository root.

# -----------------------------------------------------------------------------
# Evaluate the sweep: point scripts 2, 3 and 5 at fits/fcast_sweep/
# -----------------------------------------------------------------------------
# 1b_sweep_parallel.R writes to fits/fcast_sweep/, while _setup.R's default
# fcast_config points fit_root at fits/fcast/ - where 1_backcast_fcast.R writes
# its single-date fits. So running 2_evaluation_fcast.R straight after a sweep
# fails with "No fits at fits/fcast", which is exactly what happened the first
# time the sweep ran to completion: the two halves of the pipeline had never
# been exercised end to end, because no sweep had finished before.
#
# _setup.R was built for this - "a driver script may pre-set fcast_config before
# sourcing this file" - but nothing actually did. This is that driver.
#
# Keeping the sweep's results under their own sample_id rather than overwriting
# the single-date outputs, so the two can be compared and neither silently
# replaces the other.
#
# Cheap: no fitting, just reading the 192 fits and scoring them. Minutes.
# -----------------------------------------------------------------------------

fcast_config <- list(
  sample_id   = "fcast_sweep",
  output_root = file.path("analysis", "outputs", "fcast", "fcast_sweep"),
  fit_root    = file.path("fits", "fcast_sweep")
)

# 5_error_tables_fcast.R reads either the paper's stored panel or ours; over a
# sweep of our own fits, ours is the point.
source_panel <- "own"

stages <- c("2_evaluation_fcast.R", "3_plots_fcast.R", "5_error_tables_fcast.R")

for (stage in stages) {
  message("\n===== ", stage, " =====")
  # local = FALSE: each stage sources _setup.R itself and expects to build its
  # objects in the global environment, as it does when run directly
  source(file.path("analysis", "fcast", stage))
}

message("\nsweep evaluation complete; outputs under ", fcast_config$output_root)
