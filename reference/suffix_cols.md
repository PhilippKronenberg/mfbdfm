# Suffix the lag columns of a correlation or error table

Renames every `Lag_*` column to `Lag_*_<suffix>`, leaving all other
columns untouched. Used when several tables that share a lag layout are
put side by side and their columns would otherwise collide – one per
frequency (`"QoQ"`, `"YoY"`) or per aggregation method (`"mean"`,
`"last"`, `"lastmonth"`).

## Usage

``` r
suffix_cols(df, suffix)
```

## Arguments

- df:

  A data frame with zero or more columns named `Lag_*`.

- suffix:

  Character, appended to each lag column name after an underscore.

## Value

`df` with its `Lag_*` columns renamed. A data frame with no such columns
is returned unchanged.

## Details

Exported because `analysis/5_plots/analytics_in_sample.R` calls it in
six places. It was `@noRd` and therefore invisible outside the package,
and
[`create_combined_latex_table()`](https://philippkronenberg.github.io/mfbdfm/reference/create_combined_latex_table.md)
carried a second, identical copy defined inside its own body – so the
script failed with `could not find function "suffix_cols"` the first
time the analytics chain was run end to end (#23). One definition now,
visible to both.

## Examples

``` r
df <- data.frame(Series = c("WAI", "AR"), Lag_0 = c(1, 2), Lag_1 = c(3, 4))
suffix_cols(df, "QoQ")
#>   Series Lag_0_QoQ Lag_1_QoQ
#> 1    WAI         1         3
#> 2     AR         2         4

# columns that are not lags are left alone, and a frame without any is a no-op
suffix_cols(data.frame(Series = "WAI", value = 1), "QoQ")
#>   Series value
#> 1    WAI     1
```
