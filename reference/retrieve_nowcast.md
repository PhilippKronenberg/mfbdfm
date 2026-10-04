# Extract the nowcast from a fit object

Extract the nowcast from a fit object

## Usage

``` r
retrieve_nowcast(fit, model = c("ar", "wai"))
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

The nowcast value.

## See also

[`mfbdfm_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_nowcast.md),
which is the accessor to reach for with an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
or
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit in hand: it dispatches on the fit's class rather than taking a
`model` string, and returns the whole nowcast path with its credible
band. This function exists for the
[`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md)/[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
backcast workflow, which also needs the AR benchmark, and returns only
the latest value.

Other backcasting functions:
[`retrieve_nowcast_var()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast_var.md)

## Examples

``` r
fit <- list(nowcast = stats::ts(c(0.3, 0.5), start = 2024, frequency = 4))
retrieve_nowcast(fit, model = "wai")
#>      Qtr2
#> 2024  0.5
```
