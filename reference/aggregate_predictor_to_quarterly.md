# Aggregate a predictor data frame to quarterly frequency

Aggregates a `time`/`value` data frame to quarters by mean, by the
cut-off month, or by the last observation of the cut-off month.

## Usage

``` r
aggregate_predictor_to_quarterly(
  df,
  cut_off_month_pos = NULL,
  method = "cut_off"
)
```

## Arguments

- df:

  Data frame with `time` (Date) and `value` columns.

- cut_off_month_pos:

  Integer position of the cut-off month within the quarter (used by
  methods `"last_month"` and `"last"`).

- method:

  One of `"last_month"`, `"mean"`, `"last"`.

## Value

A quarterly data frame (columns depend on `method`).

## Details

**Warning:** this function dispatches on the *name* of the object passed
as `df`: if the deparsed argument name contains `"AR"`, the data frame
is returned with only a `yearqtr` column added. This legacy behavior is
kept for compatibility with the analysis scripts; avoid renaming objects
passed to it.

## Examples

``` r
df <- data.frame(time = seq(as.Date("2023-01-01"), by = "month", length.out = 12),
                 value = rnorm(12))
aggregate_predictor_to_quarterly(df, cut_off_month_pos = 1, method = "mean")
#> # A tibble: 4 × 3
#>   time         value yearqtr  
#>   <date>       <dbl> <yearqtr>
#> 1 2023-01-01 -1.19   2023 Q1  
#> 2 2023-04-01  0.588  2023 Q2  
#> 3 2023-07-01 -0.771  2023 Q3  
#> 4 2023-10-01 -0.0691 2023 Q4  
```
