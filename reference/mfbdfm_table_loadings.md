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
`factor`, `mean`, `sd`, `lower`, `upper`, `fixed`, `weight_sum`,
`loading_std`, `std_lower`, `std_upper` and `r_squared`; or a
`"knitr_kable"` object when `format` is not `"data.frame"`. `sd`,
`lower` and `upper` are `NA` for a fit made before `$pars_dist` existed.

**Compare series with `loading_std` and `r_squared`, not `mean`.** A raw
loading multiplies a weighted sum of factor values, and the weights sum
to 12 for a quarterly flow, 4 for a monthly flow and 1 for a weekly
series or a stock, so raw loadings of different frequencies are not
comparable. `loading_std = mean * weight_sum / weight_sum[target]` puts
them on one scale, on which the target is 1 in
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).
`r_squared` is the share of the series' variance the common component
explains.

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
#> 
  |                                                                            
  |                                                                      |   0%
  |                                                                            
  |===                                                                   |   4%
  |                                                                            
  |======                                                                |   8%
  |                                                                            
  |========                                                              |  12%
  |                                                                            
  |===========                                                           |  16%
  |                                                                            
  |==============                                                        |  20%
  |                                                                            
  |=================                                                     |  24%
  |                                                                            
  |====================                                                  |  28%
  |                                                                            
  |======================                                                |  32%
  |                                                                            
  |=========================                                             |  36%
  |                                                                            
  |============================                                          |  40%
  |                                                                            
  |===============================                                       |  44%
  |                                                                            
  |==================================                                    |  48%
  |                                                                            
  |====================================                                  |  52%
  |                                                                            
  |=======================================                               |  56%
  |                                                                            
  |==========================================                            |  60%
  |                                                                            
  |=============================================                         |  64%
  |                                                                            
  |================================================                      |  68%
  |                                                                            
  |==================================================                    |  72%
  |                                                                            
  |=====================================================                 |  76%
  |                                                                            
  |========================================================              |  80%
  |                                                                            
  |===========================================================           |  84%
  |                                                                            
  |==============================================================        |  88%
  |                                                                            
  |================================================================      |  92%
  |                                                                            
  |===================================================================   |  96%
  |                                                                            
  |======================================================================| 100%
#> processing output..
mfbdfm_table_loadings(fit)
#>                     series  type freq  factor      mean        sd      lower
#> 1 ch.seco.gdp.real.gdp.ssa  flow    4 factor1 1.0000000 0.0000000  1.0000000
#> 2                  SWISSMI  flow   48 factor1 0.1325924 0.6720110 -0.9625887
#> 3                SWCONPRCE stock   12 factor1 0.6002307 0.7783230 -0.9389970
#> 4                SWPROPRCE stock   12 factor1 0.7839288 0.6976146 -0.3505126
#>      upper fixed weight_sum loading_std   std_lower std_upper   r_squared
#> 1 1.000000  TRUE         12  1.00000000  1.00000000 1.0000000 0.998520033
#> 2 1.217861 FALSE          1  0.01104937 -0.08021573 0.1014884 0.001035428
#> 3 1.785766 FALSE          1  0.05001923 -0.07824975 0.1488138 0.013732355
#> 4 1.790473 FALSE          1  0.06532740 -0.02920938 0.1492061 0.051330571
mfbdfm_table_loadings(fit, scale = "original")
#>                     series  type freq  factor        mean          sd
#> 1 ch.seco.gdp.real.gdp.ssa  flow    4 factor1 0.006982103 0.000000000
#> 2                  SWISSMI  flow   48 factor1 0.001886912 0.009563336
#> 3                SWCONPRCE stock   12 factor1 0.000910193 0.001180253
#> 4                SWPROPRCE stock   12 factor1 0.002117874 0.001884686
#>           lower       upper fixed weight_sum loading_std   std_lower std_upper
#> 1  0.0069821027 0.006982103  TRUE         12  1.00000000  1.00000000 1.0000000
#> 2 -0.0136985252 0.017331283 FALSE          1  0.01104937 -0.08021573 0.1014884
#> 3 -0.0014239000 0.002707945 FALSE          1  0.05001923 -0.07824975 0.1488138
#> 4 -0.0009469502 0.004837170 FALSE          1  0.06532740 -0.02920938 0.1492061
#>     r_squared
#> 1 0.998520033
#> 2 0.001035428
#> 3 0.013732355
#> 4 0.051330571
mfbdfm_table_loadings(fit, format = "markdown")
#> 
#> 
#> |series                   |type  | freq|factor  |   mean|     sd|   lower|  upper|fixed | weight_sum| loading_std| std_lower| std_upper| r_squared|
#> |:------------------------|:-----|----:|:-------|------:|------:|-------:|------:|:-----|----------:|-----------:|---------:|---------:|---------:|
#> |ch.seco.gdp.real.gdp.ssa |flow  |    4|factor1 | 1.0000| 0.0000|  1.0000| 1.0000|TRUE  |         12|      1.0000|    1.0000|    1.0000|    0.9985|
#> |SWISSMI                  |flow  |   48|factor1 | 0.1326| 0.6720| -0.9626| 1.2179|FALSE |          1|      0.0110|   -0.0802|    0.1015|    0.0010|
#> |SWCONPRCE                |stock |   12|factor1 | 0.6002| 0.7783| -0.9390| 1.7858|FALSE |          1|      0.0500|   -0.0782|    0.1488|    0.0137|
#> |SWPROPRCE                |stock |   12|factor1 | 0.7839| 0.6976| -0.3505| 1.7905|FALSE |          1|      0.0653|   -0.0292|    0.1492|    0.0513|
# }
```
