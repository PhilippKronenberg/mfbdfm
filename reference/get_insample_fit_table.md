# In-sample fit metrics of the WAI and benchmarks against GDP

Regresses GDP growth on each (quarterly-aggregated) series at lags -4 to
0 and reports RMSE, MAE and R-squared, plus Diebold-Mariano p-values of
each series against the WAI.

## Usage

``` r
get_insample_fit_table(
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

A list of wide tables: `RMSE`, `MAE`, `R2`, `PVAL_RMSE`, `PVAL_MAE`.

## Examples

``` r
# A minimal `inputs` bundle. The real one is built by the scripts in
# analysis/5_plots/ from fitted models; this is the same shape with synthetic
# numbers, so the example runs and is checked rather than being a sketch.
insample_inputs <- mfbdfm_example_inputs()
fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = insample_inputs)
fit_tabs$RMSE
#> # A tibble: 12 × 7
#> # Groups:   Series [6]
#>    Frequency Series   `RMSE_Lag_-4` `RMSE_Lag_-3` `RMSE_Lag_-2` `RMSE_Lag_-1`
#>    <fct>     <fct>            <dbl>         <dbl>         <dbl>         <dbl>
#>  1 QoQ       WAI              0.499         0.515         0.484         0.489
#>  2 QoQ       SECO-WWA         0.508         0.494         0.493         0.531
#>  3 QoQ       F-CURVE          0.512         0.503         0.496         0.524
#>  4 QoQ       SECO-SEC         0.504         0.498         0.495         0.524
#>  5 QoQ       SNB-BCI          0.515         0.491         0.490         0.523
#>  6 QoQ       KOF-BARO         0.511         0.504         0.487         0.532
#>  7 YoY       WAI              1.11          1.16          1.15          1.14 
#>  8 YoY       SECO-WWA         1.16          1.17          1.15          1.15 
#>  9 YoY       F-CURVE          1.16          1.13          1.12          1.09 
#> 10 YoY       SECO-SEC         1.18          1.18          1.16          1.16 
#> 11 YoY       SNB-BCI          1.18          1.18          1.15          1.14 
#> 12 YoY       KOF-BARO         1.12          1.15          1.16          1.14 
#> # ℹ 1 more variable: RMSE_Lag_0 <dbl>
```
