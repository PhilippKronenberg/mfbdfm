# Quarter-on-quarter growth from a weekly level series

Averages the level index by quarter and computes annualized
quarter-on-quarter growth in percent.

## Usage

``` r
build_wai_qoq_mean_series(level_df)
```

## Arguments

- level_df:

  Data frame with `time` (Date) and `value` (level).

## Value

Data frame with quarterly `time` and growth `value`.
