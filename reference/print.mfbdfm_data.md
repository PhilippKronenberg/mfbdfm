# Print an mfbdfm_data object

Shows the resolved classification and the frequencies actually used, so
a mistake in either is visible before it is used for a long run.

## Usage

``` r
# S3 method for class 'mfbdfm_data'
print(x, ...)
```

## Arguments

- x:

  An object from
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md).

- ...:

  Ignored, present for compatibility with the generic.

## Value

`x`, invisibly.

## Examples

``` r
long <- data.frame(
  series = rep(c("a_flow", "b_stock"), each = 24),
  date = rep(seq(as.Date("2020-01-01"), by = "month", length.out = 24), 2),
  value = rnorm(48))
mfbdfm_data(long, data.frame(series = c("a_flow", "b_stock"),
                             type = c("flow", "stock")))
#> <mfbdfm_data>  2 series  (1 flow, 1 stock)
#> 
#>   by frequency:
#>        12   1 flow   1 stock   <- highest; flow/stock has no effect here
#> 
#>   series (first 10):
#>     a_flow                       flow   freq   12  n    24
#>     b_stock                      stock  freq   12  n    24
#> 
#> Pass to ind_dfm() or fcast_dfm() as the first argument.
```
