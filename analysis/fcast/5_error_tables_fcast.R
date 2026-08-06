# Run from the repository root.

# -----------------------------------------------------------------------------
# Multi-factor error tables (Eckert et al. 2025)
# -----------------------------------------------------------------------------
# Port of archive/error_table.R: RMSFE, MAE and mean log score by model,
# dataset and horizon, split into all / crisis / non-crisis subsamples, with
# Diebold-Mariano tests against a benchmark.
#
# Reads whichever panel is available:
#   source = "replication"  the paper's stored results (reference/rda/), so the
#                           published tables can be reproduced without fitting
#   source = "own"          the panel from 2_evaluation_fcast.R
#
# Writes CSV and LaTeX to tables_dir.
#
# Two things taken from the package rather than re-implemented: the crisis
# split is is_crisis_period_fcast() (see ?is_crisis_period_fcast - it is NOT
# is_crisis_period()), and the DM test is dm_test_modified(), the
# Harvey-Leybourne-Newbold small-sample correction the WAI tables already use.
# The original called forecast::dm.test() directly.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")

# "replication" (the paper's stored panel) or "own" (whatever
# 2_evaluation_fcast.R last wrote). Guarded so a driver script can pre-set it,
# the same way _setup.R guards fcast_config - without the guard, sourcing this
# from 1c_evaluate_sweep.R silently reverted to the paper's panel and produced
# tables for models the sweep never fitted.
if (!exists("source_panel") || is.null(source_panel)) {
  source_panel <- "replication"
}


# LOAD --------------------------------------------------------------------

if (source_panel == "replication") {

  ref_dir <- "analysis/fcast/reference/rda"
  if (!dir.exists(ref_dir)) {
    stop("No reference panels at ", ref_dir, ".\n",
         "  These are the paper's stored results and are not committed - see ",
         "analysis/fcast/README.md. Set source_panel <- \"own\" to use the ",
         "panel from 2_evaluation_fcast.R instead.", call. = FALSE)
  }

  e <- new.env(); load(file.path(ref_dir, "results_tab_2f.Rda"), envir = e)
  panel <- as.data.frame(e$tab)
  out_tag <- "replication"

} else {

  p <- file.path(results_dir, "fcast_evaluation_tab.Rda")
  if (!file.exists(p)) {
    stop("No evaluation panel at ", p, ".\n",
         "  Run 1_backcast_fcast.R then 2_evaluation_fcast.R first.",
         call. = FALSE)
  }
  e <- new.env(); load(p, envir = e)
  panel <- as.data.frame(e$tab)
  out_tag <- sample_id

}

panel <- panel %>% filter(horizon %in% 1:12, !is.na(realization))
message("panel: ", nrow(panel), " rows, models ",
        paste(unique(panel$model), collapse = "/"))


# SUBSAMPLES --------------------------------------------------------------

# all / crisis / non-crisis, stacked, exactly as error_table.R does
panel$crisis <- is_crisis_period_fcast(panel$period)

stacked <- bind_rows(
  panel %>% mutate(subsample = "all"),
  panel %>% filter(crisis)  %>% mutate(subsample = "crisis"),
  panel %>% filter(!crisis) %>% mutate(subsample = "non_crisis")
)


# ERROR TABLE -------------------------------------------------------------

error_table <- stacked %>%
  group_by(subsample, model, dataset, horizon) %>%
  summarise(n = n(),
            rmsfe = sqrt(mean(sqerror, na.rm = TRUE)),
            mae = mean(abs(error), na.rm = TRUE),
            logscore = mean(logs, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(subsample, model, dataset, desc(horizon))

# pooled over horizons, which is the headline form of the published table
error_pooled <- stacked %>%
  group_by(subsample, model, dataset) %>%
  summarise(n = n(),
            rmsfe = sqrt(mean(sqerror, na.rm = TRUE)),
            mae = mean(abs(error), na.rm = TRUE),
            logscore = mean(logs, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(subsample, model, dataset)

cat("\nPooled errors by subsample:\n")
print(as.data.frame(error_pooled), digits = 3)


# DIEBOLD-MARIANO ---------------------------------------------------------

# Each model/dataset against the benchmark, on squared errors. dm_test_modified()
# rather than forecast::dm.test(): same test with the Harvey-Leybourne-Newbold
# small-sample correction, and it is what the WAI tables use, so the two papers'
# tables stay comparable.
benchmark_model <- if ("ar" %in% panel$model) "ar" else sort(unique(panel$model))[1]

dm_rows <- list()
for (ss in unique(stacked$subsample)) {
  bench <- stacked %>%
    filter(subsample == ss, model == benchmark_model)
  if (!nrow(bench)) next

  for (m in setdiff(unique(stacked$model), benchmark_model)) {
    for (dx in unique(stacked$dataset)) {
      s <- stacked %>% filter(subsample == ss, model == m, dataset == dx) %>%
        arrange(period, date)
      b <- bench %>% filter(dataset == dx) %>% arrange(period, date)
      if (!nrow(s) || nrow(s) != nrow(b)) next

      # dm_test_modified() returns the p-value directly - it is not an htest,
      # so there is no $p.value to reach for. Errors are reported rather than
      # swallowed: an earlier version wrapped this in tryCatch(NA) and turned
      # every failure into a silent NA column.
      p <- dm_test_modified(s$error, b$error, h = 1, power = 2,
                            alternative = "less")

      dm_rows[[length(dm_rows) + 1]] <- data.frame(
        subsample = ss, model = m, dataset = dx, benchmark = benchmark_model,
        n = nrow(s), dm_p_value = p,
        rmsfe = sqrt(mean(s$sqerror, na.rm = TRUE)),
        rmsfe_benchmark = sqrt(mean(b$sqerror, na.rm = TRUE)),
        stringsAsFactors = FALSE)
    }
  }
}

dm_table <- bind_rows(dm_rows)
if (nrow(dm_table)) {
  dm_table <- dm_table %>%
    mutate(rmsfe_ratio = rmsfe / rmsfe_benchmark,
           significant = !is.na(dm_p_value) & dm_p_value < 0.05) %>%
    arrange(subsample, model, dataset)
  cat("\nDiebold-Mariano against ", benchmark_model,
      " (one-sided, p < 0.05 = model beats benchmark):\n", sep = "")
  print(as.data.frame(dm_table), digits = 3)
} else {
  message("No DM comparisons possible: only one model in the panel.")
}


# WRITE -------------------------------------------------------------------

fmt <- function(d) {
  num <- vapply(d, is.numeric, logical(1))
  d[num] <- lapply(d[num], function(x) round(x, 5))
  d
}

write_table_output(paste0("fcast_error_table_", out_tag, ".csv"),
                   utils::capture.output(
                     utils::write.csv(fmt(error_table), row.names = FALSE)),
                   tables_dir)
write_table_output(paste0("fcast_error_pooled_", out_tag, ".csv"),
                   utils::capture.output(
                     utils::write.csv(fmt(error_pooled), row.names = FALSE)),
                   tables_dir)
if (nrow(dm_table)) {
  write_table_output(paste0("fcast_dm_test_", out_tag, ".csv"),
                     utils::capture.output(
                       utils::write.csv(fmt(dm_table), row.names = FALSE)),
                     tables_dir)
}

message("\ntables written to ", tables_dir)
