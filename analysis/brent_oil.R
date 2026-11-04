# Run from the repository root; sourced, not run on its own.
#
# Brent crude oil spot price (FRED series DCOILBRENTEU) -------------------
#
# Fetching and harmonising the daily Europe Brent spot price (FOB, USD per
# barrel; EIA via FRED, public domain) to the project's weekly frequency.
#
# Why this lives in analysis/ and not in R/: the package must not acquire a
# network dependency. Everything here is analysis-side. It is a sourced helper
# rather than inline code in 1_data_prep_dataset.R because the evaluation
# script (analysis/brent_evaluation.R) needs the same series without the
# private raw data that the prep script reads.
#
# Preprocessing mirrors SWISSMI, the other daily price series in the panel:
# duplicate dates averaged, a 7-day (trailing) moving average on the daily
# level, then aggregation to the project's 48-periods-per-year weekly grid.
# brent_daily_ma7_to_weekly() below is the same computation as
# 1_data_prep_dataset.R's aggregate_duplicate_dates() + daily_ma7_to_weekly()
# chain, kept here so this file stands alone; if one is changed the other must
# be changed with it.
#
# Publication lag (measured 2026-11-04 against FRED's own series page):
#   Date Range   1987-05-20 to 2026-10-27
#   Last Updated 2026-10-28 12:18 PM CDT
# i.e. FRED carried the 27 October value on 28 October - a one-business-day
# lag. That is far shorter than the one-week lag cut_data()/cut_data_real_time()
# already impose on every frequency-48 series (`current_date - 1/48`), so the
# existing weekly convention is conservative for Brent and no series-specific
# lag is needed. See BRENT_RELEASE_LAG_DAYS below.
#
# Note the series can nonetheless go stale: on 2026-11-04 the newest observation
# was still 2026-10-27, eight days old, with no intervening update. A real-time
# user gets whatever FRED has, and the one-week cut absorbs that too.

library(zoo)
library(dplyr)

# FRED's plain CSV endpoint. Documented, no API key, no HTML scraping.
BRENT_KEY       <- "DCOILBRENTEU"
BRENT_FRED_URL  <- "https://fred.stlouisfed.org/graph/fredgraph.csv?id=DCOILBRENTEU"
BRENT_RAW_FILE  <- "FRED_DCOILBRENTEU.csv"

# Nominal publication lag in calendar days, measured above. Recorded for the
# evaluation to reason about rather than used to shift anything: one business
# day is inside the one week that cut_data_real_time() already withholds.
BRENT_RELEASE_LAG_DAYS <- 1L

