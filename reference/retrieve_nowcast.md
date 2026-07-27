# Extract the nowcast from a fit object

Extract the nowcast from a fit object

## Usage

``` r
retrieve_nowcast(fit, model)
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

The nowcast value.

## Examples

``` r
fit <- list(nowcast = stats::ts(c(0.3, 0.5), start = 2024, frequency = 4))
retrieve_nowcast(fit, model = "wai")
#>      Qtr2
#> 2024  0.5
```
