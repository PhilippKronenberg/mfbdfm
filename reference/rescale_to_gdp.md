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
