#' Export WAI results as a web-ready CSV and metadata file
#'
#' Turns a fitted WAI model into the two files the public dashboard consumes:
#' a wide, one-row-per-week CSV of the published series, and a small JSON
#' sidecar describing the run. Together they are the entire interface between
#' this package and the web front end — the page performs no computation of its
#' own, it selects columns.
#'
#' @details
#' The CSV has one row per weekly period and these columns, in this order:
#'
#' \describe{
#'   \item{`date`}{ISO date on the 7th/14th/21st/28th convention of [dec2week()].}
#'   \item{`wai_qoq`, `wai_qoq_lo`, `wai_qoq_hi`}{Annualised quarter-on-quarter
#'     growth and its 95% band, from the factor and `factor_var`.}
#'   \item{`wai_yoy`}{Year-over-year growth of the level index.}
#'   \item{`wai_index`}{Level index, rebased to the mean of 2019Q4 = 100.}
#'   \item{`wai_qoq_q`, `wai_yoy_q`}{The WAI aggregated to quarterly frequency
#'     the way GDP is actually measured, placed on the last weekly period of
#'     each quarter and empty elsewhere. See below.}
#'   \item{`gdp_qoq`, `gdp_yoy`, `gdp_index`}{Published GDP on the same three
#'     measures, placed on the last weekly period of each quarter and empty
#'     elsewhere. Omitted when `gdp` is `NULL`; which of the three appear
#'     depends on which columns `gdp` carries.}
#' }
#'
#' **`wai_qoq_q` is the series to compare with `gdp_qoq`; `wai_qoq` is not.**
#' Quarterly GDP is a *flow* — the quarter's average activity — so the
#' like-for-like aggregate is the quarterly **mean of the level index**, and
#' growth taken between those means. `wai_qoq` is the weekly factor, an
#' instantaneous annualised growth rate, and reading it against `gdp_qoq`
#' point-for-point compares different objects. The gap is not small: on a
#' V-shaped path it is the difference between quarter-endpoints (near zero
#' across 2020Q2, because the level fell and recovered inside the quarter) and
#' quarter-averages (about -23% annualised, which is what GDP reported).
#' Aggregated correctly, the WAI matches published GDP at a correlation of
#' 1.000 and an RMSE of 0.04pp.
#'
#' **`wai_index` and `wai_yoy` are published without bands, deliberately.** The
#' only genuine 95% credible interval the fit provides is the one on the growth
#' rate. The level bounds that [extract_wai_data()] returns in `tab_gr_lv_full`
#' are the index scaled by a *single* period of growth at each bound, not a
#' compounded level interval, so publishing them next to `wai_index` would
#' present something that looks like a level confidence band and is not one.
#'
#' Missing values are written as the empty string rather than `NA` or `NaN`, so
#' that the front end's parser does not have to know R's spelling of missing.
#' Numbers use `.` as the decimal separator and no thousands separator, rows are
#' sorted ascending by date, and lines end with `\n` on every platform.
#'
#' @param fit_path Path to a fit `.Rda` file containing an object `mod`, as
#'   written by [run_wai_adj()].
#' @param dir Directory to write `wai_data.csv` and `wai_meta.json` into, or
#'   `NULL` (default) to write nothing and only return the data. Created if it
#'   does not exist.
#' @param gdp Optional data frame of published GDP, with a `time` column plus
#'   either
#'   * `qoq`, `yoy` and/or `index` — as [gdp_web_series()] returns, already on
#'     the published scale. This is the intended route.
#'   * `value` — the older single-series shape, written out as `gdp_qoq`.
#'
#'   `time` may be a `Date` (as [get_real_time_gdp_vintages()] returns) or
#'   decimal time in either the [decimal_date_local()] convention or exact
#'   quarter fractions.
#'
#'   Mind the units if you build this frame yourself:
#'   [get_real_time_gdp_vintages()] returns `"quarterly"` as a log difference
#'   and `"annual"` as a fraction, whereas `wai_qoq` is an annualised
#'   percentage — unconverted, the two differ on one axis by a factor of roughly
#'   400. [gdp_web_series()] exists to spare you that conversion.
#' @param digits Number of decimal places to round the published series to.
#'   Defaults to 4, which is well past the precision the model supports and
#'   keeps the file small.
#' @param vintage_date Optional evaluation/vintage date recorded in the
#'   metadata. Defaults to the last observation date.
#'
#' @return Invisibly, a list with elements `data` (the wide data frame) and
#'   `meta` (the metadata list). Writes files only when `dir` is given.
#'
#' @seealso [extract_wai_data()], which produces the underlying tables.
#'
#' @importFrom stats time
#' @importFrom utils packageVersion write.table
#' @keywords internal
export_wai_web <- function(fit_path, dir = NULL, gdp = NULL, digits = 4,
                           vintage_date = NULL) {

  if (!is.character(fit_path) || length(fit_path) != 1L) {
    stop("`fit_path` must be a single file path.", call. = FALSE)
  }
  if (!file.exists(fit_path)) {
    stop("`fit_path` does not exist: ", fit_path, call. = FALSE)
  }
  # G4.0: the file is read with load(), so its name has to name something load()
  # can read. Checked here rather than left to load(), whose own complaint on a
  # CSV or an .rds is a "bad restore file magic number" that names neither the
  # argument nor what was expected. Nothing is appended, unlike the output-side
  # helpers in analytics-config.R: the path has to exist, and completing a name
  # that does not exist would only move the error.
  fit_ext <- tools::file_ext(fit_path)
  if (!tolower(fit_ext) %in% c("rda", "rdata")) {
    stop("`fit_path` must be an `.Rda`/`.RData` file saved by run_wai_adj(), ",
         "not ", if (nzchar(fit_ext)) paste0("a ", sQuote(paste0(".", fit_ext)),
                                             " file") else "an extensionless file",
         ": ", fit_path, call. = FALSE)
  }
  if (!is_count(digits) || digits < 0) {
    stop("`digits` must be a single non-negative whole number, not ",
         deparse(digits), ".", call. = FALSE)
  }

  tabs <- extract_wai_data(fit_path)

  qoq <- tabs$tab_gr_full
  lv <- tabs$tab_gr_lv_full
  yoy <- tabs$tab_wai_yoy

  dat <- data.frame(
    date       = as.Date(qoq$time),
    wai_qoq    = round(as.numeric(qoq$value), digits),
    wai_qoq_lo = round(as.numeric(qoq$min), digits),
    wai_qoq_hi = round(as.numeric(qoq$max), digits),
    stringsAsFactors = FALSE
  )

  dat$wai_yoy <- round(match_on_date(yoy$time, yoy$value, dat$date), digits)
  dat$wai_index <- round(match_on_date(lv$time, lv$value, dat$date), digits)

  quarterly <- wai_quarterly_flow(dat$date, dat$wai_index)
  dat$wai_qoq_q <- round(quarterly$qoq, digits)
  dat$wai_yoy_q <- round(quarterly$yoy, digits)

  if (!is.null(gdp)) {
    if (!"time" %in% names(gdp)) {
      stop("`gdp` must have a `time` column.", call. = FALSE)
    }
    measures <- intersect(c("qoq", "yoy", "index"), names(gdp))
    if (length(measures)) {
      for (m in measures) {
        dat[[paste0("gdp_", m)]] <-
          round(gdp_on_weekly_grid(data.frame(time = gdp$time, value = gdp[[m]]),
                                   dat$date), digits)
      }
    } else {
      # the older single-series shape
      dat$gdp_qoq <- round(gdp_on_weekly_grid(gdp, dat$date), digits)
    }
  }

  dat <- dat[order(dat$date), , drop = FALSE]
  rownames(dat) <- NULL

  last_obs <- max(dat$date)
  meta <- list(
    vintage_date   = as.character(if (is.null(vintage_date)) last_obs else vintage_date),
    run_timestamp  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    last_obs_date  = as.character(last_obs),
    first_obs_date = as.character(min(dat$date)),
    n_obs          = nrow(dat),
    latest_wai_qoq = unname(dat$wai_qoq[nrow(dat)]),
    latest_wai_yoy = unname(dat$wai_yoy[nrow(dat)]),
    latest_index   = unname(dat$wai_index[nrow(dat)]),
    mfbdfm_version = as.character(utils::packageVersion("mfbdfm")),
    columns        = names(dat)
  )

  if (!is.null(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    write_web_csv(dat, file.path(dir, "wai_data.csv"))
    writeLines(to_json(meta), file.path(dir, "wai_meta.json"), useBytes = TRUE)
  }

  invisible(list(data = dat, meta = meta))
}


#' Aggregate the weekly level index to quarterly growth the way GDP is measured
#'
#' GDP is a FLOW: the quarter's average activity, not its closing level. So the
#' quarterly aggregate is the MEAN of the weekly index over the quarter, and
#' growth is taken between consecutive means - never between quarter endpoints,
#' which on a V-shaped path answers a different question entirely (2020Q2:
#' endpoints say roughly zero, averages say -23% annualised, and GDP reported
#' -23.1%).
#'
#' The result is placed on the last weekly period of each quarter so it sits
#' alongside the published GDP points rather than needing its own index.
#'
#' @param dates `Date` vector of the weekly grid.
#' @param index Numeric vector of the weekly level index, same length as
#'   `dates`; `NA` entries are ignored when forming quarterly means.
#'
#' @return A list of two numeric vectors, `qoq` (annualised quarter-on-quarter
#'   growth, in percent) and `yoy` (year-on-year growth, in percent), each the
#'   length of `dates` and `NA` everywhere except the last week of a quarter.
#'
#' @noRd
wai_quarterly_flow <- function(dates, index) {
  key <- as.numeric(format(dates, "%Y")) * 4 +
    (as.numeric(format(dates, "%m")) - 1L) %/% 3L

  ok <- !is.na(index)
  means <- tapply(index[ok], key[ok], mean)
  keys <- as.numeric(names(means))
  ord <- order(keys)
  keys <- keys[ord]
  means <- as.numeric(means)[ord]

  # growth between consecutive quarters, and against four quarters back - but
  # only where the quarters really are adjacent, so a gap in the data cannot be
  # silently differenced across
  grow <- function(k) {
    prev <- match(keys - k, keys)
    ifelse(is.na(prev), NA_real_, means / means[prev])
  }
  qoq <- (grow(1)^4 - 1) * 100
  yoy <- (grow(4) - 1) * 100

  place <- function(v) {
    out <- rep(NA_real_, length(dates))
    for (i in seq_along(keys)) {
      wk <- which(key == keys[i] & !is.na(index))
      if (length(wk)) out[wk[which.max(dates[wk])]] <- v[i]
    }
    out
  }
  list(qoq = place(qoq), yoy = place(yoy))
}


#' Align a (time, value) pair onto a target vector of dates
#'
#' Returns `NA` where the target date has no match. `time` columns coming out of
#' [extract_wai_data()] are Dates already; `as.Date()` keeps this honest if that
#' ever changes.
#'
#' @param times Vector of dates (or date-coercible values) belonging to `values`.
#' @param values Vector of values to align, same length as `times`.
#' @param target `Date` vector to align onto.
#'
#' @return A numeric vector the length of `target`.
#'
#' @noRd
match_on_date <- function(times, values, target) {
  as.numeric(values)[match(target, as.Date(times))]
}


#' Place quarterly GDP growth on the weekly grid
#'
#' Each quarter's value lands on the last weekly period that falls inside it,
#' and every other week is `NA`. That is what lets the front end draw GDP as
#' points against a weekly line without carrying a second, differently-indexed
#' file.
#'
#' @param gdp Data frame with a `time` column and a `value` column, as
#'   [gdp_web_series()] returns.
#' @param target `Date` vector of the weekly grid to place the values on.
#'
#' @return A numeric vector the length of `target`, `NA` except on the last week
#'   of each quarter for which `gdp` carries an observation.
#'
#' @noRd
gdp_on_weekly_grid <- function(gdp, target) {
  if (!all(c("time", "value") %in% names(gdp))) {
    stop("`gdp` must have columns `time` and `value`, or `time` plus any of ",
         "`qoq`, `yoy`, `index` as gdp_web_series() returns.", call. = FALSE)
  }
  out <- rep(NA_real_, length(target))
  target_q <- quarter_key(as.numeric(format(target, "%Y")),
                          (as.numeric(format(target, "%m")) - 1L) %/% 3L + 1L)
  gdp_q <- quarter_of(gdp$time)

  for (i in seq_along(gdp_q)) {
    weeks <- which(target_q == gdp_q[i])
    if (length(weeks)) out[max(weeks)] <- as.numeric(gdp$value)[i]
  }
  out
}


#' Map a time vector onto quarter keys
#'
#' `gdp$time` arrives as a `Date` from [get_real_time_gdp_vintages()], but
#' decimal time is the package's other currency, so accept both.
#'
#' The decimal branch ROUNDS rather than floors, deliberately. The package's own
#' [decimal_date_local()] puts quarter starts at .000/.247/.496/.748
#' (day-of-year over 365), not at exact quarter fractions: flooring
#' `(t %% 1) * 4` sends 1990.247 to quarter 1 instead of 2, collapsing two
#' quarters onto one key so that one silently overwrites the other. Rounding
#' lands both conventions - .247-style and exact .25-style - on the right
#' quarter.
#'
#' @param time `Date` vector, or numeric decimal time.
#'
#' @return An integer-valued numeric vector of quarter keys, as built by
#'   `quarter_key()`.
#'
#' @noRd
quarter_of <- function(time) {
  if (inherits(time, "Date")) {
    return(quarter_key(as.numeric(format(time, "%Y")),
                       (as.numeric(format(time, "%m")) - 1L) %/% 3L + 1L))
  }
  t <- as.numeric(time)
  quarter_key(floor(t), round((t %% 1) * 4) + 1L)
}


#' A single comparable key per calendar quarter
#'
#' @param year Numeric vector of calendar years.
#' @param quarter Numeric vector of quarters within the year (1-4).
#'
#' @return A numeric vector of keys, ordered as the quarters are.
#'
#' @noRd
quarter_key <- function(year, quarter) year * 4L + as.integer(quarter)


#' Write the front end's CSV
#'
#' `write.csv()` would quote the header and spell missing values `"NA"`; the
#' front end wants a bare header and empty fields. `eol` is forced to `"\n"` so
#' a run on Windows does not produce a diff against a run on Linux.
#'
#' @param dat Data frame to write.
#' @param path Character, the file to write to.
#'
#' @return `NULL`, invisibly; called for the file it writes.
#'
#' @noRd
write_web_csv <- function(dat, path) {
  utils::write.table(dat, path, sep = ",", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, na = "", eol = "\n", fileEncoding = "UTF-8")
}


#' A dependency-free JSON writer
#'
#' Handles the flat, scalar-or-character-vector metadata list above and nothing
#' more. jsonlite would do this better, but it is not among the package's
#' Imports and one small writer is a poor reason to add a dependency.
#'
#' @param x A named list of atomic vectors (character, logical or numeric).
#'
#' @return A single character string holding the JSON object.
#'
#' @noRd
to_json <- function(x) {
  render <- function(v) {
    if (is.null(v) || (length(v) == 1L && is.na(v))) return("null")
    if (is.character(v)) {
      quoted <- paste0("\"", gsub("([\\\\\"])", "\\\\\\1", v), "\"")
    } else if (is.logical(v)) {
      quoted <- ifelse(v, "true", "false")
    } else {
      quoted <- ifelse(is.na(v), "null", format(v, scientific = FALSE, trim = TRUE))
    }
    if (length(v) == 1L) quoted else paste0("[", paste(quoted, collapse = ", "), "]")
  }
  paste0("{\n",
         paste0("  \"", names(x), "\": ", vapply(x, render, character(1)),
                collapse = ",\n"),
         "\n}")
}


#' Published GDP on the same scale as the exported WAI series
#'
#' Builds official GDP as quarter-on-quarter annualised growth, year-over-year
#' growth and a rebased level index, all on the units [export_wai_web()]
#' publishes, so the three can be plotted against their WAI counterparts on one
#' axis.
#'
#' @details
#' [get_real_time_gdp_vintages()] returns `"quarterly"` as a log difference and
#' `"annual"` as a fraction, neither of which is the annualised percentage the
#' WAI series use. Rather than convert at each call site — which is how an
#' unconverted log difference nearly reached the published dashboard, wrong by a
#' factor of roughly 400 — the conversion lives here, in one tested place.
#'
#' All three series are derived from the *same* vintage levels, so they are
#' mutually consistent by construction:
#'
#' \describe{
#'   \item{`qoq`}{`((level_t / level_{t-1})^4 - 1) * 100`}
#'   \item{`yoy`}{`(level_t / level_{t-4} - 1) * 100`}
#'   \item{`index`}{`100 * level_t / level_base`}
#' }
#'
#' @param vintage Which publication vintage to use: `"latest"` (default) for the
#'   most recent column, or the name of a vintage column.
#' @param base_date `Date` (or string) naming the quarter the level index is
#'   rebased to. Defaults to 2019-10-01, matching `wai_index`, whose base is the
#'   last quarter of 2019.
#' @param start_date,end_date Optional `Date` bounds on the quarters returned.
#'   The growth rates are always computed on the full available history and the
#'   window applied afterwards, so the first returned quarter carries a real
#'   `qoq` and `yoy` rather than the `NA` a post-trim lag would leave.
#' @param ... Passed to [get_real_time_gdp_vintages()], e.g. the two file-path
#'   arguments.
#'
#' @return A data frame with columns `time` (Date, quarter start), `qoq`, `yoy`
#'   and `index`. Ready to hand to [export_wai_web()]'s `gdp` argument.
#'
#' @seealso [get_real_time_gdp_vintages()] for the untransformed vintages.
#'
#' @keywords internal
gdp_web_series <- function(vintage = "latest", base_date = as.Date("2019-10-01"),
                           start_date = as.Date("1990-01-01"), end_date = NULL,
                           ...) {

  # Pull the FULL history, not the requested window. get_real_time_gdp_vintages()
  # differences before it trims, so its 1990Q1 growth is computed against 1989Q4;
  # trimming first and differencing after would silently drop the first quarter
  # of `qoq` and the first year of `yoy`. The window is applied at the end.
  lev <- get_real_time_gdp_vintages("level", start_date = NULL, end_date = NULL,
                                    ...)

  if (identical(vintage, "latest")) {
    col <- ncol(lev)
  } else {
    col <- match(as.character(vintage), names(lev))
    if (is.na(col)) {
      stop("`vintage` is not a column of the vintage table: ", vintage,
           ". Use \"latest\", or one of ", paste(utils::head(names(lev)[-1], 3),
                                                 collapse = ", "), ", ...",
           call. = FALSE)
    }
  }

  v <- as.numeric(lev[[col]])
  time <- as.Date(lev$time)

  # A vintage column is NA before the series starts and after it ends. Trim to
  # the observed span so the lags below are taken against real quarters.
  obs <- which(!is.na(v))
  if (!length(obs)) stop("vintage column `", names(lev)[col], "` is empty.",
                         call. = FALSE)
  keep <- seq(min(obs), max(obs))
  v <- v[keep]
  time <- time[keep]

  lag_ratio <- function(x, k) c(rep(NA_real_, k), x[-seq_len(k)] / utils::head(x, -k))

  base_date <- as.Date(base_date)
  base_idx <- match(base_date, time)
  if (is.na(base_idx)) {
    warning("GDP vintage does not cover the base quarter ", base_date,
            "; rebasing the level index to its first observation instead. ",
            "Level values are not comparable with `wai_index`.", call. = FALSE)
    base_idx <- 1L
  }

  out <- data.frame(
    time  = time,
    qoq   = (lag_ratio(v, 1)^4 - 1) * 100,
    yoy   = (lag_ratio(v, 4) - 1) * 100,
    index = 100 * v / v[base_idx],
    stringsAsFactors = FALSE
  )

  keep <- rep(TRUE, nrow(out))
  if (!is.null(start_date)) keep <- keep & out$time >= as.Date(start_date)
  if (!is.null(end_date))   keep <- keep & out$time <= as.Date(end_date)
  out <- out[keep, , drop = FALSE]
  rownames(out) <- NULL
  out
}


#' Write the WAI measures behind the public dashboard
#'
#' Companion to [export_wai_web()]: from the same weekly fit, write the three
#' measures the dashboard explains the indicator with, each on the scale the
#' dashboard publishes, so that its charts add up to the numbers it shows.
#' Written by `analysis/update_wai_web.R`; not package API.
#'
#' @details
#' **Contributions (`wai_contributions.csv`).** [mfbdfm_contributions()] splits
#' the factor exactly, but on the sampler's standardised, non-annualised scale.
#' The published `wai_qoq` is `F(z) = ((1 + sd*z + mean/k)^48 - 1) * 100` of
#' that, which is not linear, so contributions to it do not exist as such. The
#' file therefore uses an exact additive split on the published scale:
#' `trend = F(0)` (the growth the model implies with every contribution at
#' zero), each group's share of `F(T) - F(0)` in proportion to its
#' standardised contribution (`T` the plug-in total), and
#' `parameter_uncertainty = wai_qoq - F(T)`, the posterior-minus-plug-in
#' residual [mfbdfm_contributions()] itself reports. Per date the components
#' sum to `wai_qoq` exactly.
#'
#' **News (`wai_news.csv`).** [mfbdfm_news()] of the move from `news_fit_path`
#' (last week's fit) to `news_new_data` (this week's data), aggregated to the
#' groups and mapped onto annualised quarterly growth the same way: shares of
#' `G(new) - G(old)`, `G(x) = ((1 + x)^4 - 1) * 100`, which sum exactly to the
#' revision. Written only when both arguments are given.
#'
#' **Series (`wai_series.csv`).** One row per input series: name and group,
#' frequency, the R-squared from `summary()` and the posterior loading with its
#' 95% band (standardised scale, so loadings are comparable across series).
#'
#' @param fit_path Path to this week's fit `.Rda` (object `mod`), as for
#'   [export_wai_web()].
#' @param dir Directory to write into, or `NULL` to only return the tables.
#' @param series_info Optional data frame with columns `key`, `name` and
#'   `group`; series it lacks keep their key as name and go into `"Other"`.
#' @param news_fit_path Optional path to LAST week's fit, the old vintage of the
#'   news decomposition.
#' @param news_new_data Optional list with `flows` and `stocks`: this week's
#'   data, prepared exactly as this week's fit's was.
#' @param digits Decimal places of the published values.
#' @param vintage_date Optional vintage date recorded in the metadata.
#'
#' @return Invisibly, a list with `contributions`, `series`, `news` (or `NULL`)
#'   and `meta`.
#' @seealso [export_wai_web()], [mfbdfm_contributions()], [mfbdfm_news()].
#' @keywords internal
export_wai_measures <- function(fit_path, dir = NULL, series_info = NULL,
                                news_fit_path = NULL, news_new_data = NULL,
                                digits = 4, vintage_date = NULL) {

  load_fit <- function(p, arg) {
    if (!is.character(p) || length(p) != 1L || !file.exists(p)) {
      stop("`", arg, "` must be the path of an existing fit file.", call. = FALSE)
    }
    e <- new.env()
    load(p, envir = e)
    if (!exists("mod", envir = e, inherits = FALSE) || !inherits(e$mod, "ind_dfm")) {
      stop("`", arg, "` must hold an `ind_dfm` fit saved as `mod` by ",
           "run_wai_adj(): ", p, call. = FALSE)
    }
    e$mod
  }
  fit <- load_fit(fit_path, "fit_path")
  if (xor(is.null(news_fit_path), is.null(news_new_data))) {
    stop("`news_fit_path` and `news_new_data` go together: give both or neither.",
         call. = FALSE)
  }
  if (!is_count(digits)) {
    stop("`digits` must be a single non-negative whole number.", call. = FALSE)
  }

  inv <- fit$inventory
  keys <- inv$key
  name_of <- stats::setNames(keys, keys)
  group_of <- stats::setNames(rep("Other", length(keys)), keys)
  if (!is.null(series_info)) {
    if (!all(c("key", "name", "group") %in% names(series_info))) {
      stop("`series_info` must have columns `key`, `name` and `group`.",
           call. = FALSE)
    }
    m <- match(keys, series_info$key)
    name_of[!is.na(m)] <- series_info$name[m[!is.na(m)]]
    group_of[!is.na(m)] <- series_info$group[m[!is.na(m)]]
  }
  # The dashboard's CSVs are unquoted by contract (write_web_csv(), and the
  # front end splits on commas), so a comma inside a name or a group - which
  # also becomes a contribution component - would shift every later column of
  # its row: data_meta.csv has names such as "Total Flight Arrivals, Zurich
  # Airport".
  no_comma <- function(x) gsub("\\s*,\\s*", " - ", x)
  name_of[] <- no_comma(name_of)
  group_of[] <- no_comma(group_of)

  # contributions, on the published scale
  tgt <- inv[inv$key == fit$target, ]
  fq <- max(inv$freq)
  k <- fq / min(inv$freq)
  F_pub <- function(z) ((1 + tgt$sd * z + tgt$mean / k)^fq - 1) * 100
  F_slope0 <- 100 * fq * tgt$sd * (1 + tgt$mean / k)^(fq - 1)

  cg <- mfbdfm_contributions(fit, by = "group", groups = group_of)
  cc <- cg$contributions
  tot <- cg$totals
  wai_t <- round(as.numeric(stats::time(fit$factor)), 5)
  tot <- tot[round(tot$time, 5) %in% wai_t, ]      # drop the s pre-sample periods
  wai <- as.numeric(fit$factor)[match(round(tot$time, 5), wai_t)]

  slope <- ifelse(abs(tot$plugin) > 1e-12,
                  (F_pub(tot$plugin) - F_pub(0)) / tot$plugin, F_slope0)
  idx <- match(round(cc$time, 5), round(tot$time, 5))
  cc <- cc[!is.na(idx), ]
  idx <- idx[!is.na(idx)]
  dates <- dec2week(tot$time)

  contrib <- rbind(
    data.frame(date = dates, component = "trend", value = F_pub(0),
               stringsAsFactors = FALSE),
    data.frame(date = dates[idx], component = cc$group,
               value = cc$contribution * slope[idx], stringsAsFactors = FALSE),
    data.frame(date = dates, component = "parameter_uncertainty",
               value = wai - F_pub(tot$plugin), stringsAsFactors = FALSE)
  )
  contrib <- contrib[order(contrib$date, contrib$component), ]
  rownames(contrib) <- NULL

  # series: R-squared and loadings
  r2 <- summary(fit)$r_squared
  ld <- mfbdfm_table_loadings(fit)
  series <- data.frame(
    series     = keys,
    name       = unname(name_of[keys]),
    group      = unname(group_of[keys]),
    frequency  = inv$freq,
    r2         = r2$r_squared[match(keys, r2$series)],
    loading    = ld$mean[match(keys, ld$series)],
    loading_lo = ld$lower[match(keys, ld$series)],
    loading_hi = ld$upper[match(keys, ld$series)],
    stringsAsFactors = FALSE
  )
  series <- series[order(series$group, -series$r2), ]
  rownames(series) <- NULL

  # news: last week's fit against this week's data
  news <- NULL
  news_meta <- list(news_available = FALSE)
  if (!is.null(news_fit_path)) {
    old_fit <- load_fit(news_fit_path, "news_fit_path")
    nw <- mfbdfm_news(old_fit, new_data = news_new_data$flows,
                      stocks = news_new_data$stocks, by = "group",
                      groups = group_of[old_fit$inventory$key])
    G <- function(x) ((1 + x)^4 - 1) * 100
    o <- nw$totals$nowcast_old
    n <- nw$totals$nowcast_new
    s <- if (abs(n - o) > 1e-12) (G(n) - G(o)) / (n - o) else 400 * (1 + o)^3
    bc <- nw$by_component
    news <- data.frame(component = bc$group, impact = bc$impact * s,
                       stringsAsFactors = FALSE)
    news <- news[order(-abs(news$impact)), ]
    rownames(news) <- NULL
    old_end <- utils::tail(as.numeric(stats::time(old_fit$factor)), 1)
    news_meta <- list(
      news_available   = TRUE,
      news_period      = format(dec2week(nw$period)),
      news_nowcast_old = round(G(o), digits),
      news_nowcast_new = round(G(n), digits),
      news_old_vintage = format(dec2week(old_end)),
      news_new_obs     = nw$n_added
    )
  }

  rnd <- function(d) {
    for (v in names(d)) if (is.double(d[[v]])) d[[v]] <- round(d[[v]], digits)
    d
  }
  contrib <- rnd(contrib)
  series <- rnd(series)
  if (!is.null(news)) news <- rnd(news)

  meta <- c(list(
    vintage_date       = as.character(if (is.null(vintage_date))
                           max(contrib$date) else vintage_date),
    run_timestamp      = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    mfbdfm_version     = as.character(utils::packageVersion("mfbdfm")),
    contributions_unit = "percentage points of wai_qoq (annualised quarter-on-quarter growth, %)",
    news_unit          = "percentage points of the annualised quarterly GDP nowcast",
    loading_scale      = "standardised series",
    components         = sort(unique(contrib$component))
  ), news_meta)

  if (!is.null(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    write_web_csv(contrib, file.path(dir, "wai_contributions.csv"))
    write_web_csv(series, file.path(dir, "wai_series.csv"))
    if (!is.null(news)) write_web_csv(news, file.path(dir, "wai_news.csv"))
    writeLines(to_json(meta), file.path(dir, "wai_measures_meta.json"),
               useBytes = TRUE)
  }

  invisible(list(contributions = contrib, series = series, news = news,
                 meta = meta))
}
