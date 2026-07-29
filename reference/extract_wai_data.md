# Extract WAI growth, level and year-over-year tables from a saved fit

Loads a saved `ind_dfm` fit (an `.Rda` file containing an object `mod`)
and derives long-format tables of the weekly growth rate (with 95%
bands), the cumulated level index (rebased to 2020 = 100), and
year-over-year growth, as used by the plotting scripts.

## Usage

``` r
extract_wai_data(file_path)
```

## Arguments

- file_path:

  Path to a fit `.Rda` file containing an object `mod` with elements
  `factor` and `factor_var`.

## Value

A list of data frames: `tab_wai_yoy_full`, `tab_wai_yoy`, `tab_gr_full`,
`tab_gr_qoq`, `tab_gr_lv`.

## Examples

``` r
if (FALSE) { # \dontrun{
result_wai <- extract_wai_data("fits/updated/full_RT/fit_2025.979.Rda")
head(result_wai$tab_gr_qoq)
} # }
```
