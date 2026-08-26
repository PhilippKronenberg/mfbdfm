# Export WAI results as a web-ready CSV and metadata file

Turns a fitted WAI model into the two files the public dashboard
consumes: a wide, one-row-per-week CSV of the published series, and a
small JSON sidecar describing the run. Together they are the entire
interface between this package and the web front end — the page performs
no computation of its own, it selects columns.

## Usage

``` r
export_wai_web(
  fit_path,
  dir = NULL,
  gdp = NULL,
  digits = 4,
  vintage_date = NULL
)
```

## Arguments

- fit_path:

  Path to a fit `.Rda` file containing an object `mod`, as written by
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md).

- dir:

  Directory to write `wai_data.csv` and `wai_meta.json` into, or `NULL`
  (default) to write nothing and only return the data. Created if it
  does not exist.

- gdp:

  Optional data frame of published GDP, with a `time` column plus either

  - `qoq`, `yoy` and/or `index` — as
    [`gdp_web_series()`](https://philippkronenberg.github.io/mfbdfm/reference/gdp_web_series.md)
    returns, already on the published scale. This is the intended route.

  - `value` — the older single-series shape, written out as `gdp_qoq`.

  `time` may be a `Date` (as
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
  returns) or decimal time in either the
  [`decimal_date_local()`](https://philippkronenberg.github.io/mfbdfm/reference/decimal_date_local.md)
  convention or exact quarter fractions.

  Mind the units if you build this frame yourself:
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
  returns `"quarterly"` as a log difference and `"annual"` as a
  fraction, whereas `wai_qoq` is an annualised percentage — unconverted,
  the two differ on one axis by a factor of roughly 400.
  [`gdp_web_series()`](https://philippkronenberg.github.io/mfbdfm/reference/gdp_web_series.md)
  exists to spare you that conversion.

- digits:

  Number of decimal places to round the published series to. Defaults to
  4, which is well past the precision the model supports and keeps the
  file small.

- vintage_date:

  Optional evaluation/vintage date recorded in the metadata. Defaults to
  the last observation date.

## Value

Invisibly, a list with elements `data` (the wide data frame) and `meta`
(the metadata list). Writes files only when `dir` is given.

## Details

The CSV has one row per weekly period and these columns, in this order:

- `date`:

  ISO date on the 7th/14th/21st/28th convention of
  [`dec2week()`](https://philippkronenberg.github.io/mfbdfm/reference/dec2week.md).

- `wai_qoq`, `wai_qoq_lo`, `wai_qoq_hi`:

  Annualised quarter-on-quarter growth and its 95% band, from the factor
  and `factor_var`.

- `wai_yoy`:

  Year-over-year growth of the level index.

- `wai_index`:

  Level index, rebased to the mean of 2019Q4 = 100.

- `wai_qoq_q`, `wai_yoy_q`:

  The WAI aggregated to quarterly frequency the way GDP is actually
  measured, placed on the last weekly period of each quarter and empty
  elsewhere. See below.

- `gdp_qoq`, `gdp_yoy`, `gdp_index`:

  Published GDP on the same three measures, placed on the last weekly
  period of each quarter and empty elsewhere. Omitted when `gdp` is
  `NULL`; which of the three appear depends on which columns `gdp`
  carries.

**`wai_qoq_q` is the series to compare with `gdp_qoq`; `wai_qoq` is
not.** Quarterly GDP is a *flow* — the quarter's average activity — so
the like-for-like aggregate is the quarterly **mean of the level
index**, and growth taken between those means. `wai_qoq` is the weekly
factor, an instantaneous annualised growth rate, and reading it against
`gdp_qoq` point-for-point compares different objects. The gap is not
small: on a V-shaped path it is the difference between quarter-endpoints
(near zero across 2020Q2, because the level fell and recovered inside
the quarter) and quarter-averages (about -23% annualised, which is what
GDP reported). Aggregated correctly, the WAI matches published GDP at a
correlation of 1.000 and an RMSE of 0.04pp.

**`wai_index` and `wai_yoy` are published without bands, deliberately.**
The only genuine 95% credible interval the fit provides is the one on
the growth rate. The level bounds that
[`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md)
returns in `tab_gr_lv_full` are the index scaled by a *single* period of
growth at each bound, not a compounded level interval, so publishing
them next to `wai_index` would present something that looks like a level
confidence band and is not one.

Missing values are written as the empty string rather than `NA` or
`NaN`, so that the front end's parser does not have to know R's spelling
of missing. Numbers use `.` as the decimal separator and no thousands
separator, rows are sorted ascending by date, and lines end with `\n` on
every platform.

## See also

[`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md),
which produces the underlying tables.

## Examples

``` r
# \donttest{
# run_wai_adj() is what makes a fit file, so the example produces the file it
# then exports, on a short chain.
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                stats::window, start = 2021)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2021)
out <- tempfile(); dir.create(out)

set.seed(1)
run_wai_adj(flows = flows, stocks = stocks, target = target,
            date = 2023, dataset_used = "example",
            length_sample = 20, burn_in = 5, output_dir = out)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..

web <- export_wai_web(file.path(out, "example", "fit_2023.Rda"),
                      dir = file.path(out, "web"))
#> Warning: Fit does not cover the 2019Q4 base window; rebasing the level index to its first observation instead. Level values are not comparable with those from a fit that does cover it.
head(web$data)
#>         date wai_qoq wai_qoq_lo wai_qoq_hi wai_yoy wai_index wai_qoq_q
#> 1 2021-01-07  0.0946    -4.9856     5.1748      NA  100.0000        NA
#> 2 2021-01-14 -0.0386    -4.0295     3.9522      NA   99.9992        NA
#> 3 2021-01-21  0.6658    -3.8003     5.1319      NA  100.0130        NA
#> 4 2021-01-28  1.8277    -1.7246     5.3801      NA  100.0508        NA
#> 5 2021-02-07  2.5564    -1.0743     6.1871      NA  100.1034        NA
#> 6 2021-02-14  3.4625     0.3633     6.5617      NA  100.1744        NA
#>   wai_yoy_q
#> 1        NA
#> 2        NA
#> 3        NA
#> 4        NA
#> 5        NA
#> 6        NA
web$meta$n_obs
#> [1] 97
unlink(out, recursive = TRUE)
# }
```
