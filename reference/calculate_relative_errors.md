# Relative RMSE/MAE tables (normalized to the WAI)

Relative RMSE/MAE tables (normalized to the WAI)

## Usage

``` r
calculate_relative_errors(fit_tables)
```

## Arguments

- fit_tables:

  Output of
  [`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md).

## Value

A list with `RMSE_relative` and `MAE_relative` wide tables.

## Examples

``` r
inputs <- mfbdfm_example_inputs()
fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
rel <- calculate_relative_errors(fit_tabs)
rel$RMSE_relative
#> # A tibble: 12 × 7
#>    Frequency Series   `RMSE_rel_RMSE_Lag_-4` `RMSE_rel_RMSE_Lag_-3`
#>    <fct>     <fct>    <chr>                  <chr>                 
#>  1 QoQ       WAI      1.00                   1.00                  
#>  2 QoQ       SECO-WWA 1.02                   0.96                  
#>  3 QoQ       F-CURVE  1.02                   0.98                  
#>  4 QoQ       SECO-SEC 1.01                   0.97                  
#>  5 QoQ       SNB-BCI  1.03                   0.95                  
#>  6 QoQ       KOF-BARO 1.02                   0.98                  
#>  7 YoY       WAI      1.00                   1.00                  
#>  8 YoY       SECO-WWA 1.05                   1.01                  
#>  9 YoY       F-CURVE  1.04                   0.97                  
#> 10 YoY       SECO-SEC 1.07                   1.02                  
#> 11 YoY       SNB-BCI  1.06                   1.02                  
#> 12 YoY       KOF-BARO 1.02                   0.99                  
#> # ℹ 3 more variables: `RMSE_rel_RMSE_Lag_-2` <chr>,
#> #   `RMSE_rel_RMSE_Lag_-1` <chr>, RMSE_rel_RMSE_Lag_0 <chr>
```
