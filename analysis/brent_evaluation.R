# Run from the repository root.
#
# Does adding Brent improve the WAI nowcast? (issue #173) -----------------
#
# A pseudo-real-time comparison of two dataset variants, identical except that
# `with_brent` carries the transformed weekly Brent series and `full_RT` does
# not. Same dates, same settings, same seeds, real-time GDP vintages
# throughout. Outputs relative RMSFE / MAE / mean log score by horizon and
# subsample, Diebold-Mariano p-values in both directions, and the Brent loading.
#
# COST. One full-length fit (run_wai_adj()'s 5000 draws after 1000 burn-in) on
# this panel was measured at ~33 min on a 4-core x86_64 Linux CI runner
# (2026-11-04: 120 draws in 39.6 s, i.e. ~0.33 s/draw, extrapolated). The
# default grid here is 46 dates x 2 variants x 1 seed = 92 fits, so about
# **50 hours serially**, or ~13 h on 4 workers. That is why this script is
# committed rather than run by the agent that wrote it; see
# analysis/brent_diagnostics.R for the cheap single-date diagnostics.
#
# RESUMABLE. Every fit is cached to `fit_root/<variant>/fit_<date>.Rda` by
# run_wai_adj() and the per-date nowcast rows are cached under `cache_dir`, so
# the script can be stopped and restarted, or run over a subset of dates with
# `BRENT_DATES`, and the tables rebuilt at the end from whatever is cached.
#
# ENVIRONMENT OVERRIDES (all optional):
#   BRENT_LENGTH_SAMPLE  retained draws per fit (default 5000, the WAI setting)
#   BRENT_BURN_IN        burn-in draws          (default 1000)
#   BRENT_SEEDS          comma-separated seeds  (default "1")
#   BRENT_WORKERS        parallel workers       (default 1)
#   BRENT_DATES          comma-separated subset of evaluation dates
#   BRENT_TABLES_ONLY    "true" to skip fitting and only rebuild the tables

suppressMessages({
  library(zoo)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(foreach)
  library(doParallel)
  library(mfbdfm)
})

source("analysis/brent_oil.R")
source("analysis/brent_evaluation_setup.R")
# No analysis/_internals.R: every package function used below
# (run_wai_adj, cut_data_real_time, select_most_recent_GDP_vintage,
# get_real_time_gdp_vintages, dm_test_modified, create_error_summary_tables,
# mfbdfm_contributions) is exported, so nothing needs binding.

env_num <- function(name, default) {
  v <- Sys.getenv(name, "")
  if (!nzchar(v)) default else as.numeric(v)
}
env_flag <- function(name) tolower(Sys.getenv(name, "")) %in% c("1", "true", "yes")

fit_root <- file.path("fits", "brent")
cache_dir <- file.path("analysis", "Rda", "brent_eval")
out_dir <- file.path("analysis", "out", "brent")
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

length_sample <- env_num("BRENT_LENGTH_SAMPLE", 5000)
burn_in <- env_num("BRENT_BURN_IN", 1000)
seeds <- {
  v <- Sys.getenv("BRENT_SEEDS", "1")
  as.integer(trimws(strsplit(v, ",", fixed = TRUE)[[1]]))
}
n_workers <- env_num("BRENT_WORKERS", 1)

date_vec <- BRENT_EVAL_DATES
if (nzchar(Sys.getenv("BRENT_DATES", ""))) {
  date_vec <- as.numeric(trimws(strsplit(Sys.getenv("BRENT_DATES"), ",", fixed = TRUE)[[1]]))
}

datasets <- brent_variant_datasets()
GDP_gr_vintages <- get_real_time_gdp_vintages("quarterly")

# `with_brent` is the variant under test; `full_RT` is the reference. The error
# tables divide by the model literally named "WAI", so the reference takes that
# name and the relative figures read "with_brent over full_RT", which is what
# the issue asks for.
model_label <- c(full_RT = "WAI", with_brent = "WAI-Brent")
model_order <- unname(model_label)

message(length(date_vec), " date(s) x ", length(datasets), " variant(s) x ",
        length(seeds), " seed(s) = ",
        length(date_vec) * length(datasets) * length(seeds), " fit(s); ",
        length_sample, " draws after ", burn_in, " burn-in")


# ONE EVALUATION DATE -----------------------------------------------------

