# Standardize and align mixed-frequency series into one matrix

Standardizes each series using the moments from the inventory, aligns
all series on the highest-frequency time grid, and returns a single
multivariate `ts` matrix in which missing observations are encoded as
zero (as expected by the
[`hfdfm()`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
sampler).

## Usage

``` r
prepare_data(flows, stocks, inventory, target)
```

## Arguments

- flows:

  Named list of `ts` objects treated as flow variables.

- stocks:

  Named list of `ts` objects treated as stock variables.

- inventory:

  Data frame from
  [`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md).

- target:

  Character, name of the target series (currently unused here; kept for
  interface stability).

## Value

A multivariate `ts` at the highest input frequency with one column per
series; missing values are encoded as `0`.

## Examples

``` r
data(data_ch_dataset_test)
inv <- create_inventory(flows = data_ch_dataset_test$flows,
                        stocks = data_ch_dataset_test$stocks)
Ymat <- prepare_data(flows = data_ch_dataset_test$flows,
                     stocks = data_ch_dataset_test$stocks,
                     inventory = inv,
                     target = "ch.seco.gdp.real.gdp.ssa")
dim(Ymat)
#> [1] 1742   46
```
