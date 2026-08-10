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


#' Flag dates falling into the crisis periods
#'
#' Marks dates inside the financial crisis (2008-07-07 to 2009-09-28) or
#' the Covid-19 crisis (2020-01-01 to 2021-12-28).
#'
#' @param date_vec `Date` vector (or coercible).
#'
#' @return Logical vector.
#'
#' @examples
#' is_crisis_period(as.Date(c("2015-01-01", "2020-06-01")))
#'
#' @export
is_crisis_period <- function(date_vec) {
  crisis_dates <- data.frame(
    start = as.Date(c("2008-07-07", "2020-01-01")),
    end = as.Date(c("2009-09-28", "2021-12-28"))
  )
  vapply(as.Date(date_vec), function(d) any(d >= crisis_dates$start & d <= crisis_dates$end), logical(1))
}


#' Flag target quarters falling into the Eckert et al. (2025) crisis periods
#'
#' The crisis/non-crisis split used in the out-of-sample evaluation of Eckert,
#' Kronenberg, Mikosch & Neuwirth (2025). Carries the `_fcast` suffix for the
#' same reason the multi-factor internals do: it is the counterpart of
#' [is_crisis_period()] for that paper, and the two are **not** interchangeable.
#'
#' @details
#' Two differences from [is_crisis_period()], both of which matter:
#'
#' \describe{
#'   \item{What is classified}{This takes the **target quarter** being nowcast,
#'     as decimal time (`2020.25` for 2020Q2). [is_crisis_period()] takes the
#'     **date the nowcast was made**. In a real-time evaluation those are weeks
#'     or months apart, so the two label different rows.}
#'   \item{Which episodes}{Four windows here -- the global financial crisis, the
#'     euro crisis, the 2015 Swiss franc shock and Covid-19. [is_crisis_period()]
#'     covers only the first and last.}
#' }
#'
#' Measured on the paper's own evaluation panel, the two agree on only 124 of
#' its 240 crisis dates, and substituting [is_crisis_period()] does not
#' reproduce the published figures: crisis RMSFE for the monthly benchmark comes
#' out at 0.0262 against the 0.0210 this definition gives, which is what the
#' paper plots.
#'
#' @param period Numeric vector of target quarters in decimal time, e.g.
#'   `2020.25` for 2020Q2. This is the `period` column of the evaluation panel,
#'   not the nowcast date.
#'
#' @return Logical vector, `TRUE` for quarters inside a crisis window.
#'
#' @examples
#' # 2020Q1-2021Q3 are crisis quarters; 2019 and 2022 are not
#' is_crisis_period_fcast(c(2019, 2020, 2021.25, 2022))
#'
#' @references
#' Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
#' Tracking economic activity with alternative high-frequency data.
#' *Journal of Applied Econometrics*, 40(3), 270-290.
#' \doi{10.1002/jae.3104}
#'
#' @seealso [is_crisis_period()] for the date-based definition used by the
#'   Weekly Activity Index analysis.
#' @export
is_crisis_period_fcast <- function(period) {

  if (!is.numeric(period)) {
    stop("`period` must be numeric decimal time (e.g. 2020.25 for 2020Q2), ",
         "not a ", class(period)[1], ". This function classifies the target ",
         "quarter, not the nowcast date - see is_crisis_period() for the ",
         "latter.", call. = FALSE)
  }

  # Verbatim from 3a_evaluation_full.R of the paper's replication code; the
  # windows are inclusive at both ends.
  (period >= 2008.75 & period <= 2009.5)    |   # global financial crisis
    (period >= 2011.5  & period <= 2013)    |   # euro crisis
    (period >= 2015    & period <= 2015.25) |   # Swiss franc shock
    (period >= 2020    & period <= 2021.5)      # Covid-19

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
#'   the quarter (used by methods `"last_month"` and `"last"`).
#' @param method One of `"last_month"`, `"mean"`, `"last"`.
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
aggregate_predictor_to_quarterly <- function(df, cut_off_month_pos = NULL, method = "cut_off") {
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
    stop("Unknown method. Please choose 'cut_off', 'mean', or 'last'.")
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
#' @examples
#' get_next_target_vintage(2020.5, c(2020.25, 2020.75, 2021))
#'
#' @export
get_next_target_vintage <- function(pred_vintage, target_vintages) {
  valid_targets <- target_vintages[target_vintages > pred_vintage]
  if (length(valid_targets) == 0) return(NA_real_)
  min(valid_targets)
}
