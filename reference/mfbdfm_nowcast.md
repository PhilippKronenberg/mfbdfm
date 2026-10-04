# Extract the nowcasts from a model fit

The accessor for the nowcasts of the target series, for fits from either
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
or
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).
The nowcasts are computed while the model is fitted and stored in the
fit object; this returns them as a data frame, with the posterior
standard deviation and a credible band where the fit records the nowcast
variance.

## Usage

``` r
mfbdfm_nowcast(object, last = FALSE, level = 0.95, ...)

# S3 method for class 'ind_dfm'
mfbdfm_nowcast(object, last = FALSE, level = 0.95, ...)

# S3 method for class 'fcast_dfm'
mfbdfm_nowcast(object, last = FALSE, level = 0.95, ...)
```

## Arguments

- object:

  A fit from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  or
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- last:

  Logical. If `TRUE`, only the most recent period is returned (one row)
  – the usual real-time query. Defaults to `FALSE`, the whole path.

- level:

  Numeric in `(0, 1)`, the width of the credible interval reported in
  `lower`/`upper`. Defaults to `0.95`.

- ...:

  Ignored, present for compatibility with the generic.

## Value

A data frame with one row per period of the target series' frequency and
columns

- time:

  Numeric (decimal) time of the period.

- nowcast:

  Posterior mean nowcast, the values in `object$nowcast`.

- sd:

  Posterior standard deviation, `sqrt(object$nowcast_var)`.

- lower, upper:

  The `level` credible bounds, normal-approximated from `nowcast` and
  `sd`.

The last three columns are present only when the fit stores
`nowcast_var`, which both model entry points currently do.

## Details

This is deliberately **not** a
[`predict()`](https://rdrr.io/r/stats/predict.html) method. These models
do not forecast in the usual sense – there is no separate prediction
step to run on new data – so a
[`predict()`](https://rdrr.io/r/stats/predict.html) returning stored
values would advertise a capability that does not exist. The name is
prefixed rather than a bare `nowcast()` to avoid masking the same verb
in other packages.

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
and
[fcast_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm_methods.md)
for the other accessors, and
[`retrieve_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast.md)
for the backcast-workflow helper it replaces for ordinary fits.

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                stats::window, start = 2021)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2021)
set.seed(1)
fit <- ind_dfm(flows = flows, stocks = stocks, target = target,
               length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..

head(mfbdfm_nowcast(fit))
#>      time     nowcast           sd       lower       upper
#> 1 2021.00 0.005967520 2.189887e-07 0.005967090 0.005967949
#> 2 2021.25 0.025367012 2.038934e-07 0.025366612 0.025367411
#> 3 2021.50 0.019780758 2.650326e-07 0.019780238 0.019781277
#> 4 2021.75 0.010104511 2.754155e-07 0.010103971 0.010105051
#> 5 2022.00 0.002357668 1.907220e-07 0.002357294 0.002358041
#> 6 2022.25 0.006806128 2.513755e-07 0.006805635 0.006806621
mfbdfm_nowcast(fit, last = TRUE)          # just the current quarter
#>      time     nowcast           sd       lower       upper
#> 1 2025.75 0.001506254 1.589362e-07 0.001505942 0.001506565
mfbdfm_nowcast(fit, last = TRUE, level = 0.68)
#>      time     nowcast           sd       lower       upper
#> 1 2025.75 0.001506254 1.589362e-07 0.001506096 0.001506412
# }
```
