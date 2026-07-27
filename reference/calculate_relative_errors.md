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
if (FALSE) { # \dontrun{
fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = insample_inputs)
rel <- calculate_relative_errors(fit_tabs)
rel$RMSE_relative
} # }
```
