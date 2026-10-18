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
