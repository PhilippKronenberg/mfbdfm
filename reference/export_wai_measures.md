# Write the WAI measures behind the public dashboard

Companion to
[`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md):
from the same weekly fit, write the three measures the dashboard
explains the indicator with, each on the scale the dashboard publishes,
so that its charts add up to the numbers it shows. Written by
`analysis/update_wai_web.R`; not package API.

## Usage

``` r
export_wai_measures(
  fit_path,
  dir = NULL,
  series_info = NULL,
  news_fit_path = NULL,
  news_new_data = NULL,
  digits = 4,
  vintage_date = NULL
)
```

## Arguments

- fit_path:

  Path to this week's fit `.Rda` (object `mod`), as for
  [`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md).

- dir:

  Directory to write into, or `NULL` to only return the tables.

- series_info:

  Optional data frame with columns `key`, `name` and `group`; series it
  lacks keep their key as name and go into `"Other"`.

- news_fit_path:

  Optional path to LAST week's fit, the old vintage of the news
  decomposition.

- news_new_data:

  Optional list with `flows` and `stocks`: this week's data, prepared
  exactly as this week's fit's was.

- digits:

  Decimal places of the published values.

- vintage_date:

  Optional vintage date recorded in the metadata.

## Value

Invisibly, a list with `contributions`, `series`, `news` (or `NULL`) and
`meta`.

## Details

**Contributions (`wai_contributions.csv`).**
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md)
splits the factor exactly, but on the sampler's standardised,
non-annualised scale. The published `wai_qoq` is
`F(z) = ((1 + sd*z + mean/k)^48 - 1) * 100` of that, which is not
linear, so contributions to it do not exist as such. The file therefore
uses an exact additive split on the published scale: `trend = F(0)` (the
growth the model implies with every contribution at zero), each group's
share of `F(T) - F(0)` in proportion to its standardised contribution
(`T` the plug-in total), and `parameter_uncertainty = wai_qoq - F(T)`,
the posterior-minus-plug-in residual
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md)
itself reports. Per date the components sum to `wai_qoq` exactly.

**News (`wai_news.csv`).**
[`mfbdfm_news()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_news.md)
of the move from `news_fit_path` (last week's fit) to `news_new_data`
(this week's data), aggregated to the groups and mapped onto annualised
quarterly growth the same way: shares of `G(new) - G(old)`,
`G(x) = ((1 + x)^4 - 1) * 100`, which sum exactly to the revision.
Written only when both arguments are given.

**Series (`wai_series.csv`).** One row per input series: name and group,
frequency, the R-squared from
[`summary()`](https://rdrr.io/r/base/summary.html) and the posterior
loading with its 95% band (standardised scale, so loadings are
comparable across series).

## See also

[`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md),
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
[`mfbdfm_news()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_news.md).
