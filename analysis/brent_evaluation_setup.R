# Run from the repository root; sourced, not run on its own.
#
# Shared prelude for the two Brent scripts (issue #173) -------------------
#
# analysis/brent_diagnostics.R (one date, cheap) and
# analysis/brent_evaluation.R (the full pseudo-real-time loop) must use the
# same dataset variants, the same target and the same real-time cutting, or the
# diagnostics do not describe the fits the evaluation runs. That shared part
# lives here.

suppressMessages({
  library(zoo)
  library(mfbdfm)
})

if (!exists("BRENT_KEY")) source("analysis/brent_oil.R")

BRENT_TARGET <- "ch.seco.gdp.real.gdp.ssa"

# The panel with GDP in it. analysis/Rda/data_ch_dataset_test.Rda is tracked, so
# this works on a fresh clone; the private raw sources under data/dataset/ are
# only needed to *rebuild* it.
BRENT_PANEL_RDA <- file.path("analysis", "Rda", "data_ch_dataset_test.Rda")

# Where the raw daily Brent CSV lives. Fetched by analysis/1_data_prep_dataset.R
# in a normal prep run; fetched here on demand, since the evaluation has to be
# runnable without the rest of the private data.
BRENT_DATASET_DIR <- file.path("data", "dataset")

#' First week of every quarter from 2015 to the end of the panel
#'
#' The evaluation dates. They must sit on a quarter's first week (0/48, 12/48,
#' 24/48 or 36/48) for the horizon bookkeeping in the error tables to line up -
#' see the note in analysis/real_time_backcast.R.
brent_eval_dates <- function(from_year = 2015, to_year = NULL, panel_end = NULL) {
  if (is.null(to_year)) {
    to_year <- if (is.null(panel_end)) as.integer(format(Sys.Date(), "%Y")) else floor(panel_end)
  }
  grid <- as.numeric(outer(from_year:to_year, c(0, 12, 24, 36) / 48, "+"))
  grid <- sort(grid)
  if (!is.null(panel_end)) grid <- grid[grid <= panel_end]
  grid
}

#' The weekly, transformed Brent series, fetching the raw CSV if it is absent
brent_series <- function(dataset_dir = BRENT_DATASET_DIR, refetch = FALSE) {
  path <- file.path(dataset_dir, BRENT_RAW_FILE)
  if (refetch || !file.exists(path)) {
    message("fetching ", BRENT_KEY, " from FRED")
    fetch_brent_daily(dataset_dir, overwrite = TRUE, quiet = TRUE)
  }
  brent_weekly_transformed(path = path)
}

#' The two dataset variants the evaluation compares
#'
#' `full_RT` is the baseline, exactly as in analysis/real_time_backcast.R.
#' `with_brent` is that panel with the transformed Brent series appended to
#' `flows` (Flow = 1 in data_meta.csv, like SWISSMI). Nothing else differs.
brent_variant_datasets <- function(panel_rda = BRENT_PANEL_RDA, ...) {
  env <- new.env(parent = emptyenv())
  load(panel_rda, envir = env)
  base <- get("dat", envir = env)

  brent <- brent_series(...)
  with_brent <- base
  with_brent$flows[[BRENT_KEY]] <- brent

  list(full_RT = base, with_brent = with_brent)
}

#' Cut a dataset to a real-time vintage and inject the GDP vintage
#'
#' The same two steps analysis/real_time_backcast.R performs inside its date
#' loop, factored out so both Brent scripts do it identically.
#'
#' Brent needs no series-specific publication lag: cut_data_real_time() already
#' withholds every frequency-48 series for one week (`current_date - 1/48`),
#' and FRED publishes Brent with a one-business-day lag (see analysis/brent_oil.R),
#' so the standard weekly convention is already conservative for it.
brent_prepare_realtime <- function(dataset, eval_date, GDP_gr_vintages) {
  out <- cut_data_real_time(dataset, eval_date, GDP_gr_vintages)
  out$flows[[BRENT_TARGET]] <- zoo::na.trim(
    stats::ts(
      select_most_recent_GDP_vintage(eval_date, GDP_gr_vintages),
      start = c(1990, 1),
      frequency = 4
    )
  )
  out
}

# The dates both scripts use. Capped at the end of the baseline panel so a
# refetched Brent series cannot push the loop past where GDP exists.
BRENT_PANEL_END <- local({
  env <- new.env(parent = emptyenv())
  load(BRENT_PANEL_RDA, envir = env)
  d <- get("dat", envir = env)
  weekly <- Filter(function(x) stats::frequency(x) == 48, c(d$flows, d$stocks))
  max(vapply(weekly, function(x) as.numeric(utils::tail(stats::time(x), 1)), numeric(1)))
})

BRENT_EVAL_DATES <- brent_eval_dates(from_year = 2015, panel_end = BRENT_PANEL_END)
