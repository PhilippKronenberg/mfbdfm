# Rescale an indicator to GDP moments

Standardizes an indicator over a reference window and rescales it to the
mean and standard deviation of GDP over the same window.

## Usage

``` r
rescale_to_gdp(
  indicator_df,
  gdp_hist_df,
  ref_start = as.Date("2005-01-01"),
  ref_end = as.Date("2025-12-31")
)
```

## Arguments

- indicator_df:

  Data frame with `time` (Date) and `value` columns.

- gdp_hist_df:

  Data frame with GDP history: column `value` holds the observation
  `Date` and column `y` the GDP value (legacy layout).

- ref_start, ref_end:

  Reference window (`Date`).

## Value

`indicator_df` with the `value` column rescaled.

## Examples

``` r
ind <- data.frame(time = seq(as.Date("2010-01-07"), by = "week", length.out = 200),
                  value = rnorm(200, 5, 2))
gdp <- data.frame(value = seq(as.Date("2010-01-01"), by = "quarter", length.out = 40),
                  y = rnorm(40, 1, 1))
head(rescale_to_gdp(ind, gdp))
#>         time      value
#> 1 2010-01-07 -0.7128131
#> 2 2010-01-14  0.4764508
#> 3 2010-01-21  1.2788464
#> 4 2010-01-28  1.8301885
#> 5 2010-02-04 -0.6191266
#> 6 2010-02-11  0.2259172
```
