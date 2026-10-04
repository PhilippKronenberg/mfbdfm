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
data(mfbdfm_example_data)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..
summary(fit)          # dispatches here
#> Single-factor mixed-frequency dynamic factor model (Kronenberg 2026)
#> Call: ind_dfm(flows = mfbdfm_example_data, length_sample = 20, burn_in = 5)
#> 
#>   series (n) : 8
#>   factors (q): 1
#>   periods (t): 541
#>   target     : ch.seco.gdp.real.gdp.ssa
#> 
#> Factor loadings (posterior mean, 95% interval):
#>                         series    mean     sd   lower  upper
#> 1 ch.fso.rtt.ind.r.noga0801.sa -0.1577 0.2911 -0.7205 0.4174
#> 2     ch.ozd.e.wa.index.re.d11  0.6121 0.1696  0.3008 0.8708
#> 3                      SWISSMI -0.0719 0.2893 -0.5361 0.5060
#> 4                   traffic_PW  0.7593 0.4984  0.0881 1.6555
#> 5              electricity_out  0.3525 0.2226 -0.0466 0.7123
#> 6     ch.seco.gdp.real.gdp.ssa  1.0000 0.0000  1.0000 1.0000
#> 7                    SWPMIPROQ  0.8001 0.3523  0.2893 1.4558
#> 8                 Arbeitsmarkt  0.3209 0.3095 -0.0599 1.0155
#> 
#> Measurement error variance (posterior mean, 95% interval):
#>                         series   mean     sd  lower  upper
#> 1 ch.fso.rtt.ind.r.noga0801.sa 0.8260 0.1360 0.6616 1.0546
#> 2     ch.ozd.e.wa.index.re.d11 0.8771 0.1633 0.6735 1.1180
#> 3                      SWISSMI 0.8339 0.0489 0.7415 0.9155
#> 4                   traffic_PW 0.7401 0.0373 0.6890 0.8187
#> 5              electricity_out 0.9835 0.0499 0.8891 1.0518
#> 6     ch.seco.gdp.real.gdp.ssa 0.0167 0.0160 0.0024 0.0520
#> 7                    SWPMIPROQ 0.0840 0.0234 0.0666 0.1416
#> 8                 Arbeitsmarkt 0.3136 0.0170 0.2776 0.3376
#>   (the measurement error sd is the square root of `mean`)
#> 
#> Fit to observed data:
#>   observed values: 2582
#>   residual RMSE  : 7.018e-06 (standardized scale)
#> 
#> R-squared of the common component, by series:
#>   series                                  freq  n_obs R-squared
#>   ch.seco.gdp.real.gdp.ssa                   4     44     0.884
#>   ch.ozd.e.wa.index.re.d11                  12    131     0.122
#>   traffic_PW                                48    532     0.061
#>   SWPMIPROQ                                 12    134     0.040
#>   Arbeitsmarkt                              48    541     0.035
#>   electricity_out                           48    529     0.003
#>   SWISSMI                                   48    538    -0.001
#>   ch.fso.rtt.ind.r.noga0801.sa              12    133    -0.027
#>   Note: the target's loading is fixed to 1 and its measurement error
#>   shrunk towards zero to identify the factor, so its R-squared is ~1
#>   by construction rather than as a finding.
# }
```
