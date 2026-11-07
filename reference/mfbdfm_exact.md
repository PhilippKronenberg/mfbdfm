# Exact estimate of the factor and the nowcast over stored parameter draws

Replaces the sampled factor and nowcast paths in a posterior average by
exact conditional calculations at a set of the chain's retained
parameter draws. The parameter draws still come from the chain, so this
removes the simulation noise of the latent paths and not any error in
the distribution of the parameters.

## Usage

``` r
mfbdfm_exact(fit, n_draws = 100, paths = 20, seed = NULL)

# S3 method for class 'mfbdfm_exact'
print(x, ...)
```

## Arguments

- fit:

  A fitted
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  model carrying its draws, the default. A fit made before this function
  existed holds no volatility paths and is refused.

- n_draws:

  Whole number, how many parameter draws to use, evenly spaced along the
  chain. At most the 200 stored.

- paths:

  Even whole number, simulated factor paths per parameter draw.

- seed:

  Optional whole number, for reproducible simulated paths. The caller's
  random stream is restored afterwards.

- x:

  An object from `mfbdfm_exact()`.

- ...:

  Ignored.

## Value

An object of class `"mfbdfm_exact"`, a list with `factor`, `factor_var`,
`index`, `nowcast` and `nowcast_var`, on the scales and date axes of the
same components of `fit`, and `nowcast_between` (the conditional means,
one row per selected draw), `nowcast_within` (the conditional variances,
same shape, which with `nowcast_between` give the nowcast's predictive
density as a mixture of normals), `mcse_nowcast`, `n_draws` and `paths`.

## Details

For each selected draw of the parameters and the volatility path, the
latent data and the factor given the observations are jointly Gaussian
with a sparse precision matrix. The nowcast is linear in them, so its
conditional mean comes from one solve, with no simulation. The published
factor is a nonlinear function of the standardised one, so its mean and
variance use `paths` draws from that Gaussian, in antithetic pairs.

Total variances combine the two parts:
`Var = E[Var(. | parameters)] + Var(E[. | parameters])`. The first is
what a chain has to simulate and the second is what is left to estimate
from parameter draws. `mcse_nowcast` is the Monte Carlo error of the
nowcast from the second part alone, treating the selected draws as
independent, which the even spacing along the chain makes roughly true
for a chain that mixes.

Applies to
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
only. A
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit identifies its factors after sampling, so its draws are not
comparable before that step.

Takes about 1 to 2 seconds per selected draw on a 46-series weekly
panel.

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`mfbdfm_quality()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_quality.md),
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md).

Other model functions:
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md),
[`mfbdfm_draws`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md),
[`mfbdfm_news()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_news.md),
[`mfbdfm_quality()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_quality.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
set.seed(1)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 100, burn_in = 20)
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
  |=======================================                               |  56%
  |                                                                            
  |========================================                              |  57%
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
ex <- mfbdfm_exact(fit, n_draws = 5, paths = 4)
ex
#> Exact estimate over 5 parameter draws, 4 factor paths each
#>   latest nowcast : 0.00077 (sd 0.00635, Monte Carlo error 0.00038)
#>   latest factor  : 9.736 (sd 12.440)
utils::tail(ex$nowcast, 2)
#>              Qtr1 Qtr2 Qtr3         Qtr4
#> 2025                        0.0015062510
#> 2026 0.0007660439                       
# }
```
