# Combine per-method lag tables into one LaTeX table

Combine per-method lag tables into one LaTeX table

## Usage

``` r
create_combined_latex_table(
  combined_tables_list,
  caption = "Cross Correlation with GDP for Different Lags and Aggregation Methods",
  include_period = FALSE,
  measure_label_map = NULL
)
```

## Arguments

- combined_tables_list:

  Named list of lag tables (one per aggregation method), e.g. from
  [`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md).

- caption:

  LaTeX table caption.

- include_period:

  If `TRUE`, keep a `Period` column.

- measure_label_map:

  Named character vector mapping method names to LaTeX section labels.

## Value

A list with `combined_wide` (the assembled data frame) and `table_tex`
(the LaTeX code).

## Examples

``` r
if (FALSE) { # \dontrun{
out <- create_combined_latex_table(list(mean = cor_tab_mean, last = cor_tab_last))
cat(out$table_tex)
} # }
```
