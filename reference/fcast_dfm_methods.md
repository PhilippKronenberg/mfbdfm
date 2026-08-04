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
fitted(object, ...)

# S3 method for class 'fcast_dfm'
residuals(object, ...)

# S3 method for class 'fcast_dfm'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S3 method for class 'fcast_dfm'
plot(x, ...)

# S3 method for class 'fcast_dfm'
summary(object, ...)
```

## Arguments

- n_show:

  Integer, how many of the most recent periods
  [`print()`](https://rdrr.io/r/base/print.html) shows.

- ...:

  Ignored, present for compatibility with the generics.

- object, x:

  A fit from
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- row.names, optional:

  Ignored, present for compatibility with the
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  generic.

## Value

As
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md),
except that [`coef()`](https://rdrr.io/r/stats/coef.html) returns a
matrix.

## Details

[`coef()`](https://rdrr.io/r/stats/coef.html) returns an `n x q` loading
matrix here rather than a vector, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) returns
one mean/lower/upper triple per factor.

## See also

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
fit <- fcast_dfm(flows = lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                                stats::window, start = 2021),
                 stocks = lapply(data_ch_dataset_test$stocks[1:2],
                                 stats::window, start = 2021),
                 target = target, q = 2, length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> running rotation of each draw..
#> Rotation iteration 1: convergence 2.83e-05
#> Rotation iteration 2: convergence 2.05e-05
#> Rotation iteration 3: convergence 2.71e-06
#> Rotation iteration 4: convergence 1.09e-06
#> Rotation iteration 5: convergence 4.44e-06
#> Warning: Rotation did not converge after 5 iterations (last change 4.44e-06, criterion "mean", tolerance 1e-09). Factor draws may not be rotated onto a common reference; consider raising `rotation_max_iter` in dfm_control().
#> running identification..
#> processing output..
fit
#> Multi-factor mixed-frequency dynamic factor model (Eckert et al. 2025)
#> Call: fcast_dfm(flows = lapply(data_ch_dataset_test$flows[c(target,     "SWISSMI")], stats::window, start = 2021), stocks = lapply(data_ch_dataset_test$stocks[1:2], 
#> 
#>   series (n)      : 4
#>   factors (q)     : 2
#>   factor lags (p) : 1
#>   periods (t)     : 250
#> 
#> Target series: ch.seco.gdp.real.gdp.ssa
#> 
#>   Most recent nowcasts (95% band):
#> 
#>         time   observed    nowcast      lower      upper
#>     2024.000    -0.0012    -0.0012    -0.0012    -0.0012
#>     2024.250     0.0078     0.0078     0.0078     0.0078
#>     2024.500     0.0029     0.0029     0.0029     0.0029
#>     2024.750     0.0052     0.0052     0.0052     0.0052
#>     2025.000     0.0079     0.0079     0.0079     0.0079
#>     2025.250     0.0012     0.0012     0.0012     0.0012
#>     2025.500    -0.0044    -0.0044    -0.0044    -0.0044
#>     2025.750     0.0015     0.0015     0.0015     0.0015
#> 
#> Full results: $factor, $ncst (all series), $data_hf, $target_series
coef(fit)          # a q-column matrix here, a vector for ind_dfm()
#>                               factor1      factor2
#> ch.seco.gdp.real.gdp.ssa -0.006836276 -0.003745831
#> SWISSMI                  -0.030761363 -0.011022397
#> SWCONPRCE                 0.149391280  0.084153123
#> SWPROPRCE                 0.029629679  0.065903122
head(as.data.frame(fit))
#>       time     factor1 factor1_lower factor1_upper     factor2 factor2_lower
#> 1 2020.542 -0.23909098     -2.230828      1.752646 -0.16804491     -2.262626
#> 2 2020.562  0.08903385     -2.247697      2.425765 -0.17912296     -2.315936
#> 3 2020.583  0.49154136     -2.081632      3.064715 -0.27295845     -2.351980
#> 4 2020.604  0.53385847     -1.525837      2.593554  0.07218768     -2.250751
#> 5 2020.625  0.52847328     -1.826084      2.883031  0.13162465     -1.680698
#> 6 2020.646  0.72151460     -2.085460      3.528489  0.30193638     -1.933885
#>   factor2_upper
#> 1      1.926536
#> 2      1.957690
#> 3      1.806064
#> 4      2.395126
#> 5      1.943948
#> 6      2.537758
# }
```
