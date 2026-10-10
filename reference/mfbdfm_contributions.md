# Contribution of each input series to the factor and to the nowcast

Decomposes the smoothed factor path, and the nowcast of the fit's
`target`, into the contribution of each input series (or of each group
of series) in every period. Answers "which series drive the factor, and
by how much, when?"

## Usage

``` r
mfbdfm_contributions(fit, by = c("series", "group"), groups = NULL)

# S3 method for class 'mfbdfm_contributions'
print(x, n_show = 10, ...)

# S3 method for class 'mfbdfm_contributions'
as.data.frame(
  x,
  row.names = NULL,
  optional = FALSE,
  what = c("factor", "nowcast"),
  ...
)

# S3 method for class 'mfbdfm_contributions'
plot(x, what = c("factor", "nowcast"), factor = 1, ...)
```

## Arguments

- fit:

  A fitted model from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  or
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- by:

  Either `"series"` (default, one component per input series) or
  `"group"` (one component per group of series).

- groups:

  Optional named character vector or list mapping every series name to a
  group name, used when `by = "group"` and the inventory has no `group`
  or `category` column. Ignored when `by = "series"`.

- x:

  An object of class `"mfbdfm_contributions"`.

- n_show:

  Number of components to list, ordered by mean absolute contribution.

- ...:

  Passed on to the underlying plotting calls; ignored by
  [`print()`](https://rdrr.io/r/base/print.html) and
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html).

- row.names, optional:

  Ignored, present for consistency with the generic.

- what:

  Either `"factor"` (default) for contributions to the factor path or
  `"nowcast"` for contributions to the target's nowcast.

- factor:

  Which factor to plot, as an index into `1:q`. Only relevant for a
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  fit with `q > 1`.

## Value

An object of class `"mfbdfm_contributions"`, a list with

- contributions:

  Long data frame of contributions to the factor: `time`, the component
  column (named `series` or `group` after `by`), `factor` and
  `contribution`.

- totals:

  Data frame of `time`, `factor`, `plugin`, `posterior` and `residual`.

- nowcast:

  Long data frame of contributions to the target's nowcast, at the
  target's own frequency: `time`, the component column, `contribution`.

- nowcast_totals:

  Data frame of `time`, `systematic`, `idiosyncratic`, `plugin`,
  `posterior` and `residual`.

- by, components, target, q, model, call:

  Metadata.

With [`print()`](https://rdrr.io/r/base/print.html),
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) and
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) methods.

## Details

The decomposition is the smoother's own. Conditional on the posterior
mean parameters and volatility path, the posterior mean of the factor
path is a linear function of the observed data, `E[f | y, theta] = W y`,
and summing the columns of `W` that belong to one series gives that
series' contribution. It is exact: the contributions sum to
`E[f | y, theta]` to numerical tolerance, a series whose loading is zero
contributes zero, and an observation carries weight in a period even
when the series was not observed in it – which is the whole point, and
is why "loading times standardised series" is not an answer to this
question. That product is the series' reconstruction *from* the factor
and does not sum to anything.

Everything is reported on the **standardised, non-annualised scale the
sampler works on**, which is the scale on which the decomposition is
linear. `$factor` on an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit is de-standardised and annualised through
`((1 + f)^frequency - 1) * 100`; that transformation is not linear, so
contributions to it do not exist. `totals$posterior` maps the fit's own
posterior mean back to the sampler's scale so that the two are
comparable.

### The residual term

