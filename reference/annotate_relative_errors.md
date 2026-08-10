# Annotate relative error tables with significance stars

Annotate relative error tables with significance stars

## Usage

``` r
annotate_relative_errors(rel_table, pval_table, metric_prefix)
```

## Arguments

- rel_table:

  Relative error table from
  [`calculate_relative_errors()`](https://philippkronenberg.github.io/mfbdfm/reference/calculate_relative_errors.md).

- pval_table:

  Matching p-value table from
  [`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md).

- metric_prefix:

  `"RMSE"` or `"MAE"`.

## Value

Wide table of annotated values.

## Examples

``` r
inputs <- mfbdfm_example_inputs()
fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
rel <- calculate_relative_errors(fit_tabs)
annotate_relative_errors(rel$RMSE_relative, fit_tabs$PVAL_RMSE, "RMSE")
#> # A tibble: 12 × 7
#>    Frequency Series   `RMSE_rel_-4` `RMSE_rel_-3` `RMSE_rel_-2` `RMSE_rel_-1`
#>    <fct>     <fct>    <chr>         <chr>         <chr>         <chr>        
#>  1 QoQ       WAI      1.00          1.00          1.00          1.00         
#>  2 QoQ       SECO-WWA 1.02          0.96          1.02          1.09         
#>  3 QoQ       F-CURVE  1.02          0.98          1.02          1.07         
#>  4 QoQ       SECO-SEC 1.01          0.97          1.02          1.07         
#>  5 QoQ       SNB-BCI  1.03          0.95          1.01          1.07         
#>  6 QoQ       KOF-BARO 1.02          0.98          1.01          1.09         
#>  7 YoY       WAI      1.00          1.00          1.00          1.00         
#>  8 YoY       SECO-WWA 1.05          1.01          1.00          1.00         
#>  9 YoY       F-CURVE  1.04          0.97          0.98          0.95         
#> 10 YoY       SECO-SEC 1.07          1.02          1.01          1.02         
#> 11 YoY       SNB-BCI  1.06          1.02          1.00          1.00         
#> 12 YoY       KOF-BARO 1.02          0.99          1.01          1.00         
#> # ℹ 1 more variable: RMSE_rel_0 <chr>
```
