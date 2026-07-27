# Cut a dataset in real time, using GDP vintages for the target

Like
[`cut_data()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data.md),
but instead of truncating the quarterly target series, replaces it with
the newest GDP vintage that was available at `current_date`.

## Usage

``` r
cut_data_real_time(dat, current_date, GDP_gr_vintages)
```

## Arguments

- dat:

  A list with components `flows` and `stocks` (named lists of `ts`
  objects), e.g.
  [data_ch_dataset_test](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset_test.md).

- current_date:

  Numeric (decimal time), the evaluation date.

- GDP_gr_vintages:

  Vintage table from
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md).

## Value

A list with components `flows` and `stocks`.

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
vintages <- get_real_time_gdp_vintages("quarterly")
cut <- cut_data_real_time(data_ch_dataset_test, 2024.5, vintages)
utils::tail(cut$flows[["ch.seco.gdp.real.gdp.ssa"]])
#>               Qtr1          Qtr2          Qtr3          Qtr4
#> 2022                                            0.0005006722
#> 2023  0.0091940850 -0.0025524009  0.0026667204  0.0033793290
#> 2024  0.0027648443                                          
# }
```
