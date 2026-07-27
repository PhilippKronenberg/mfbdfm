# Fit an AR(1) benchmark model and nowcast the target

Estimates an AR(1) model on the target series and produces a one-step
nowcast with variance. Used as the benchmark model in the out-of-sample
evaluation.

## Usage

``` r
run_ar(
  flows,
  stocks,
  target,
  date,
  dataset_used,
  stochastic_volatility = TRUE,
  output_dir = NULL
)
```

## Arguments

- flows:

  Named list of `ts` objects containing `target`.

- stocks:

  Named list of `ts` objects (unused, kept for a uniform interface with
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)).

- target:

  Character, name of the target series in `flows`.

- date:

  Numeric (decimal time), evaluation date used in the file name when
  saving.

- dataset_used:

  Character, dataset label used as sub-directory when saving.

- stochastic_volatility:

  Logical, unused; kept for a uniform interface with
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md).

- output_dir:

  Directory to save the fit to, or `NULL` (default) to skip saving. When
  given, the fit is saved as
  `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.

## Value

Invisibly, a list with elements `nowcast` and `nowcast_var`.

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
fit <- run_ar(flows = data_ch_dataset_test$flows, stocks = NULL,
              target = "ch.seco.gdp.real.gdp.ssa",
              date = 2024.5, dataset_used = "example")
fit$nowcast
#>             Qtr1
#> 2026 0.004169741
# }
```
