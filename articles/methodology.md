# The model behind mfbdfm

This vignette describes the model that `mfbdfm` estimates. It is
reference material: nothing is fitted here, and no code is needed to
read it. For the applied walkthrough — load data, fit, inspect, nowcast
— see
[`vignette("mfbdfm")`](https://philippkronenberg.github.io/mfbdfm/articles/mfbdfm.md).

The model is the one derived in Kronenberg (2026), which is the
single-factor, target-anchored special case of the multi-factor
framework of Eckert, Kronenberg, Mikosch & Neuwirth (2025). The two
exported entry points correspond to the two papers:
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
implements Kronenberg (2026),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
implements Eckert et al. (2025). They are genuinely different models,
not one model with a factor-count argument, and the section on
identification below is where the difference lives.

## Notation

Everything is written on the **highest** frequency present in the data —
weekly in the Weekly Activity Index (WAI) application, so 48 periods per
year. Let

- $`t = 1, \dots, T`$ index the high-frequency periods,
- $`i = 1, \dots, n`$ index the observed series,
- $`f_t`$ be the latent factor, and
- $`k`$ be the ratio of the highest to the lowest frequency in the
  dataset (weekly to quarterly: $`k = 12`$), with $`s = 2(k - 1)`$ the
  longest distributed lag any series needs.

Every series, the target included, is standardized to mean zero and unit
variance before estimation, so loadings are comparable across series;
[`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md)
records the mean and standard deviation used, and the nowcast and the
factor are converted back to the target’s original units at the end.

## The measurement equation

Each observed series loads on a distributed lag of the factor:

``` math
y_{i,t} \;=\; \lambda_i \sum_{j=0}^{s} \ell_{i,j}\, f_{t-j} \;+\; e_{i,t}.
```

$`\lambda_i`$ is the loading. The weights $`\ell_{i,j}`$ are *not*
estimated — they are fixed by the frequency and the type of series
$`i`$, and they are what makes the model mixed-frequency. That is the
subject of the next section.

The idiosyncratic errors are allowed to be serially correlated,

``` math
e_{i,t} \;=\; \rho_i\, e_{i,t-1} + \varepsilon_{i,t},
\qquad \varepsilon_{i,t} \sim N(0, \sigma_i^2),
```

with $`\rho_i`$ drawn series by series. This matters because a
persistent quirk of one indicator — a measurement convention, a
slow-moving reporting artefact — would otherwise be attributed to the
common factor, which is the one thing the model is supposed to estimate
cleanly.

Rather than carrying $`e_{i,t}`$ as an extra state, the measurement
equation is **quasi-differenced** (Chib & Greenberg, 1994): subtracting
$`\rho_i`$ times its own lag gives

``` math
y_{i,t} - \rho_i y_{i,t-1}
\;=\; \lambda_i \sum_{j=0}^{s} \ell_{i,j}\,\bigl(f_{t-j} - \rho_i f_{t-j-1}\bigr)
\;+\; \varepsilon_{i,t},
```

whose error is serially independent by construction. Setting
`serial_correlation = FALSE` holds every $`\rho_i`$ at (effectively)
zero, which reduces this to the plain measurement equation above.

## Mixed frequency: aggregation weights

A quarterly series is not observed 12 times a quarter with 11 values
missing; it is observed once, as a statement about the whole quarter.
The weights $`\ell_{i,j}`$ encode which statement.

For a series observed every $`a = k_{\max}/k_i`$ high-frequency periods:

- **Flow** variables (GDP, transactions, traffic counts — quantities
  accumulated over the period) use the triangular weights of Mariano and
  Murasawa (2003),
  ``` math
  \ell_i = \tfrac{1}{a}\,(1, 2, \dots, a-1, a, a-1, \dots, 2, 1),
  ```
  of length $`2a - 1`$. These are the weights that make a *growth rate*
  of a temporally aggregated level approximately equal to a weighted
  average of the underlying high-frequency growth rates — which is why
  they extend backwards past the period itself.
- **Stock** variables (prices, indices, survey levels — quantities
  measured at a point or averaged within the period) use the simple
  average $`\ell_i = (1/a, \dots, 1/a)`$, of length $`a`$.

Getting the classification wrong changes the weights and therefore the
results, which is why
[`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
prints the resolved flow/stock split before anything is estimated.

Everything else about missing data is handled by **data augmentation**:
unobserved high-frequency values, including all the periods in which a
quarterly series is silent, are treated as latent states and drawn from
their conditional posterior alongside the factor. A series that starts
in 2020 and updates weekly, one that starts in 1990 and updates monthly,
and quarterly GDP can therefore all enter the same state-space model
without imputation or truncation. In the prepared data matrix a `0`
encodes *missing* (the series are standardized, so zero is the
unconditional mean), which is why
[`fitted()`](https://rdrr.io/r/stats/fitted.values.html) and
[`residuals()`](https://rdrr.io/r/stats/residuals.html) mask those
entries rather than reporting them as fitted zeros.

## The state equation and stochastic volatility

The factor follows an autoregression of order `p`:

``` math
f_t \;=\; \sum_{m=1}^{p} \phi_m f_{t-m} + u_t,
\qquad u_t \sim N\!\bigl(0,\, e^{2 h_t}\bigr),
```

where the log standard deviation $`h_t`$ is itself a random walk,

``` math
h_t \;=\; h_{t-1} + \eta_t, \qquad \eta_t \sim N(0, \omega).
```

This is what lets the model treat 2020 as a period of genuinely higher
volatility rather than as a run of outliers to be smoothed away. Under a
constant variance, a shock the size of the pandemic quarter is so
improbable that the filter pulls the factor towards its mean instead of
following it; under stochastic volatility the variance moves with the
data and the factor tracks the swing.

The volatility block is drawn by the standard linearization: squaring
and taking logs turns the state equation residual into
$`\log u_t^2 = 2 h_t + \log \chi^2_1`$, and the $`\log \chi^2_1`$ error
is replaced by the seven-component normal mixture of Kim, Shephard and
Chib (1998), leaving a conditionally linear Gaussian state-space model
for $`h`$.

Setting `stochastic_volatility = FALSE` replaces the path $`h_t`$ with a
constant — but see the next section, because *what* that constant is
differs between the two models.

## Estimation

All blocks are drawn by Gibbs sampling, using the precision-based
simulation smoother of Chan and Jeliazkov (2009) for the
high-dimensional Gaussian blocks (the factor, the volatility path, and
the augmented data). Working with banded precision matrices rather than
running a Kalman filter forward and backward is what keeps a weekly
model over three decades tractable.

One sweep draws, in turn: the augmented data; the factor; the volatility
path $`h`$ (or the constant variance) and its innovation variance
$`\omega`$; the autoregressive coefficients $`\phi`$; the loadings
$`\lambda`$; the measurement variances $`\sigma_i^2`$; and the
measurement autocorrelations $`\rho_i`$. `length_sample` draws are kept
after `burn_in` discarded, thinned by `thinning`, and the returned
`$pars` are posterior means.

The nowcast is not a separate forecasting step. The target series is
part of the augmented data, so the sampler already produces a value for
it in every high-frequency period, observed or not; `$nowcast` is that
latent target series read off at the periods where the target is
normally recorded and converted back to its original units. This is why
the package deliberately has **no
[`predict()`](https://rdrr.io/r/stats/predict.html) method** — there is
no forecast to compute after the fact, and a
[`predict()`](https://rdrr.io/r/stats/predict.html) that returned stored
values would advertise a capability the model does not have.

## Identification: one scale, pinned in exactly one place

Any factor model has an unavoidable scale indeterminacy: replacing
$`f_t \to c f_t`$ and $`\lambda_i \to \lambda_i / c`$ leaves the
likelihood unchanged. The scale must therefore be pinned in exactly one
place, and only one. The two models spend that identification
differently, and almost every behavioural difference between them
follows from it.

|  | pins the loadings | pins the state variance |
|----|----|----|
| [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md) | yes — $`\lambda_{\text{target}} \equiv 1`$ | no, must stay free |
| [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md) | no — loadings unrestricted | yes — state covariance $`= I`$ |

### `ind_dfm()`: anchoring to the target

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
fixes the factor’s loading on `target` to one and, in addition, shrinks
the target’s measurement-error variance and its measurement
autocorrelation toward zero through informative priors (Kronenberg 2026,
Sect. 2.4). Together these make the factor track the observed growth
rate of the target rather than merely correlate with it: the extracted
factor *is* a high-frequency GDP growth rate, in percentage points, not
a standardized activity index that has to be rescaled before it means
anything.

This is a supervised alternative to extracting a factor from
high-frequency data alone (principal components, say). The price is that
the target’s priors are structural: they are the identification, not
tuning knobs.
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)
therefore moves tunable priors only, and relaxing the target’s
measurement variance would silently dissolve the anchoring rather than
producing a slightly different model.

Because the loadings carry the identification, the factor innovation
variance is a free parameter the data must determine. Setting
`stochastic_volatility = FALSE` in
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
therefore does **not** fix that variance at a value: it estimates a
single constant variance from its conjugate inverse-gamma posterior.

### `fcast_dfm()`: post-hoc rotation

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
samples an unrestricted $`q`$-factor model with the state covariance
fixed at the identity, and resolves the remaining rotational
indeterminacy *after* sampling, by a Procrustes rotation followed by a
varimax rotation. Its `target` argument does not enter estimation at all
— it only selects which series’ nowcast is surfaced at the top level of
the returned object.

Here the identification sits in the state variance, so
`stochastic_volatility = FALSE` means the innovation variance is fixed
at exactly one (Aßmann et al.’s original assumption, which Eckert et al.
relax to $`I e^{h}`$). Estimating a free constant there would sit on an
unidentified ridge, trading off exactly against the scale of
$`\Lambda`$. For the same reason the volatility path’s level and spread
are normalized away on every draw — only the *shape* of the volatility
path is identified — whereas in
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
the level is identified by the anchoring and is left alone.

The practical consequence: **`fcast_dfm(q = 1)` is not
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).**
They differ in identification, in priors (uninformative versus
target-anchored), and in how $`\phi`$ is drawn (Metropolis-Hastings
versus conjugate Gibbs). Use
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
when you want a directly interpretable proxy for one target series, and
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
when you want several common factors.

## References

### Primary references for this package

- Kronenberg, P. (2026) — *A high-frequency GDP indicator for
  Switzerland*, Swiss Journal of Economics and Statistics, 162:10.
  <https://doi.org/10.1186/s41937-026-00157-w>. The model described
  above, and the paper
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  implements.
- Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025) —
  *Tracking economic activity with alternative high-frequency data*,
  Journal of Applied Econometrics, 40(3), 270-290.
  <https://doi.org/10.1002/jae.3104>. The multi-factor framework
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  implements.

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
  aggregation scheme for flow variables (the distributed lag weights
  $`\ell_{i,j}`$).
- Bai, J., & Wang, P. (2015) — *Identification and Bayesian estimation
  of dynamic factor models*, Journal of Business & Economic Statistics,
  33(2), 221-240. Factor loading normalization used for identification.
- Kim, S., Shephard, N., & Chib, S. (1998) — *Stochastic volatility:
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
