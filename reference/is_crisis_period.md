# Flag crisis periods

Flags the crisis episodes of either published analysis.
`windows = "wai"` (the default) marks **dates** inside the two windows
used by the Weekly Activity Index analysis; `windows = "fcast"` marks
**target quarters** inside the four windows used by the out-of-sample
evaluation of Eckert, Kronenberg, Mikosch & Neuwirth (2025).

## Usage

``` r
is_crisis_period(date_vec, windows = c("wai", "fcast"))
```

## Arguments

- date_vec:

  Periods to classify. For `windows = "wai"` a `Date` vector (or
  coercible). For `windows = "fcast"` a numeric vector of target
  quarters in decimal time, e.g. `2020.25` for 2020Q2.

- windows:

  Which crisis definition to apply: `"wai"` (default) for the date-based
  windows of the Weekly Activity Index analysis, or `"fcast"` for the
  quarter-based windows of Eckert et al. (2025).

## Value

Logical vector, `TRUE` for periods inside a crisis window.

## Details

The two definitions are **not** interchangeable, which is why the choice
is an explicit argument rather than something a caller can drift past.
They differ in two ways, both of which matter:

- What is classified:

  `"wai"` takes the **date the nowcast was made**, as a `Date`.
  `"fcast"` takes the **target quarter** being nowcast, as decimal time
  (`2020.25` for 2020Q2) – the `period` column of the evaluation panel.
  In a real-time evaluation those are weeks or months apart, so the two
  label different rows.

- Which episodes:

  `"wai"` covers the global financial crisis (2008-07-07 to 2009-09-28)
  and Covid-19 (2020-01-01 to 2021-12-28). `"fcast"` adds the euro
  crisis and the 2015 Swiss franc shock, and its windows are quarters
  rather than days.

Measured on the paper's own evaluation panel, the two agree on only 124
of its 240 crisis dates, and using `"wai"` where `"fcast"` is meant does
not reproduce the published figures: crisis RMSFE for the monthly
benchmark comes out at 0.0262 against the 0.0210 the `"fcast"`
definition gives, which is what the paper plots.

Before version 0.1.0.9000 the `"fcast"` windows lived in a second
exported function, `is_crisis_period_fcast()`. Two exported functions
for one concept with different hard-coded windows is exactly the parity
problem the `windows` argument removes;
`is_crisis_period(x, windows = "fcast")` replaces it.

## References

Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025). Tracking
economic activity with alternative high-frequency data. *Journal of
Applied Econometrics*, 40(3), 270-290.
[doi:10.1002/jae.3104](https://doi.org/10.1002/jae.3104)

## Examples

``` r
is_crisis_period(as.Date(c("2015-01-01", "2020-06-01")))
#> [1] FALSE  TRUE

# the Eckert et al. (2025) windows, on target quarters in decimal time:
# 2020Q1-2021Q3 are crisis quarters, 2019 and 2022 are not
is_crisis_period(c(2019, 2020, 2021.25, 2022), windows = "fcast")
#> [1] FALSE  TRUE  TRUE FALSE

# and the two genuinely differ -- 2012 is a crisis quarter only for "fcast"
is_crisis_period(2012, windows = "fcast")
#> [1] TRUE
is_crisis_period(as.Date("2012-06-01"))
#> [1] FALSE
```
