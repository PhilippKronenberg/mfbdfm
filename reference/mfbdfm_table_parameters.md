# Estimated parameters as a table, with posterior uncertainty

Every parameter block of a fitted model in one tidy data frame: the
factor autoregressive coefficients `phi`, the measurement-error
variances `sigma` and autocorrelations `rho`, and the volatility
parameter - `omega` where a stochastic volatility path was estimated,
the constant `factor_var` where it was not.

## Usage

``` r
mfbdfm_table_parameters(
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

A data frame with columns `block`, `parameter`, `series` (`NA` for
blocks that are not per-series), `mean`, `sd`, `lower`, `upper`, `fixed`
and `structural`; or a `"knitr_kable"` object when `format` is not
`"data.frame"`.

## What is not an estimate

Two columns mark values that should not be read as estimates:

- `fixed`:

  The value was imposed, not drawn. The only case is a
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  fit with `stochastic_volatility = FALSE`, whose factor innovation
  variance is fixed at exactly one because it carries the identification
  there.

- `structural`:

  The value was drawn, but under a prior that *is* the model's
  identification rather than a tuning knob - so it is informative by
  design and tells you about the restriction as much as about the data.
  For
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  these are the target series' own `sigma` and `rho`, shrunk toward zero
  to anchor the factor to the target; see
  [`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md),
  which lists the same two as structural.

## Blocks that are absent, and why

- `omega` for a
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  fit:

  `omega` is drawn in that model but is not packed into the retained
  draw vector, so no posterior summary of it exists. It is omitted
  rather than reported from a value that was never retained.

- `omega` with `stochastic_volatility = FALSE`:

  There is no volatility path for `omega` to be the innovation variance
  of, and the sampler never draws it - it keeps its start value.
  Reporting that number would be a silent wrong answer, so `factor_var`
  is reported instead.

- The volatility path itself:

  `h` is a latent state, one value per period, not a parameter. It is in
  `fit$pars$h`, with its posterior spread in `fit$pars_dist$h`. Note
  that the `factor_var` row is the posterior mean of the *variance*,
  `mean(exp(2h))` over draws – not `exp(2h)` evaluated at the posterior
  mean of `h`, which is strictly smaller since `exp` is convex.

- The loadings:

  In
  [`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
  which also handles the original-scale conversion they need.

## See also

[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md),
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)
for which priors are structural

Other model tables:
[`mfbdfm_kable()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_kable.md),
[`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md),
[`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md)

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
mfbdfm_table_parameters(fit)
#>    block                       parameter                   series         mean
#> 1    phi                          phi[1]                     <NA> 6.283522e-01
#> 2  sigma sigma[ch.seco.gdp.real.gdp.ssa] ch.seco.gdp.real.gdp.ssa 3.907145e-02
#> 3  sigma                  sigma[SWISSMI]                  SWISSMI 8.347070e-01
#> 4  sigma                sigma[SWCONPRCE]                SWCONPRCE 3.808958e-01
#> 5  sigma                sigma[SWPROPRCE]                SWPROPRCE 4.778498e-01
#> 6    rho   rho[ch.seco.gdp.real.gdp.ssa] ch.seco.gdp.real.gdp.ssa 3.942927e-06
#> 7    rho                    rho[SWISSMI]                  SWISSMI 4.162621e-01
#> 8    rho                  rho[SWCONPRCE]                SWCONPRCE 7.684636e-01
#> 9    rho                  rho[SWPROPRCE]                SWPROPRCE 7.362171e-01
#> 10 omega                           omega                     <NA> 1.115900e-02
#>              sd         lower        upper fixed structural
#> 1  2.069206e-01  2.903370e-01 0.8681942372 FALSE      FALSE
#> 2  2.727817e-02  1.027660e-02 0.0893629291 FALSE       TRUE
#> 3  7.641271e-02  7.023660e-01 0.9544230185 FALSE      FALSE
#> 4  4.737441e-02  2.946458e-01 0.4398751030 FALSE      FALSE
#> 5  1.020260e-01  3.423951e-01 0.6878589683 FALSE      FALSE
#> 6  4.558677e-05 -6.803303e-05 0.0000986538 FALSE       TRUE
#> 7  5.139411e-02  3.313423e-01 0.5127555367 FALSE      FALSE
#> 8  4.440423e-02  7.042077e-01 0.8518853328 FALSE      FALSE
#> 9  5.229508e-02  6.432053e-01 0.8007451666 FALSE      FALSE
#> 10 1.011621e-03  9.555133e-03 0.0127682070 FALSE      FALSE
# }
```
