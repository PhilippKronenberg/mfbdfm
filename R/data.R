#' Harmonized Swiss indicator dataset for the WAI model
#'
#' The curated, model-ready dataset shipped with the package.
#' Mixed-frequency time series are harmonized to the project conventions
#' (weekly series use 48 observations per year) and transformed
#' according to the variable metadata in `data-raw/data_meta.csv` (see
#' the data dictionary in `README.md` for the per-series source,
#' category, unit, and transformation).
#'
#' @format A list with two components, as expected by `ind_dfm()`:
#' \describe{
#'   \item{flows}{Named list of 45 `ts` objects treated as flow
#'     variables. The quarterly GDP target series is *not* included;
#'     the analysis scripts add it at runtime from the real-time GDP
#'     vintage database that ships with the package at
#'     `system.file("extdata", "realtime_gdp.csv", package = "mfbdfm")`
#'     (see `get_real_time_gdp_vintages()`).}
#'   \item{stocks}{Named list of 7 `ts` objects treated as stock
#'     variables.}
#' }
#' @source Produced from SECO, KOF, FSO, SNB, Datastream and further
#'   high-frequency sources; see the data dictionary in `README.md` for
#'   the per-series source and metadata.
#' @examples
#' data(data_ch_dataset)
#' names(data_ch_dataset)
#' # NOTE: this one does NOT carry the GDP target series. For a small
#' # self-contained dataset that does, see mfbdfm_example_data; otherwise use
#' # data_ch_dataset_test, or inject it via get_real_time_gdp_vintages().
#' head(names(data_ch_dataset$flows))
"data_ch_dataset"

#' Harmonized Swiss indicator dataset (test variant)
#'
#' A variant of [data_ch_dataset] built from the test metadata
#' (`data_meta_test.xlsx`) with a different flow/stock split, used for
#' model development and evaluation runs.
#'
#' @format A list with two components, as expected by `ind_dfm()`:
#' \describe{
#'   \item{flows}{Named list of 28 `ts` objects treated as flow
#'     variables, including the quarterly target series
#'     `ch.seco.gdp.real.gdp.ssa`.}
#'   \item{stocks}{Named list of 18 `ts` objects treated as stock
#'     variables.}
#' }
#' @source See [data_ch_dataset].
#' @examples
#' data(data_ch_dataset_test)
#' names(data_ch_dataset_test)
#' "ch.seco.gdp.real.gdp.ssa" %in% names(data_ch_dataset_test$flows)
"data_ch_dataset_test"

#' Small self-contained example dataset, GDP target included
#'
#' A ready [mfbdfm_data()] object holding eight series: the quarterly GDP
#' target and seven indicators, enough for [ind_dfm()] or [fcast_dfm()] to be
#' fitted meaningfully in a few seconds on a short chain. Unlike
#' [data_ch_dataset] it **carries the target**, and unlike both shipped
#' datasets it is an `mfbdfm_data` object rather than a bare `flows`/`stocks`
#' list -- so the whole of a runnable example is
#'
#' ```
#' data(mfbdfm_example_data)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 50, burn_in = 10)
#' ```
#'
#' with no `target =` argument and no windowing prelude. It exists for exactly
#' that: examples, the vignette and quick experiments. For the real application
#' use [data_ch_dataset] with a GDP vintage injected at runtime (see
#' [get_real_time_gdp_vintages()]).
#'
#' @details
#' The seven indicators are taken **as they already appear** in
#' [data_ch_dataset], i.e. already transformed per `data-raw/data_meta.csv`
#' (`transformation` in `$meta` records which), and windowed to `start = 2015`.
#' They were chosen to cover all three frequencies the model handles and both
#' aggregation types, and to have an unbroken history over the window -- so the
#' only missingness in the dataset is the ragged edge at the end, which is kept
#' deliberately, that being the thing the model exists to handle.
#'
#' | series | freq | type | what it is |
#' | --- | --- | --- | --- |
#' | `ch.seco.gdp.real.gdp.ssa` | 4 | flow | **target** -- GDP, q/q log difference (SECO) |
#' | `ch.fso.rtt.ind.r.noga0801.sa` | 12 | flow | retail sales, total (FSO) |
#' | `ch.ozd.e.wa.index.re.d11` | 12 | flow | goods exports, total, real (FOCBS) |
#' | `SWPMIPROQ` | 12 | stock | PMI manufacturing, output (procure.ch & UBS) |
#' | `SWISSMI` | 48 | flow | Swiss Market Index (SIX Group) |
#' | `traffic_PW` | 48 | flow | passenger-car counts on motorways (ASTRA) |
#' | `electricity_out` | 48 | flow | electricity consumed by end users (Swissgrid) |
#' | `Arbeitsmarkt` | 48 | stock | Google search index, labour market (KOF) |
#'
#' The target is the **2026.167 vintage** (published 2026-02-27, the newest in
#' the shipped real-time database), transformed with
#' `get_real_time_gdp_vintages("quarterly")`. It is pinned to that vintage so
#' the dataset does not change when a newer one is appended to
#' `inst/extdata/realtime_gdp.csv`; to move it on, change `GDP_VINTAGE` in
#' `data-raw/example_data.R` and rerun it.
#'
#' @format An [mfbdfm_data()] object -- a list with four components:
#' \describe{
#'   \item{flows}{Named list of 6 `ts` objects: GDP (frequency 4), two monthly
#'     (12) and three weekly (48) series.}
#'   \item{stocks}{Named list of 2 `ts` objects, one monthly and one weekly.}
#'   \item{meta}{Data frame, one row per series, with `series`, `type`,
#'     `frequency`, `n_obs`, the level screen's `ac1` and `df_t` (see
#'     [mfbdfm_data()]) and the carried-through `label`, `source`,
#'     `category`, `unit` and `transformation`.}
#'   \item{target}{`"ch.seco.gdp.real.gdp.ssa"`, used as the default `target`
#'     by both model entry points.}
#' }
#'
#' @source Built by `data-raw/example_data.R` from [data_ch_dataset] (series)
#'   and the real-time GDP vintage database shipped at
#'   `system.file("extdata", "realtime_gdp.csv", package = "mfbdfm")` (target).
#'   Original sources are per-series in `$meta$source`; see the data dictionary
#'   in `README.md`.
#'
#' @seealso [mfbdfm_data()], [data_ch_dataset], [get_real_time_gdp_vintages()]
#' @examples
#' data(mfbdfm_example_data)
#' mfbdfm_example_data
#' mfbdfm_example_data$target
#'
#' \donttest{
#' set.seed(1)
#' fit <- ind_dfm(mfbdfm_example_data, length_sample = 50, burn_in = 10)
#' utils::tail(fit$nowcast)
#' }
"mfbdfm_example_data"
