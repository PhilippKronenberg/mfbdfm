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
inputs <- mfbdfm_example_inputs()
cor_tab <- get_combined_cor_table("mean", "indicators", inputs = inputs)
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

dir <- tempfile(); dir.create(dir)
# a null device, or ggsave() opens a real one and leaves Rplots.pdf behind
grDevices::pdf(NULL)
render_correlation_heatmap(
  cor_tables = list(mean = cor_tab),
  series_order = c("WAI", "SECO-WWA", "F-CURVE", "SECO-SEC",
                   "SNB-BCI", "KOF-BARO"),
  output_file = "correlation_heatmap.pdf", figures_dir = dir)
grDevices::dev.off()
#> agg_record_1abe77e15e8a 
#>                       2 
unlink(dir, recursive = TRUE)
```
