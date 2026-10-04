# Estimate a multi-factor mixed-frequency dynamic factor model

Estimates the Bayesian multi-factor mixed-frequency dynamic factor model
of Eckert, Kronenberg, Mikosch & Neuwirth (2025) by Markov chain Monte
Carlo. Flow and stock indicator series of different frequencies are
combined into `q` common factors, from which high-frequency estimates
and nowcasts are derived for every input series.

## Usage

``` r
fcast_dfm(
  flows = NULL,
  stocks = NULL,
  target,
  p = 1,
  q = 2,
  length_sample = 1000,
  burn_in = 1000,
  thinning = 1,
  plots = FALSE,
  extend = NULL,
  stochastic_volatility = TRUE,
  serial_correlation = TRUE,
  ncores = NULL,
  priors = dfm_priors("fcast_dfm"),
  control = NULL
)
```

## Arguments

- flows:

  Either an
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  object carrying all series and their flow/stock classification, or a
  named list of `ts` objects treated as flow variables, or `NULL`. Must
  contain `target` if `stocks` does not.

- stocks:

  Named list of `ts` objects treated as stock variables, or `NULL`.

- target:

  Character, name of the series of interest (e.g.
  `"ch.seco.gdp.real.gdp.ssa"`). Must be present in `flows` or `stocks`.
  Does not affect estimation; see Details.

- p:

  Integer, number of lags in the factor VAR.

- q:

  Integer, number of factors. Must be smaller than the number of input
  series.

- length_sample:

  Integer, number of posterior draws to keep.

- burn_in:

  Integer, number of initial draws to discard.

- thinning:

  Integer, keep every `thinning`-th draw after burn-in.

- plots:

  Logical, if `TRUE` draw diagnostic plots of the factors, stochastic
  volatility and trace plots during sampling.

- extend:

  Numeric or `NULL`. If given, the dataset is extended by this many
  years with zeros so forecasts can be produced.

- stochastic_volatility:

  Logical, include stochastic volatility in the factor state equation.

- serial_correlation:

  Logical, model serial correlation in the measurement errors. If
  `FALSE`, the autocorrelations are fixed near zero.

- ncores:

  Integer or `NULL`. Number of cores for the rotation step, which is run
  in parallel via doParallel when supplied.

- priors:

  Prior specification from
  [`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md).
  The default reproduces the published priors exactly. Note that the
  loading prior carries the identification – it must stay diffuse for
  the post-hoc rotation to work; see
  [`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md).

- control:

  Optional numerical and algorithmic settings from
  [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md),
  or a named list of them. Bundles the rotation stopping rule and the
  stability bounds that were previously hard-coded. Omit it (the
  default) and the published behaviour is reproduced exactly;
  `dfm_control("fcast_dfm", strict = TRUE)` switches the rotation to the
  algorithm as specified in the online appendix, and
  `dfm_control("fcast_dfm", verbose = FALSE)` silences the progress
  messages and the progress bar.

## Value

An object of class `"fcast_dfm"`: a list with components

- factor:

  `ts` matrix of the `q` posterior mean factors, on the model's own
  standardized scale and covering the `2*(k - 1)` latent periods the
  distributed-lag aggregation reaches back into as well as the sample.
  ([`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  annualizes and de-standardizes its `factor`; the counterpart of this
  component there is `factor_std`.)

- factor_var:

  `ts` matrix of the corresponding variances.

- target:

  Character, the series named by `target`.

- nowcast, nowcast_var:

  `ts`, posterior mean and variance of the nowcast for `target`,
  extracted from `ncst`.

- pars:

  List of posterior means (`lambda`, `phi`, `sigma`, `rho`, `rho_var`,
  `h`) and the model dimensions (`n`, `q`, `p`, `s`, `t`, `k`).

- pars_dist:

  List of posterior spreads – `sd` and the 2.5%/97.5% quantiles – for
  `lambda`, `phi`, `sigma`, `rho` and `h`, read out of the rotated draws
  at fit time. The posterior *mean* stays in `pars`, so the two cannot
  disagree. There is deliberately no `omega` entry: `omega` is drawn
  here but not retained. Used by
  [`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md)
  and
  [`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md).

- ncst:

  List with `mean` and `var`, each a named list of nowcasts for every
  input series at its own frequency.

- data:

  `ts` matrix of the prepared (standardized) data, in which `0` encodes
  a missing observation.

- data_raw:

  The input series, as supplied.

- data_hf:

  List with `mean` and `var`, each a named list of high-frequency
  growth-rate estimates for every input series.

- data_augmented:

  `ts` matrix of the augmented dataset.

- data_augmented_rescaled:

  The same, back on each series' original scale.

- inventory:

  Data frame describing the series (see
  [`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md)).

- target_series:

  List collecting everything about `target` for inspection: `nowcast` (a
  data frame of `time`, `observed`, `mean`, `lower`, `upper` at the
  target's own frequency) and `high_frequency` (the same columns for the
  high-frequency growth estimate). See
  [fcast_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm_methods.md).

- call:

  The matched call.

## Details

This is a different model from
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
not a multi-factor setting of it. The two differ in how the factors are
identified, in their priors, and in how the autoregressive coefficients
are drawn:

