# Filter a data frame to the evaluation sample window

Filter a data frame to the evaluation sample window

## Usage

``` r
filter_to_sample(
  df,
  time_col = "time",
  start_date = as.Date("1990-01-01"),
  end_date
)
```

## Arguments

- df:

  Data frame with a date column.

- time_col:

  Name of the date column.

- start_date:

  Window start (`Date`).

- end_date:

  Window end (`Date`), e.g. `wai_sample_config()$sample_end_date`.

## Value

The filtered data frame.

## Examples

``` r
df <- data.frame(time = seq(as.Date("2019-01-01"), by = "quarter", length.out = 12),
                 value = rnorm(12))
filter_to_sample(df, end_date = as.Date("2020-12-31"))
#>         time         value
#> 1 2019-01-01 -0.3868075669
#> 2 2019-04-01 -1.5986946061
#> 3 2019-07-01 -0.0007509675
#> 4 2019-10-01 -0.9402699180
#> 5 2020-01-01 -2.0139644881
#> 6 2020-04-01  0.0430520683
#> 7 2020-07-01 -1.2600917104
#> 8 2020-10-01 -0.0417979580
```
