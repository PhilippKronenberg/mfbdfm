# Per-observation in-sample errors of each series against GDP

Runs the lag regressions of
[`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md)
but returns the full error series per observation date, model, method,
lag and frequency, for use in
[`create_error_summary_tables()`](https://philippkronenberg.github.io/mfbdfm/reference/create_error_summary_tables.md).

## Usage

``` r
get_insample_error_details(
  method = c("mean", "last", "last_month"),
  analysis_set = c("wai_versions", "indicators"),
  inputs
)
```

## Arguments

- method:

  Quarterly aggregation method: `"mean"`, `"last"`, or `"last_month"`.

- analysis_set:

  `"wai_versions"` to compare WAI model variants, or `"indicators"` to
  compare against the benchmark indicators.

- inputs:

  Named list of the input data objects (formerly free variables in the
  calling script). Always required: `tab_gr`, `tab_gr_lv`,
  `x_hist_gr_yoy`, `x_hist_gr_ann`. For `analysis_set = "indicators"`
  additionally: `tab_wai_yoy`, `wwa_gr_df`, `wwa_gr_df_qoq`,
  `fcurve_gr_df`, `tab_kss`, `tab_snb`, `tab_baro`. For
  `"wai_versions"`: `result_wai`, `result_wai_no_sv`,
  `result_wai_only_monthly_no_sv`, `result_wai_no_hf`,
  `result_wai_no_financial`.

## Value

A long data frame with columns `observation_date`, `error`, `model`,
`method`, `lag_number`, `frequency`.

## Examples

``` r
if (FALSE) { # \dontrun{
details <- get_insample_error_details("mean", "indicators", inputs = insample_inputs)
head(details)
} # }
```
