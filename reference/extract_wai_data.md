# Extract WAI growth, level and year-over-year tables from a saved fit

Loads a saved `ind_dfm` fit (an `.Rda` file containing an object `mod`)
and derives long-format tables of the weekly growth rate (with 95%
bands), the cumulated level index (rebased to 2020 = 100), and
year-over-year growth, as used by the plotting scripts.

## Usage

``` r
extract_wai_data(file_path)
```

## Arguments

- file_path:

  Path to a fit `.Rda` file containing an object `mod` with elements
  `factor` and `factor_var`.

## Value

A list of data frames: `tab_wai_yoy_full`, `tab_wai_yoy`, `tab_gr_full`,
`tab_gr_qoq`, `tab_gr_lv`.

## Examples

``` r
# \donttest{
# Needs a fit file, and run_wai_adj() is what makes one - so this example
# produces the file it then reads, on a short chain.
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                stats::window, start = 2021)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2021)
out <- tempfile(); dir.create(out)

set.seed(1)
run_wai_adj(flows = flows, stocks = stocks, target = target,
            date = 2023, dataset_used = "example",
            length_sample = 20, burn_in = 5, output_dir = out)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..

result_wai <- extract_wai_data(file.path(out, "example", "fit_2023.Rda"))
head(result_wai$tab_gr_qoq)
#> # A tibble: 6 × 3
#>   time       name    value
#>   <date>     <chr>   <dbl>
#> 1 2021-01-07 mean   0.0946
#> 2 2021-01-14 mean  -0.0386
#> 3 2021-01-21 mean   0.666 
#> 4 2021-01-28 mean   1.83  
#> 5 2021-02-07 mean   2.56  
#> 6 2021-02-14 mean   3.46  
unlink(out, recursive = TRUE)
# }
```
