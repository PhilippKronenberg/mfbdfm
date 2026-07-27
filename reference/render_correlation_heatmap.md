# Render the lag-correlation heatmap grid and save it

Render the lag-correlation heatmap grid and save it

## Usage

``` r
render_correlation_heatmap(cor_tables, series_order, output_file, figures_dir)
```

## Arguments

- cor_tables:

  Named list of correlation tables from
  [`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md),
  one per aggregation method.

- series_order:

  Character vector giving the series display order.

- output_file:

  File name for the saved figure.

- figures_dir:

  Directory the figure is written to (e.g.
  `wai_sample_config()$figures_dir`).

## Value

Invisibly, the assembled plot.

## Examples

``` r
if (FALSE) { # \dontrun{
render_correlation_heatmap(
  cor_tables = list(mean = cor_tab_mean, last = cor_tab_last),
  series_order = c("WAI", "SECO-WWA", "KOF-BARO"),
  output_file = "correlation_heatmap.pdf",
  figures_dir = cfg$figures_dir
)
} # }
```
