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
#> 1 ch.fso.rtt.ind.r.noga0801.sa -0.0784 0.2481 -0.4581 0.3589
#> 2     ch.ozd.e.wa.index.re.d11  0.5544 0.1212  0.3061 0.7117
#> 3                      SWISSMI  0.0383 0.2112 -0.2152 0.4783
#> 4                   traffic_PW  0.6173 0.3887 -0.0659 1.2701
#> 5              electricity_out  0.1229 0.2012 -0.2859 0.4153
#> 6     ch.seco.gdp.real.gdp.ssa  1.0000 0.0000  1.0000 1.0000
#> 7                    SWPMIPROQ  0.8821 0.4982  0.2260 2.0542
#> 8                 Arbeitsmarkt  0.1626 0.2371 -0.2321 0.5554
#> 
#> Measurement error variance (posterior mean, 95% interval):
#>                         series   mean     sd  lower  upper
#> 1 ch.fso.rtt.ind.r.noga0801.sa 0.9481 0.1534 0.7343 1.2696
#> 2     ch.ozd.e.wa.index.re.d11 0.8663 0.1305 0.7214 1.1258
#> 3                      SWISSMI 0.8435 0.0485 0.7710 0.9406
#> 4                   traffic_PW 0.7510 0.0296 0.7050 0.8005
#> 5              electricity_out 0.9489 0.0659 0.8454 1.0503
#> 6     ch.seco.gdp.real.gdp.ssa 0.0133 0.0151 0.0020 0.0504
#> 7                    SWPMIPROQ 0.1071 0.0295 0.0759 0.1703
#> 8                 Arbeitsmarkt 0.3132 0.0192 0.2846 0.3495
#>   (the measurement error sd is the square root of `mean`)
#> 
#> Fit to observed data:
#>   observed values: 2582
#>   residual RMSE  : 7.137e-06 (standardized scale)
#> 
#> R-squared of the common component, by series:
#>   series                                  freq  n_obs R-squared
#>   ch.seco.gdp.real.gdp.ssa                   4     44     0.923
#>   ch.ozd.e.wa.index.re.d11                  12    131     0.121
#>   SWPMIPROQ                                 12    134     0.054
#>   traffic_PW                                48    532     0.050
#>   Arbeitsmarkt                              48    541     0.016
#>   electricity_out                           48    529     0.001
#>   SWISSMI                                   48    538     0.000
#>   ch.fso.rtt.ind.r.noga0801.sa              12    133    -0.010
#>   Note: the target's loading is fixed to 1 and its measurement error
#>   shrunk towards zero to identify the factor, so its R-squared is ~1
#>   by construction rather than as a finding.
#> 
#> Priors for ind_dfm()  [type: default]
#> 
#>   sigma_target  c0 = 541, d0 = 0.541  [structural]
#>   rho_target    r0 = 0, R0 = 1e-09  [structural]
#>   sigma_other   c0 = 3, d0 = 0.05
#>   rho_other     r0 = 0, R0 = 5
#>   lambda        b0 = 0, B0 = 1
#>   phi           a0 = 0, A0 = 0.12
#>   omega         k0 = 541, l0 = 5.41
#>   factor_var    c0 = 3, d0 = 0.01
#> 
#> Control settings for ind_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
#>   seed                     NULL      
#>   starting_values          NULL      
#>   phi_sum_max              0.9       
#>   sigma_max                5         
#>   keep_burn_in             FALSE     
#> 
#>   (the specification above is stored with the fit, as $priors and $control)
# }
```
