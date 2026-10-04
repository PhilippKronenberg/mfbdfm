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

  Integer, number of initial draws to discard.

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
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> processing output..
fit$nowcast
#>               Qtr1          Qtr2          Qtr3          Qtr4
#> 2015 -0.0005457446  0.0016734651  0.0070060306  0.0073791456
#> 2016  0.0034292197  0.0027130242  0.0023325391  0.0004948448
#> 2017  0.0026200338  0.0080291263  0.0079216530  0.0100128103
#> 2018  0.0103583351  0.0073478798 -0.0014074061  0.0052686346
#> 2019  0.0020116369  0.0065038823  0.0030230466  0.0019993583
#> 2020 -0.0107537455 -0.0657946724  0.0590157031  0.0091009021
#> 2021  0.0059674727  0.0253669834  0.0197807718  0.0101045612
#> 2022  0.0023577388  0.0068062742  0.0049970388  0.0020753272
#> 2023  0.0061921435 -0.0036206964  0.0045563970  0.0036724122
#> 2024 -0.0011812273  0.0078460677  0.0029016792  0.0051753619
#> 2025  0.0078585224  0.0012305562 -0.0044007143  0.0015062784
#> 2026  0.0114443811                                          
list.files(out, recursive = TRUE)
#> [1] "example/fit_2023.Rda"
unlink(out, recursive = TRUE)
# }
```
