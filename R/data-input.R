#' Assemble and check the input data for a dynamic factor model
#'
#' Converts the data you have into the form the models need, and -- more
#' importantly -- makes the flow/stock classification and the inferred
#' frequencies visible so they can be checked *before* committing to a run
#' that takes minutes to hours.
#'
#' @details
#' # Why this exists
#'
#' [ind_dfm()] and [fcast_dfm()] take `flows` and `stocks` as two separate
#' named lists of `ts` objects. That shape is necessary -- mixed frequencies
#' cannot sit in one rectangular table without padding -- but it means each
#' series' type is expressed by *which argument it was passed in*, so there is
#' nowhere to inspect or correct it.
#'
#' That matters because the type selects the temporal aggregation weights:
#'
#' \describe{
#'   \item{`"flow"`}{A quantity accumulated over the period (GDP, sales,
#'     traffic counts). Gets the triangular Mariano-Murasawa weights.}
#'   \item{`"stock"`}{A level observed at a point, or an average (a price
#'     index, VIX, a sentiment balance). Gets simple averaging weights.}
#' }
#'
#' For series at the **highest** frequency in the dataset the two sets of
#' weights are identical, so the choice cannot matter there. For lower-frequency
#' series they differ substantially (measured on a weekly-highest dataset: a
#' monthly series gets 7 nonzero lags as a flow against 4 as a stock, a
#' quarterly one 23 against 12), and misclassifying one silently changes your
#' results. `mfbdfm_data()` therefore requires `type` for exactly the series
#' where it can change the answer, and `print()` shows the classification back
#' to you.
#'
#' # What it accepts
#'
#' `data` may be
#' \itemize{
#'   \item a **long** data frame with columns `series`, `date` (or `time`) and
#'     `value` -- handles ragged histories and mixed frequency with no padding;
#'   \item a **wide** data frame with a date/time column and one column per
#'     series (leading and trailing `NA`s are trimmed per series, so a ragged
#'     panel does not become a padded one);
#'   \item an `mts` (multivariate `ts`), for a single-frequency dataset;
#'   \item a named **list of `ts`** objects, which is what the models use
#'     internally, so this is a pass-through with validation.
#' }
#'
#' # Frequency
#'
#' For data frames the frequency is inferred from each series' own date
#' spacing and reported by `print()`, so an inference you did not intend is
#' visible rather than silent. Only the frequencies this package models are
#' recognised -- 4 (quarterly), 12 (monthly), 48, 52 (weekly) and 365 (daily);
#' anything else is an error rather than a guess, because a wrong frequency
#' silently corrupts the temporal aggregation.
#'
#' Frequency 48 is the four-weeks-per-month grid used by the Weekly Activity
#' Index, on which observations fall on the 7th, 14th, 21st and 28th of each
#' month (see [dec2week()]). It has the same ~7-day spacing as a true weekly
#' series, so it is identified by that day-of-month convention; a series with
#' 7-day steps that does not follow it is taken to be frequency 52. Supply a
#' `frequency` column in `meta` to declare the frequency outright and skip
#' the inference. Declaring one that contradicts an input that is already a
#' `ts` is an error rather than a silent override.
#'
#' # Weekly and daily series are put on the 48-week grid
#'
#' 48 is not an arbitrary house convention -- it is the grid the models are
#' built on, and a series at a finer frequency **silently loses most of the
#' lower-frequency data**.
#'
#' [prepare_data()] shifts each series' observations to the end of their period
#' by `(max(freq)/frequency(x) - 1)/max(freq)` and then matches them onto a
#' `1/max(freq)` grid by an exact join. When the highest frequency is 48 that
#' ratio is a whole number for monthly (4) and quarterly (12) series, so every
#' observation lands on a grid point. When a frequency-52 series raises the
#' maximum to 52, `52/12` is 4.33: the shifted monthly observations no longer
#' fall on the grid, the join does not match them, and they are recorded as
#' missing. Measured on a 20-quarter / 60-month / 260-week panel, the monthly
#' series retained **20 of its 60 observations** -- and the fit completed
#' without any error or warning.
#'
#' So any series arriving at a frequency finer than 48 -- 52 (weekly) or 365
#' (daily) -- is aggregated onto the 48-week grid with [daily2weekly()], the
#' same function the analysis scripts use for this. A `message()` names the
#' series converted, `print()` shows the original frequency alongside the new
#' one, and `meta$frequency_in` records it.
#'
#' For a weekly series this goes **via daily**: the observations are first
#' expanded to the calendar days their weeks cover, and those days are then
#' aggregated onto the 48 grid. The reason is that 48 does not divide 52, so
#' mapping weekly points straight onto the grid gives each slot either one or
#' two of them -- a nearest-point pick rather than a resampling, which leaves
#' occasional empty slots and a handful of slots a year that blend two weeks
#' while the rest blend one. Routing through a common finer grid gives every
#' slot 7-8 days and makes its value an overlap-weighted blend of the weeks it
#' straddles. On a linear ramp the direct route yields steps of
#' `1.5, 1.5, 1, 1, ...` where the correct constant rate is `52/48 = 1.083`,
#' which the daily route reproduces. Daily input is already on that grid and is
#' passed straight through.
#'
#' A weekly observation's date is taken to label the **end** of its week, which
#' is this package's own convention (see [dec2week()]).
#'
#' Note this is one of the things you get by going through `mfbdfm_data()`:
#' passing `flows`/`stocks` straight to a model does no such conversion, and a
#' frequency-52 series there will still quietly cost you most of your monthly
#' observations.
#'
#' `aggregate` chooses how the days falling in one slot are combined. Because
#' the expansion repeats each weekly value across its days rather than dividing
#' it, `"mean"` (the default) is exactly the overlap-weighted average of the
#' weekly rates -- what these models want, being estimated on growth rates --
#' and `"sum"` is exactly proportional to the period total, the constant being
#' the days per period, which [prepare_data()]'s standardization removes.
#'
#' @param data The input series, in any of the forms above.
#' @param meta A data frame with one row per series and at least the columns
#'   `series` and `type` (`"flow"` or `"stock"`). May carry further columns
#'   (`label`, `source`, ...), which are kept but unused. A `frequency`
#'   column, if present, declares the frequency instead of inferring it.
#' @param target Optional character. If given, checked to be present among the
#'   series, so a typo surfaces here rather than deep in the sampler. It is
#'   stored on the object and used as the default `target` by [ind_dfm()] and
#'   [fcast_dfm()].
#' @param aggregate How to combine observations that fall into the same
#'   48-week slot when a weekly or daily series is put on the grid, either
#'   `"mean"` (the default) or `"sum"`. See the "Weekly and daily series"
#'   section.
#'
#' @return An object of class `"mfbdfm_data"`: a list with `flows`, `stocks`
#'   (named lists of `ts`, ready to pass to a model), `meta` (the resolved
#'   per-series table, with the frequency and observation count actually used,
#'   plus `frequency_in` where a series was converted) and `target`.
#'
#' @examples
#' # from a long data frame
#' long <- data.frame(
#'   series = rep(c("a_flow", "b_stock"), each = 24),
#'   date = rep(seq(as.Date("2020-01-01"), by = "month", length.out = 24), 2),
#'   value = rnorm(48))
#' meta <- data.frame(series = c("a_flow", "b_stock"),
#'                    type = c("flow", "stock"))
#' d <- mfbdfm_data(long, meta)
#' d
#'
#' # a true weekly series is aggregated onto the 48-week grid the models use,
#' # and the original frequency is reported
#' wk <- seq(as.Date("2020-01-06"), by = "week", length.out = 157)
#' d <- mfbdfm_data(
#'   rbind(data.frame(series = "weekly", date = wk, value = rnorm(length(wk))),
#'         data.frame(series = "monthly",
#'                    date = seq(as.Date("2020-01-01"), by = "month",
#'                               length.out = 36),
#'                    value = rnorm(36))),
#'   data.frame(series = c("weekly", "monthly"), type = c("flow", "stock")))
#' d$meta
#'
#' # from the shipped dataset, which is already a list of `ts`
#' data(data_ch_dataset_test)
#' series <- c(data_ch_dataset_test$flows, data_ch_dataset_test$stocks)
#' meta <- data.frame(
#'   series = names(series),
#'   type = rep(c("flow", "stock"), lengths(data_ch_dataset_test)))
#' mfbdfm_data(series, meta, target = "ch.seco.gdp.real.gdp.ssa")
#'
#' @seealso [ind_dfm()], [fcast_dfm()], [create_inventory()], [prepare_data()]
#' @family data preparation functions
#' @export
mfbdfm_data <- function(data, meta, target = NULL,
                        aggregate = c("mean", "sum")){

  aggregate <- match.arg(aggregate)

  # `meta` is checked before the data is touched, because a declared frequency
  # has to be available while the series are being built.
  meta <- check_meta(meta)

  series <- as_series_list(data, declared_freq(meta))

  if(!length(series)){
    stop("`data` contained no series.", call. = FALSE)
  }
  if(is.null(names(series)) || any(!nzchar(names(series)))){
    stop("Every series must be named.", call. = FALSE)
  }
  if(anyDuplicated(names(series))){
    dup <- unique(names(series)[duplicated(names(series))])
    stop("Duplicated series name", if(length(dup) > 1) "s" else "", ": ",
         paste(sQuote(dup), collapse = ", "), ".", call. = FALSE)
  }

  # weekly/daily series go onto the 48-week grid the models require
  conv <- harmonise_to_week48(series, aggregate)
  series <- conv$series

  meta <- resolve_meta(meta, series, conv$frequency_in)

  if(!is.null(target)){
    if(!is.character(target) || length(target) != 1){
      stop("`target` must be a single series name (character).", call. = FALSE)
    }
    if(!target %in% names(series)){
      stop("`target` (\"", target, "\") is not among the supplied series.\n",
           "  Available: ", paste(utils::head(names(series), 10), collapse = ", "),
           if(length(series) > 10) ", ..." else "", ".", call. = FALSE)
    }
  }

  is_flow <- meta$type[match(names(series), meta$series)] == "flow"

  structure(list(flows = series[is_flow],
                 stocks = series[!is_flow],
                 meta = meta,
                 target = target),
            class = "mfbdfm_data")

}


