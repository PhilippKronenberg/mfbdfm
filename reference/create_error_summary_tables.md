# Error summary tables with crisis/non-crisis split

Aggregates in-sample error details, computes RMSE/MAE per model with
Diebold-Mariano tests against the WAI, and returns annotated relative
and absolute error tables per aggregation method.

## Usage

``` r
create_error_summary_tables(
  error_data,
  model_order,
  date_col,
  lag_range = -4:0,
  include_period = FALSE
)
```

## Arguments

- error_data:

  Long error table from
  [`get_insample_error_details()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_error_details.md).

- model_order:

  Character vector of models in display order.

- date_col:

  Name of the date column (e.g. `"observation_date"`).

- lag_range:

  Integer lags covered.

- include_period:

  If `TRUE`, split by crisis/non-crisis periods.

## Value

A list: `rel_rmse`, `rel_mae`, `abs_rmse`, `abs_mae` (each a per-method
list of tables) and `summary`.

## Examples

``` r
inputs <- mfbdfm_example_inputs()
details <- get_insample_error_details("mean", "indicators", inputs = inputs)
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
tabs <- create_error_summary_tables(details,
                                    model_order = c("WAI", "KOF-BARO"),
                                    date_col = "observation_date")
names(tabs)
#> [1] "rel_rmse" "rel_mae"  "abs_rmse" "abs_mae"  "summary" 
```
