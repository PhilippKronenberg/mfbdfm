# Date and vintage aggregation utilities shared by the analytics workflow.

#' Convert dates to decimal years (day-of-year convention)
#'
#' Converts dates to decimal years as `year + (day_of_year - 1)/365`,
#' the convention used throughout the WAI vintage handling. Unlike
#' `lubridate::decimal_date()`, this does not account for leap years.
#'
#' @param x `Date` vector (or coercible).
#'
#' @return Numeric vector of decimal years.
#'
#' @examples
#' decimal_date_local(as.Date("2020-03-07"))
#'
#' @export
decimal_date_local <- function(x) {
  x <- as.Date(x)
  as.numeric(format(x, "%Y")) +
    (as.numeric(format(x, "%j")) - 1) / 365
}


#' Flag crisis periods
#'
#' Flags the crisis episodes of either published analysis. `windows = "wai"`
#' (the default) marks **dates** inside the two windows used by the Weekly
#' Activity Index analysis; `windows = "fcast"` marks **target quarters**
#' inside the four windows used by the out-of-sample evaluation of Eckert,
#' Kronenberg, Mikosch & Neuwirth (2025).
#'
#' @details
#' The two definitions are **not** interchangeable, which is why the choice is
#' an explicit argument rather than something a caller can drift past. They
#' differ in two ways, both of which matter:
#'
#' \describe{
#'   \item{What is classified}{`"wai"` takes the **date the nowcast was made**,
#'     as a `Date`. `"fcast"` takes the **target quarter** being nowcast, as
#'     decimal time (`2020.25` for 2020Q2) -- the `period` column of the
#'     evaluation panel. In a real-time evaluation those are weeks or months
#'     apart, so the two label different rows.}
#'   \item{Which episodes}{`"wai"` covers the global financial crisis
#'     (2008-07-07 to 2009-09-28) and Covid-19 (2020-01-01 to 2021-12-28).
#'     `"fcast"` adds the euro crisis and the 2015 Swiss franc shock, and its
#'     windows are quarters rather than days.}
#' }
#'
#' Measured on the paper's own evaluation panel, the two agree on only 124 of
#' its 240 crisis dates, and using `"wai"` where `"fcast"` is meant does not
#' reproduce the published figures: crisis RMSFE for the monthly benchmark comes
#' out at 0.0262 against the 0.0210 the `"fcast"` definition gives, which is
#' what the paper plots.
#'
#' Before version 0.1.0.9000 the `"fcast"` windows lived in a second exported
#' function, `is_crisis_period_fcast()`. Two exported functions for one concept
#' with different hard-coded windows is exactly the parity problem the `windows`
#' argument removes; `is_crisis_period(x, windows = "fcast")` replaces it.
#'
#' @param date_vec Periods to classify. For `windows = "wai"` a `Date` vector
#'   (or coercible). For `windows = "fcast"` a numeric vector of target quarters
#'   in decimal time, e.g. `2020.25` for 2020Q2.
#' @param windows Which crisis definition to apply: `"wai"` (default) for the
#'   date-based windows of the Weekly Activity Index analysis, or `"fcast"` for
#'   the quarter-based windows of Eckert et al. (2025).
#'
#' @return Logical vector, `TRUE` for periods inside a crisis window.
#'
#' @examples
#' is_crisis_period(as.Date(c("2015-01-01", "2020-06-01")))
#'
#' # the Eckert et al. (2025) windows, on target quarters in decimal time:
#' # 2020Q1-2021Q3 are crisis quarters, 2019 and 2022 are not
#' is_crisis_period(c(2019, 2020, 2021.25, 2022), windows = "fcast")
#'
#' # and the two genuinely differ -- 2012 is a crisis quarter only for "fcast"
#' is_crisis_period(2012, windows = "fcast")
#' is_crisis_period(as.Date("2012-06-01"))
#'
#' @references
#' Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
#' Tracking economic activity with alternative high-frequency data.
#' *Journal of Applied Econometrics*, 40(3), 270-290.
#' \doi{10.1002/jae.3104}
#'
#' @export
is_crisis_period <- function(date_vec, windows = c("wai", "fcast")) {

  windows <- match.arg(windows)

  if (windows == "wai") {
    crisis_dates <- data.frame(
      start = as.Date(c("2008-07-07", "2020-01-01")),
      end = as.Date(c("2009-09-28", "2021-12-28"))
    )
    return(vapply(as.Date(date_vec),
                  function(d) any(d >= crisis_dates$start & d <= crisis_dates$end),
                  logical(1)))
  }

  if (!is.numeric(date_vec)) {
    stop("With `windows = \"fcast\"`, `date_vec` must be numeric decimal time ",
         "(e.g. 2020.25 for 2020Q2), not a ", class(date_vec)[1], ". That ",
         "definition classifies the target quarter being nowcast, not the date ",
         "the nowcast was made - use `windows = \"wai\"` for the latter.",
         call. = FALSE)
  }

  # Verbatim from 3a_evaluation_full.R of the paper's replication code; the
  # windows are inclusive at both ends.
  (date_vec >= 2008.75 & date_vec <= 2009.5)    |   # global financial crisis
    (date_vec >= 2011.5  & date_vec <= 2013)    |   # euro crisis
    (date_vec >= 2015    & date_vec <= 2015.25) |   # Swiss franc shock
    (date_vec >= 2020    & date_vec <= 2021.5)      # Covid-19

}


