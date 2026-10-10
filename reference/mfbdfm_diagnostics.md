# MCMC convergence diagnostics for a fitted model

Effective sample size, the Geweke (1992) convergence z-score and – on
request – the Heidelberger & Welch (1983) stationarity test, for every
retained parameter draw of an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
or
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit.

## Usage

``` r
mfbdfm_diagnostics(
  x,
  which = "parameters",
  heidel = FALSE,
  ess_min = 100,
  geweke_crit = 1.96
)

# S3 method for class 'mfbdfm_diagnostics'
print(x, n_show = 10, ...)

# S3 method for class 'mfbdfm_diagnostics'
plot(x, which = NULL, ...)
```

## Arguments

- x:

  A fitted model from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  or
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
  or the `fit$draws` object itself.

- which:

  Columns to diagnose. Defaults to `"parameters"`, every parameter
  column; see
  [mfbdfm_draws](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)
  for the accepted forms. `"all"` adds the nowcast (and, if kept,
  factor) draws, which can be hundreds of columns.

- heidel:

  Logical, add the Heidelberger-Welch columns.

- ess_min:

  Numeric, effective sample size below which a parameter is flagged.

- geweke_crit:

  Numeric, absolute Geweke z-score above which a parameter is flagged.

- n_show:

  Number of flagged parameters to list.

