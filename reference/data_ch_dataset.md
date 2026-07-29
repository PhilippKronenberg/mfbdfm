# Harmonized Swiss indicator dataset for the WAI model

The curated, model-ready dataset shipped with the package.
Mixed-frequency time series are harmonized to the project conventions
(weekly series use 48 observations per year) and transformed according
to the variable metadata in `data-raw/data_meta.csv` (see the data
dictionary in `README.md` for the per-series source, category, unit, and
transformation).

## Usage

``` r
data_ch_dataset
```

## Format

A list with two components, as expected by
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md):

- flows:

  Named list of 45 `ts` objects treated as flow variables. The quarterly
  GDP target series is *not* included; the analysis scripts add it at
  runtime from the real-time GDP vintage database that ships with the
  package at
  `system.file("extdata", "realtime_gdp.csv", package = "mfbdfm")` (see
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)).

- stocks:

  Named list of 7 `ts` objects treated as stock variables.

## Source

Produced from SECO, KOF, FSO, SNB, Datastream and further high-frequency
sources; see the data dictionary in `README.md` for the per-series
source and metadata.
