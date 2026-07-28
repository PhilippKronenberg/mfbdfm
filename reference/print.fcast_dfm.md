# Print a summary of a multi-factor dynamic factor model fit

Reports the model dimensions and shows the most recent values of the
target series: its observed values alongside the model's nowcast and 95%
band, so the fit can be inspected at a glance.

## Usage

``` r
# S3 method for class 'fcast_dfm'
print(x, n_show = 8, ...)
```

## Arguments

- x:

  An object of class `"fcast_dfm"` from
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- n_show:

  Integer, how many of the most recent target observations to display.

- ...:

  Ignored, present for compatibility with the
  [`print()`](https://rdrr.io/r/base/print.html) generic.

## Value

`x`, invisibly.

## Examples

``` r
if (FALSE) { # \dontrun{
fit <- fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2)
fit          # calls print.fcast_dfm()
print(fit, n_show = 12)
} # }
```
