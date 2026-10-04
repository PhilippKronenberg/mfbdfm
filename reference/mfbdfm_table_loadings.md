# Factor loadings as a table, with posterior uncertainty

The posterior mean, standard deviation and 95% interval of every factor
loading, as a tidy data frame - one row per series for an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit, one row per series and factor for a
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit.

## Usage

``` r
mfbdfm_table_loadings(
  fit,
  scale = c("standardized", "original"),
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

- scale:

  Character, `"standardized"` (the default, the model's own loadings) or
  `"original"` (rescaled into each series' own units). See Details.

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

A data frame with columns `series`, `type` (flow or stock), `freq`,
`factor`, `mean`, `sd`, `lower`, `upper` and `fixed`; or a
`"knitr_kable"` object when `format` is not `"data.frame"`. `sd`,
`lower` and `upper` are `NA` for a fit made before `$pars_dist` existed.

## Scale

The model works on standardized data:
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
replaces each series `x` by `(x - mean(x))/sd(x)`, so the loadings it
estimates are loadings on the standardized series. That is the
**default** here, `scale = "standardized"` - the model's own numbers,
unaltered, and the same values
[`coef()`](https://rdrr.io/r/stats/coef.html) returns.

`scale = "original"` multiplies each row by that series' standard
deviation from the inventory. Writing the measurement equation for
series `i` as `(x_i - m_i)/s_i = lambda_i f + e_i` and multiplying
through by `s_i` gives `x_i = m_i + (s_i lambda_i) f + s_i e_i`, so
`s_i lambda_i` is the loading in the series' own units: the change in
`x_i` per unit of the factor. The series mean does not enter, being an
intercept rather than a slope.

## The fixed loading

An
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit pins the loading on `target` at exactly one - that restriction is
the model's identification, which is what makes the factor interpretable
as the target's growth rate (see
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
and
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)).
The `fixed` column flags that row, so a value of one is not read as an
estimate that happened to land there. Its posterior `sd` is zero for the
same reason. On the original scale the fixed row reads `sd(target)`, the
target's own standard deviation, which is the correct unit conversion of
a loading of one.

A
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit has no fixed loading: its loadings are unrestricted during sampling
and identified afterwards by rotation. Note that the rotation does not
reach uniqueness (see the Maturity section of
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)),
so individual loadings there should not be read as unique across runs
even though this table reports a posterior interval for them.

## See also

[`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md),
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md),
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)

Other model tables:
[`mfbdfm_kable()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_kable.md),
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md),
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
mfbdfm_table_loadings(fit)
#>                     series  type freq  factor      mean        sd       lower
#> 1 ch.seco.gdp.real.gdp.ssa  flow    4 factor1 1.0000000 0.0000000  1.00000000
#> 2                  SWISSMI  flow   48 factor1 0.4162289 0.4708109 -0.33766472
#> 3                SWCONPRCE stock   12 factor1 0.4048938 0.8463779 -0.77656100
#> 4                SWPROPRCE stock   12 factor1 1.1901925 0.5948794  0.07909828
#>      upper fixed
#> 1 1.000000  TRUE
#> 2 1.090126 FALSE
#> 3 2.391210 FALSE
#> 4 2.061474 FALSE
mfbdfm_table_loadings(fit, scale = "original")
#>                     series  type freq  factor         mean          sd
#> 1 ch.seco.gdp.real.gdp.ssa  flow    4 factor1 0.0069821027 0.000000000
#> 2                  SWISSMI  flow   48 factor1 0.0059233213 0.006700074
#> 3                SWCONPRCE stock   12 factor1 0.0006139831 0.001283452
#> 4                SWPROPRCE stock   12 factor1 0.0032154423 0.001607135
#>           lower       upper fixed
#> 1  0.0069821027 0.006982103  TRUE
#> 2 -0.0048052804 0.015513502 FALSE
#> 3 -0.0011775811 0.003626043 FALSE
#> 4  0.0002136931 0.005569311 FALSE
mfbdfm_table_loadings(fit, format = "markdown")
#> 
#> 
#> |series                   |type  | freq|factor  |   mean|     sd|   lower|  upper|fixed |
#> |:------------------------|:-----|----:|:-------|------:|------:|-------:|------:|:-----|
#> |ch.seco.gdp.real.gdp.ssa |flow  |    4|factor1 | 1.0000| 0.0000|  1.0000| 1.0000|TRUE  |
#> |SWISSMI                  |flow  |   48|factor1 | 0.4162| 0.4708| -0.3377| 1.0901|FALSE |
#> |SWCONPRCE                |stock |   12|factor1 | 0.4049| 0.8464| -0.7766| 2.3912|FALSE |
#> |SWPROPRCE                |stock |   12|factor1 | 1.1902| 0.5949|  0.0791| 2.0615|FALSE |
# }
```