# Returns one row per (variant, seed, nowcast quarter beyond the last published
# GDP observation). `horizon_weeks` is the distance from the evaluation date to
# the end of the quarter being nowcast, in weeks of 1/48 - negative when the
# quarter has not finished yet (a nowcast), positive when it has (a backcast).
eval_one_date <- function(ix) {

  cache_file <- file.path(cache_dir, paste0("rows_", round(ix, 3), ".rds"))
  if (file.exists(cache_file)) return(readRDS(cache_file))

  rows <- list()
  for (variant in names(datasets)) {

    prepared <- brent_prepare_realtime(datasets[[variant]], ix, GDP_gr_vintages)
    gdp_now <- prepared$flows[[BRENT_TARGET]]
    last_obs <- as.numeric(utils::tail(stats::time(gdp_now), 1))

    for (sd_i in seeds) {
      set.seed(sd_i)
      fit <- run_wai_adj(
        flows = prepared$flows,
        stocks = prepared$stocks,
        target = BRENT_TARGET,
        date = ix,
        dataset_used = file.path(variant, paste0("seed", sd_i)),
        length_sample = length_sample,
        burn_in = burn_in,
        output_dir = fit_root
      )

      ncst <- fit$nowcast
      ncst_var <- fit$nowcast_var
      tt <- as.numeric(stats::time(ncst))
      # Only the periods the vintage at `ix` did not yet contain are forecasts.
      unobserved <- tt > last_obs + 1e-8
      if (!any(unobserved)) next

      # coef.ind_dfm() is a named numeric vector, names = inventory keys. Only
      # the posterior mean of lambda is stored (see R/ind_dfm.R), so there is
      # no credible interval to extract here.
      cf <- stats::coef(fit)
      brent_loading <- if (BRENT_KEY %in% names(cf)) unname(cf[[BRENT_KEY]]) else NA_real_

      rows[[length(rows) + 1L]] <- data.frame(
        eval_date = ix,
        variant = variant,
        model = model_label[[variant]],
        seed = sd_i,
        # Rounded, because this is joined against the realisations below on
        # equality. Both sides are `start + (i-1)/4` from different `ts`
        # objects with different starts, so the raw doubles need not be
        # bit-identical; R/contributions.R rounds to 5 for the same reason.
        forecast_period = round(tt[unobserved], 5),
        forecast_value = as.numeric(ncst)[unobserved],
        forecast_sd = sqrt(as.numeric(ncst_var)[unobserved]),
        brent_loading = brent_loading,
        stringsAsFactors = FALSE
      )

      rm(fit)
      invisible(gc())
    }
  }

  out <- if (length(rows)) dplyr::bind_rows(rows) else NULL
  saveRDS(out, cache_file)
  out
}


# FIT LOOP ----------------------------------------------------------------

if (!env_flag("BRENT_TABLES_ONLY")) {
  if (n_workers > 1) {
    cl <- makeCluster(n_workers)
    registerDoParallel(cl)
    message("running ", length(date_vec), " date(s) on ", n_workers, " workers")
  } else {
    registerDoSEQ()
    message("running ", length(date_vec), " date(s) serially")
  }

  invisible(foreach(ix = date_vec,
                    .packages = c("mfbdfm", "Matrix", "zoo", "dplyr", "tidyr")) %dopar% {
    eval_one_date(ix)
    NULL
  })

  if (exists("cl")) stopCluster(cl)
}


# COLLECT -----------------------------------------------------------------

cached <- list.files(cache_dir, pattern = "^rows_.*\\.rds$", full.names = TRUE)
if (!length(cached)) {
  stop("No cached evaluation rows under ", cache_dir, ". Nothing to tabulate.",
       call. = FALSE)
}
panel <- dplyr::bind_rows(lapply(cached, readRDS))
message("panel: ", nrow(panel), " row(s), ",
        length(unique(panel$eval_date)), " date(s), models ",
        paste(sort(unique(panel$model)), collapse = "/"))

# Realised GDP: the latest vintage available, i.e. the final estimate.
final_vintage <- GDP_gr_vintages[[ncol(GDP_gr_vintages)]]
final_gdp <- stats::ts(final_vintage, start = c(1990, 1), frequency = 4)
final_df <- data.frame(
  forecast_period = round(as.numeric(stats::time(final_gdp)), 5),
  actual_value = as.numeric(final_gdp)
)

panel <- panel %>%
  left_join(final_df, by = "forecast_period") %>%
  filter(!is.na(actual_value), !is.na(forecast_value)) %>%
  mutate(
    error = forecast_value - actual_value,
    sqerror = error^2,
    # -log density of the realisation under the posterior predictive, the same
    # definition analysis/fcast/2_evaluation_fcast.R uses. Lower is better.
    logs = -stats::dnorm(actual_value, mean = forecast_value,
                         sd = forecast_sd, log = TRUE),
    # Weeks from the evaluation date to the end of the nowcast quarter.
    # Negative = quarter still running (nowcast), positive = finished (backcast).
    horizon_weeks = round((forecast_period + 0.25 - eval_date) * 48),
    # create_error_summary_tables() keys its columns off `lag_number`; one
    # horizon per lag, so they are the same thing here.
    lag_number = horizon_weeks,
    method = "nowcast",
    frequency = "QoQ"
  )

