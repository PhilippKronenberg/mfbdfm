# Print a fit summary

Print a fit summary

## Usage

``` r
# S3 method for class 'summary.mfbdfm_fit'
print(x, ...)
```

## Arguments

- x:

  An object from
  [`summary.ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
  or
  [`summary.fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm_methods.md).

- ...:

  Ignored.

## Value

`x`, invisibly.

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
fit <- ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                              stats::window, start = 2021),
               stocks = lapply(data_ch_dataset_test$stocks[1:2],
                               stats::window, start = 2021),
               target = target, length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..
summary(fit)          # dispatches here
#> Single-factor mixed-frequency dynamic factor model (Kronenberg 2026)
#> Call: ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],     stats::window, start = 2021), stocks = lapply(data_ch_dataset_test$stocks[1:2], 
#> 
#>   series (n) : 4
#>   factors (q): 1
#>   periods (t): 250
#>   target     : ch.seco.gdp.real.gdp.ssa
#> 
#> Factor loadings (posterior mean):
#> ch.seco.gdp.real.gdp.ssa                  SWISSMI                SWCONPRCE 
#>                   1.0000                   0.0350                   0.5373 
#>                SWPROPRCE 
#>                   1.2517 
#> 
#> Measurement error sd (posterior mean):
#> [1] 0.1350 0.8929 0.6168 0.7110
#> 
#> Fit to observed data:
#>   observed values: 393
#>   residual RMSE  : 6.797e-06 (standardized scale)
# }
```
