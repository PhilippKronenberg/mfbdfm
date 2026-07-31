# Run from the repository root.

# -----------------------------------------------------------------------------
# Multi-factor out-of-sample evaluation (Eckert et al. 2025)
# -----------------------------------------------------------------------------
# Turns the fits written by 1_backcast_fcast.R into the evaluation panel the
# plotting scripts consume: one row per (evaluation date, target period), with
# the nowcast, its standard deviation, the realised value, and the scores.
#
# This is a port of old_code_fcast_dfm/3a_evaluation_full.R's evaluation core,
# rebuilt against the actual fcast_dfm() fit structure rather than the old
# `out`/`var` nested lists it read - those were produced by a gathering step
# whose inputs no longer exist. The column semantics are kept identical so the
# figures remain comparable with the paper:
#
#   period      target period (quarterly GDP date)
#   date        nowcast date, i.e. the evaluation date (weekly, 48/year)
#   value, sd   posterior mean nowcast and its standard deviation
#   realization the GDP growth rate actually observed for `period`
#   observed    week in which that GDP figure is published
#   horizon     weeks between the nowcast and publication
#
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")


# GATHER FITS -------------------------------------------------------------

gather_fits <- function(fit_root){

  if (!dir.exists(fit_root)) {
    stop("No fits at ", fit_root, ".\n",
         "  Run analysis/fcast/1_backcast_fcast.R first - it writes the fits ",
         "this script reads.", call. = FALSE)
  }

  datasets <- list.dirs(fit_root, full.names = FALSE, recursive = FALSE)
  if (!length(datasets)) {
    stop("No dataset sub-directories under ", fit_root, ".", call. = FALSE)
  }

  rows <- list()

  for (dx in datasets) {
    files <- list.files(file.path(fit_root, dx), pattern = "^fit_.*\\.Rda$",
                        full.names = TRUE)
    if (!length(files)) {
      warning("No fits in ", file.path(fit_root, dx), ", skipping.", call. = FALSE)
      next
    }

    for (f in files) {
      # each file holds a single object `mod`, as written by run_fcast()
      e <- new.env()
      load(f, envir = e)
      mod <- e$mod

      # the evaluation date is in the file name, which is what run_fcast()
      # rounds to 3 digits - not recoverable from the fit itself
      eval_date <- as.numeric(sub("^fit_(.*)\\.Rda$", "\\1", basename(f)))

      ncst <- mod$nowcast
      ncst_var <- mod$nowcast_var
      keep <- !is.na(ncst)

      rows[[length(rows) + 1]] <- tibble(
        dataset = dx,
        model = "fcast",
        date = eval_date,
        period = round(as.numeric(time(ncst))[keep], 3),
        value = as.numeric(ncst)[keep],
        sd = sqrt(as.numeric(ncst_var)[keep])
      )
    }
  }

  bind_rows(rows)

}

tab <- gather_fits(fcast_fit_root)
message("gathered ", nrow(tab), " nowcast rows from ",
        length(unique(tab$date)), " evaluation date(s), ",
        length(unique(tab$dataset)), " dataset(s)")


# REALISATIONS ------------------------------------------------------------

# The realised GDP growth rate for each target period, from the same real-time
# vintage source the backcast used.
GDP_gr_vintages_quarterly <- get_real_time_gdp_vintages("quarterly")
latest_vintage <- get_latest_numeric_vintage(
  GDP_gr_vintages_quarterly,
  lower_bound = 2005.438,
  upper_bound = round(decimal_date_local(Sys.Date()), 3)
)
gdp_actual <- na.trim(ts(
  GDP_gr_vintages_quarterly[[as.character(latest_vintage)]],
  start = c(1990, 1), frequency = 4
))

gdp_time <- round(as.numeric(time(gdp_actual)), 3)
tab$realization <- as.numeric(gdp_actual)[match(tab$period, gdp_time)]

n_missing <- sum(is.na(tab$realization))
if (n_missing) {
  message("  ", n_missing, " row(s) have no realisation yet (period beyond the ",
          "latest GDP vintage); these are kept but score to NA.")
}


# SCORES ------------------------------------------------------------------

# Logarithmic score: the negative log predictive density. Identical to
# scoringRules::logs(y, family = "normal", mean, sd), which the original script
# used - written out here rather than taking a dependency for one line.
tab$logs <- -dnorm(tab$realization, mean = tab$value, sd = tab$sd, log = TRUE)

tab$error <- tab$value - tab$realization
tab$sqerror <- tab$error^2

# GDP is published in the first week of the third month after the quarter ends,
# e.g. 2019Q4 = 2019.75 is observed at 2020.000 + 8/48.
tab$observed <- round(tab$period + 1/4 + 8/48, 3)
tab$horizon <- round((tab$observed - tab$date) * 48)
tab$year <- floor(tab$date)
tab$week <- round(tab$date %% 1 * 48 + 1)

tab <- tab %>% arrange(dataset, date, period)


# IN-SAMPLE VS OUT-OF-SAMPLE ----------------------------------------------

# A fit at evaluation date `d` produces a value for every period its nowcast
# series covers, including periods whose GDP was already published before `d`.
# Those rows have horizon <= 0 and are NOT forecasts - the model saw that GDP as
# an input, so it reproduces it almost exactly. Mixing them into an evaluation
# gives an RMSE near zero and a model that looks perfect.
#
# This bit us on the first run of this script: a single evaluation date produced
# 31 rows, all with negative horizons and RMSE ~1e-7. Flagged rather than
# silently filtered, so the distinction is visible in the saved panel too.
tab$in_sample <- tab$horizon <= 0

# The published evaluation window is the 12 weeks before publication - one
# quarter. Verified against the paper's own panel (analysis/fcast/figures/
# results_tab_2f.Rda): its horizon runs exactly 1 to 12, with no rows at or
# below zero. Kept as a flag rather than a filter so the wider panel stays
# available, but the summaries and figures use this window.
HORIZON_WINDOW <- 1:12
tab$in_window <- tab$horizon %in% HORIZON_WINDOW

n_oos <- sum(!tab$in_sample & !is.na(tab$realization))
if (!n_oos) {
  warning("No out-of-sample rows (every horizon <= 0).\n",
          "  Every nowcast here is for a period whose GDP was already ",
          "published at the evaluation date, so the model had it as an input ",
          "and the errors are meaningless as a forecast evaluation.\n",
          "  A real evaluation needs a sweep of evaluation dates - set ",
          "`quick_check <- FALSE` in 1_backcast_fcast.R and widen `date_vec`.",
          call. = FALSE)
}

by_horizon <- tab %>%
  filter(!is.na(realization), !in_sample, in_window) %>%
  group_by(dataset, horizon) %>%
  summarise(n = n(),
            rmse = sqrt(mean(sqerror, na.rm = TRUE)),
            mae = mean(abs(error), na.rm = TRUE),
            logs = mean(logs, na.rm = TRUE),
            .groups = "drop") %>%
  arrange(dataset, desc(horizon))

cat("\nOut-of-sample rows (horizon > 0): ", n_oos, " of ", nrow(tab), "\n", sep = "")
if (nrow(by_horizon)) print(by_horizon, n = 20)


# SAVE --------------------------------------------------------------------

# save_result_output() uses the filename verbatim, so the extension is ours to
# supply; .Rda matches the rest of analysis/
save_result_output(tab, "fcast_evaluation_tab.Rda", results_dir)
save_result_output(by_horizon, "fcast_evaluation_by_horizon.Rda", results_dir)

message("evaluation panel written to ", results_dir)