#' Download the raw daily Brent CSV into the dataset directory
#'
#' Writes to `file.path(dataset_dir, BRENT_RAW_FILE)`, alongside every other
#' raw source. Returns the path invisibly.
#'
#' @param dataset_dir Directory to write into (created if absent).
#' @param overwrite Re-download even if the file is already there.
#' @param quiet Passed to `utils::download.file()`.
fetch_brent_daily <- function(dataset_dir, overwrite = TRUE, quiet = FALSE) {
  dir.create(dataset_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(dataset_dir, BRENT_RAW_FILE)
  if (!overwrite && file.exists(dest)) {
    return(invisible(dest))
  }
  utils::download.file(BRENT_FRED_URL, destfile = dest, mode = "wb", quiet = quiet)
  invisible(dest)
}

#' Read the raw daily Brent CSV
#'
#' FRED's CSV has two columns, a date and the value, and writes missing
#' observations as a bare `.`; both that and an empty field are read as `NA`.
#' The column names have changed over the years (`DATE` then
#' `observation_date`), so the columns are taken by position.
#'
#' @param path Path to the CSV written by [fetch_brent_daily()].
#' @return A data frame with columns `date` (`Date`) and `value` (numeric),
#'   sorted by date, with missing values kept as `NA`.
read_brent_daily <- function(path) {
  raw <- utils::read.csv(
    path,
    stringsAsFactors = FALSE,
    check.names = FALSE,
    na.strings = c("", ".", "NA", "NaN")
  )
  if (ncol(raw) < 2L) {
    stop("Unexpected Brent CSV layout in ", path, ": ", ncol(raw), " column(s).",
         call. = FALSE)
  }
  out <- data.frame(
    date = as.Date(trimws(as.character(raw[[1]])), format = "%Y-%m-%d"),
    value = suppressWarnings(as.numeric(raw[[2]]))
  )
  out <- out[!is.na(out$date), , drop = FALSE]
  out[order(out$date), , drop = FALSE]
}

#' Aggregate daily observations to the project's 48-per-year weekly grid
#'
#' Same rule as `daily_to_weekly()` in analysis/1_data_prep_dataset.R.
#'
#' @noRd
brent_daily_to_weekly <- function(dates, values) {
  dates <- as.Date(dates)
  values <- as.numeric(values)
  keep <- !is.na(dates)
  dates <- dates[keep]
  values <- values[keep]
  frac <- as.numeric(format(dates, "%Y")) +
    (as.numeric(format(dates, "%m")) - 1) / 12 +
    as.numeric(format(dates, "%d")) / 365
  idx <- floor(frac * 48) / 48
  weekly_df <- data.frame(idx = idx, value = values) |>
    dplyr::group_by(idx) |>
    dplyr::summarise(
      value = if (all(is.na(value))) NA_real_ else mean(value, na.rm = TRUE),
      .groups = "drop"
    )
  weekly_vals <- weekly_df$value
  weekly_vals[is.nan(weekly_vals)] <- NA_real_
  stats::ts(weekly_vals, start = weekly_df$idx[1], frequency = 48)
}

#' Smooth the daily level with a 7-day moving average, then aggregate to weekly
#'
#' Same rule as `daily_ma7_to_weekly()` in analysis/1_data_prep_dataset.R:
#' trailing 7-day mean on the daily level, then the weekly aggregation above,
#' then leading/trailing `NA`s trimmed.
#'
#' @noRd
brent_daily_ma7_to_weekly <- function(dates, values) {
  dates <- as.Date(dates)
  values <- as.numeric(values)
  keep <- !(is.na(dates) | is.na(values))
  dates <- dates[keep]
  values <- values[keep]
  if (!length(values)) {
    return(stats::ts(numeric(0), start = 0, frequency = 48))
  }
  ord <- order(dates)
  dates <- dates[ord]
  values <- values[ord]
  # Average any duplicated dates first, as the SWISSMI block does.
  agg <- stats::aggregate(values, by = list(date = dates),
                          FUN = function(x) mean(x, na.rm = TRUE))
  agg <- agg[order(agg$date), , drop = FALSE]
  ma7_vals <- stats::filter(agg$x, rep(1 / 7, 7), sides = 1)
  stats::as.ts(zoo::na.trim(zoo::as.zoo(
    brent_daily_to_weekly(agg$date, ma7_vals)
  ), sides = "both"))
}

#' Build the harmonised weekly Brent level from a raw CSV
#'
#' @param path Path to the raw CSV; defaults to the copy in `dataset_dir`.
#' @param dataset_dir Directory holding the raw sources.
#' @return A weekly (`frequency = 48`) `ts` of the smoothed Brent level in USD
#'   per barrel, pre-transformation.
brent_weekly_level <- function(path = NULL, dataset_dir = file.path("data", "dataset")) {
  if (is.null(path)) path <- file.path(dataset_dir, BRENT_RAW_FILE)
  daily <- read_brent_daily(path)
  brent_daily_ma7_to_weekly(daily$date, daily$value)
}

#' The modelled Brent series: the weekly level, log-differenced
#'
#' Applies the transformation the `data_meta.csv` row specifies
#' (`Log Difference`), matching what 1_data_prep_dataset.R does to every other
#' `Log Difference` series. This is the series to append to a dataset variant.
#'
#' @inheritParams brent_weekly_level
#' @return A weekly (`frequency = 48`) `ts`, ready to go into `dat$flows`.
brent_weekly_transformed <- function(path = NULL,
                                     dataset_dir = file.path("data", "dataset")) {
  lvl <- brent_weekly_level(path = path, dataset_dir = dataset_dir)
  out <- diff(log(lvl))
  if (as.numeric(stats::time(out))[1] < 1990) out <- stats::window(out, start = 1990)
  stats::as.ts(zoo::na.trim(zoo::as.zoo(out), sides = "both"))
}
