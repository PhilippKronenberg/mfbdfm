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
out <- create_combined_latex_table(list(mean = cor_tab))
cat(substr(out$table_tex, 1, 300))
#> \begin{table}[!h]
#> \centering
#> \caption{Cross Correlation with GDP for Different Lags and Aggregation Methods}
#> \centering
#> \begin{tabularx}{\linewidth}{>{\raggedright\arraybackslash}p{2.3cm}>{\raggedleft\arraybackslash}p{0.9cm}>{\raggedleft\arraybackslash}p{0.9cm}>{\raggedleft\arraybackslash}p{0.9cm}>{
```
