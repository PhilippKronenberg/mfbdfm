# Fit the multi-factor model at a given evaluation date

Runs
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
at one evaluation date and windows the factor and nowcast output to it.
The multi-factor counterpart of
[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md),
with the same arguments, the same file layout and the same
no-side-effects-by-default rule, so the two can be driven by the same
backcasting loop.

## Usage

``` r
run_fcast(
  flows,
  stocks,
  target,
  date,
  dataset_used,
  q = 2,
  p = 1,
  length_sample = 1000,
  burn_in = 1000,
  thinning = 1,
  stochastic_volatility = TRUE,
  serial_correlation = TRUE,
  extend = 0.5,
  ncores = NULL,
  control = NULL,
  output_dir = NULL
)
```

## Arguments

- flows:

  Named list of `ts` objects containing `target`.

- stocks:

  Named list of `ts` objects.

- target:

  Character, name of the target series in `flows`.

- date:

  Numeric (decimal time), evaluation date; the factor is cut at this
  date.

- dataset_used:

  Character, dataset label used as sub-directory when saving.

- q:

  Integer, number of factors, passed to
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- p:

  Integer, number of factor lags in the factor state equation.

- length_sample:

  Integer, number of posterior draws to keep.

- burn_in:

  Integer, number of initial draws to discard.

- thinning:

  Integer, keep every `thinning`-th draw after burn-in.

- stochastic_volatility:

  Logical. If `TRUE` (default) the factor innovation variance follows a
  stochastic volatility process. If `FALSE` it is a single constant
  variance, **still estimated** rather than fixed – see `@details`.

- serial_correlation:

  Logical. If `TRUE` (default) the measurement errors are allowed to be
  serially correlated and their autocorrelations are drawn. If `FALSE`
  they are held at (effectively) zero.

- extend:

  Numeric, years by which to extend the dataset past its end before
  estimating, passed to
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).
  **Required for this function to nowcast at all**, and the reason it
  defaults to a non-`NULL` value here. At a real-time evaluation date
  the target's last observation is one or two quarters old, so the
  quarter actually being nowcast lies beyond the data; without
  extending,
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  produces values only over the observed span and every result is an
  in-sample fit rather than a forecast. The default of half a year
  covers the current quarter and the next.

- ncores:

  Integer or `NULL`, passed to
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  to parallelise the rotation step.

- control:

  Optional settings from
  [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md),
  passed to
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).
  Use `dfm_control("fcast_dfm", strict = TRUE)` to run the rotation as
  specified in the online appendix.

- output_dir:

  Directory to save the fit to, or `NULL` (default) to skip saving. When
  given, the fit is saved as
  `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.

## Value

Invisibly, the windowed `fcast_dfm` fit object.

## Details

Note what `target` does and does not do here.
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
estimates every series jointly and `target` only selects which nowcast
is surfaced at the top level – unlike
[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md),
where the target is what identifies the factor. Results for every series
remain in `ncst` and `data_hf` on the returned object.

`q` is the setting that has no counterpart in
[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md):
the single-factor model has exactly one factor by construction, so a
multi-factor sweep varies `q` where the WAI sweep varies the dataset.

## See also

[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
for the single-factor equivalent,
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
for the model itself.

Other model fitting functions:
[`dfm_memory()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)

## Examples

``` r
# \donttest{
# Short chain on the shipped data; a real evaluation uses the defaults.
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                stats::window, start = 2021)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2021)
set.seed(1)
fit <- run_fcast(flows = flows, stocks = stocks, target = target,
                 date = 2023, dataset_used = "example",
                 q = 2, length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> running rotation of each draw..
#> Rotation iteration 1: convergence 5.47e-05
#> Rotation iteration 2: convergence 3.39e-06
#> Rotation iteration 3: convergence 4.66e-07
#> Rotation iteration 4: convergence 1.5e-06
#> Rotation iteration 5: convergence 2.54e-07
#> Warning: Rotation did not converge after 5 iterations (last change 2.54e-07, criterion "mean", tolerance 1e-09). Factor draws may not be rotated onto a common reference; consider raising `rotation_max_iter` in dfm_control().
#> running identification..
#> processing output..
fit$nowcast
#>              Qtr1         Qtr2         Qtr3         Qtr4
#> 2021  0.005967557  0.025366966  0.019780820  0.010104478
#> 2022  0.002357692  0.006806119  0.004997249  0.002075261
#> 2023  0.006192138 -0.003620645  0.004556591  0.003672488
#> 2024 -0.001181443  0.007846066  0.002901737  0.005175346
#> 2025  0.007858543  0.001230692 -0.004400705  0.001506235
#> 2026 -0.001819610                                       
# }
```