#' Aggregate a higher-frequency series to the 48-week grid
#'
#' Aggregates a date-indexed `zoo` series into the project's
#' 48-periods-per-year weekly grid. Despite the name it is not restricted to
#' daily input -- the aggregation is driven entirely by the date index, so a
#' true weekly (52-per-year) series is handled the same way. That is how
#' [mfbdfm_data()] puts weekly and daily input onto the grid the models use;
#' see its "Frequency" section.
#'
#' @param x Series to aggregate (`zoo` indexed by `Date`).
#' @param FUN Function used to combine the observations falling into one
#'   48-week slot. Defaults to `mean`. Which is appropriate depends on the
#'   series: these models are estimated on growth rates, for which the mean is
#'   the per-period rate, whereas `sum` would preserve the total but leave a
#'   visible spike in the roughly four slots per year that receive two weekly
#'   observations.
#'
#' @return A `ts` with frequency 48; slots with no observation are `NA`.
#'
#' @importFrom stats time as.ts aggregate
#' @examples
#' daily <- zoo::zoo(rnorm(120),
#'                   order.by = seq(as.Date("2024-01-01"), by = "day", length.out = 120))
#' weekly <- daily2weekly(daily)
#' stats::frequency(weekly)
#' @export
daily2weekly <- function(x, FUN = mean){

  idx <- plyr::round_any(x = as.numeric(format(time(x), "%Y")) +
                           (as.numeric(format(time(x), "%m"))-1)/12 +
                           as.numeric(format(time(x), "%d"))/365,
                         accuracy = 1/48,
                         f = floor)

  ts_weekly <- as.ts(aggregate(x = x,
                               by = idx,
                               FUN = FUN,
                               na.rm=TRUE))
  ts_weekly[is.nan(ts_weekly)] <- NA
  ts_weekly

}


