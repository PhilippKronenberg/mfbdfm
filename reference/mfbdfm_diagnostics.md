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

A low-frequency series observed an even number of periods apart
identifies its weekly `rho` only through even powers, so `rho[...]` is
reported and not judged. The rows `rho_obs[...]` (`rho^gap`, the error's
autocorrelation from one observation to the next) and `innovation[...]`
(its variance from one observation to the next) are what the data
identify, and are judged as usual.

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
[`mfbdfm_draws`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md),
[`mfbdfm_exact()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_exact.md),
[`mfbdfm_news()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_news.md),
[`mfbdfm_quality()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_quality.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
set.seed(1)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 120, burn_in = 30)
#> preallocating..
#> simulating posterior distribution..
#> 
  |                                                                            
  |                                                                      |   0%
  |                                                                            
  |                                                                      |   1%
  |                                                                            
  |=                                                                     |   1%
  |                                                                            
  |=                                                                     |   2%
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
  |======                                                                |   8%
  |                                                                            
  |======                                                                |   9%
  |                                                                            
  |=======                                                               |   9%
  |                                                                            
  |=======                                                               |  10%
  |                                                                            
  |=======                                                               |  11%
  |                                                                            
  |========                                                              |  11%
  |                                                                            
  |========                                                              |  12%
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
  |=============                                                         |  18%
  |                                                                            
  |=============                                                         |  19%
  |                                                                            
  |==============                                                        |  19%
  |                                                                            
  |==============                                                        |  20%
  |                                                                            
  |==============                                                        |  21%
  |                                                                            
  |===============                                                       |  21%
  |                                                                            
  |===============                                                       |  22%
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
  |====================                                                  |  28%
  |                                                                            
  |====================                                                  |  29%
  |                                                                            
  |=====================                                                 |  29%
  |                                                                            
  |=====================                                                 |  30%
  |                                                                            
  |=====================                                                 |  31%
  |                                                                            
  |======================                                                |  31%
  |                                                                            
  |======================                                                |  32%
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
  |===========================                                           |  38%
  |                                                                            
  |===========================                                           |  39%
  |                                                                            
  |============================                                          |  39%
  |                                                                            
  |============================                                          |  40%
  |                                                                            
  |============================                                          |  41%
  |                                                                            
  |=============================                                         |  41%
  |                                                                            
  |=============================                                         |  42%
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
  |==================================                                    |  48%
  |                                                                            
  |==================================                                    |  49%
  |                                                                            
  |===================================                                   |  49%
  |                                                                            
  |===================================                                   |  50%
  |                                                                            
  |===================================                                   |  51%
  |                                                                            
  |====================================                                  |  51%
  |                                                                            
  |====================================                                  |  52%
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
  |=========================================                             |  58%
  |                                                                            
  |=========================================                             |  59%
  |                                                                            
  |==========================================                            |  59%
  |                                                                            
  |==========================================                            |  60%
  |                                                                            
  |==========================================                            |  61%
  |                                                                            
  |===========================================                           |  61%
  |                                                                            
  |===========================================                           |  62%
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
  |================================================                      |  68%
  |                                                                            
  |================================================                      |  69%
  |                                                                            
  |=================================================                     |  69%
  |                                                                            
  |=================================================                     |  70%
  |                                                                            
  |=================================================                     |  71%
  |                                                                            
  |==================================================                    |  71%
  |                                                                            
  |==================================================                    |  72%
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
  |=======================================================               |  78%
  |                                                                            
  |=======================================================               |  79%
  |                                                                            
  |========================================================              |  79%
  |                                                                            
  |========================================================              |  80%
  |                                                                            
  |========================================================              |  81%
  |                                                                            
  |=========================================================             |  81%
  |                                                                            
  |=========================================================             |  82%
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
  |==============================================================        |  88%
  |                                                                            
  |==============================================================        |  89%
  |                                                                            
  |===============================================================       |  89%
  |                                                                            
  |===============================================================       |  90%
  |                                                                            
  |===============================================================       |  91%
  |                                                                            
  |================================================================      |  91%
  |                                                                            
  |================================================================      |  92%
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
  |===================================================================== |  98%
  |                                                                            
  |===================================================================== |  99%
  |                                                                            
  |======================================================================|  99%
  |                                                                            
  |======================================================================| 100%
#> processing output..

d <- mfbdfm_diagnostics(fit)
d
#> MCMC convergence diagnostics for a ind_dfm fit
#>   (single chain: effective sample size and Geweke z, no R-hat)
#> 
#>   draws          : 120
#>   parameters     : 34
#>   tested         : 30  (1 constant, not drawn)
#>   flagged        : 15  (|geweke z| > 1.96 or ESS < 100)
#>   min ESS        : 1.4
#>   max |geweke z| : 8.84
#> 
#> Flagged parameters:
#> 
#>   parameter                           ess   geweke z   geweke p
#>   sigma[Arbeitsmarkt]                 1.4       8.84      0.000
#>   rho[Arbeitsmarkt]                   1.6      -4.45      0.000
#>   lambda[Arbeitsmarkt]                2.9      -6.64      0.000
#>   h_mean                              4.3       4.99      0.000
#>   lambda[traffic_PW]                  5.4       5.81      0.000
#>   sigma[traffic_PW]                  25.5      -5.00      0.000
#>   sigma[ch.seco.gdp.real.gdp.s       48.3       0.73      0.468
#>   omega                              49.6      -0.26      0.792
#>   rho[traffic_PW]                    54.1      -1.90      0.057
#>   lambda[SWISSMI]                    58.5      -0.97      0.330
#>   ... and 5 more
#> 
#> A flag is a prompt to look, not a verdict: run a longer chain and
#> inspect plot() of this object before trusting the affected block.
#> 
#> as.data.frame() for the full table; plot() for traces and densities
head(as.data.frame(d))
#>                              parameter  block      mean        sd        ess
#> 1 lambda[ch.fso.rtt.ind.r.noga0801.sa] lambda 0.6774805 0.1662594 120.000000
#> 2     lambda[ch.ozd.e.wa.index.re.d11] lambda 0.6164111 0.1551753 120.000000
#> 3                      lambda[SWISSMI] lambda 1.2038376 0.4071266  58.460212
#> 4                   lambda[traffic_PW] lambda 3.3563466 0.3457008   5.422928
#> 5              lambda[electricity_out] lambda 0.3013594 0.2330802 120.000000
#> 6     lambda[ch.seco.gdp.real.gdp.ssa] lambda 1.0000000 0.0000000         NA
#>     geweke_z     geweke_p    ok     note
#> 1 -0.7435869 4.571264e-01  TRUE         
#> 2  0.2608950 7.941735e-01  TRUE         
#> 3 -0.9738249 3.301435e-01 FALSE         
#> 4  5.8086484 6.297920e-09 FALSE         
#> 5  0.6310556 5.280042e-01  TRUE         
#> 6         NA           NA    NA constant

# the target's loading is fixed at 1 by the identification, so it is
# reported as constant rather than as a convergence failure
subset(as.data.frame(d), note == "constant")
#>                          parameter  block mean sd ess geweke_z geweke_p ok
#> 6 lambda[ch.seco.gdp.real.gdp.ssa] lambda    1  0  NA       NA       NA NA
#>       note
#> 6 constant
# }
```