#' Coerce various shapes into a named list of `ts`
#'
#' `freq` is a named integer vector of declared frequencies (possibly empty).
#' For inputs that are already `ts`, a declared frequency is *checked* against
#' the object rather than applied to it -- silently reinterpreting a `ts` the
#' user built themselves would be exactly the kind of wrong answer this
#' constructor exists to prevent.
#'
#' @noRd
as_series_list <- function(data, freq = integer()){

  check_declared <- function(out){
    common <- intersect(names(out), names(freq))
    for(nm in common){
      actual <- stats::frequency(out[[nm]])
      if(actual != freq[[nm]]){
        stop("`meta` declares frequency ", freq[[nm]], " for series ", sQuote(nm),
             ", but the supplied `ts` has frequency ", actual, ".\n",
             "  Drop the `frequency` column or fix the series - this constructor ",
             "will not reinterpret a `ts` you built yourself.", call. = FALSE)
      }
    }
    out
  }

  if(inherits(data, "mfbdfm_data")) return(check_declared(c(data$flows, data$stocks)))

  if(stats::is.ts(data)){
    # mts: one column per series. A univariate ts is a single unnamed series,
    # which cannot be matched to meta, so it is refused.
    if(is.null(dim(data))){
      stop("A univariate `ts` carries no series name; supply a named list ",
           "or a data frame instead.", call. = FALSE)
    }
    nms <- colnames(data)
    if(is.null(nms)) stop("The `mts` has no column names to use as series names.",
                          call. = FALSE)
    out <- lapply(seq_len(ncol(data)), function(j) data[, j])
    names(out) <- nms
    return(check_declared(out))
  }

  if(is.list(data) && !is.data.frame(data)){
    bad <- names(data)[!vapply(data, stats::is.ts, logical(1))]
    if(length(bad)){
      stop("These elements of `data` are not `ts` objects: ",
           paste(sQuote(bad), collapse = ", "), ".", call. = FALSE)
    }
    return(check_declared(data))
  }

  if(is.data.frame(data)) return(df_to_series(data, freq))

  stop("`data` must be a data frame, an `mts`, a named list of `ts`, or an ",
       "`mfbdfm_data` object, not a ", class(data)[1], ".", call. = FALSE)

}


