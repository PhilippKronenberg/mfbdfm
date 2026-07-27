# Select the newest GDP vintage available at a given date

Select the newest GDP vintage available at a given date

## Usage

``` r
select_most_recent_GDP_vintage(current_date, GDP_gr_vintages)
```

## Arguments

- current_date:

  Numeric (decimal time), the evaluation date.

- GDP_gr_vintages:

  Vintage table from
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md).

## Value

The selected vintage column (numeric vector).

## Examples

``` r
# \donttest{
vintages <- get_real_time_gdp_vintages("quarterly")
v <- select_most_recent_GDP_vintage(2024.5, vintages)
utils::tail(stats::na.omit(v))
#> [1]  0.0005006722  0.0091940850 -0.0025524009  0.0026667204  0.0033793290
#> [6]  0.0027648443
# }
```
