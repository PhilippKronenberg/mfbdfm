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
#'   \item{`gdp_qoq`, `gdp_yoy`, `gdp_index`}{Published GDP on the same three
#'     measures, placed on the last weekly period of each quarter and empty
#'     elsewhere. Omitted when `gdp` is `NULL`; which of the three appear
#'     depends on which columns `gdp` carries.}
#' }
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
#' @examples
#' \donttest{
#' # run_wai_adj() is what makes a fit file, so the example produces the file it
#' # then exports, on a short chain.
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                 stats::window, start = 2021)
#' stocks <- lapply(data_ch_dataset_test$stocks[1:2],
#'                  stats::window, start = 2021)
#' out <- tempfile(); dir.create(out)
#'
#' set.seed(1)
#' run_wai_adj(flows = flows, stocks = stocks, target = target,
#'             date = 2023, dataset_used = "example",
#'             length_sample = 20, burn_in = 5, output_dir = out)
#'
#' web <- export_wai_web(file.path(out, "example", "fit_2023.Rda"),
#'                       dir = file.path(out, "web"))
#' head(web$data)
#' web$meta$n_obs
#' unlink(out, recursive = TRUE)
#' }
#' @export
export_wai_web <- function(fit_path, dir = NULL, gdp = NULL, digits = 4,
                           vintage_date = NULL) {

  if (!is.character(fit_path) || length(fit_path) != 1L) {
    stop("`fit_path` must be a single file path.", call. = FALSE)
  }
  if (!file.exists(fit_path)) {
    stop("`fit_path` does not exist: ", fit_path, call. = FALSE)
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


# Align a (time, value) pair onto a target vector of dates, returning NA where
# the target date has no match. `time` columns coming out of extract_wai_data()
# are Dates already; as.Date() keeps this honest if that ever changes.
match_on_date <- function(times, values, target) {
  as.numeric(values)[match(target, as.Date(times))]
}


# Place quarterly GDP growth on the weekly grid: each quarter's value lands on
# the last weekly period that falls inside it, and every other week is NA. That
# is what lets the front end draw GDP as points against a weekly line without
# carrying a second, differently-indexed file.
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


# `gdp$time` arrives as a Date from get_real_time_gdp_vintages(), but decimal
# time is the package's other currency, so accept both.
#
# The decimal branch ROUNDS rather than floors, deliberately. The package's own
# decimal_date_local() puts quarter starts at .000/.247/.496/.748 (day-of-year
# over 365), not at exact quarter fractions: flooring `(t %% 1) * 4` sends
# 1990.247 to quarter 1 instead of 2, collapsing two quarters onto one key so
# that one silently overwrites the other. Rounding lands both conventions -
# .247-style and exact .25-style - on the right quarter.
quarter_of <- function(time) {
  if (inherits(time, "Date")) {
    return(quarter_key(as.numeric(format(time, "%Y")),
                       (as.numeric(format(time, "%m")) - 1L) %/% 3L + 1L))
  }
  t <- as.numeric(time)
  quarter_key(floor(t), round((t %% 1) * 4) + 1L)
}


quarter_key <- function(year, quarter) year * 4L + as.integer(quarter)


# write.csv() would quote the header and spell missing values "NA"; the front
# end wants a bare header and empty fields. eol is forced to "\n" so a run on
# Windows does not produce a diff against a run on Linux.
write_web_csv <- function(dat, path) {
  utils::write.table(dat, path, sep = ",", row.names = FALSE, col.names = TRUE,
                     quote = FALSE, na = "", eol = "\n", fileEncoding = "UTF-8")
}


# A dependency-free JSON writer for the flat, scalar-or-character-vector
# metadata list above. jsonlite would do this better, but it is not among the
# package's Imports and one small writer is a poor reason to add a dependency.
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
#' @examples
#' \donttest{
#' gdp <- gdp_web_series()
#' tail(gdp)
#' }
#' @export
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