#' Convert a long or wide data frame into a named list of `ts`
#'
#' @noRd
df_to_series <- function(df, freq = integer()){

  nms <- names(df)
  time_col <- nms[tolower(nms) %in% c("date", "time", "period")][1]

  if(is.na(time_col)){
    stop("Could not find a date column in `data`; expected one named ",
         "`date`, `time` or `period`.", call. = FALSE)
  }

  # a declared frequency for this series, or NA
  fr <- function(nm) if(nm %in% names(freq)) freq[[nm]] else NA_integer_

  long <- all(c("series", "value") %in% tolower(nms))

  if(long){
    s_col <- nms[tolower(nms) == "series"][1]
    v_col <- nms[tolower(nms) == "value"][1]
    parts <- split(df[, c(time_col, v_col)], as.character(df[[s_col]]))
    out <- lapply(names(parts), function(nm){
      part <- parts[[nm]]
      part <- part[order(part[[time_col]]), , drop = FALSE]
      keep <- !is.na(part[[v_col]])
      # trim leading/trailing gaps only; interior NAs are legitimate missings
      ok <- which(keep)
      if(!length(ok)) stop("Series ", sQuote(nm), " is entirely missing.", call. = FALSE)
      part <- part[ok[1]:ok[length(ok)], , drop = FALSE]
      make_ts(part[[time_col]], part[[v_col]], fr(nm), nm)
    })
    names(out) <- names(parts)
    return(out)
  }

  # wide: every non-time column is a series
  value_cols <- setdiff(nms, time_col)
  if(!length(value_cols)){
    stop("`data` has a date column but no series columns.", call. = FALSE)
  }
  tm <- df[[time_col]]
  ord <- order(tm)
  tm <- tm[ord]
  out <- lapply(value_cols, function(cl){
    v <- df[[cl]][ord]
    ok <- which(!is.na(v))
    if(!length(ok)) stop("Series ", sQuote(cl), " is entirely missing.", call. = FALSE)
    idx <- ok[1]:ok[length(ok)]
    make_ts(tm[idx], v[idx], fr(cl), cl)
  })
  names(out) <- value_cols
  out

}