lag_range <- sort(unique(panel$lag_number))
message("horizons present (weeks to quarter end): ",
        paste(lag_range, collapse = ", "))


# SUBSAMPLES --------------------------------------------------------------

# The three the issue asks for. "excl. 2020-2021" drops the pandemic quarters,
# which dominate squared errors; "since 2015" starts at the exchange-rate shock.
subsamples <- list(
  full          = function(d) d,
  `excl_2020_21` = function(d) d[d$forecast_period < 2020 | d$forecast_period >= 2022, , drop = FALSE],
  since_2015    = function(d) d[d$forecast_period >= 2015, , drop = FALSE]
)


# TABLES ------------------------------------------------------------------

# Mean over seeds first: a seed is a nuisance dimension, not an observation.
by_seed_collapsed <- panel %>%
  group_by(eval_date, model, method, frequency, lag_number, forecast_period,
           actual_value) %>%
  summarise(
    forecast_value = mean(forecast_value, na.rm = TRUE),
    forecast_sd = sqrt(mean(forecast_sd^2, na.rm = TRUE)),
    n_seeds = dplyr::n(),
    .groups = "drop"
  ) %>%
  mutate(
    error = forecast_value - actual_value,
    sqerror = error^2,
    logs = -stats::dnorm(actual_value, mean = forecast_value,
                         sd = forecast_sd, log = TRUE)
  )

