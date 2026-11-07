# Methods for multi-factor model fits

The generics supported by a
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit. These mirror the single-factor methods exactly – see
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
for what each one does and for why there is no
[`predict()`](https://rdrr.io/r/stats/predict.html) method.

## Usage

``` r
# S3 method for class 'fcast_dfm'
print(x, n_show = 8, ...)

# S3 method for class 'fcast_dfm'
coef(object, ...)

# S3 method for class 'fcast_dfm'
fitted(object, scale = c("standardized", "original"), ...)

# S3 method for class 'fcast_dfm'
residuals(object, scale = c("standardized", "original"), ...)

# S3 method for class 'fcast_dfm'
logLik(object, ...)

# S3 method for class 'fcast_dfm'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S3 method for class 'fcast_dfm'
plot(
  x,
  type = c("factor", "nowcast", "loadings", "residuals", "volatility", "fit"),
  series = NULL,
  level = 0.95,
  ...
)

# S3 method for class 'fcast_dfm'
autoplot(object, ...)

# S3 method for class 'fcast_dfm'
summary(object, ...)

# S3 method for class 'fcast_dfm'
screeplot(x, npcs = NULL, type = c("barplot", "lines"), main = NULL, ...)
```

## Arguments

- n_show:

  Integer, how many of the most recent periods
  [`print()`](https://rdrr.io/r/base/print.html) shows.

- ...:

  Ignored, present for compatibility with the generics. For
  `autoplot()`, passed on to
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html).

- object, x:

  A fit from
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- scale:

  Character, the scale
  [`fitted()`](https://rdrr.io/r/stats/fitted.values.html) and
  [`residuals()`](https://rdrr.io/r/stats/residuals.html) report on:
  `"standardized"` (the default) or `"original"`. As for
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md);
  see
  [ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md).

- row.names, optional:

  Ignored, present for compatibility with the
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  generic.

- type:

  Character. For
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html), which view
  to draw (see "Plot views" in
  [ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md));
  for [`screeplot()`](https://rdrr.io/r/stats/screeplot.html),
  `"barplot"` or `"lines"`, as for
  [`stats::screeplot()`](https://rdrr.io/r/stats/screeplot.html).

- series:

  Character vector of series names, or a numeric vector of column
  positions, restricting the `"residuals"` and `"fit"` views. `NULL`
  (the default) draws every series.

- level:

  Numeric in `(0, 1)`, the coverage of the credible band drawn by the
  `"factor"` and `"nowcast"` views. Defaults to `0.95`.

- npcs:

  Integer, how many factors
  [`screeplot()`](https://rdrr.io/r/stats/screeplot.html) shows, or
  `NULL` for all of them.

- main:

  [`screeplot()`](https://rdrr.io/r/stats/screeplot.html) title, or
  `NULL` for the default.

## Value

As
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md),
except that [`coef()`](https://rdrr.io/r/stats/coef.html) returns a
matrix and [`screeplot()`](https://rdrr.io/r/stats/screeplot.html)
invisibly returns the sorted variance shares.

## Details

[`coef()`](https://rdrr.io/r/stats/coef.html) returns an `n x q` loading
matrix here rather than a vector, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) returns
one mean/lower/upper triple per factor.

[`screeplot()`](https://rdrr.io/r/stats/screeplot.html) shows the share
of the standardized panel's variance explained by each factor, computed
from the posterior mean loadings and factors: the factor's own variance
times the sum of squared loadings on it, over the total variance of the
observed entries of the prepared data. **The rotated factors are not
ordered by variance the way principal components are** – the post-hoc
rotation has no such convention – so the bars are sorted for the plot
and labelled `f1`, `f2`, ... by their position in the fit, not by their
position in the plot. It is a description of a fitted model, not a
selection criterion; for choosing `q` before fitting, use
[`select_factors()`](https://philippkronenberg.github.io/mfbdfm/reference/select_factors.md).

As for
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fits, the stored nowcasts are reached with
[`mfbdfm_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_nowcast.md).

[`logLik()`](https://rdrr.io/r/stats/logLik.html) uses the same
definition as it does for
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
– see "What [`logLik()`](https://rdrr.io/r/stats/logLik.html) means
here" in
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md),
including why [`AIC()`](https://rdrr.io/r/stats/AIC.html) and
[`BIC()`](https://rdrr.io/r/stats/AIC.html) are only approximate. The
`df` count differs: the loadings are unrestricted in sampling and
identified post hoc by rotation, so `n*q - q*(q-1)/2` of them are
counted as free, and the volatility contributes a parameter only when
`stochastic_volatility = TRUE` (with it off the factor innovation
variance is *fixed* at one and carries the identification, where
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
still estimates a constant).

[`plot()`](https://rdrr.io/r/graphics/plot.default.html) offers the same
views as
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
– `"factor"`, `"nowcast"`, `"loadings"`, `"residuals"`, `"volatility"`
and `"fit"` – and returns a `ggplot`. The `"factor"` view gets one panel
per factor here, and `"loadings"` one facet per factor, with the series
ordered by their loading on the first factor so that a series sits in
the same row of every panel.

## See also

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md),
[`mfbdfm_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_nowcast.md)
for the nowcasts

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
fit <- fcast_dfm(mfbdfm_example_data, q = 2, length_sample = 20, burn_in = 5)
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
#> running rotation of each draw..
#> Rotation iteration 1: convergence 1.3e-07
#> Rotation iteration 2: convergence 3.94e-08
#> Rotation iteration 3: convergence 1.3e-08
#> Rotation iteration 4: convergence 4.28e-09
#> Rotation iteration 5: convergence 1.4e-09
#> Warning: Rotation did not converge after 5 iterations (last change 1.4e-09, criterion "mean", tolerance 1e-09). Factor draws may not be rotated onto a common reference; consider raising `rotation_max_iter` in dfm_control().
#> running identification..
#> processing output..
fit
#> Multi-factor mixed-frequency dynamic factor model (Eckert et al. 2025)
#> Call: fcast_dfm(flows = mfbdfm_example_data, q = 2, length_sample = 20,     burn_in = 5)
#> 
#>   series (n)      : 8
#>   factors (q)     : 2
#>   factor lags (p) : 1
#>   periods (t)     : 541
#> 
#> Target series: ch.seco.gdp.real.gdp.ssa
#> 
#>   Most recent nowcasts (95% band):
#> 
#>         time   observed    nowcast      lower      upper
#>     2024.250     0.0078     0.0078     0.0078     0.0078
#>     2024.500     0.0029     0.0029     0.0029     0.0029
#>     2024.750     0.0052     0.0052     0.0052     0.0052
#>     2025.000     0.0079     0.0079     0.0079     0.0079
#>     2025.250     0.0012     0.0012     0.0012     0.0012
#>     2025.500    -0.0044    -0.0044    -0.0044    -0.0044
#>     2025.750     0.0015     0.0015     0.0015     0.0015
#>     2026.000         NA     0.0008    -0.0259     0.0275
#> 
#>   1 of 45 periods have no observed value (nowcast/backcast).
#> 
#> Priors for fcast_dfm()  [type: default]
#> 
#>   lambda        b0 = 0, B0 = 1e+09  [structural]
#>   sigma         c0 = 3, d0 = 1e-09
#>   rho           r0 = 0, R0 = 0.001848
#>   omega         c0 = 3, d0 = 1
#> 
#> Control settings for fcast_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
#>   seed                     NULL      
#>   starting_values          NULL      
#>   omega_max                1         
#>   rotation_criterion       "mean"    
#>   rotation_tol             1e-09     
#>   rotation_max_iter        5         
#>   rotation_init_tol        1e-09     
#>   rotation_init_max_iter   100       
#>   rotation_on_failure      "warning" 
#> 
#>   Note: rotation_criterion "mean" is weaker than the published rule.
#>   dfm_control("fcast_dfm", strict = TRUE) matches Eckert et al. (2025).
#> 
#>   (the specification above is stored with the fit, as $priors and $control)
#> 
#> Full results: $factor, $ncst (all series), $data_hf, $target_series;
#> mfbdfm_nowcast() for the target's nowcasts
#> Tables: mfbdfm_table_loadings(), mfbdfm_table_parameters(),
#> mfbdfm_table_nowcast()
#> Draws: $draws, mfbdfm_diagnostics()
coef(fit)          # a q-column matrix here, a vector for ind_dfm()
#>                                  factor1      factor2
#> ch.fso.rtt.ind.r.noga0801.sa -0.11614185 -0.023241598
#> ch.ozd.e.wa.index.re.d11     -0.03344327 -0.033298774
#> SWISSMI                      -0.20132190  0.005643735
#> traffic_PW                   -0.48952469 -0.247890867
#> electricity_out              -0.05136667 -0.055091962
#> ch.seco.gdp.real.gdp.ssa     -0.06667733 -0.105825054
#> SWPMIPROQ                     0.05105061 -0.599251431
#> Arbeitsmarkt                 -0.26193214 -0.111643061
screeplot(fit)     # share of panel variance per rotated factor

head(as.data.frame(fit))
#>       time   factor1 factor1_lower factor1_upper    factor2 factor2_lower
#> 1 2014.542 0.3891046     -1.986084      2.764293 -0.3040175     -2.302868
#> 2 2014.562 0.1830946     -3.305745      3.671934 -0.5435117     -3.379361
#> 3 2014.583 0.3322598     -1.833357      2.497877 -0.4383906     -3.246427
#> 4 2014.604 0.3113668     -2.705500      3.328234 -0.3124634     -3.092800
#> 5 2014.625 0.2599294     -2.635831      3.155690 -0.3898384     -3.055476
#> 6 2014.646 0.1691983     -3.075359      3.413756 -0.1616238     -1.733753
#>   factor2_upper
#> 1      1.694833
#> 2      2.292338
#> 3      2.369646
#> 4      2.467873
#> 5      2.275799
#> 6      1.410506
logLik(fit)
#> 'log Lik.' -3263.138 (df=36)
BIC(fit)           # approximate here - see ?ind_dfm_methods
#> [1] 6809.103
mfbdfm_nowcast(fit, last = TRUE)
#>   time      nowcast         sd       lower      upper
#> 1 2026 0.0008331184 0.01361889 -0.02585941 0.02752565

plot(fit)                       # one panel per factor

plot(fit, type = "loadings")    # one facet per factor

plot(fit, type = "fit", series = 1:2)

# }
```
