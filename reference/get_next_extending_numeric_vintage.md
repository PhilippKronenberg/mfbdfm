# Next vintage that extends the data beyond a reference date's vintage

Finds the newest vintage available at `reference_date`, then returns the
first later vintage whose series reaches further into the sample.

## Usage

``` r
get_next_extending_numeric_vintage(df, reference_date, lower_bound = -Inf)
```

## Arguments

- df:

  Vintage table with a `time` column and vintage-named columns.

- reference_date:

  `Date` at which the base vintage is selected.

- lower_bound:

  Numeric lower bound on vintages considered.

## Value

The extending vintage as a numeric decimal date.
