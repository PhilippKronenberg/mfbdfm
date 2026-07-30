# Aggregate a higher-frequency series to the 48-week grid

Aggregates a date-indexed `zoo` series into the project's
48-periods-per-year weekly grid. Despite the name it is not restricted
to daily input – the aggregation is driven entirely by the date index,
so a true weekly (52-per-year) series is handled the same way. That is
how
[`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
puts weekly and daily input onto the grid the models use; see its
"Frequency" section.

## Usage

``` r
daily2weekly(x, FUN = mean)
```

## Arguments

- x:

  Series to aggregate (`zoo` indexed by `Date`).

- FUN:

  Function used to combine the observations falling into one 48-week
  slot. Defaults to `mean`. Which is appropriate depends on the series:
  these models are estimated on growth rates, for which the mean is the
  per-period rate, whereas `sum` would preserve the total but leave a
  visible spike in the roughly four slots per year that receive two
  weekly observations.

## Value

A `ts` with frequency 48; slots with no observation are `NA`.

## Examples

``` r
daily <- zoo::zoo(rnorm(120),
                  order.by = seq(as.Date("2024-01-01"), by = "day", length.out = 120))
weekly <- daily2weekly(daily)
stats::frequency(weekly)
#> [1] 48
```
