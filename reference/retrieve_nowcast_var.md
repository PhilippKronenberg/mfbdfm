# Extract the nowcast variance from a fit object

Extract the nowcast variance from a fit object

## Usage

``` r
retrieve_nowcast_var(fit, model = c("ar", "wai"))
```

## Arguments

- fit:

  A fit object from
  [`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md)
  or
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md).

- model:

  Character, which kind of fit `fit` is: `"ar"` for the AR benchmark
  (whose nowcast is already a single value) or `"wai"` for the dynamic
  factor model (whose nowcast is a series, of which the last value is
  taken). Matched with
  [`match.arg()`](https://rdrr.io/r/base/match.arg.html).

## Value

The nowcast variance.

## See also

Other backcasting functions:
[`retrieve_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast.md)

## Examples

``` r
fit <- list(nowcast_var = stats::ts(c(0.02, 0.04), start = 2024, frequency = 4))
retrieve_nowcast_var(fit, model = "wai")
#>      Qtr2
#> 2024 0.04
```
