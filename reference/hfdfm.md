# Estimate a high-frequency dynamic factor model

Estimates the Bayesian mixed-frequency dynamic factor model behind the
Swiss Weekly Activity Index (WAI) by Markov chain Monte Carlo (Gibbs)
sampling. Flow and stock indicator series of different frequencies are
combined into a single weekly activity factor that is coherent with the
low-frequency target series (typically quarterly real GDP), from which
weekly GDP nowcasts are derived.

## Usage

``` r
hfdfm(
  flows,
  stocks,
  target,
  p = 1,
  q = 1,
  length_sample = 10000,
  burn_in = 1000,
  thinning = 1,
  plots = FALSE,
  extend_to = NULL,
  stochastic_volatility = TRUE,
  serial_correlation = TRUE
)
```

## Arguments

- flows:

  Named list of `ts` objects treated as flow variables. Must contain
  `target`.

- stocks:

  Named list of `ts` objects treated as stock variables.

- target:

  Character, name of the low-frequency target series in `flows` (e.g.
  `"ch.seco.gdp.real.gdp.ssa"`).

- p:

  Integer, number of factor lags in the factor state equation.

- q:

  Integer, number of factors. Currently ignored: the sampler always uses
  a single factor.

- length_sample:

  Integer, number of posterior draws to keep.

- burn_in:

  Integer, number of initial draws to discard.

- thinning:

  Integer, keep every `thinning`-th draw after burn-in.

- plots:

  Logical, if `TRUE` draw base-graphics diagnostic plots of the data and
  of factor/volatility convergence during sampling.

- extend_to:

  Numeric (decimal time) or `NULL`. If beyond the sample end, the
  dataset is extended with zeros so forecasts can be produced.

- stochastic_volatility:

  Logical. Currently ignored: the sampler always includes stochastic
  volatility. Kept for API compatibility.

- serial_correlation:

  Logical. Currently ignored: the sampler always models serial
  correlation in measurement errors. Kept for API compatibility.

## Value

An object of class `"hfdfm"`: a list with components

- factor:

  `ts`, posterior mean of the annualized activity factor.

- factor_var:

  `ts`, posterior variance of the factor.

- index:

  `ts`, posterior mean of the cumulated activity index.

- nowcast:

  `ts`, posterior mean nowcast of the target series.

- nowcast_var:

  `ts`, posterior variance of the nowcast.

- target:

  Character, the target series name.

- pars:

  List of posterior parameter means (`h`, `lambda`, `phi`, `sigma`,
  `omega`, `rho`, `rho_var`).

- data:

  `ts` matrix of the prepared (standardized) data.

- data_augmented:

  `ts` matrix of the augmented dataset.

- inventory:

  Data frame describing the series (see
  [`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md)).

## Details

The factor is identified by fixing its loading on `target` to one and
shrinking the target's measurement-error variance and autocorrelation
toward zero (informative priors), so the extracted factor closely tracks
the observed growth rate of `target` rather than being merely correlated
with it. This resolves the usual scale/sign indeterminacy of dynamic
factor models and yields a directly interpretable high-frequency proxy
for the target series (see Kronenberg 2026, Sect. 2.4). All other series
are standardized and enter with uninformative priors. Missing and
lower-frequency observations are estimated as latent states via data
augmentation; the factor state equation includes stochastic volatility,
and measurement errors are quasi-differenced to remove serial
correlation (see `@references`).

## References

Kronenberg, P. (2026). A high-frequency GDP indicator for Switzerland.
*Swiss Journal of Economics and Statistics*, 162, 10.
[doi:10.1186/s41937-026-00157-w](https://doi.org/10.1186/s41937-026-00157-w)

Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025). Tracking
economic activity with alternative high-frequency data. *Journal of
Applied Econometrics*, 40(3), 270-290.

## Examples

``` r
# \donttest{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                stats::window, start = 2018)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2018)
set.seed(1)
fit <- hfdfm(flows = flows, stocks = stocks, target = target,
             length_sample = 50, burn_in = 10)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |=                                                                     |   2%  |                                                                              |==                                                                    |   3%  |                                                                              |====                                                                  |   5%  |                                                                              |=====                                                                 |   7%  |                                                                              |======                                                                |   8%  |                                                                              |=======                                                               |  10%  |                                                                              |========                                                              |  12%  |                                                                              |=========                                                             |  13%  |                                                                              |==========                                                            |  15%  |                                                                              |============                                                          |  17%  |                                                                              |=============                                                         |  18%  |                                                                              |==============                                                        |  20%  |                                                                              |===============                                                       |  22%  |                                                                              |================                                                      |  23%  |                                                                              |==================                                                    |  25%  |                                                                              |===================                                                   |  27%  |                                                                              |====================                                                  |  28%  |                                                                              |=====================                                                 |  30%  |                                                                              |======================                                                |  32%  |                                                                              |=======================                                               |  33%  |                                                                              |========================                                              |  35%  |                                                                              |==========================                                            |  37%  |                                                                              |===========================                                           |  38%  |                                                                              |============================                                          |  40%  |                                                                              |=============================                                         |  42%  |                                                                              |==============================                                        |  43%  |                                                                              |================================                                      |  45%  |                                                                              |=================================                                     |  47%  |                                                                              |==================================                                    |  48%  |                                                                              |===================================                                   |  50%  |                                                                              |====================================                                  |  52%  |                                                                              |=====================================                                 |  53%  |                                                                              |======================================                                |  55%  |                                                                              |========================================                              |  57%  |                                                                              |=========================================                             |  58%  |                                                                              |==========================================                            |  60%  |                                                                              |===========================================                           |  62%  |                                                                              |============================================                          |  63%  |                                                                              |==============================================                        |  65%  |                                                                              |===============================================                       |  67%  |                                                                              |================================================                      |  68%  |                                                                              |=================================================                     |  70%  |                                                                              |==================================================                    |  72%  |                                                                              |===================================================                   |  73%  |                                                                              |====================================================                  |  75%  |                                                                              |======================================================                |  77%  |                                                                              |=======================================================               |  78%  |                                                                              |========================================================              |  80%  |                                                                              |=========================================================             |  82%  |                                                                              |==========================================================            |  83%  |                                                                              |============================================================          |  85%  |                                                                              |=============================================================         |  87%  |                                                                              |==============================================================        |  88%  |                                                                              |===============================================================       |  90%  |                                                                              |================================================================      |  92%  |                                                                              |=================================================================     |  93%  |                                                                              |==================================================================    |  95%  |                                                                              |====================================================================  |  97%  |                                                                              |===================================================================== |  98%  |                                                                              |======================================================================| 100%
#> processing output..
fit$nowcast
#>              Qtr1         Qtr2         Qtr3         Qtr4
#> 2018  0.010358423  0.007347718 -0.001407741  0.005268504
#> 2019  0.002011790  0.006503837  0.003023097  0.001999369
#> 2020 -0.010753687 -0.065794475  0.059015687  0.009101038
#> 2021  0.005967522  0.025366881  0.019780812  0.010104476
#> 2022  0.002357706  0.006806281  0.004997254  0.002075209
#> 2023  0.006192308 -0.003620620  0.004556568  0.003672424
#> 2024 -0.001181540  0.007845926  0.002901892  0.005175521
#> 2025  0.007858584  0.001230728 -0.004400683  0.001506290
# }
```
