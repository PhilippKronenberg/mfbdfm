# mfbdfm: A Mixed-Frequency Bayesian Dynamic Factor Model

``` r

library(mfbdfm)
```

## What is mfbdfm?

`mfbdfm` estimates a Bayesian mixed-frequency dynamic factor model: a
single dynamic factor extracted from indicators observed at different
frequencies, optionally anchored to a target series so the factor is
directly interpretable as that series’ growth rate rather than a generic
activity index. The package ships a flagship application, the **Weekly
Activity Index (WAI)**, a high-frequency GDP indicator for Switzerland
anchored to GDP growth, which this vignette uses as the worked example
throughout. WAI is built to combine two kinds of data:

- **Conventional macroeconomic indicators** — surveys, prices, trade,
  purchasing manager indices — published monthly or quarterly, and
- **Alternative high-frequency data** — payment and transaction volumes,
  mobility indicators, search-trend indices, traffic and flight counts —
  available daily or weekly, often with very short histories and
  irregular publication lags.

Unlike unsupervised approaches that extract a factor from high-frequency
data alone (e.g. principal components), the WAI is *supervised*: an
identification restriction anchors the factor to observed GDP growth, so
it is a direct high-frequency proxy for GDP rather than a generic
activity index that merely correlates with it.

The methodology, full empirical results, and a real-time forecast
evaluation are described in Kronenberg (2026); see
[`?mfbdfm`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm-package.md)
for the full citation and the underlying multi-factor framework of
Eckert, Kronenberg, Mikosch & Neuwirth (2025). This vignette covers the
package’s user-facing workflow only.

## The model, briefly