`E[f | y, theta-hat]` is not the same thing as the MCMC posterior mean
factor, which averages over the posterior of `theta` rather than
plugging in its mean. The difference is reported rather than hidden:
`totals` carries `plugin` (the sum of the contributions), `posterior`
(the fit's own posterior mean, mapped to the same scale) and
`residual = posterior - plugin`. Read `residual` as parameter
uncertainty. It shrinks as the chain lengthens and as the sample grows;
on a short chain over a couple of years it is not small, and a
decomposition whose residual dominates should not be read as if it
explained the factor.

### Contributions to the nowcast

The target's value in period `i` is the aggregated factor plus its own
measurement error, `x[i] = sum(L[sx] * lambda' f[i - sx]) + u[i]`, so
the factor contributions are carried through the target's loading and
the model's own distributed-lag aggregation weights `L`.
`nowcast_totals` splits the nowcast into `systematic` (the sum of those
contributions) and `idiosyncratic` (`E[x | y, theta-hat]` minus the
systematic part, i.e. the measurement error the smoother attributes to
the target itself). Where the target was actually observed, `E[x | y]`
is the observation, and the idiosyncratic term absorbs whatever the
factor does not explain.

### Both classes

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
gets one decomposition per factor. No extra rotation is needed:
`run_rotation_fcast()` and `run_identification_fcast()` rotate the draws
themselves, so the stored posterior mean `lambda` and `phi` are already
in the identified orientation and `W` is built from them.

The reported time axis covers all `t+s` periods of the factor path,
including the `s` pre-sample periods the distributed lags carry.
`totals$posterior` is read from `$factor` for a
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit and from `$factor_std` for an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit, both on the sampler's scale over all `t+s` periods. (An
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit saved before `$factor_std` existed falls back to inverting the
annualised `$factor`, which leaves the pre-sample periods `NA`.)

## References

Kronenberg, P. (2026). A weekly activity index for Switzerland. *Swiss
Journal of Economics and Statistics*, 162:10.
[doi:10.1186/s41937-026-00157-w](https://doi.org/10.1186/s41937-026-00157-w)

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)

Other model functions:
[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md),
[`mfbdfm_draws`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
fit <- ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                              stats::window, start = 2021),
               stocks = lapply(data_ch_dataset_test$stocks[1:2],
                               stats::window, start = 2021),
               target = target, length_sample = 20, burn_in = 5,
               plots = FALSE)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..

ct <- mfbdfm_contributions(fit)
ct
#> Contributions to the factor and nowcast of a ind_dfm fit
#> Call: mfbdfm_contributions(fit = fit)
#> 
#>   by         : series
#>   components : 4
#>   factors    : 1
#>   periods    : 272
#>   target     : ch.seco.gdp.real.gdp.ssa
#> 
#> Mean absolute contribution to the factor (standardized scale):
#> 
#>   ch.seco.gdp.real.gdp.ssa                      0.05430
#>   SWPROPRCE                                     0.00108
#>   SWCONPRCE                                     0.00080
#>   SWISSMI                                       0.00062
#> 
#> Mean |residual| (parameter uncertainty, not explained by any series): 0.032
#> 
#> Full results: $contributions, $totals, $nowcast, $nowcast_totals;
#> as.data.frame(), plot()
head(as.data.frame(ct))
#>       time                   series  factor  contribution
#> 1 2020.542 ch.seco.gdp.real.gdp.ssa factor1 -0.0005584833
#> 2 2020.562 ch.seco.gdp.real.gdp.ssa factor1 -0.0011443835
#> 3 2020.583 ch.seco.gdp.real.gdp.ssa factor1 -0.0017864633
#> 4 2020.604 ch.seco.gdp.real.gdp.ssa factor1 -0.0025162433
#> 5 2020.625 ch.seco.gdp.real.gdp.ssa factor1 -0.0033695497
#> 6 2020.646 ch.seco.gdp.real.gdp.ssa factor1 -0.0043882726

# the contributions add up to the smoothed factor, by construction
agg <- tapply(as.data.frame(ct)$contribution, as.data.frame(ct)$time, sum)
max(abs(agg - ct$totals$plugin))
#> [1] 0

# by group, with a user-supplied mapping
grp <- c(rep("real", 2), rep("financial", nrow(fit$inventory) - 2))
names(grp) <- fit$inventory$key
mfbdfm_contributions(fit, by = "group", groups = grp)
#> Contributions to the factor and nowcast of a ind_dfm fit
#> Call: mfbdfm_contributions(fit = fit, by = "group", groups = grp)
#> 
#>   by         : group
#>   components : 2
#>   factors    : 1
#>   periods    : 272
#>   target     : ch.seco.gdp.real.gdp.ssa
#> 
#> Mean absolute contribution to the factor (standardized scale):
#> 
#>   real                                          0.05428
#>   financial                                     0.00156
#> 
#> Mean |residual| (parameter uncertainty, not explained by any series): 0.032
#> 
#> Full results: $contributions, $totals, $nowcast, $nowcast_totals;
#> as.data.frame(), plot()
# }
```
