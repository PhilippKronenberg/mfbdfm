# Cut a dataset to what was observable at a given date

Truncates every series in the dataset at the point in time when it would
have been observable at `current_date`, given the publication lag
conventions of its frequency: weekly series appear one week after the
period, monthly series in the first week of the next month, and the
quarterly target roughly ten weeks after the end of the quarter. Series
that end up empty or shorter than 24 observations are dropped.

## Usage

``` r
cut_data(dat, current_date)
```

## Arguments

- dat:

  A list with components `flows` and `stocks` (named lists of `ts`
  objects), e.g.
  [data_ch_dataset_test](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset_test.md).

- current_date:

  Numeric (decimal time), the evaluation date.

## Value

A list with components `flows` and `stocks`, truncated.

## Examples

``` r
data(data_ch_dataset_test)
cut <- cut_data(data_ch_dataset_test, current_date = 2024.5)
range(stats::time(cut$flows[[1]]))
#> [1] 2000.083 2024.417
```
