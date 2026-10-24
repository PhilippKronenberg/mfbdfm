# Retained posterior draws of a fitted model

The draws both samplers keep internally, returned with the fit instead
of being averaged and discarded. This is what makes convergence
diagnostics
([`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md))
and trace/density plots possible after the fact, and what lets any
posterior functional be computed from the chain rather than from the
stored summaries.

## Usage

``` r
# S3 method for class 'mfbdfm_draws'
print(x, n_show = 8, ...)

# S3 method for class 'mfbdfm_draws'
as.data.frame(x, row.names = NULL, optional = FALSE, which = NULL, ...)

# S3 method for class 'mfbdfm_draws'
as.mcmc(x, which = NULL, ...)

# S3 method for class 'mfbdfm_draws'
plot(
  x,
  which = NULL,
  type = c("both", "trace", "density"),
  level = 0.95,
  max_panels = 12,
  ...
)
```

## Arguments

- x:

  An object of class `"mfbdfm_draws"`, i.e. `fit$draws`.

- n_show:

  Number of column names to list.

- ...:

  Passed on to the underlying plotting calls; ignored otherwise.

- row.names, optional:

  Ignored, present for consistency with the generic.

- which:

  Columns to use; see "Selecting columns". `NULL` (the default) is the
  readable subset.

- type:

  `"both"` (default) for trace and density side by side, as in coda's
  `plot.mcmc`, or `"trace"` / `"density"` for one of them.

- level:

  Coverage of the interval marked on the density, as a probability.

- max_panels:

  Largest number of parameters to draw. A selection larger than this is
  truncated with a warning rather than silently producing an unreadable
  grid.

## Value

[`print()`](https://rdrr.io/r/base/print.html) returns `x` invisibly.
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) returns a
long data frame with columns `parameter`, `iteration`, `value` and
`phase`. `as.mcmc()` returns a coda `mcmc` object with `start`/`thin`
set from the chain.
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) returns a
ggplot object, or a `ggarrange` grid when `type = "both"`.

## Details

A fit carries this in `fit$draws` whenever `keep_draws` is `TRUE`, which
is the default – see
[`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
for `keep_draws`, `keep_factor_draws` and `keep_burn_in`, and for the
memory each costs.

## Structure

- `$parameters`:

  Iterations x parameters matrix. One column per *scalar* parameter,
  named `block[label]`: `lambda[<series>]`, `phi1`...`phip`
  (`phi<lag>[i,j]` for
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)),
  `sigma[<series>]`, `rho[<series>]`, `omega`, and two summaries of the
  volatility path, `h_mean` and `h_last`. The path itself is `t+s` long
  *per draw* and is a latent state rather than a parameter, so it is
  summarised rather than stored in full.

- `$nowcast`:

  Iterations x periods matrix of the target's nowcast draws, at the
  target's own frequency.

- `$factor`:

  Iterations x periods matrix of the factor path (one block of columns
  per factor for
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)),
  on the **same scale as `fit$factor`** – rescaled and annualized for
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  rotated for
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  – so that [`colMeans()`](https://rdrr.io/r/base/colSums.html)
  reproduces it. `NULL` unless `keep_factor_draws = TRUE`, since it is
  the one large component.

- `$info`:

  Chain metadata: `model`, `target`, `blocks`, `length_sample`,
  `burn_in`, `thinning`, `n_burn_in` (leading rows of `$parameters` that
  are burn-in) and the iteration index of each row.

With `stochastic_volatility = FALSE` the volatility columns differ,
because the two models pin the factor's scale in different places (see
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)'s
details and CLAUDE.md, "Scale identification"):
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
reports the single estimated constant variance as `factor_var` and has
no `omega`, while
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
has neither, its variance being *fixed* at one.

## Burn-in

