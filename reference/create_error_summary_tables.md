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
if (FALSE) { # \dontrun{
details <- get_insample_error_details("mean", "indicators", inputs = insample_inputs)
tabs <- create_error_summary_tables(details, model_order = c("WAI", "KOF-BARO"),
                                    date_col = "observation_date")
} # }
```
