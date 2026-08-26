# Read the real-time GDP vintage database

Reads the Swiss real-time GDP vintage database and returns a table of
GDP growth vintages: one column per publication vintage (named by its
decimal publication date, rounded to a 48th of a year), one row per
quarter. Pre-2018Q3 vintages are taken from `gdp_file_path`, later ones
from `gdp_cssa_file_path`.

## Usage

``` r
get_real_time_gdp_vintages(
  output_type = c("quarterly", "annual", "level"),
  gdp_file_path = system.file("extdata", "realtime_gdp.csv", package = "mfbdfm"),
  gdp_cssa_file_path = system.file("extdata", "realtime_gdp_cssa.csv", package =
    "mfbdfm"),
  start_date = as.Date("1990-01-01"),
  end_date = NULL
)
```

## Arguments

- output_type:

  Character, one of `"quarterly"`, `"annual"` or `"level"`. See the
  return section for what each one is, and in particular for its units.

- gdp_file_path:

  Path to the pre-2018Q3 vintage CSV. Defaults to the file shipped with
  the package.

- gdp_cssa_file_path:

  Path to the 2018Q3-onward vintage CSV. Defaults to the file shipped
  with the package.

- start_date, end_date:

  Optional `Date` bounds on the quarters returned. `start_date` defaults
  to 1990-01-01; `end_date` defaults to `NULL`, meaning no upper bound.

## Value

A data frame with a `time` column (Date, quarter start) and one numeric
column per vintage. `output_type` selects the transformation, and the
three differ in units:

- `"quarterly"`:

  Quarter-on-quarter *log difference*, e.g. `0.00151`.

- `"annual"`:

  Year-on-year growth as a *fraction*, e.g. `0.0241`.

- `"level"`:

  The vintage *levels*, untransformed.

None of these is the annualised percentage that
[`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md)
publishes as `wai_qoq`: plotted on one axis unconverted, `"quarterly"`
and `wai_qoq` differ by a factor of roughly 400.
[`gdp_web_series()`](https://philippkronenberg.github.io/mfbdfm/reference/gdp_web_series.md)
does the conversion.

## Examples

``` r
# \donttest{
vintages <- get_real_time_gdp_vintages("quarterly")
vintages[1:5, 1:3]
#>          time     2000.417     2000.667
#> 43 1990-01-01  0.010908853  0.010918119
#> 44 1990-04-01  0.007636141  0.007629653
#> 45 1990-07-01  0.006578892  0.006561792
#> 46 1990-10-01  0.006121410  0.006134495
#> 47 1991-01-01 -0.014265158 -0.014242164
# }
```