#' Build a `ts` from a date/time vector and values
#'
#' `freq`, if not NA, is taken as declared and used as-is. Otherwise the
#' frequency is inferred from the spacing; see the "Frequency" section of
#' [mfbdfm_data()] for why only a fixed set is accepted and how 48 is told
#' apart from 52.
#'
#' @noRd
make_ts <- function(tm, value, freq = NA_integer_, nm = "a series"){

  dated <- inherits(tm, "Date") || inherits(tm, "POSIXt")

  if(dated){
    tm <- as.Date(tm)
    if(length(tm) < 2L){
      stop("Series ", sQuote(nm), " has fewer than two observations, so its ",
           "frequency cannot be inferred. Declare it with a `frequency` column ",
           "in `meta`.", call. = FALSE)
    }
    if(is.na(freq)) freq <- infer_freq_dates(tm, nm)
    return(stats::ts(value, start = start_from_date(tm[1], freq), frequency = freq))
  }

  # numeric decimal time, e.g. 2020.25
  tmn <- as.numeric(tm)
  if(is.na(freq)){
    if(length(tmn) < 2L){
      stop("Series ", sQuote(nm), " has fewer than two observations, so its ",
           "frequency cannot be inferred. Declare it with a `frequency` column ",
           "in `meta`.", call. = FALSE)
    }
    step <- stats::median(diff(tmn))
    freq <- round(1/step)
    if(!freq %in% c(1L, 4L, 12L, 48L, 52L, 365L)){
      stop("Inferred an implausible frequency of ", freq, " for series ", sQuote(nm),
           " from a median time step of ", signif(step, 4),
           ". Declare it with a `frequency` column in `meta`.", call. = FALSE)
    }
  }
  stats::ts(value, start = tmn[1], frequency = freq)

}


