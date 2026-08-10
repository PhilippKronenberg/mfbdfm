# Cross correlations of the WAI and benchmarks with GDP

Computes lagged correlations of the WAI (and either the benchmark
indicators or the WAI model variants) with GDP growth, for YoY and QoQ
frequencies, at lags -4 to 0.

## Usage

``` r
get_combined_cor_table(
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

A data frame of correlations by `Frequency`, `Series` and lag.

## Examples

``` r
# `inputs` is the bundle the analysis/5_plots/ scripts build from fitted
# models. Constructed here with synthetic numbers of the same shape, so the
# example actually runs and is checked rather than being a sketch.
insample_inputs <- mfbdfm_example_inputs()
cor_tab <- get_combined_cor_table("mean", "indicators", inputs = insample_inputs)
#> 
#> Evaluation periods: In-sample fit table, indicators YoY
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
#> Evaluation periods: In-sample fit table, indicators QoQ
#> # A tibble: 6 × 5
#>   Series   Frequency Method start_quarter end_quarter
#>   <chr>    <chr>     <chr>  <chr>         <chr>      
#> 1 F-CURVE  QoQ       mean   2010 Q1       2015 Q4    
#> 2 KOF-BARO QoQ       mean   2010 Q1       2015 Q4    
#> 3 SECO-SEC QoQ       mean   2010 Q1       2015 Q4    
#> 4 SECO-WWA QoQ       mean   2010 Q1       2015 Q4    
#> 5 SNB-BCI  QoQ       mean   2010 Q1       2015 Q4    
#> 6 WAI      QoQ       mean   2010 Q2       2015 Q4    
head(cor_tab)
#> # A tibble: 6 × 7
#> # Groups:   Series [6]
#>   Frequency Series   `Lag_-4` `Lag_-3` `Lag_-2` `Lag_-1`    Lag_0
#>   <chr>     <chr>       <dbl>    <dbl>    <dbl>    <dbl>    <dbl>
#> 1 YoY       WAI       -0.349   -0.194  -0.134    -0.193  -0.0557 
#> 2 YoY       SECO-WWA   0.195   -0.136  -0.113     0.184  -0.00987
#> 3 YoY       F-CURVE   -0.207   -0.295  -0.251    -0.355  -0.256  
#> 4 YoY       SECO-SEC   0.0148  -0.0804 -0.0573   -0.0729 -0.129  
#> 5 YoY       SNB-BCI    0.0661   0.0822  0.124     0.192   0.144  
#> 6 YoY       KOF-BARO   0.307    0.248  -0.00117  -0.199  -0.0445 
```
