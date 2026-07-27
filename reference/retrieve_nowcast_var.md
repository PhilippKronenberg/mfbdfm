# Extract the nowcast variance from a fit object

Extract the nowcast variance from a fit object

## Usage

``` r
retrieve_nowcast_var(fit, model)
```

## Arguments

- fit:

  A fit object from
  [`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md)
  or
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md).

- model:

  Character, `"ar"` or `"wai"`.

## Value

The nowcast variance.

## Examples

``` r
fit <- list(nowcast_var = stats::ts(c(0.02, 0.04), start = 2024, frequency = 4))
retrieve_nowcast_var(fit, model = "wai")
#>      Qtr2
#> 2024 0.04
```
