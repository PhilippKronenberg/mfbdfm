# Methods for single-factor model fits

The generics supported by an
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fit.
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fits support the same set – see
[fcast_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm_methods.md).

## Usage

``` r
# S3 method for class 'ind_dfm'
coef(object, ...)

# S3 method for class 'ind_dfm'
fitted(object, ...)

# S3 method for class 'ind_dfm'
residuals(object, ...)

# S3 method for class 'ind_dfm'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S3 method for class 'ind_dfm'
plot(x, ...)

# S3 method for class 'ind_dfm'
summary(object, ...)

# S3 method for class 'ind_dfm'
print(x, n_show = 8, ...)
```

## Arguments

- object, x:

  A fit from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).

- ...:

  Ignored, present for compatibility with the generics.

- row.names, optional:

  Ignored, present for compatibility with the
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  generic.

- n_show:

  Integer, how many of the most recent periods
  [`print()`](https://rdrr.io/r/base/print.html) shows.

## Value

[`coef()`](https://rdrr.io/r/stats/coef.html) a named numeric vector;
[`fitted()`](https://rdrr.io/r/stats/fitted.values.html) and
[`residuals()`](https://rdrr.io/r/stats/residuals.html) `ts` matrices
with one column per series;
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) a data
frame with `time` and the factor with bands;
[`summary()`](https://rdrr.io/r/base/summary.html) an object of class
`"summary.mfbdfm_fit"`; [`print()`](https://rdrr.io/r/base/print.html)
and [`plot()`](https://rdrr.io/r/graphics/plot.default.html) return
their input invisibly.

## Details

- [`print()`](https://rdrr.io/r/base/print.html):

  Model dimensions and the most recent target nowcasts.

- [`summary()`](https://rdrr.io/r/base/summary.html):

  Dimensions, posterior mean parameters and residual fit; returns an
  object with its own [`print()`](https://rdrr.io/r/base/print.html)
  method.

- [`plot()`](https://rdrr.io/r/graphics/plot.default.html):

  The factor with a 95% band.

- [`coef()`](https://rdrr.io/r/stats/coef.html):

  The posterior mean factor loadings, named by series. The other
  parameter blocks (`phi`, `sigma`, `rho`, `h`) remain in `object$pars`.

- [`fitted()`](https://rdrr.io/r/stats/fitted.values.html):

  The augmented dataset: observed values where a series was observed,
  the model's latent estimate where it was not, on the standardized
  scale the model works in.

- [`residuals()`](https://rdrr.io/r/stats/residuals.html):

  Observed minus fitted. **Unobserved periods are `NA`, not zero** – the
  prepared data encodes a missing observation as `0`, so differencing
  directly would report a spurious residual wherever a series was not
  observed, which in a mixed-frequency model is most of the matrix for
  the low-frequency series.

- [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html):

  The factor with 95% bands, one row per period, so downstream code need
  not reach into the list structure.

There is deliberately no
[`predict()`](https://rdrr.io/r/stats/predict.html) method: the model
does not forecast in the usual sense – nowcasts are computed during
fitting and stored – so a
[`predict()`](https://rdrr.io/r/stats/predict.html) returning stored
values would advertise a capability that does not exist.

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[fcast_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm_methods.md)

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
fit
#> Single-factor mixed-frequency dynamic factor model (Kronenberg 2026)
#> Call: ind_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],     stats::window, start = 2021), stocks = lapply(data_ch_dataset_test$stocks[1:2], 
#> 
#>   series (n) : 4
#>   periods (t): 250
#>   target     : ch.seco.gdp.real.gdp.ssa
#> 
#>   Most recent nowcasts for ch.seco.gdp.real.gdp.ssa:
#> 
#>         time      nowcast
#>     2024.000     -0.00118
#>     2024.250      0.00785
#>     2024.500      0.00290
#>     2024.750      0.00518
#>     2025.000      0.00786
#>     2025.250      0.00123
#>     2025.500     -0.00440
#>     2025.750      0.00151
#> 
#> Full results: $factor, $nowcast, $index, $pars; summary(), plot(),
#> as.data.frame(), coef(), fitted(), residuals()
coef(fit)
#> ch.seco.gdp.real.gdp.ssa                  SWISSMI                SWCONPRCE 
#>               1.00000000               0.05379545               0.61872745 
#>                SWPROPRCE 
#>               0.94094691 
head(as.data.frame(fit))
#>       time    factor factor_lower factor_upper
#> 1 2021.000 0.4344031   -2.6906568     3.559463
#> 2 2021.021 0.9593749   -1.9345476     3.853297
#> 3 2021.042 1.4212840   -0.9120996     3.754668
#> 4 2021.062 2.0404843   -1.1264859     5.207455
#> 5 2021.083 2.1820033   -0.7314820     5.095489
#> 6 2021.104 3.7034597    0.2151573     7.191762
# }
```
