# Quality checks on a fit's published quantities

Measures the mixing and the precision of what is actually published,
which parameter diagnostics do not. Meant as a gate: if a check fails,
keep the last publication and investigate, rather than lowering the bar.

## Usage

``` r
mfbdfm_quality(
  fit,
  exact = NULL,
  unexplained = NULL,
  ess_min = 400,
  mcse_max = 0.1,
  rhat_max = 1.01,
  anchor_max = 0.001,
  fallback_max = 0.01,
  param_ess_min = 100,
  exact_z = 3,
  unexplained_max = 0.5
)

# S3 method for class 'mfbdfm_quality'
print(x, ...)
```

## Arguments

- fit:

  A fitted model carrying its draws, the default.

- exact:

  Optional result of
  [`mfbdfm_exact()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_exact.md)
  on `fit`.

- unexplained:

  Optional single number: the published revision minus the sum of its
  news, in annualised points.

- ess_min, mcse_max, rhat_max, anchor_max, fallback_max, param_ess_min,
  exact_z, unexplained_max:

  The limits, see Details.

- x:

  An object from `mfbdfm_quality()`.

- ...:

  Ignored.

## Value

A data frame of class `"mfbdfm_quality"` with columns `check`, `value`,
`limit`, `pass`. A check that does not apply here is left out. `pass` is
`NA` for one that cannot be judged, such as a constant chain. The
attribute `pass` is `TRUE` only if no row has `pass` of `FALSE`.

## Details

For the latest unobserved nowcast (annualised percentage points), and
for an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit also for the latest weekly factor value and the mean of the latest
13 weeks:

- `ess`:

  Rank-normalised effective sample size, at least `ess_min`.

- `mcse`:

  Monte Carlo error of the mean, `sd / sqrt(ess)`, at most `mcse_max`.

- `rhat`:

  Split R-hat from one chain cut in half, at most `rhat_max`.

And for the fit as a whole:

- `anchor`:

  An
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  nowcast reproduces the observed target, largest absolute difference at
  most `anchor_max`.

- `rho_fallback`:

  How often `rho` was forced to `rho_fallback` rather than drawn, at
  most `fallback_max` of the draws per series. An
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  fit.

- `parameters`:

  The smallest effective sample size among the identified parameters, at
  least `param_ess_min`.

- `exact`:

  With `exact`, the chain's latest nowcast differs from
  [`mfbdfm_exact()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_exact.md)'s
  by at most `exact_z` joint Monte Carlo errors.

- `unexplained`:

  With `unexplained`, the part of a revision the news decomposition
  leaves unexplained is at most `unexplained_max`.

The default limits follow Vehtari et al. (2021) for ESS and R-hat. The
limit on the Monte Carlo error is a judgement about one-decimal
communication: `mcse_max` of 0.10 means that two runs differ by about
0.14 (one standard deviation).

## References

