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
# Same synthetic `inputs` bundle as [get_insample_fit_table()]; see there for
# what the real one is built from.
insample_inputs <- mfbdfm_example_inputs()
details <- get_insample_error_details("mean", "indicators", inputs = insample_inputs)
#> 
#> Evaluation periods: In-sample error evaluation, indicators YoY
#> # A tibble: 6 × 5
#>   Series   Frequency Method start_quarter end_quarter
#>   <chr>    <chr>     <chr>  <chr>         <chr>      
#> 1 F-CURVE  YoY       mean   2010 Q1       2015 Q4    
#> 2 KOF-BARO YoY       mean   2010 Q1       2015 Q4    
#> 3 SECO-SEC YoY       mean   2010 Q1       2015 Q4    
#> 4 SECO-WWA YoY       mean   2010 Q1       2015 Q4    
#> 5 SNB-BCI  YoY       mean   2010 Q1       2015 Q4    
#> 6 WAI      YoY       mean   2010 Q1       2015 Q4    
#> 
#> Evaluation periods: In-sample error evaluation, indicators QoQ
#> # A tibble: 6 × 5
#>   Series   Frequency Method start_quarter end_quarter
#>   <chr>    <chr>     <chr>  <chr>         <chr>      
#> 1 F-CURVE  QoQ       mean   2010 Q1       2015 Q4    
#> 2 KOF-BARO QoQ       mean   2010 Q1       2015 Q4    
#> 3 SECO-SEC QoQ       mean   2010 Q1       2015 Q4    
#> 4 SECO-WWA QoQ       mean   2010 Q1       2015 Q4    
#> 5 SNB-BCI  QoQ       mean   2010 Q1       2015 Q4    
#> 6 WAI      QoQ       mean   2010 Q2       2015 Q4    
#> Adding missing grouping variables: `Series`
#> Adding missing grouping variables: `Series`
head(details)
#> # A tibble: 6 × 7
#> # Groups:   Series [1]
#>   Series  observation_date   error model   method lag_number frequency
#>   <chr>   <date>             <dbl> <chr>   <chr>       <int> <chr>    
#> 1 F-CURVE 2010-01-01       -0.624  F-CURVE mean           -4 YoY      
#> 2 F-CURVE 2010-04-01        0.228  F-CURVE mean           -4 YoY      
#> 3 F-CURVE 2010-07-01        0.0169 F-CURVE mean           -4 YoY      
#> 4 F-CURVE 2010-10-01       -1.29   F-CURVE mean           -4 YoY      
#> 5 F-CURVE 2011-01-01       -0.559  F-CURVE mean           -4 YoY      
#> 6 F-CURVE 2011-04-01        0.909  F-CURVE mean           -4 YoY      
```