[`hfdfm()`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
estimates a single latent weekly factor $`f_t`$ whose (distributed-lag,
temporally aggregated) measurement equation links it to every input
series, and whose autoregressive state equation includes **stochastic
volatility** so the variance of common shocks can rise during crises
instead of being smoothed away. Three features make this work with
real-world mixed-frequency data:

- **Data augmentation** treats missing and lower-frequency observations
  as latent states, so a series that starts in 2020 and updates weekly,
  another that starts in 1990 and updates monthly, and quarterly GDP
  itself can all enter the same state-space model.
- **Stochastic volatility** in the factor state equation lets abrupt
  swings (e.g. the COVID-19 pandemic) show up as genuinely higher
  volatility rather than being averaged away.
- **Quasi-differencing** of the measurement equation removes serial
  correlation in each series’ idiosyncratic errors, so persistent
  indicator-specific noise doesn’t get misattributed to the common
  factor.

Identification fixes the factor’s loading on the target series (GDP) to
one and shrinks its measurement error toward zero, so the factor tracks
GDP growth closely by construction — see
[`?hfdfm`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
for the details and references, and
[`vignette("mfbdfm")`](https://philippkronenberg.github.io/mfbdfm/articles/mfbdfm.md)’s
“Real-time GDP vintages” section below for how the target series itself
is constructed for live use.

## A minimal worked example

The package ships a curated, model-ready dataset,
`data_ch_dataset_test`, so a small demonstration model can be estimated
without any external data. Real analyses use the full indicator set and
a much longer chain (the accompanying paper uses `length_sample = 5000`
after a burn-in of 1000); here we use a tiny subset and a short chain
purely so this vignette builds quickly.

``` r

data(data_ch_dataset_test)

target <- "ch.seco.gdp.real.gdp.ssa"
flows <- lapply(
  data_ch_dataset_test$flows[c(target, "SWISSMI", "traffic_PW")],
  stats::window, start = 2018
)
stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2018)

set.seed(1)
fit <- hfdfm(
  flows = flows, stocks = stocks, target = target,
  length_sample = 200, burn_in = 50
)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |=                                                                     |   1%  |                                                                              |=                                                                     |   2%  |                                                                              |==                                                                    |   2%  |                                                                              |==                                                                    |   3%  |                                                                              |===                                                                   |   4%  |                                                                              |===                                                                   |   5%  |                                                                              |====                                                                  |   5%  |                                                                              |====                                                                  |   6%  |                                                                              |=====                                                                 |   7%  |                                                                              |=====                                                                 |   8%  |                                                                              |======                                                                |   8%  |                                                                              |======                                                                |   9%  |                                                                              |=======                                                               |  10%  |                                                                              |========                                                              |  11%  |                                                                              |========                                                              |  12%  |                                                                              |=========                                                             |  12%  |                                                                              |=========                                                             |  13%  |                                                                              |==========                                                            |  14%  |                                                                              |==========                                                            |  15%  |                                                                              |===========                                                           |  15%  |                                                                              |===========                                                           |  16%  |                                                                              |============                                                          |  17%  |                                                                              |============                                                          |  18%  |                                                                              |=============                                                         |  18%  |                                                                              |=============                                                         |  19%  |                                                                              |==============                                                        |  20%  |                                                                              |===============                                                       |  21%  |                                                                              |===============                                                       |  22%  |                                                                              |================                                                      |  22%  |                                                                              |================                                                      |  23%  |                                                                              |=================                                                     |  24%  |                                                                              |=================                                                     |  25%  |                                                                              |==================                                                    |  25%  |                                                                              |==================                                                    |  26%  |                                                                              |===================                                                   |  27%  |                                                                              |===================                                                   |  28%  |                                                                              |====================                                                  |  28%  |                                                                              |====================                                                  |  29%  |                                                                              |=====================                                                 |  30%  |                                                                              |======================                                                |  31%  |                                                                              |======================                                                |  32%  |                                                                              |=======================                                               |  32%  |                                                                              |=======================                                               |  33%  |                                                                              |========================                                              |  34%  |                                                                              |========================                                              |  35%  |                                                                              |=========================                                             |  35%  |                                                                              |=========================                                             |  36%  |                                                                              |==========================                                            |  37%  |                                                                              |==========================                                            |  38%  |                                                                              |===========================                                           |  38%  |                                                                              |===========================                                           |  39%  |                                                                              |============================                                          |  40%  |                                                                              |=============================                                         |  41%  |                                                                              |=============================                                         |  42%  |                                                                              |==============================                                        |  42%  |                                                                              |==============================                                        |  43%  |                                                                              |===============================                                       |  44%  |                                                                              |===============================                                       |  45%  |                                                                              |================================                                      |  45%  |                                                                              |================================                                      |  46%  |                                                                              |=================================                                     |  47%  |                                                                              |=================================                                     |  48%  |                                                                              |==================================                                    |  48%  |                                                                              |==================================                                    |  49%  |                                                                              |===================================                                   |  50%  |                                                                              |====================================                                  |  51%  |                                                                              |====================================                                  |  52%  |                                                                              |=====================================                                 |  52%  |                                                                              |=====================================                                 |  53%  |                                                                              |======================================                                |  54%  |                                                                              |======================================                                |  55%  |                                                                              |=======================================                               |  55%  |                                                                              |=======================================                               |  56%  |                                                                              |========================================                              |  57%  |                                                                              |========================================                              |  58%  |                                                                              |=========================================                             |  58%  |                                                                              |=========================================                             |  59%  |                                                                              |==========================================                            |  60%  |                                                                              |===========================================                           |  61%  |                                                                              |===========================================                           |  62%  |                                                                              |============================================                          |  62%  |                                                                              |============================================                          |  63%  |                                                                              |=============================================                         |  64%  |                                                                              |=============================================                         |  65%  |                                                                              |==============================================                        |  65%  |                                                                              |==============================================                        |  66%  |                                                                              |===============================================                       |  67%  |                                                                              |===============================================                       |  68%  |                                                                              |================================================                      |  68%  |                                                                              |================================================                      |  69%  |                                                                              |=================================================                     |  70%  |                                                                              |==================================================                    |  71%  |                                                                              |==================================================                    |  72%  |                                                                              |===================================================                   |  72%  |                                                                              |===================================================                   |  73%  |                                                                              |====================================================                  |  74%  |                                                                              |====================================================                  |  75%  |                                                                              |=====================================================                 |  75%  |                                                                              |=====================================================                 |  76%  |                                                                              |======================================================                |  77%  |                                                                              |======================================================                |  78%  |                                                                              |=======================================================               |  78%  |                                                                              |=======================================================               |  79%  |                                                                              |========================================================              |  80%  |                                                                              |=========================================================             |  81%  |                                                                              |=========================================================             |  82%  |                                                                              |==========================================================            |  82%  |                                                                              |==========================================================            |  83%  |                                                                              |===========================================================           |  84%  |                                                                              |===========================================================           |  85%  |                                                                              |============================================================          |  85%  |                                                                              |============================================================          |  86%  |                                                                              |=============================================================         |  87%  |                                                                              |=============================================================         |  88%  |                                                                              |==============================================================        |  88%  |                                                                              |==============================================================        |  89%  |                                                                              |===============================================================       |  90%  |                                                                              |================================================================      |  91%  |                                                                              |================================================================      |  92%  |                                                                              |=================================================================     |  92%  |                                                                              |=================================================================     |  93%  |                                                                              |==================================================================    |  94%  |                                                                              |==================================================================    |  95%  |                                                                              |===================================================================   |  95%  |                                                                              |===================================================================   |  96%  |                                                                              |====================================================================  |  97%  |                                                                              |====================================================================  |  98%  |                                                                              |===================================================================== |  98%  |                                                                              |===================================================================== |  99%  |                                                                              |======================================================================| 100%
#> processing output..

class(fit)
#> [1] "hfdfm"
names(fit)
#>  [1] "factor"         "factor_var"     "index"          "nowcast"       
#>  [5] "nowcast_var"    "target"         "pars"           "data"          
#>  [9] "data_augmented" "inventory"
```

`fit$factor` is the annualized weekly growth rate implied by the model —
the WAI itself — and `fit$nowcast` is that same information aggregated
back up to the target’s own (here quarterly) frequency:

``` r

plot(fit$factor, ylab = "WAI (annualized %, weekly)", xlab = NULL)
```

![](mfbdfm_files/figure-html/plot-factor-1.png)

``` r

fit$nowcast
#>              Qtr1         Qtr2         Qtr3         Qtr4
#> 2018  0.010358258  0.007347781 -0.001407579  0.005268532
#> 2019  0.002011808  0.006503894  0.003023009  0.001999370
#> 2020 -0.010753651 -0.065794476  0.059015689  0.009101004
#> 2021  0.005967472  0.025366943  0.019780739  0.010104565
#> 2022  0.002357652  0.006806208  0.004997186  0.002075334
#> 2023  0.006192212 -0.003620587  0.004556616  0.003672437
#> 2024 -0.001181404  0.007846092  0.002901754  0.005175476
#> 2025  0.007858613  0.001230707 -0.004400680  0.001506296
```

`fit$index` gives the cumulated activity level (rebased to 100 at the
start of the estimation window), and `fit$pars` holds the posterior
means of the model parameters, including the factor loadings
(`fit$pars$lambda`) — the target series’ loading is fixed at 1 by
construction:

``` r

fit$pars$lambda[which(fit$inventory$key == target)]
#> [1] 1
```

## Real-time GDP vintages

The full `data_ch_dataset` deliberately ships *without* a GDP target
series: real analyses inject GDP at runtime from the real-time vintage
database, which ships with the package and needs no configuration:

``` r

vintages <- get_real_time_gdp_vintages("quarterly")
dim(vintages)
#> [1] 144 105
```

[`cut_data_real_time()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data_real_time.md)
truncates a dataset to what would have been observable at a given date,
substituting the appropriate GDP vintage for the target series — the
building block for the paper’s real-time out-of-sample evaluation:

``` r

dat_rt <- cut_data_real_time(data_ch_dataset_test, current_date = 2024.5,
                             GDP_gr_vintages = vintages)
tail(time(dat_rt$flows[[target]]))
#>         Qtr1    Qtr2    Qtr3    Qtr4
#> 2022                         2022.75
#> 2023 2023.00 2023.25 2023.50 2023.75
#> 2024 2024.00
```

## Beyond this vignette

The functions used in the accompanying analysis pipeline are exported
but need either the full (non-shipped) indicator set or previously saved
model fits, so they aren’t run here:

``` r

# Estimate the full WAI and optionally save the fit:
fit_full <- run_wai_adj(
  flows = dat$flows, stocks = dat$stocks, target = target,
  date = 2024.5, dataset_used = "full_RT", output_dir = "fits/updated"
)

# AR(1) benchmark, and the Diebold-Mariano test used to compare them:
fit_ar <- run_ar(flows = dat$flows, stocks = dat$stocks, target = target,
                 date = 2024.5, dataset_used = "full_RT")
dm_test_modified(errors_wai, errors_ar)
```

For the in-sample and out-of-sample evaluation tables and plots shown in
the paper (correlation heatmaps, relative RMSE/MAE tables against the
SECO-WEA, F-CURVE, SECO-SEC, SNB-BCI and KOF-BARO benchmarks), see the
`analysis/5_plots/` scripts in the package’s source repository, which
call
[`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md),
[`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md),
[`create_rel_error_tables()`](https://philippkronenberg.github.io/mfbdfm/reference/create_rel_error_tables.md)
and related functions documented under
[`?get_combined_cor_table`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md).

## References

### Methodology / WAI background

- Kronenberg, P. (2026) — *A high-frequency GDP indicator for
  Switzerland*, Swiss Journal of Economics and Statistics, 162:10.
  <https://doi.org/10.1186/s41937-026-00157-w>. The primary methodology
  and application paper for this package: derives the WAI as a single,
  GDP-identified factor from the model above, with full in-sample and
  real-time out-of-sample evaluation against the benchmarks listed
  below.
- Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025) —
  *Tracking economic activity with alternative high-frequency data*,
  Journal of Applied Econometrics, 40(3), 270-290. The underlying
  (multi-factor) Bayesian mixed-frequency dynamic factor model that
  [`hfdfm()`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
  implements as a single-factor special case.
- Eckert, Kronenberg, Mikosch, Neuwirth — *Weekly Activity Index (WWA)*,
  SECO technical note and press material, 2021. Available from SECO
  (seco.admin.ch).
- SECO — *Die Wöchentliche Wirtschaftsaktivität (WWA)*,
  Diskussionspapier.
- SECO — *Konjunkturtendenzen*, Exkurs on the WWA, issue 2020/4.
- SECO — *BIP-Flash Machbarkeitsstudie*, May 2024.
- SECO — *Einfliessende Indikatoren* (WWA input indicator list).
- SECO — *Methodik* note.

### Model derivation references (cited in Kronenberg 2026, Sect. 2)

- Chan, J. C., & Jeliazkov, I. (2009) — *Efficient simulation and
  integrated likelihood estimation in state space models*, International
  Journal of Mathematical Modelling and Numerical Optimisation, 1(1-2),
  101-120. Precision sampler used for the factor, stochastic volatility,
  and augmented-data Gibbs blocks.
- Chib, S., & Greenberg, E. (1994) — *Bayes inference in regression
  models with ARMA(p,q) errors*, Journal of Econometrics, 64(1-2),
  183-206. Quasi-differencing approach used to remove serial correlation
  in the measurement errors.
- Mariano, R. S., & Murasawa, Y. (2003) — *A new coincident index of
  business cycles based on monthly and quarterly series*, Journal of
  Applied Econometrics, 18(4), 427-443. Geometric-mean temporal
  aggregation scheme for flow variables (the distributed lag matrices
  `L0, ..., Ls`).
- Bai, J., & Wang, P. (2015) — *Identification and Bayesian estimation
  of dynamic factor models*, Journal of Business & Economic Statistics,
  33(2), 221-240. Factor loading normalization used for identification.
- Kim, S., Shepherd, N., & Chib, S. (1998) — *Stochastic volatility:
  Likelihood inference and comparison with ARCH models*, Review of
  Economic Studies, 65(3), 361-393. Mixture-of-normals approximation
  used to linearize the stochastic volatility measurement equation.
- Primiceri, G. E. (2005) — *Time varying structural vector
  autoregressions and monetary policy*, Review of Economic Studies,
  72(3), 821-852.
- Indergand, R., & Leist, S. (2014) — *A Real-Time Data Set for
  Switzerland*, Swiss Journal of Economics and Statistics, 150(4),
  331-352. Source of the real-time GDP vintages read by
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md).

### Swiss business-cycle indicator benchmarks

The in-sample and out-of-sample evaluations compare the WAI against
these existing Swiss business-cycle indicators:

- Glocker, C. and Kaniovski, S. (2018) — *Evaluation of Swiss Business
  Cycle Indicators*, WIFO.
- Glocker, C. and Wegmüller, P. (2019) — *30 Indikatoren auf einen
  Schlag*, Die Volkswirtschaft.
- Wegmüller, P. and Glocker, C. (2024) — *Capturing Swiss Economic
  Confidence*.
- Abberger, K. et al. (2014) — *The KOF Economic Barometer*, KOF, ETH
  Zurich.
- Abberger, K. et al. (2018) — *Using rule-based updating procedures to
  improve the performance*.
- Indergand, R. and Leist, S. (2014) — *A Real-Time Data Set for
  Switzerland*.
- Siliverstovs, B. (2011) — *The Real-Time Predictive Content*.

### Official statistics documentation

- FSO — national accounts documentation.
- SNB — Quartalsbulletin 2018/1.
