# Harmonized Swiss indicator dataset (test variant)

A variant of
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
built from the test metadata (`data_meta_test.xlsx`) with a different
flow/stock split, used for model development and evaluation runs.

## Usage

``` r
data_ch_dataset_test
```

## Format

A list with two components, as expected by
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md):

- flows:

  Named list of 28 `ts` objects treated as flow variables, including the
  quarterly target series `ch.seco.gdp.real.gdp.ssa`.

- stocks:

  Named list of 18 `ts` objects treated as stock variables.

## Source

See
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md).

## Examples

``` r
data(data_ch_dataset_test)
names(data_ch_dataset_test)
#> [1] "flows"  "stocks"
"ch.seco.gdp.real.gdp.ssa" %in% names(data_ch_dataset_test$flows)
#> [1] TRUE
```
