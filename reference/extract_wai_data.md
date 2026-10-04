# Extract WAI growth, level and year-over-year tables from a saved fit

Loads a saved `ind_dfm` fit (an `.Rda` file containing an object `mod`)
and derives long-format tables of the weekly growth rate (with 95%
bands), the cumulated level index (rebased so that the mean of the last
quarter of 2019 equals 100), and year-over-year growth, as used by the
plotting scripts and by
[`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md).

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
`tab_gr_qoq`, `tab_gr_lv`, `tab_gr_lv_full`. `tab_gr_full` and
`tab_gr_lv_full` carry `min`/`max` columns holding the 95% band;
`tab_gr_qoq`, `tab_gr_lv` and `tab_wai_yoy` are the narrow
`time`/`name`/`value` shape the analytics helpers consume.

## Examples

``` r
# \donttest{
# Needs a fit file, and run_wai_adj() is what makes one - so this example
# produces the file it then reads, on a short chain.
data(mfbdfm_example_data)
d <- mfbdfm_example_data
out <- tempfile(); dir.create(out)

set.seed(1)
run_wai_adj(flows = d$flows, stocks = d$stocks, target = d$target,
            date = 2023, dataset_used = "example",
            length_sample = 20, burn_in = 5, output_dir = out)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..

result_wai <- extract_wai_data(file.path(out, "example", "fit_2023.Rda"))
head(result_wai$tab_gr_qoq)
#> # A tibble: 6 × 3
#>   time       name   value
#>   <date>     <chr>  <dbl>
#> 1 2015-01-07 mean  -1.88 
#> 2 2015-01-14 mean  -1.42 
#> 3 2015-01-21 mean  -0.682
#> 4 2015-01-28 mean  -0.118
#> 5 2015-02-07 mean   1.29 
#> 6 2015-02-14 mean   3.20 
unlink(out, recursive = TRUE)
# }
```