#' Aggregate a predictor data frame to quarterly frequency
#'
#' Aggregates a `time`/`value` data frame to quarters by mean, by the
#' cut-off month, or by the last observation of the cut-off month.
#'
#' **Warning:** this function dispatches on the *name* of the object
#' passed as `df`: if the deparsed argument name contains `"AR"`, the
#' data frame is returned with only a `yearqtr` column added. This
#' legacy behavior is kept for compatibility with the analysis scripts;
#' avoid renaming objects passed to it.
#'
#' @param df Data frame with `time` (Date) and `value` columns.
#' @param cut_off_month_pos Integer position of the cut-off month within
#'   the quarter. Required by methods `"last_month"` and `"last"`, ignored
#'   by `"mean"`.
#' @param method One of `"last_month"`, `"mean"`, `"last"`. **Required —
#'   there is deliberately no default.** The choice changes the result, so it
#'   is the caller's to make: a quarterly mean and a cut-off-month reading of
#'   the same weekly series are different numbers, and silently picking one
#'   would be a silent wrong answer.
#'
#' @return A quarterly data frame (columns depend on `method`).
#'
#' @importFrom dplyr mutate group_by filter summarise ungroup rename slice_max select
#' @importFrom zoo as.yearqtr
#' @importFrom lubridate floor_date
#' @examples
#' df <- data.frame(time = seq(as.Date("2023-01-01"), by = "month", length.out = 12),
#'                  value = rnorm(12))
#' aggregate_predictor_to_quarterly(df, cut_off_month_pos = 1, method = "mean")
#' @export
aggregate_predictor_to_quarterly <- function(df, cut_off_month_pos = NULL, method) {

  # Validated BEFORE the "AR" dispatch below, so the requirement holds on every
  # path rather than only on the ones that happen to reach the aggregation.
  #
  # The default used to be method = "cut_off", which no branch implements - so
  # calling with defaults always fell through to the final stop(). A default
  # that cannot work is worse than no default: it reads as though the function
  # has a sensible fallback when it has none.
  if (missing(method)) {
    stop("`method` must be given explicitly, as one of \"last_month\", ",
         "\"mean\" or \"last\". There is deliberately no default: the ",
         "aggregation changes the result, so the caller has to choose it.",
         call. = FALSE)
  }
  method <- match.arg(method, c("last_month", "mean", "last"))

  # cut_off_month_pos = NULL reached `month %% 3 == (NULL %% 3)`, which is
  # logical(0); filter() then dropped every row and returned an EMPTY quarterly
  # frame rather than complaining.
  if (method %in% c("last_month", "last") && is.null(cut_off_month_pos)) {
    stop("`cut_off_month_pos` is required when `method` is \"", method,
         "\"; it names the month within the quarter to read.", call. = FALSE)
  }

  df_name <- deparse(substitute(df))

  # If name contains "AR", return df with time converted to yearqtr
  if (grepl("AR", df_name)) {
    return(
      result <- df %>%
        mutate(yearqtr = as.yearqtr(time))
    )
  }
  if (method == "last_month") {
    result <- df %>%
    mutate(month = as.numeric(format(time, "%m")),
           yearqtr = as.yearqtr(time)) %>%
    group_by(yearqtr) %>%
      filter(month %% 3 == (cut_off_month_pos %% 3)) %>%
    summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
    ungroup()

  } else if (method == "mean") {
    result <- df %>%
      mutate(quarter = floor_date(time, unit = "quarter")) %>%
      group_by(quarter) %>%
      summarise(value = mean(value, na.rm = TRUE), .groups = "drop") %>%
      ungroup() %>%
      rename(time = quarter) %>%
    mutate(yearqtr = as.yearqtr(time))

  } else if (method == "last") {
    result <- df %>%
      mutate(month = as.numeric(format(time, "%m")),
             yearqtr = as.yearqtr(time)) %>%
      group_by(yearqtr) %>%
      filter(month %% 3 == (cut_off_month_pos %% 3)) %>%
      slice_max(order_by = time, with_ties = FALSE) %>%  # Select the latest date per yearqtr
      ungroup() %>%
      select(yearqtr, value)
  } else {
    # unreachable: match.arg() above admits only the three handled methods
    stop("Unknown method: ", method, ".", call. = FALSE)
  }

  return(result)
}


#' First target vintage after a prediction vintage
#'
#' @param pred_vintage Numeric decimal date of the prediction vintage.
#' @param target_vintages Numeric vector of available target vintages.
#'
#' @return The smallest target vintage strictly after `pred_vintage`, or
#'   `NA` if none exists.
#'
#' @keywords internal
get_next_target_vintage <- function(pred_vintage, target_vintages) {
  valid_targets <- target_vintages[target_vintages > pred_vintage]
  if (length(valid_targets) == 0) return(NA_real_)
  min(valid_targets)
}