- ...:

  Passed on to the underlying plotting calls; ignored by
  [`print()`](https://rdrr.io/r/base/print.html).

## Value

A data frame of class `"mfbdfm_diagnostics"`, one row per parameter,
with columns `parameter`, `block`, `mean`, `sd`, `ess`, `geweke_z`,
`geweke_p`, (optionally `heidel_stationary`, `heidel_p`,
`heidel_halfwidth`), `ok` and `note`. The draws it was computed from are
attached, so [`plot()`](https://rdrr.io/r/graphics/plot.default.html) on
the result draws the traces of whatever failed.

## Details

Requires the fit to carry its draws, which it does by default; see
[`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)'s
`keep_draws` and
[mfbdfm_draws](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)
for the container.

## The statistics

- `ess`:

  Effective sample size,
  [`coda::effectiveSize()`](https://rdrr.io/pkg/coda/man/effectiveSize.html):
  the number of independent draws the autocorrelated chain is worth.
  Small relative to the number of draws means slow mixing, not
  necessarily non-convergence.

- `geweke_z`:

  [`coda::geweke.diag()`](https://rdrr.io/pkg/coda/man/geweke.diag.html):
  a z-test that the mean of the first 10% of the chain equals the mean
  of the last 50%. Large absolute values indicate the chain was still
  moving.

- `heidel_*`:

  [`coda::heidel.diag()`](https://rdrr.io/pkg/coda/man/heidel.diag.html)'s
  stationarity test and half-width accuracy test, under `heidel = TRUE`.

A row fails – `ok` is `FALSE` – when `abs(geweke_z) > geweke_crit` or
`ess < ess_min`. Both thresholds are arguments: the defaults are the
usual rules of thumb, not properties of this model.

## Single chain

Both samplers run **one** chain, so there is no R-hat here: the
between-chain variance it is built from does not exist. The diagnostics
offered are the single-chain ones. Running several chains from different
seeds and comparing them is possible today – fit twice and compare – but
is not something the fit object represents, so R-hat is deliberately
absent rather than computed from one chain and quietly meaningless.

## Constant chains are reported, not failed

A parameter that was never drawn has zero variance, and no convergence
statistic is defined for it. Those rows carry `NA` statistics,
`note = "constant"` and `ok = NA`, and are left out of the failure
count. This is a normal outcome here rather than an edge case:
`lambda[target]` is fixed at 1 by
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)'s
identifying restriction, `rho` is held at `1e-9` when
`serial_correlation = FALSE`, and the volatility parameters do not exist
when `stochastic_volatility = FALSE`.

## References

Geweke, J. (1992). Evaluating the accuracy of sampling-based approaches
to the calculation of posterior moments. In *Bayesian Statistics 4*,
169-193. Oxford University Press.

Heidelberger, P., & Welch, P. D. (1983). Simulation run length control
in the presence of an initial transient. *Operations Research*, 31(6),
1109-1144.
[doi:10.1287/opre.31.6.1109](https://doi.org/10.1287/opre.31.6.1109)

## See also

[mfbdfm_draws](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)
for the draws themselves and their trace/density plots,
[`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
for `keep_draws`,
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

Other model functions:
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
[`mfbdfm_draws`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
set.seed(1)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 120, burn_in = 30)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |                                                                      |   1%  |                                                                              |=                                                                     |   1%  |                                                                              |=                                                                     |   2%  |                                                                              |==                                                                    |   3%  |                                                                              |===                                                                   |   4%  |                                                                              |===                                                                   |   5%  |                                                                              |====                                                                  |   5%  |                                                                              |====                                                                  |   6%  |                                                                              |=====                                                                 |   7%  |                                                                              |======                                                                |   8%  |                                                                              |======                                                                |   9%  |                                                                              |=======                                                               |   9%  |                                                                              |=======                                                               |  10%  |                                                                              |=======                                                               |  11%  |                                                                              |========                                                              |  11%  |                                                                              |========                                                              |  12%  |                                                                              |=========                                                             |  13%  |                                                                              |==========                                                            |  14%  |                                                                              |==========                                                            |  15%  |                                                                              |===========                                                           |  15%  |                                                                              |===========                                                           |  16%  |                                                                              |============                                                          |  17%  |                                                                              |=============                                                         |  18%  |                                                                              |=============                                                         |  19%  |                                                                              |==============                                                        |  19%  |                                                                              |==============                                                        |  20%  |                                                                              |==============                                                        |  21%  |                                                                              |===============                                                       |  21%  |                                                                              |===============                                                       |  22%  |                                                                              |================                                                      |  23%  |                                                                              |=================                                                     |  24%  |                                                                              |=================                                                     |  25%  |                                                                              |==================                                                    |  25%  |                                                                              |==================                                                    |  26%  |                                                                              |===================                                                   |  27%  |                                                                              |====================                                                  |  28%  |                                                                              |====================                                                  |  29%  |                                                                              |=====================                                                 |  29%  |                                                                              |=====================                                                 |  30%  |                                                                              |=====================                                                 |  31%  |                                                                              |======================                                                |  31%  |                                                                              |======================                                                |  32%  |                                                                              |=======================                                               |  33%  |                                                                              |========================                                              |  34%  |                                                                              |========================                                              |  35%  |                                                                              |=========================                                             |  35%  |                                                                              |=========================                                             |  36%  |                                                                              |==========================                                            |  37%  |                                                                              |===========================                                           |  38%  |                                                                              |===========================                                           |  39%  |                                                                              |============================                                          |  39%  |                                                                              |============================                                          |  40%  |                                                                              |============================                                          |  41%  |                                                                              |=============================                                         |  41%  |                                                                              |=============================                                         |  42%  |                                                                              |==============================                                        |  43%  |                                                                              |===============================                                       |  44%  |                                                                              |===============================                                       |  45%  |                                                                              |================================                                      |  45%  |                                                                              |================================                                      |  46%  |                                                                              |=================================                                     |  47%  |                                                                              |==================================                                    |  48%  |                                                                              |==================================                                    |  49%  |                                                                              |===================================                                   |  49%  |                                                                              |===================================                                   |  50%  |                                                                              |===================================                                   |  51%  |                                                                              |====================================                                  |  51%  |                                                                              |====================================                                  |  52%  |                                                                              |=====================================                                 |  53%  |                                                                              |======================================                                |  54%  |                                                                              |======================================                                |  55%  |                                                                              |=======================================                               |  55%  |                                                                              |=======================================                               |  56%  |                                                                              |========================================                              |  57%  |                                                                              |=========================================                             |  58%  |                                                                              |=========================================                             |  59%  |                                                                              |==========================================                            |  59%  |                                                                              |==========================================                            |  60%  |                                                                              |==========================================                            |  61%  |                                                                              |===========================================                           |  61%  |                                                                              |===========================================                           |  62%  |                                                                              |============================================                          |  63%  |                                                                              |=============================================                         |  64%  |                                                                              |=============================================                         |  65%  |                                                                              |==============================================                        |  65%  |                                                                              |==============================================                        |  66%  |                                                                              |===============================================                       |  67%  |                                                                              |================================================                      |  68%  |                                                                              |================================================                      |  69%  |                                                                              |=================================================                     |  69%  |                                                                              |=================================================                     |  70%  |                                                                              |=================================================                     |  71%  |                                                                              |==================================================                    |  71%  |                                                                              |==================================================                    |  72%  |                                                                              |===================================================                   |  73%  |                                                                              |====================================================                  |  74%  |                                                                              |====================================================                  |  75%  |                                                                              |=====================================================                 |  75%  |                                                                              |=====================================================                 |  76%  |                                                                              |======================================================                |  77%  |                                                                              |=======================================================               |  78%  |                                                                              |=======================================================               |  79%  |                                                                              |========================================================              |  79%  |                                                                              |========================================================              |  80%  |                                                                              |========================================================              |  81%  |                                                                              |=========================================================             |  81%  |                                                                              |=========================================================             |  82%  |                                                                              |==========================================================            |  83%  |                                                                              |===========================================================           |  84%  |                                                                              |===========================================================           |  85%  |                                                                              |============================================================          |  85%  |                                                                              |============================================================          |  86%  |                                                                              |=============================================================         |  87%  |                                                                              |==============================================================        |  88%  |                                                                              |==============================================================        |  89%  |                                                                              |===============================================================       |  89%  |                                                                              |===============================================================       |  90%  |                                                                              |===============================================================       |  91%  |                                                                              |================================================================      |  91%  |                                                                              |================================================================      |  92%  |                                                                              |=================================================================     |  93%  |                                                                              |==================================================================    |  94%  |                                                                              |==================================================================    |  95%  |                                                                              |===================================================================   |  95%  |                                                                              |===================================================================   |  96%  |                                                                              |====================================================================  |  97%  |                                                                              |===================================================================== |  98%  |                                                                              |===================================================================== |  99%  |                                                                              |======================================================================|  99%  |                                                                              |======================================================================| 100%
#> processing output..

d <- mfbdfm_diagnostics(fit)
d
#> MCMC convergence diagnostics for a ind_dfm fit
#>   (single chain: effective sample size and Geweke z, no R-hat)
#> 
#>   draws          : 120
#>   parameters     : 28
#>   tested         : 27  (1 constant, not drawn)
#>   flagged        : 20  (|geweke z| > 1.96 or ESS < 100)
#>   min ESS        : 2.4
#>   max |geweke z| : 8.45
#> 
#> Flagged parameters:
#> 
#>   parameter                           ess   geweke z   geweke p
#>   rho[ch.fso.rtt.ind.r.noga080        2.4       0.37      0.714
#>   rho[ch.ozd.e.wa.index.re.d11        9.4      -0.03      0.978
#>   lambda[Arbeitsmarkt]               12.3      -4.06      0.000
#>   sigma[ch.fso.rtt.ind.r.noga0       15.3      -1.67      0.095
#>   lambda[traffic_PW]                 15.6      -8.45      0.000
#>   lambda[ch.ozd.e.wa.index.re.       17.0      -1.52      0.127
#>   sigma[SWPMIPROQ]                   17.0       2.49      0.013
#>   lambda[ch.fso.rtt.ind.r.noga       17.4      -0.06      0.951
#>   sigma[ch.seco.gdp.real.gdp.s       21.0       1.54      0.123
#>   h_mean                             23.3       0.18      0.858
#>   ... and 10 more
#> 
#> A flag is a prompt to look, not a verdict: run a longer chain and
#> inspect plot() of this object before trusting the affected block.
#> 
#> as.data.frame() for the full table; plot() for traces and densities
head(as.data.frame(d))
#>                              parameter  block        mean        sd       ess
#> 1 lambda[ch.fso.rtt.ind.r.noga0801.sa] lambda -0.05864951 0.2107075  17.43684
#> 2     lambda[ch.ozd.e.wa.index.re.d11] lambda  0.59118095 0.1807192  16.96502
#> 3                      lambda[SWISSMI] lambda  0.05736548 0.1579083  47.60082
#> 4                   lambda[traffic_PW] lambda  0.61490223 0.1769202  15.64151
#> 5              lambda[electricity_out] lambda  0.19235833 0.1742932 110.23961
#> 6     lambda[ch.seco.gdp.real.gdp.ssa] lambda  1.00000000 0.0000000        NA
#>      geweke_z     geweke_p    ok     note
#> 1 -0.06197664 9.505814e-01 FALSE         
#> 2 -1.52496457 1.272679e-01 FALSE         
#> 3 -1.80905640 7.044224e-02 FALSE         
#> 4 -8.44699452 2.988978e-17 FALSE         
#> 5  0.51518805 6.064216e-01  TRUE         
#> 6          NA           NA    NA constant

# the target's loading is fixed at 1 by the identification, so it is
# reported as constant rather than as a convergence failure
subset(as.data.frame(d), note == "constant")
#>                          parameter  block mean sd ess geweke_z geweke_p ok
#> 6 lambda[ch.seco.gdp.real.gdp.ssa] lambda    1  0  NA       NA       NA NA
#>       note
#> 6 constant
# }
```