- Identification:

  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  identifies the factor *during* sampling, by fixing the loading on
  `target` to one and shrinking that series' measurement error toward
  zero, so the factor is directly interpretable as the target's growth
  rate. `fcast_dfm()` instead samples an unidentified model and resolves
  the rotational indeterminacy afterwards: every draw is rotated onto a
  common reference by orthogonal Procrustes, then one global rotation is
  chosen to make the average loading matrix close to its varimax
  rotation.

- Priors:

  `fcast_dfm()` uses uninformative priors throughout; no series is
  treated specially.

- Factor dynamics:

  The factors follow a VAR(`p`) whose coefficients are drawn by
  Metropolis-Hastings with a stationarity constraint, rather than the
  conjugate Gibbs step used by
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).
  A single stochastic volatility path is shared by all `q` factors.

Because identification differs, `fcast_dfm(q = 1)` is **not** equivalent
to
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).
Use
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
for the target-anchored single-factor model of Kronenberg (2026), and
`fcast_dfm()` for the multi-factor model.

## Maturity

The **sampler is validated by simulation recovery**: data generated from
a known `q`-factor process is recovered at the trace R-squared values
published for this model (Eckert et al. 2025, Table 1, columns 6-8),
with the paper's figure inside the 95% interval of the Monte Carlo mean
in all three cells – including the misspecified `q_f = 2, q_hat = 1`
cell, which acts as a negative control by scoring around 0.4 rather than
high. (`dev/mc_recovery.R`, \#52.)

The **post-hoc rotation is not** so validated, and cannot be by that
measure: the trace R-squared is rotation-invariant by construction, so
it is blind to the rotation step – measured directly, unrotated 0.868
against rotated 0.869. A test that does exercise it, agreement of the
loading matrix across seeds, shows the rotation doing real work (0.62 to
0.88 in the worst case) but not reaching uniqueness: runs at different
seeds still settle on visibly different rotations. The likely cause is
the stopping rule, which uses the mean of the Givens angles where the
online appendix specifies the sum; see \#46.

So the factors and the nowcasts are on solid ground, while the *sign and
scale of individual loadings* should not be read as unique across runs.
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
whose factor is identified during sampling rather than afterwards,
remains the settled entry point.

`target` does not enter the estimation. It names the series whose
nowcast is surfaced at the top level of the return value for
convenience; results for every series remain available in `ncst` and
`data_hf`.

## References

Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025). Tracking
economic activity with alternative high-frequency data. *Journal of
Applied Econometrics*, 40(3), 270-290.
[doi:10.1002/jae.3104](https://doi.org/10.1002/jae.3104)

Kronenberg, P. (2026). A high-frequency GDP indicator for Switzerland.
*Swiss Journal of Economics and Statistics*, 162, 10.
[doi:10.1186/s41937-026-00157-w](https://doi.org/10.1186/s41937-026-00157-w)

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
for the single-factor, target-anchored model,
[`mfbdfm_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_nowcast.md)
to extract the nowcasts from the fit, and
[fcast_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm_methods.md)
for the methods the fit supports.

Other model fitting functions:
[`dfm_memory()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md),
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md),
[`select_factors()`](https://philippkronenberg.github.io/mfbdfm/reference/select_factors.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)
set.seed(1)
fit <- fcast_dfm(mfbdfm_example_data, q = 2, length_sample = 20, burn_in = 5)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |===                                                                   |   4%  |                                                                              |======                                                                |   8%  |                                                                              |========                                                              |  12%  |                                                                              |===========                                                           |  16%  |                                                                              |==============                                                        |  20%  |                                                                              |=================                                                     |  24%  |                                                                              |====================                                                  |  28%  |                                                                              |======================                                                |  32%  |                                                                              |=========================                                             |  36%  |                                                                              |============================                                          |  40%  |                                                                              |===============================                                       |  44%  |                                                                              |==================================                                    |  48%  |                                                                              |====================================                                  |  52%  |                                                                              |=======================================                               |  56%  |                                                                              |==========================================                            |  60%  |                                                                              |=============================================                         |  64%  |                                                                              |================================================                      |  68%  |                                                                              |==================================================                    |  72%  |                                                                              |=====================================================                 |  76%  |                                                                              |========================================================              |  80%  |                                                                              |===========================================================           |  84%  |                                                                              |==============================================================        |  88%  |                                                                              |================================================================      |  92%  |                                                                              |===================================================================   |  96%  |                                                                              |======================================================================| 100%
#> running rotation of each draw..
#> Rotation iteration 1: convergence 3.46e-06
#> Rotation iteration 2: convergence 5.1e-06
#> Rotation iteration 3: convergence 6.52e-07
#> Rotation iteration 4: convergence 1.28e-08
#> Rotation iteration 5: convergence 1.12e-08
#> Warning: Rotation did not converge after 5 iterations (last change 1.12e-08, criterion "mean", tolerance 1e-09). Factor draws may not be rotated onto a common reference; consider raising `rotation_max_iter` in dfm_control().
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
#>     2026.000         NA     0.0035    -0.0117     0.0187
#> 
#>   1 of 45 periods have no observed value (nowcast/backcast).
#> 
#> Full results: $factor, $ncst (all series), $data_hf, $target_series;
#> mfbdfm_nowcast() for the target's nowcasts
#> Tables: mfbdfm_table_loadings(), mfbdfm_table_parameters(),
#> mfbdfm_table_nowcast()
# }
```