Vehtari, A., Gelman, A., Simpson, D., Carpenter, B., & Burkner, P.-C.
(2021). Rank-normalization, folding, and localization: An improved R-hat
for assessing convergence of MCMC. *Bayesian Analysis*, 16(2), 667-718.
[doi:10.1214/20-BA1221](https://doi.org/10.1214/20-BA1221)

## See also

[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md)
for every parameter,
[`mfbdfm_exact()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_exact.md).

Other model functions:
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md),
[`mfbdfm_draws`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md),
[`mfbdfm_exact()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_exact.md),
[`mfbdfm_news()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_news.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
set.seed(1)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 200, burn_in = 50)
#> preallocating..
#> simulating posterior distribution..
#> 
  |                                                                            
  |                                                                      |   0%
  |                                                                            
  |=                                                                     |   1%
  |                                                                            
  |=                                                                     |   2%
  |                                                                            
  |==                                                                    |   2%
  |                                                                            
  |==                                                                    |   3%
  |                                                                            
  |===                                                                   |   4%
  |                                                                            
  |===                                                                   |   5%
  |                                                                            
  |====                                                                  |   5%
  |                                                                            
  |====                                                                  |   6%
  |                                                                            
  |=====                                                                 |   7%
  |                                                                            
  |=====                                                                 |   8%
  |                                                                            
  |======                                                                |   8%
  |                                                                            
  |======                                                                |   9%
  |                                                                            
  |=======                                                               |  10%
  |                                                                            
  |========                                                              |  11%
  |                                                                            
  |========                                                              |  12%
  |                                                                            
  |=========                                                             |  12%
  |                                                                            
  |=========                                                             |  13%
  |                                                                            
  |==========                                                            |  14%
  |                                                                            
  |==========                                                            |  15%
  |                                                                            
  |===========                                                           |  15%
  |                                                                            
  |===========                                                           |  16%
  |                                                                            
  |============                                                          |  17%
  |                                                                            
  |============                                                          |  18%
  |                                                                            
  |=============                                                         |  18%
  |                                                                            
  |=============                                                         |  19%
  |                                                                            
  |==============                                                        |  20%
  |                                                                            
  |===============                                                       |  21%
  |                                                                            
  |===============                                                       |  22%
  |                                                                            
  |================                                                      |  22%
  |                                                                            
  |================                                                      |  23%
  |                                                                            
  |=================                                                     |  24%
  |                                                                            
  |=================                                                     |  25%
  |                                                                            
  |==================                                                    |  25%
  |                                                                            
  |==================                                                    |  26%
  |                                                                            
  |===================                                                   |  27%
  |                                                                            
  |===================                                                   |  28%
  |                                                                            
  |====================                                                  |  28%
  |                                                                            
  |====================                                                  |  29%
  |                                                                            
  |=====================                                                 |  30%
  |                                                                            
  |======================                                                |  31%
  |                                                                            
  |======================                                                |  32%
  |                                                                            
  |=======================                                               |  32%
  |                                                                            
  |=======================                                               |  33%
  |                                                                            
  |========================                                              |  34%
  |                                                                            
  |========================                                              |  35%
  |                                                                            
  |=========================                                             |  35%
  |                                                                            
  |=========================                                             |  36%
  |                                                                            
  |==========================                                            |  37%
  |                                                                            
  |==========================                                            |  38%
  |                                                                            
  |===========================                                           |  38%
  |                                                                            
  |===========================                                           |  39%
  |                                                                            
  |============================                                          |  40%
  |                                                                            
  |=============================                                         |  41%
  |                                                                            
  |=============================                                         |  42%
  |                                                                            
  |==============================                                        |  42%
  |                                                                            
  |==============================                                        |  43%
  |                                                                            
  |===============================                                       |  44%
  |                                                                            
  |===============================                                       |  45%
  |                                                                            
  |================================                                      |  45%
  |                                                                            
  |================================                                      |  46%
  |                                                                            
  |=================================                                     |  47%
  |                                                                            
  |=================================                                     |  48%
  |                                                                            
  |==================================                                    |  48%
  |                                                                            
  |==================================                                    |  49%
  |                                                                            
  |===================================                                   |  50%
  |                                                                            
  |====================================                                  |  51%
  |                                                                            
  |====================================                                  |  52%
  |                                                                            
  |=====================================                                 |  52%
  |                                                                            
  |=====================================                                 |  53%
  |                                                                            
  |======================================                                |  54%
  |                                                                            
  |======================================                                |  55%
  |                                                                            
  |=======================================                               |  55%
  |                                                                            
  |=======================================                               |  56%
  |                                                                            
  |========================================                              |  57%
  |                                                                            
  |========================================                              |  58%
  |                                                                            
  |=========================================                             |  58%
  |                                                                            
  |=========================================                             |  59%
  |                                                                            
  |==========================================                            |  60%
  |                                                                            
  |===========================================                           |  61%
  |                                                                            
  |===========================================                           |  62%
  |                                                                            
  |============================================                          |  62%
  |                                                                            
  |============================================                          |  63%
  |                                                                            
  |=============================================                         |  64%
  |                                                                            
  |=============================================                         |  65%
  |                                                                            
  |==============================================                        |  65%
  |                                                                            
  |==============================================                        |  66%
  |                                                                            
  |===============================================                       |  67%
  |                                                                            
  |===============================================                       |  68%
  |                                                                            
  |================================================                      |  68%
  |                                                                            
  |================================================                      |  69%
  |                                                                            
  |=================================================                     |  70%
  |                                                                            
  |==================================================                    |  71%
  |                                                                            
  |==================================================                    |  72%
  |                                                                            
  |===================================================                   |  72%
  |                                                                            
  |===================================================                   |  73%
  |                                                                            
  |====================================================                  |  74%
  |                                                                            
  |====================================================                  |  75%
  |                                                                            
  |=====================================================                 |  75%
  |                                                                            
  |=====================================================                 |  76%
  |                                                                            
  |======================================================                |  77%
  |                                                                            
  |======================================================                |  78%
  |                                                                            
  |=======================================================               |  78%
  |                                                                            
  |=======================================================               |  79%
  |                                                                            
  |========================================================              |  80%
  |                                                                            
  |=========================================================             |  81%
  |                                                                            
  |=========================================================             |  82%
  |                                                                            
  |==========================================================            |  82%
  |                                                                            
  |==========================================================            |  83%
  |                                                                            
  |===========================================================           |  84%
  |                                                                            
  |===========================================================           |  85%
  |                                                                            
  |============================================================          |  85%
  |                                                                            
  |============================================================          |  86%
  |                                                                            
  |=============================================================         |  87%
  |                                                                            
  |=============================================================         |  88%
  |                                                                            
  |==============================================================        |  88%
  |                                                                            
  |==============================================================        |  89%
  |                                                                            
  |===============================================================       |  90%
  |                                                                            
  |================================================================      |  91%
  |                                                                            
  |================================================================      |  92%
  |                                                                            
  |=================================================================     |  92%
  |                                                                            
  |=================================================================     |  93%
  |                                                                            
  |==================================================================    |  94%
  |                                                                            
  |==================================================================    |  95%
  |                                                                            
  |===================================================================   |  95%
  |                                                                            
  |===================================================================   |  96%
  |                                                                            
  |====================================================================  |  97%
  |                                                                            
  |====================================================================  |  98%
  |                                                                            
  |===================================================================== |  98%
  |                                                                            
  |===================================================================== |  99%
  |                                                                            
  |======================================================================| 100%
#> processing output..
q <- mfbdfm_quality(fit)
q
#> Quality checks: FAIL 
#>   FAIL latest nowcast: ess               75.33   limit 400
#>   FAIL latest nowcast: mcse             0.3891   limit 0.1
#>   ok   latest nowcast: rhat             0.9961   limit 1.01
#>   FAIL latest week: ess                  94.15   limit 400
#>   FAIL latest week: mcse                0.8263   limit 0.1
#>   ok   latest week: rhat                 1.006   limit 1.01
#>   FAIL latest 13 weeks: ess              61.17   limit 400
#>   FAIL latest 13 weeks: mcse            0.5797   limit 0.1
#>   ok   latest 13 weeks: rhat            0.9951   limit 1.01
#>   ok   anchor                        8.689e-08   limit 0.001
#>   ok   rho_fallback                          0   limit 0.01
#>   FAIL parameters: smallest ess          3.502   limit 100
attr(q, "pass")
#> [1] FALSE
# }
```
