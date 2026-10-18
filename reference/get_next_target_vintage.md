# First target vintage after a prediction vintage

First target vintage after a prediction vintage

## Usage

``` r
get_next_target_vintage(pred_vintage, target_vintages)
```

## Arguments

- pred_vintage:

  Numeric decimal date of the prediction vintage.

- target_vintages:

  Numeric vector of available target vintages.

## Value

The smallest target vintage strictly after `pred_vintage`, or `NA` if
none exists.