`keep_burn_in = TRUE`
([`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
only) prepends the burn-in draws to `$parameters`, so a trace plot can
show the chain settling. They are **parameter draws only**: the nowcast
and factor draws are derived quantities that the sampler computes for
retained iterations, and computing them for the burn-in as well would
change the cost of a fit for a plotting convenience. Each row's sampler
iteration is recorded in `$info$iteration`, so the two sets are plotted
on a common axis rather than concatenated.

## Selecting columns

`which` accepts column names, block names (`"lambda"`, `"phi"`,
`"sigma"`, `"rho"`, `"omega"`, `"h"`, `"nowcast"`, `"factor"`),
`"parameters"` for every parameter column, `"all"`, or column positions.
The default is a readable subset: the factor VAR coefficients, the
volatility parameter, the three largest loadings and the latest nowcast.

## See also

[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md)
for convergence statistics over these draws,
[`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
for the `keep_*` settings,
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
and
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

Other model functions:
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
set.seed(1)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 60, burn_in = 20)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |=                                                                     |   1%  |                                                                              |==                                                                    |   2%  |                                                                              |===                                                                   |   4%  |                                                                              |====                                                                  |   5%  |                                                                              |====                                                                  |   6%  |                                                                              |=====                                                                 |   8%  |                                                                              |======                                                                |   9%  |                                                                              |=======                                                               |  10%  |                                                                              |========                                                              |  11%  |                                                                              |=========                                                             |  12%  |                                                                              |==========                                                            |  14%  |                                                                              |==========                                                            |  15%  |                                                                              |===========                                                           |  16%  |                                                                              |============                                                          |  18%  |                                                                              |=============                                                         |  19%  |                                                                              |==============                                                        |  20%  |                                                                              |===============                                                       |  21%  |                                                                              |================                                                      |  22%  |                                                                              |=================                                                     |  24%  |                                                                              |==================                                                    |  25%  |                                                                              |==================                                                    |  26%  |                                                                              |===================                                                   |  28%  |                                                                              |====================                                                  |  29%  |                                                                              |=====================                                                 |  30%  |                                                                              |======================                                                |  31%  |                                                                              |=======================                                               |  32%  |                                                                              |========================                                              |  34%  |                                                                              |========================                                              |  35%  |                                                                              |=========================                                             |  36%  |                                                                              |==========================                                            |  38%  |                                                                              |===========================                                           |  39%  |                                                                              |============================                                          |  40%  |                                                                              |=============================                                         |  41%  |                                                                              |==============================                                        |  42%  |                                                                              |===============================                                       |  44%  |                                                                              |================================                                      |  45%  |                                                                              |================================                                      |  46%  |                                                                              |=================================                                     |  48%  |                                                                              |==================================                                    |  49%  |                                                                              |===================================                                   |  50%  |                                                                              |====================================                                  |  51%  |                                                                              |=====================================                                 |  52%  |                                                                              |======================================                                |  54%  |                                                                              |======================================                                |  55%  |                                                                              |=======================================                               |  56%  |                                                                              |========================================                              |  57%  |                                                                              |=========================================                             |  59%  |                                                                              |==========================================                            |  60%  |                                                                              |===========================================                           |  61%  |                                                                              |============================================                          |  62%  |                                                                              |=============================================                         |  64%  |                                                                              |==============================================                        |  65%  |                                                                              |==============================================                        |  66%  |                                                                              |===============================================                       |  68%  |                                                                              |================================================                      |  69%  |                                                                              |=================================================                     |  70%  |                                                                              |==================================================                    |  71%  |                                                                              |===================================================                   |  72%  |                                                                              |====================================================                  |  74%  |                                                                              |====================================================                  |  75%  |                                                                              |=====================================================                 |  76%  |                                                                              |======================================================                |  78%  |                                                                              |=======================================================               |  79%  |                                                                              |========================================================              |  80%  |                                                                              |=========================================================             |  81%  |                                                                              |==========================================================            |  82%  |                                                                              |===========================================================           |  84%  |                                                                              |============================================================          |  85%  |                                                                              |============================================================          |  86%  |                                                                              |=============================================================         |  88%  |                                                                              |==============================================================        |  89%  |                                                                              |===============================================================       |  90%  |                                                                              |================================================================      |  91%  |                                                                              |=================================================================     |  92%  |                                                                              |==================================================================    |  94%  |                                                                              |==================================================================    |  95%  |                                                                              |===================================================================   |  96%  |                                                                              |====================================================================  |  98%  |                                                                              |===================================================================== |  99%  |                                                                              |======================================================================| 100%
#> processing output..

fit$draws
#> Retained posterior draws of a ind_dfm fit
#> 
#>   draws kept      : 60
#>   burn-in         : 20 (discarded)
#>   parameters      : 28
#>   nowcast periods : 45
#>   factor draws    : not kept (keep_factor_draws = FALSE)
#> 
#> Parameter columns:
#> 
#>   lambda[ch.fso.rtt.ind.r.noga0801.sa], lambda[ch.ozd.e.wa.index.re.d11], lambda[SWISSMI], lambda[traffic_PW], lambda[electricity_out], lambda[ch.seco.gdp.real.gdp.ssa], lambda[SWPMIPROQ], lambda[Arbeitsmarkt], ... (20 more)
#> 
#> Blocks: lambda, phi, sigma, rho, omega, h
#> 
#> mfbdfm_diagnostics() for convergence statistics; plot() for traces
#> and posterior densities; as.mcmc() to hand the chain to coda
dim(fit$draws$parameters)
#> [1] 60 28

# the stored means are the means of the retained draws
max(abs(colMeans(fit$draws$parameters[, 1:8]) -
          as.numeric(fit$pars$lambda)[1:8]))
#> [1] 3.330669e-16

head(as.data.frame(fit$draws, which = "phi"))
#>   parameter iteration     value    phase
#> 1      phi1        21 0.8012045 sampling
#> 2      phi1        22 0.7835176 sampling
#> 3      phi1        23 0.8157791 sampling
#> 4      phi1        24 0.7841856 sampling
#> 5      phi1        25 0.7643328 sampling
#> 6      phi1        26 0.7918949 sampling
# }
```
