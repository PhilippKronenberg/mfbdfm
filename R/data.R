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
#' # NOTE: this one does NOT carry the GDP target series; see
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
