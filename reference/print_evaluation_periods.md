# Print the evaluation period per series

Print the evaluation period per series

## Usage

``` r
print_evaluation_periods(
  data,
  series_col,
  date_col,
  context_label,
  frequency_label = NULL,
  method_label = NULL
)
```

## Arguments

- data:

  Data frame with a series and a date column.

- series_col, date_col:

  Column names.

- context_label:

  Label printed above the summary.

- frequency_label, method_label:

  Optional annotation columns.

## Value

Invisibly, the period summary data frame.
