# Newest numeric vintage within bounds

Newest numeric vintage within bounds

## Usage

``` r
get_latest_numeric_vintage(df, lower_bound = -Inf, upper_bound)
```

## Arguments

- df:

  Vintage table whose column names (except the first) are decimal
  vintage dates, e.g. from
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md).

- lower_bound:

  Numeric lower bound (inclusive).

- upper_bound:

  Numeric upper bound (inclusive), e.g.
  `wai_sample_config()$sample_end_decimal`.

## Value

The newest vintage as a numeric decimal date.

## Examples

``` r
vintages <- data.frame(time = 1:3, "2020.25" = rnorm(3), "2020.75" = rnorm(3),
                       check.names = FALSE)
get_latest_numeric_vintage(vintages, upper_bound = 2020.5)
#> [1] 2020.25
```
