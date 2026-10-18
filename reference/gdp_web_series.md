# Published GDP on the same scale as the exported WAI series

Builds official GDP as quarter-on-quarter annualised growth,
year-over-year growth and a rebased level index, all on the units
[`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md)
publishes, so the three can be plotted against their WAI counterparts on
one axis.

## Usage

``` r
gdp_web_series(
  vintage = "latest",
  base_date = as.Date("2019-10-01"),
  start_date = as.Date("1990-01-01"),
  end_date = NULL,
  ...
)
```

## Arguments

- vintage:

  Which publication vintage to use: `"latest"` (default) for the most
  recent column, or the name of a vintage column.

- base_date:

  `Date` (or string) naming the quarter the level index is rebased to.
  Defaults to 2019-10-01, matching `wai_index`, whose base is the last
  quarter of 2019.

- start_date, end_date:

  Optional `Date` bounds on the quarters returned. The growth rates are
  always computed on the full available history and the window applied
  afterwards, so the first returned quarter carries a real `qoq` and
  `yoy` rather than the `NA` a post-trim lag would leave.

- ...:

  Passed to
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md),
  e.g. the two file-path arguments.

## Value

A data frame with columns `time` (Date, quarter start), `qoq`, `yoy` and
`index`. Ready to hand to
[`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md)'s
`gdp` argument.

## Details

[`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
returns `"quarterly"` as a log difference and `"annual"` as a fraction,
neither of which is the annualised percentage the WAI series use. Rather
than convert at each call site — which is how an unconverted log
difference nearly reached the published dashboard, wrong by a factor of
roughly 400 — the conversion lives here, in one tested place.

All three series are derived from the *same* vintage levels, so they are
mutually consistent by construction:

- `qoq`:

  `((level_t / level_{t-1})^4 - 1) * 100`

- `yoy`:

  `(level_t / level_{t-4} - 1) * 100`

- `index`:

  `100 * level_t / level_base`

## See also

[`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
for the untransformed vintages.
