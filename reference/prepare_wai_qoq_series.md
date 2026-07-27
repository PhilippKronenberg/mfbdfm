# Select the QoQ series for a WAI result, given the aggregation method

Select the QoQ series for a WAI result, given the aggregation method

## Usage

``` r
prepare_wai_qoq_series(wai_result, method)
```

## Arguments

- wai_result:

  List with elements `tab_gr_qoq` and `tab_gr_lv` (as produced by
  [`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md)).

- method:

  Aggregation method; `"mean"` derives QoQ growth from the level index,
  anything else returns the stored QoQ table.

## Value

Data frame with `time` and `value`.

## Examples

``` r
res <- list(tab_gr_qoq = data.frame(time = as.Date("2020-01-07"), value = 1),
            tab_gr_lv = data.frame(time = seq(as.Date("2020-01-07"), by = "week",
                                              length.out = 150),
                                   value = cumprod(1 + rnorm(150, 0, 0.002))))
prepare_wai_qoq_series(res, method = "last")
#>         time value
#> 1 2020-01-07     1
```