#' Infer a modelled frequency from a `Date` vector
#'
#' @noRd
infer_freq_dates <- function(tm, nm){

  step <- stats::median(as.numeric(diff(tm)))

  if(step >= 80 && step <= 100) return(4L)
  if(step >= 26 && step <= 32)  return(12L)
  if(step == 1)                 return(365L)

  if(step >= 6 && step <= 8){
    # 48 and 52 have the same ~7-day spacing. The 48-grid puts observations on
    # the 7th/14th/21st/28th (dec2week()'s convention); a 7-day-step series
    # walks off those days within five observations, so the test is safe once
    # there are enough of them.
    dom <- as.integer(format(tm, "%d"))
    if(all(dom %in% c(7L, 14L, 21L, 28L))){
      if(length(tm) < 6L){
        stop("Series ", sQuote(nm), " has ~7-day spacing on the 7th/14th/21st/",
             "28th, which is frequency 48, but too few observations (",
             length(tm), ") to be sure it is not weekly (52). Declare it with ",
             "a `frequency` column in `meta`.", call. = FALSE)
      }
      return(48L)
    }
    return(52L)
  }

  stop("Could not infer a frequency for series ", sQuote(nm),
       " from a median date step of ", step, " days. This package models ",
       "frequencies 4, 12, 48, 52 and 365; declare it with a `frequency` ",
       "column in `meta`.", call. = FALSE)

}


#' Put any series finer than 48 onto the 48-week grid
#'
#' A frequency finer than 48 raises `max(freq)` above the grid `prepare_data()`
#' can align monthly and quarterly observations onto, which silently drops most
#' of them (see the "Weekly and daily series" section of [mfbdfm_data()] for the
#' measurement). Conversion goes through [daily2weekly()], the same function the
#' analysis scripts use, and is reported rather than done quietly.
#'
#' Returns the series plus a named integer vector of the original frequencies
#' of whatever was converted, so `print()` can show both.
#'
#' @noRd
harmonise_to_week48 <- function(series, aggregate = "mean"){

  freqs <- vapply(series, stats::frequency, numeric(1))
  todo <- names(series)[freqs > 48]

  if(!length(todo)) return(list(series = series, frequency_in = integer()))

  fun <- switch(aggregate, mean = mean, sum = sum)

  for(nm in todo){
    x <- series[[nm]]
    # 48 does not divide 52, so mapping weekly points straight onto the grid
    # gives each slot either one or two of them - a lumpy nearest-point pick,
    # not a resampling. Expanding to daily first puts both frequencies on a
    # common finer grid, after which every slot draws on 7-8 days and its value
    # is a proper overlap-weighted blend of the weeks it straddles. Daily input
    # is already on that grid and is passed through.
    z <- if(stats::frequency(x) < 365) expand_to_daily(x) else
      zoo::zoo(as.numeric(x), order.by = ts_to_dates(x))
    out <- daily2weekly(z, FUN = fun)
    if(stats::frequency(out) != 48){
      stop("Failed to put series ", sQuote(nm), " on the 48-week grid: got ",
           "frequency ", stats::frequency(out), ".", call. = FALSE)
    }
    series[[nm]] <- out
  }

  message("Aggregated to the 48-week grid the models use (by ", aggregate, "): ",
          paste0(sQuote(todo), " (", freqs[todo], " -> 48)", collapse = ", "), ".")

  list(series = series,
       frequency_in = stats::setNames(as.integer(freqs[todo]), todo))

}


#' Expand a sub-daily-frequency `ts` to a daily `zoo`
#'
#' Each observation is repeated across the calendar days its period covers. The
#' label date is taken as the **end** of the period, which is this package's own
#' convention -- [dec2week()] puts week `k` of the 48-grid on day `7k`, the last
#' day of the period, and [prepare_data()] likewise shifts low-frequency
#' observations to the end of their period.
#'
#' Repeating (rather than dividing) keeps the value interpretable as a rate, so
#' a later `mean` over a 48-slot is the overlap-weighted average of the periods
#' it straddles. A later `sum` is then proportional to the period total, the
#' constant of proportionality being the number of days per period -- which
#' [prepare_data()]'s standardization removes.
#'
#' @noRd
expand_to_daily <- function(x){

  ends <- ts_to_dates(x)
  span <- max(1L, round(365 / stats::frequency(x)))     # days per period

  days <- rep(ends, each = span) - rep(seq.int(span - 1L, 0L), times = length(ends))
  value <- rep(as.numeric(x), each = span)

  ord <- order(days)
  days <- days[ord]
  value <- value[ord]

  # contiguous periods should not overlap, but guard rather than let zoo build a
  # duplicated index
  keep <- !duplicated(days)
  zoo::zoo(value[keep], order.by = days[keep])

}


