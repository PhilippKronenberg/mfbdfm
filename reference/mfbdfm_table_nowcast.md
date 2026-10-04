# The target series' nowcast as a table, with posterior uncertainty

The stored nowcast for the fit's `target` series at that series' own
frequency, with its posterior standard deviation, a 95% interval, and
the observed value where one exists.

## Usage

``` r
mfbdfm_table_nowcast(
  fit,
  format = c("data.frame", "latex", "html", "markdown"),
  digits = 4,
  caption = NULL
)
```

## Arguments

- fit:

  A fit from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  or
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- format:

  Character, `"data.frame"` (the default), `"latex"`, `"html"` or
  `"markdown"`. The data frame is the primary output; the other three
  render it through
  [`mfbdfm_kable()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_kable.md).

- digits:

  Integer, significant digits for the rendered formats. The data frame
  is returned unrounded.

- caption:

  Character or `NULL`, a caption for the rendered formats.

## Value

A data frame with columns `time`, `observed`, `nowcast`, `sd`, `lower`
and `upper`; or a `"knitr_kable"` object when `format` is not
`"data.frame"`.

## Details

The nowcast is computed *during* fitting and stored, not produced on
demand - which is why neither fit class has a
[`predict()`](https://rdrr.io/r/stats/predict.html) method (see
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)).
This function reads `$nowcast` and `$nowcast_var` and lines the observed
target series up against them; it does not re-estimate anything.

Rows where `observed` is `NA` are the periods the target series does not
cover - the genuine nowcasts and backcasts.

The nowcast is on the target series' **original scale** already, having
been de-standardized inside the sampler, so there is no `scale` argument
here.

## See also

[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md)

Other model tables:
[`mfbdfm_kable()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_kable.md),
[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md)

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
fit <- ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                              stats::window, start = 2021),
               stocks = lapply(data_ch_dataset_test$stocks[1:2],
                               stats::window, start = 2021),
               target = target, length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..
utils::tail(mfbdfm_table_nowcast(fit))
#>       time     observed      nowcast           sd        lower        upper
#> 15 2024.50  0.002901739  0.002901714 2.130158e-07  0.002901296  0.002902131
#> 16 2024.75  0.005175429  0.005175472 1.554287e-07  0.005175168  0.005175777
#> 17 2025.00  0.007858602  0.007858556 2.491472e-07  0.007858068  0.007859045
#> 18 2025.25  0.001230711  0.001230658 1.405407e-07  0.001230383  0.001230933
#> 19 2025.50 -0.004400677 -0.004400635 1.810394e-07 -0.004400990 -0.004400280
#> 20 2025.75  0.001506251  0.001506267 2.733247e-07  0.001505731  0.001506803
# }
```
