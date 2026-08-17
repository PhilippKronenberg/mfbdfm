# Fit the WAI dynamic factor model at a given evaluation date

Runs
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
with the settings used in the WAI out-of-sample evaluation and windows
the factor and nowcast output to the evaluation date.

## Usage

``` r
run_wai_adj(
  flows,
  stocks,
  target,
  date,
  dataset_used,
  stochastic_volatility = TRUE,
  length_sample = 5000,
  burn_in = 1000,
  thinning = 1,
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

- stochastic_volatility:

  Logical, passed to
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  (currently without effect there).

- length_sample:

  Integer, number of posterior draws to keep.

- burn_in:

  Integer, number of initial draws to discard.

- thinning:

  Integer, keep every `thinning`-th draw after burn-in.

- output_dir:

  Directory to save the fit to, or `NULL` (default) to skip saving. When
  given, the fit is saved as
  `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.

## Value

Invisibly, the windowed `ind_dfm` fit object.

## Details

`length_sample`, `burn_in` and `thinning` default to the chain this
wrapper has always run — 5000 retained draws after 1000 burn-in,
unthinned — so existing results are unaffected. They are arguments
rather than hard-coded values so that a short chain can be used to check
the wiring, which is what the example below does; note that the default
differs from
[`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)'s
1000, deliberately, because that is what each wrapper has always used.

## Examples

``` r
# \donttest{
# Short chain on the shipped data; a real evaluation uses the defaults, which
# run for minutes to tens of minutes.
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                stats::window, start = 2021)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2021)
out <- tempfile(); dir.create(out)

set.seed(1)
fit <- run_wai_adj(flows = flows, stocks = stocks, target = target,
                   date = 2023, dataset_used = "example",
                   length_sample = 20, burn_in = 5,
                   output_dir = out)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..
fit$nowcast
#>              Qtr1         Qtr2         Qtr3         Qtr4
#> 2021  0.005967520  0.025367012  0.019780758  0.010104511
#> 2022  0.002357668  0.006806128  0.004997204  0.002075303
#> 2023  0.006192130 -0.003620599  0.004556572  0.003672473
#> 2024 -0.001181425  0.007845983  0.002901709  0.005175446
#> 2025  0.007858650  0.001230720 -0.004400745  0.001506254
list.files(out, recursive = TRUE)
#> [1] "example/fit_2023.Rda"
unlink(out, recursive = TRUE)
# }
```
