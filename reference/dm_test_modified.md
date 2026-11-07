# Modified Diebold-Mariano test

Diebold-Mariano test of equal predictive accuracy with the
Harvey-Leybourne-Newbold (1997) small-sample correction.

## Usage

``` r
dm_test_modified(
  e1,
  e2,
  h = 1,
  power = 2,
  alternative = c("greater", "less", "two.sided")
)
```

## Arguments

- e1, e2:

  Numeric vectors of forecast errors of the two models.

- h:

  Forecast horizon.

- power:

  Loss function power (2 = squared error, 1 = absolute).

- alternative:

  One of `"greater"` (the second model is more accurate), `"less"`,
  `"two.sided"`.

## Value

The p-value.

## Details

The loss differential's long-run variance includes its autocovariances
up to lag `h - 1`, the statistic is multiplied by the HLN factor
`sqrt((n + 1 - 2h + h(h - 1)/n) / n)`, and the p-value comes from a
t-distribution with `n - 1` degrees of freedom, as in Harvey, Leybourne
and Newbold (1997). This equals
[`forecast::dm.test()`](https://pkg.robjhyndman.com/forecast/reference/dm.test.html).

Earlier versions divided by the factor instead, took the p-value from
the normal distribution and left the autocovariances out, so their
p-values were too small: with 18 errors and
`mean(d) / sqrt(var(d) / 18) = 2`, 0.040 two-sided instead of 0.062.

## References

Harvey, D., Leybourne, S. and Newbold, P. (1997). Testing the equality
of prediction mean squared errors. *International Journal of
Forecasting*, 13(2), 281-291.

## Examples

``` r
set.seed(1)
dm_test_modified(rnorm(40) + 0.3, rnorm(40))
#> [1] 0.3981177
```
