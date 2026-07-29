# Build an inventory of the model input series

Combines the flow and stock series lists into a data frame describing
each series: its name, type, frequency, and the mean and standard
deviation used for standardization in
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md).

## Usage

``` r
create_inventory(flows, stocks)
```

## Arguments

- flows:

  Named list of `ts` objects treated as flow variables, or `NULL` for a
  model with no flow variables.

- stocks:

  Named list of `ts` objects treated as stock variables, or `NULL` for a
  model with no stock variables.

## Value

A data frame with one row per series and columns `key` (series name),
`type` (factor, `"flow"` or `"stock"`), `freq` (observations per year),
`mean` and `sd` (moments of the raw series, NA-removed).

## See also

Other data preparation functions:
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)

## Examples

``` r
data(data_ch_dataset_test)
inv <- create_inventory(flows = data_ch_dataset_test$flows,
                        stocks = data_ch_dataset_test$stocks)
head(inv)
#>                            key type freq         mean         sd
#> 1 ch.fso.rtt.ind.r.noga0801.sa flow   12 1.192470e-03 0.02605552
#> 2                      FINANSW flow   48 7.484738e-04 0.02336711
#> 3                      INDUSSW flow   48 9.465819e-04 0.02343454
#> 4                      SWISSMI flow   48 1.166533e-03 0.01726364
#> 5         oev_freq_hardbruecke flow   48 5.283703e-04 0.15218650
#> 6                  oev_freq_hb flow   48 7.679032e-05 0.01836277
```
