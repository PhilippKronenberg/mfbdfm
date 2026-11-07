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
#> 
  |                                                                            
  |                                                                      |   0%
  |                                                                            
  |===                                                                   |   4%
  |                                                                            
  |======                                                                |   8%
  |                                                                            
  |========                                                              |  12%
  |                                                                            
  |===========                                                           |  16%
  |                                                                            
  |==============                                                        |  20%
  |                                                                            
  |=================                                                     |  24%
  |                                                                            
  |====================                                                  |  28%
  |                                                                            
  |======================                                                |  32%
  |                                                                            
  |=========================                                             |  36%
  |                                                                            
  |============================                                          |  40%
  |                                                                            
  |===============================                                       |  44%
  |                                                                            
  |==================================                                    |  48%
  |                                                                            
  |====================================                                  |  52%
  |                                                                            
  |=======================================                               |  56%
  |                                                                            
  |==========================================                            |  60%
  |                                                                            
  |=============================================                         |  64%
  |                                                                            
  |================================================                      |  68%
  |                                                                            
  |==================================================                    |  72%
  |                                                                            
  |=====================================================                 |  76%
  |                                                                            
  |========================================================              |  80%
  |                                                                            
  |===========================================================           |  84%
  |                                                                            
  |==============================================================        |  88%
  |                                                                            
  |================================================================      |  92%
  |                                                                            
  |===================================================================   |  96%
  |                                                                            
  |======================================================================| 100%
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
#> How each series relates to the factor: R-squared, and the loading
#> standardised by its aggregation weights, target = 1 (95% interval):
#>                         series r_squared loading_std std_lower std_upper
#> 1 ch.fso.rtt.ind.r.noga0801.sa    0.1404      0.2317    0.0956    0.3148
#> 2     ch.ozd.e.wa.index.re.d11    0.1353      0.2330    0.1462    0.2961
#> 3                      SWISSMI    0.0587      0.1184    0.0536    0.1684
#> 4                   traffic_PW    0.4247      0.3160    0.2901    0.3467
#> 5              electricity_out    0.0027      0.0244   -0.0183    0.0572
#> 6     ch.seco.gdp.real.gdp.ssa    0.9998      1.0000    1.0000    1.0000
#> 7                    SWPMIPROQ    0.0519      0.0653    0.0282    0.1056
#> 8                 Arbeitsmarkt    0.4687      0.3509    0.2436    0.3882
#> 
#> Measurement error variance (posterior mean, 95% interval):
#>                         series   mean     sd  lower  upper
#> 1 ch.fso.rtt.ind.r.noga0801.sa 0.7849 0.0771 0.6746 0.9189
#> 2     ch.ozd.e.wa.index.re.d11 0.7942 0.1002 0.6210 0.9458
#> 3                      SWISSMI 0.8002 0.0514 0.7259 0.8913
#> 4                   traffic_PW 0.5726 0.0340 0.5178 0.6240
#> 5              electricity_out 0.9890 0.0470 0.9161 1.0664
#> 6     ch.seco.gdp.real.gdp.ssa 0.0021 0.0027 0.0009 0.0096
#> 7                    SWPMIPROQ 0.0801 0.0099 0.0653 0.1005
#> 8                 Arbeitsmarkt 0.1968 0.0478 0.1535 0.3138
#>   (the measurement error sd is the square root of `mean`)
#> 
#> Fit to observed data:
#>   observed values: 2582
#>   residual RMSE  : 0.8749 (standardized scale)
#> 
#> R-squared of the common component, by series:
#>   series                                  freq  n_obs R-squared
#>   ch.seco.gdp.real.gdp.ssa                   4     44     1.000
#>   Arbeitsmarkt                              48    541     0.469
#>   traffic_PW                                48    532     0.425
#>   ch.fso.rtt.ind.r.noga0801.sa              12    133     0.140
#>   ch.ozd.e.wa.index.re.d11                  12    131     0.135
#>   SWISSMI                                   48    538     0.059
#>   SWPMIPROQ                                 12    134     0.052
#>   electricity_out                           48    529     0.003
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
#>   keep_burn_in             FALSE     
#> 
#>   (the specification above is stored with the fit, as $priors and $control)
# }
```
