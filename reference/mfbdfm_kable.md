# Render a table in one of the supported output formats

The shared knitr wrapper behind the `format` argument of
[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md)
and
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md).
Exported so that a table built by hand, or one of those data frames
after further manipulation, can be rendered the same way.

## Usage

``` r
mfbdfm_kable(
  x,
  format = c("latex", "html", "markdown"),
  digits = 4,
  caption = NULL
)
```

## Arguments

- x:

  A data frame.

- format:

  Character, one of `"latex"`, `"html"` or `"markdown"`.

- digits:

  Integer, significant digits passed to
  [`knitr::kable()`](https://rdrr.io/pkg/knitr/man/kable.html).

- caption:

  Character or `NULL`, a table caption.

## Value

A character vector of class `"knitr_kable"`.

## See also

[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md),
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md)

Other model tables:
[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md),
[`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md)

## Examples

``` r
mfbdfm_kable(data.frame(series = c("a", "b"), mean = c(1.234567, 2)),
             format = "markdown")
#> 
#> 
#> |series |   mean|
#> |:------|------:|
#> |a      | 1.2346|
#> |b      | 2.0000|
```