#' Calendar dates for the observations of a `ts`
#'
#' Needed because [daily2weekly()] aggregates on a `Date` index, while a `ts`
#' carries only decimal time. Inverts the mapping [make_ts()] uses, so a series
#' that came in as dates round-trips.
#'
#' @noRd
ts_to_dates <- function(x){
  tm <- as.numeric(stats::time(x))
  yr <- floor(tm + 1e-8)
  frac <- tm - yr
  as.Date(paste0(yr, "-01-01")) + round(frac * 365)
}


#' Convert a first date into a `ts` start value
#'
#' @noRd
start_from_date <- function(d, freq){
  y <- as.integer(format(d, "%Y"))
  mo <- as.integer(format(d, "%m"))
  doy <- as.integer(format(d, "%j"))
  dom <- as.integer(format(d, "%d"))
  switch(as.character(freq),
         "4"   = c(y, (mo - 1L) %/% 3L + 1L),
         "12"  = c(y, mo),
         # inverse of dec2week(): weeks on the 7th/14th/21st/28th
         "48"  = c(y, (mo - 1L) * 4L + min(4L, max(1L, dom %/% 7L))),
         "52"  = c(y, (doy - 1L) %/% 7L + 1L),
         "365" = c(y, doy),
         c(y, 1L))
}


#' Check the shape of `meta` (before the data is looked at)
#'
#' @noRd
check_meta <- function(meta){

  if(missing(meta) || is.null(meta)){
    stop("`meta` is required: a data frame with columns `series` and `type` ",
         "(\"flow\" or \"stock\"). See ?mfbdfm_data.", call. = FALSE)
  }
  if(!is.data.frame(meta)){
    stop("`meta` must be a data frame, not a ", class(meta)[1], ".", call. = FALSE)
  }
  if(!all(c("series", "type") %in% names(meta))){
    stop("`meta` must have columns `series` and `type`; it has: ",
         paste(names(meta), collapse = ", "), ".", call. = FALSE)
  }

  meta$series <- as.character(meta$series)
  meta$type <- as.character(meta$type)

  if(anyDuplicated(meta$series)){
    dup <- unique(meta$series[duplicated(meta$series)])
    stop("`meta` has more than one row for: ",
         paste(sQuote(dup), collapse = ", "), ".", call. = FALSE)
  }

  bad <- setdiff(stats::na.omit(unique(meta$type)), c("flow", "stock"))
  if(length(bad)){
    stop("`type` must be \"flow\" or \"stock\"; found ",
         paste(sQuote(bad), collapse = ", "), ".", call. = FALSE)
  }

  if("frequency" %in% names(meta)){
    fq <- suppressWarnings(as.integer(meta$frequency))
    if(any(is.na(fq) & !is.na(meta$frequency))){
      stop("`meta$frequency` must be whole numbers.", call. = FALSE)
    }
    bad <- setdiff(stats::na.omit(unique(fq)), c(1L, 4L, 12L, 48L, 52L, 365L))
    if(length(bad)){
      stop("`meta$frequency` must be one of 1, 4, 12, 48, 52, 365; found ",
           paste(bad, collapse = ", "), ".", call. = FALSE)
    }
    meta$frequency <- fq
  }

  meta

}


#' Declared frequencies as a named integer vector
#'
#' @noRd
declared_freq <- function(meta){
  if(!"frequency" %in% names(meta)) return(integer())
  keep <- !is.na(meta$frequency)
  stats::setNames(meta$frequency[keep], meta$series[keep])
}


