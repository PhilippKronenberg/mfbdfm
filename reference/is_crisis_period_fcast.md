# Flag target quarters falling into the Eckert et al. (2025) crisis periods

The crisis/non-crisis split used in the out-of-sample evaluation of
Eckert, Kronenberg, Mikosch & Neuwirth (2025). Carries the `_fcast`
suffix for the same reason the multi-factor internals do: it is the
counterpart of
[`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md)
for that paper, and the two are **not** interchangeable.

## Usage

``` r
is_crisis_period_fcast(period)
```

## Arguments

- period:

  Numeric vector of target quarters in decimal time, e.g. `2020.25` for
  2020Q2. This is the `period` column of the evaluation panel, not the
  nowcast date.

## Value

Logical vector, `TRUE` for quarters inside a crisis window.

## Details

Two differences from
[`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md),
both of which matter:

- What is classified:

  This takes the **target quarter** being nowcast, as decimal time
  (`2020.25` for 2020Q2).
  [`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md)
  takes the **date the nowcast was made**. In a real-time evaluation
  those are weeks or months apart, so the two label different rows.

- Which episodes:

  Four windows here – the global financial crisis, the euro crisis, the
  2015 Swiss franc shock and Covid-19.
  [`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md)
  covers only the first and last.

Measured on the paper's own evaluation panel, the two agree on only 124
of its 240 crisis dates, and substituting
[`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md)
does not reproduce the published figures: crisis RMSFE for the monthly
benchmark comes out at 0.0262 against the 0.0210 this definition gives,
which is what the paper plots.

## References

Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025). Tracking
economic activity with alternative high-frequency data. *Journal of
Applied Econometrics*, 40(3), 270-290.

## See also

[`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md)
for the date-based definition used by the Weekly Activity Index
analysis.

## Examples

``` r
# 2020Q1-2021Q3 are crisis quarters; 2019 and 2022 are not
is_crisis_period_fcast(c(2019, 2020, 2021.25, 2022))
#> [1] FALSE  TRUE  TRUE FALSE
```