# Plain RMSFE / MAE / log score by horizon, per subsample. Reported next to the
# relative figures because a ratio with no level behind it is unreadable.
score_table <- dplyr::bind_rows(lapply(names(subsamples), function(s) {
  d <- subsamples[[s]](as.data.frame(by_seed_collapsed))
  if (!nrow(d)) return(NULL)
  d %>%
    group_by(model, lag_number) %>%
    summarise(n = dplyr::n(),
              rmsfe = sqrt(mean(sqerror, na.rm = TRUE)),
              mae = mean(abs(error), na.rm = TRUE),
              logscore = mean(logs, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(subsample = s, .before = 1)
}))

rel_score_table <- score_table %>%
  group_by(subsample, lag_number) %>%
  mutate(
    rel_rmsfe = rmsfe / rmsfe[model == "WAI"],
    rel_mae = mae / mae[model == "WAI"],
    # The log score is negative-friendly: a difference, not a ratio, is what
    # reads correctly here. Same reasoning as analysis/fcast/4_*.R records.
    d_logscore = logscore - logscore[model == "WAI"]
  ) %>%
  ungroup()

cat("\n== RMSFE / MAE / mean log score by horizon and subsample ==\n")
print(as.data.frame(score_table), digits = 4, row.names = FALSE)
cat("\n== with_brent relative to full_RT (ratio < 1 / difference < 0 favours Brent) ==\n")
print(as.data.frame(rel_score_table[, c("subsample", "lag_number", "model", "n",
                                        "rel_rmsfe", "rel_mae", "d_logscore")]),
      digits = 4, row.names = FALSE)

# Diebold-Mariano, both directions, so the table cannot be read as one-sided by
# accident. `alternative = "greater"` tests H1: loss(e1) > loss(e2).
dm_table <- dplyr::bind_rows(lapply(names(subsamples), function(s) {
  d <- subsamples[[s]](as.data.frame(by_seed_collapsed))
  if (!nrow(d)) return(NULL)
  dplyr::bind_rows(lapply(sort(unique(d$lag_number)), function(h) {
    dh <- d[d$lag_number == h, , drop = FALSE]
    e_base <- dh$error[dh$model == "WAI"][order(dh$forecast_period[dh$model == "WAI"])]
    e_brent <- dh$error[dh$model == "WAI-Brent"][order(dh$forecast_period[dh$model == "WAI-Brent"])]
    n <- min(length(e_base), length(e_brent))
    if (n < 5) return(NULL)
    e_base <- e_base[seq_len(n)]
    e_brent <- e_brent[seq_len(n)]
    safe <- function(expr) tryCatch(expr, error = function(e) NA_real_)
    data.frame(
      subsample = s, lag_number = h, n = n,
      p_brent_worse_rmse = safe(dm_test_modified(e_brent, e_base, h = 1, power = 2,
                                                 alternative = "greater")),
      p_brent_better_rmse = safe(dm_test_modified(e_base, e_brent, h = 1, power = 2,
                                                  alternative = "greater")),
      p_brent_worse_mae = safe(dm_test_modified(e_brent, e_base, h = 1, power = 1,
                                                alternative = "greater")),
      p_brent_better_mae = safe(dm_test_modified(e_base, e_brent, h = 1, power = 1,
                                                 alternative = "greater")),
      stringsAsFactors = FALSE
    )
  }))
}))

cat("\n== Diebold-Mariano p-values (modified; both directions) ==\n")
if (nrow(dm_table)) {
  print(as.data.frame(dm_table), digits = 3, row.names = FALSE)
} else {
  cat("too few paired observations per horizon for a DM test\n")
}

# The repo's own error-table machinery, for a table shaped like the published
# ones. Needs at least one horizon inside its lag_range.
error_tables <- tryCatch(
  create_error_summary_tables(as.data.frame(by_seed_collapsed), model_order,
                              date_col = "forecast_period",
                              lag_range = lag_range),
  error = function(e) {
    message("create_error_summary_tables() skipped: ", conditionMessage(e))
    NULL
  }
)
error_tables_period <- tryCatch(
  create_error_summary_tables(as.data.frame(by_seed_collapsed), model_order,
                              date_col = "forecast_period",
                              lag_range = lag_range, include_period = TRUE),
  error = function(e) {
    message("create_error_summary_tables(include_period) skipped: ",
            conditionMessage(e))
    NULL
  }
)

if (!is.null(error_tables)) {
  cat("\n== relative RMSE table (create_error_summary_tables; stars = Brent significantly WORSE) ==\n")
  print(error_tables$rel_rmse)
  cat("\n== relative RMSE, crisis / non-crisis split ==\n")
  print(error_tables_period$rel_rmse)
}


# SEED NOISE --------------------------------------------------------------

# A variant difference no bigger than the seed-to-seed spread is not evidence.
# ?ind_dfm's "Reproducibility across seeds" section records nowcast
# correlations of 0.987-1.000 across five seeds, so a small difference here
# should be read against that, not against zero.
if (length(seeds) > 1) {
  seed_spread <- panel %>%
    group_by(model, eval_date, forecast_period) %>%
    summarise(spread = diff(range(forecast_value)), .groups = "drop") %>%
    group_by(model) %>%
    summarise(mean_seed_spread = mean(spread, na.rm = TRUE),
              max_seed_spread = max(spread, na.rm = TRUE), .groups = "drop")
  variant_gap <- panel %>%
    group_by(seed, eval_date, forecast_period) %>%
    filter(dplyr::n_distinct(model) == 2) %>%
    summarise(gap = abs(diff(forecast_value[order(model)])), .groups = "drop") %>%
    summarise(mean_variant_gap = mean(gap, na.rm = TRUE),
              max_variant_gap = max(gap, na.rm = TRUE))
  cat("\n== seed noise versus the variant difference ==\n")
  print(as.data.frame(seed_spread), digits = 4, row.names = FALSE)
  print(as.data.frame(variant_gap), digits = 4, row.names = FALSE)
} else {
  cat("\n== seed noise ==\nOne seed only; re-run with BRENT_SEEDS=1,2 to measure it.\n")
}


# BRENT LOADING -----------------------------------------------------------

loading <- panel %>%
  filter(model == "WAI-Brent", !is.na(brent_loading)) %>%
  distinct(eval_date, seed, brent_loading)
if (nrow(loading)) {
  cat("\n== Brent loading on the factor (posterior mean, per fit) ==\n")
  print(data.frame(
    n_fits = nrow(loading),
    mean = mean(loading$brent_loading),
    sd = stats::sd(loading$brent_loading),
    min = min(loading$brent_loading),
    max = max(loading$brent_loading)
  ), digits = 4, row.names = FALSE)
}


# SAVE --------------------------------------------------------------------

write.csv(as.data.frame(score_table),
          file.path(out_dir, "brent_scores_by_horizon.csv"), row.names = FALSE)
write.csv(as.data.frame(rel_score_table),
          file.path(out_dir, "brent_relative_scores.csv"), row.names = FALSE)
if (nrow(dm_table)) {
  write.csv(as.data.frame(dm_table),
            file.path(out_dir, "brent_dm_tests.csv"), row.names = FALSE)
}
saveRDS(list(panel = panel, collapsed = by_seed_collapsed,
             score_table = score_table, rel_score_table = rel_score_table,
             dm_table = dm_table, error_tables = error_tables,
             error_tables_period = error_tables_period,
             settings = list(length_sample = length_sample, burn_in = burn_in,
                             seeds = seeds, dates = date_vec)),
        file.path(out_dir, "brent_evaluation.rds"))
message("wrote outputs to ", out_dir)
