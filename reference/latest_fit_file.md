# Find the newest fit file up to a cutoff date

Find the newest fit file up to a cutoff date

## Usage

``` r
latest_fit_file(folder, cutoff_decimal)
```

## Arguments

- folder:

  Directory containing `fit_<decimal-date>.Rda` files.

- cutoff_decimal:

  Numeric decimal date; only fits at or before this cutoff are
  considered.

## Value

Full path of the selected fit file.

## Examples

``` r
dir <- tempfile(); dir.create(dir)
mod <- list()
save(mod, file = file.path(dir, "fit_2020.5.Rda"))
save(mod, file = file.path(dir, "fit_2021.25.Rda"))
latest_fit_file(dir, cutoff_decimal = 2020.9)
#> [1] "/tmp/Rtmpe0hbmn/file1adc6e855de7/fit_2020.5.Rda"
```