#' Build the per-series table, requiring `type` only where it can change the answer
#'
#' The frequency reported here is read off the series themselves, which are
#' authoritative by this point: a declared frequency was either applied while
#' building them or checked against them.
#'
#' @noRd
resolve_meta <- function(meta, series, frequency_in = integer()){

  extra <- setdiff(meta$series, names(series))
  if(length(extra)){
    warning("`meta` describes series not present in `data`: ",
            paste(sQuote(utils::head(extra, 5)), collapse = ", "),
            if(length(extra) > 5) ", ..." else "", ". Ignored.", call. = FALSE)
    meta <- meta[meta$series %in% names(series), , drop = FALSE]
  }

  freqs <- vapply(series, stats::frequency, numeric(1))

  out <- data.frame(series = names(series),
                    type = meta$type[match(names(series), meta$series)],
                    frequency = as.integer(freqs),
                    n_obs = vapply(series, length, integer(1)),
                    stringsAsFactors = FALSE, row.names = NULL)

  # `type` only changes the aggregation weights below the highest frequency; at
  # the highest frequency flow and stock are provably identical, so a missing
  # value there is filled rather than refused - requiring a decision that
  # cannot affect the result would be noise.
  missing_type <- is.na(out$type)
  need <- missing_type & out$frequency < max(out$frequency)

  if(any(need)){
    stop("`type` is missing for ", sum(need), " series below the highest ",
         "frequency, where \"flow\" and \"stock\" give different temporal ",
         "aggregation weights:\n  ",
         paste(sQuote(out$series[need]), collapse = ", "), "\n",
         "  Add them to `meta`. See ?mfbdfm_data for what the two mean.",
         call. = FALSE)
  }
  out$type[missing_type] <- "flow"

  # only present when something was actually converted, so the common case
  # keeps a clean table
  if(length(frequency_in)){
    out$frequency_in <- unname(frequency_in[out$series])
  }

  carry <- setdiff(names(meta), c("series", "type", "frequency", "frequency_in"))
  for(cl in carry) out[[cl]] <- meta[[cl]][match(out$series, meta$series)]

  out

}


#' Print an mfbdfm_data object
#'
#' Shows the resolved classification and the frequencies actually used, so a
#' mistake in either is visible before it is used for a long run.
#'
#' @param x An object from [mfbdfm_data()].
#' @param ... Ignored, present for compatibility with the generic.
#'
#' @return `x`, invisibly.
#'
#' @examples
#' long <- data.frame(
#'   series = rep(c("a_flow", "b_stock"), each = 24),
#'   date = rep(seq(as.Date("2020-01-01"), by = "month", length.out = 24), 2),
#'   value = rnorm(48))
#' mfbdfm_data(long, data.frame(series = c("a_flow", "b_stock"),
#'                              type = c("flow", "stock")))
#'
#' @method print mfbdfm_data
#' @export
print.mfbdfm_data <- function(x, ...){

  m <- x$meta
  cat("<mfbdfm_data>  ", nrow(m), " series",
      "  (", sum(m$type == "flow"), " flow, ", sum(m$type == "stock"), " stock)\n",
      sep = "")
  if(!is.null(x$target)) cat("target: ", x$target, "\n", sep = "")

  mx <- max(m$frequency)
  cat("\n  by frequency:\n")
  for(f in sort(unique(m$frequency))){
    sel <- m$frequency == f
    cat(sprintf("    %5d  %2d flow  %2d stock%s\n", f,
                sum(sel & m$type == "flow"), sum(sel & m$type == "stock"),
                if(f == mx) "   <- highest; flow/stock has no effect here" else ""))
  }

  conv <- if("frequency_in" %in% names(m)) !is.na(m$frequency_in) else rep(FALSE, nrow(m))
  if(any(conv)){
    cat("\n  aggregated onto the 48-week grid the models use:\n")
    for(i in which(conv)){
      cat(sprintf("    %-28s %d -> 48\n", substr(m$series[i], 1, 28),
                  m$frequency_in[i]))
    }
  }

  cat("\n  series (first 10):\n")
  show <- utils::head(m, 10)
  for(i in seq_len(nrow(show))){
    cat(sprintf("    %-28s %-6s freq %4d  n %5d%s\n",
                substr(show$series[i], 1, 28), show$type[i],
                show$frequency[i], show$n_obs[i],
                if(conv[i]) sprintf("  (from %d)", show$frequency_in[i]) else ""))
  }
  if(nrow(m) > 10) cat("    ... and ", nrow(m) - 10, " more\n", sep = "")

  cat("\nPass to ind_dfm() or fcast_dfm() as the first argument.\n")

  invisible(x)

}
