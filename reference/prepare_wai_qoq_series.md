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
