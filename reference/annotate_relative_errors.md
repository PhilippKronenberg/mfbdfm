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
if (FALSE) { # \dontrun{
annotated <- annotate_relative_errors(rel$RMSE_relative, fit_tabs$PVAL_RMSE, "RMSE")
} # }
```
