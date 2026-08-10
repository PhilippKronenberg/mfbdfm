# Relative out-of-sample error tables across vintages

Aggregates out-of-sample errors per target vintage, computes relative
RMSE/MAE against the WAI with Diebold-Mariano significance stars, and
returns per-method wide tables.

## Usage

``` r
create_rel_error_tables(combined_results, model_order, lag_range = -4:0)
```

## Arguments

- combined_results:

  Long data frame of out-of-sample errors with columns `target_vintage`,
  `model`, `method`, `lag_number`, `GDP_type`, `frequency`, `error`.

- model_order:

  Character vector of models in display order.

- lag_range:

  Integer lags covered.

## Value

A list with `rel_rmse` and `rel_mae` (per-method lists).

## Examples

``` r
# `combined_results` is the long out-of-sample error table that
# analysis/5_plots/analytics_out-of-sample.R builds; this is the same shape.
set.seed(1)
combined_results <- expand.grid(
  target_vintage = seq(2015, 2019.75, by = 0.25),
  model = c("WAI", "AR"), method = "mean", lag_number = -4:0,
  GDP_type = "ssa", frequency = "QoQ", stringsAsFactors = FALSE)
combined_results$error <- rnorm(nrow(combined_results), 0, 0.5)

rel <- create_rel_error_tables(combined_results, model_order = c("WAI", "AR"))
rel$rel_rmse
#> $mean
#> # A tibble: 2 × 7
#>   Frequency Series `RMSE_rel_-4` `RMSE_rel_-3` `RMSE_rel_-2` `RMSE_rel_-1`
#>   <fct>     <fct>  <chr>         <chr>         <chr>         <chr>        
#> 1 QoQ       WAI    1.00          1.00          1.00          1.00         
#> 2 QoQ       AR     0.93          1.28          0.90          1.78***      
#> # ℹ 1 more variable: RMSE_rel_0 <chr>
#> 
```
