# Fit the WAI dynamic factor model at a given evaluation date

Runs
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
with the settings used in the WAI out-of-sample evaluation and windows
the factor and nowcast output to the evaluation date.

## Usage

``` r
run_wai_adj(
  flows,
  stocks,
  target,
  date,
  dataset_used,
  p = 1,
  length_sample = 5000,
  burn_in = 1000,
  thinning = 1,
  stochastic_volatility = TRUE,
  serial_correlation = TRUE,
  output_dir = NULL
)
```

## Arguments

- flows:

  Named list of `ts` objects containing `target`.

- stocks:

  Named list of `ts` objects.

- target:

  Character, name of the target series in `flows`.

- date:

  Numeric (decimal time), evaluation date; the factor is cut at this
  date.

- dataset_used:

  Character, dataset label used as sub-directory when saving.

- p:

  Integer, number of factor lags in the factor state equation.

- length_sample:

  Integer, number of posterior draws to keep.

- burn_in:

  Integer, number of initial draws to discard. `0` is allowed, which is
  what the second leg of a continued chain wants – see
  [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)'s
  `starting_values`.

- thinning:

  Integer, keep every `thinning`-th draw after burn-in.

- stochastic_volatility:

  Logical. If `TRUE` (default) the factor innovation variance follows a
  stochastic volatility process. If `FALSE` it is a single constant
  variance, **still estimated** rather than fixed – see `@details`.

- serial_correlation:

  Logical. If `TRUE` (default) the measurement errors are allowed to be
  serially correlated and their autocorrelations are drawn. If `FALSE`
  they are held at (effectively) zero.

- output_dir:

  Directory to save the fit to, or `NULL` (default) to skip saving. When
  given, the fit is saved as
  `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.

## Value

Invisibly, the windowed `ind_dfm` fit object.

## Details

Every modelling argument is passed straight through to
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
and the defaults are the ones this wrapper has always used, so existing
results are unaffected: `p = 1`, 5000 retained draws after 1000 burn-in,
unthinned, with both stochastic volatility and serial correlation on.
They are arguments rather than hard-coded values so that a short chain
can check the wiring — which is what the example below does — and so
that the wrapper does not silently withhold settings the model supports.
`length_sample`'s default differs from
[`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)'s
1000 deliberately: that is what each wrapper has always run.

## Examples

``` r
# \donttest{
# Short chain on the shipped data; a real evaluation uses the defaults, which
# run for minutes to tens of minutes.
data(mfbdfm_example_data)
d <- mfbdfm_example_data
out <- tempfile(); dir.create(out)

set.seed(1)
fit <- run_wai_adj(flows = d$flows, stocks = d$stocks, target = d$target,
                   date = 2023, dataset_used = "example",
                   length_sample = 20, burn_in = 5,
                   output_dir = out)
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
fit$nowcast
#>               Qtr1          Qtr2          Qtr3          Qtr4
#> 2015 -0.0005457363  0.0016735159  0.0070058593  0.0073790860
#> 2016  0.0034292383  0.0027133730  0.0023326153  0.0004949634
#> 2017  0.0026201705  0.0080288198  0.0079215760  0.0100126723
#> 2018  0.0103581705  0.0073476599 -0.0014075161  0.0052685469
#> 2019  0.0020117097  0.0065041489  0.0030230867  0.0019993062
#> 2020 -0.0107537155 -0.0657943355  0.0590157323  0.0091009700
#> 2021  0.0059674385  0.0253669005  0.0197808184  0.0101046076
#> 2022  0.0023577510  0.0068061259  0.0049971831  0.0020752830
#> 2023  0.0061923285 -0.0036205819  0.0045565768  0.0036724680
#> 2024 -0.0011814137  0.0078461706  0.0029018794  0.0051755931
#> 2025  0.0078585032  0.0012307624 -0.0044005955  0.0015062633
#> 2026 -0.0031351972                                          
list.files(out, recursive = TRUE)
#> [1] "example/fit_2023.Rda"
unlink(out, recursive = TRUE)
# }
```
