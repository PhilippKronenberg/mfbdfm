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

## Examples

``` r
lv <- data.frame(time = seq(as.Date("2020-01-07"), by = "week", length.out = 150),
                 value = 100 * cumprod(1 + rnorm(150, 0, 0.002)))
head(build_wai_qoq_mean_series(lv))
#> # A tibble: 6 × 2
#>   time        value
#>   <date>      <dbl>
#> 1 2020-04-01  0.876
#> 2 2020-07-01  0.305
#> 3 2020-10-01  2.00 
#> 4 2021-01-01 -2.96 
#> 5 2021-04-01 -0.857
#> 6 2021-07-01  4.33 
```
