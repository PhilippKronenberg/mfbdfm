# mfbdfm: A Mixed-Frequency Bayesian Dynamic Factor Model

Estimates a Bayesian mixed-frequency dynamic factor model
([`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md))
that combines indicators observed at weekly, monthly and quarterly
frequencies into a single dynamic factor. The package ships a flagship
application, the Weekly Activity Index (WAI): a weekly GDP indicator for
Switzerland derived from conventional macroeconomic indicators combined
with alternative high-frequency data (mobility, transactions, search
trends, and similar series).

## Model in brief

The model extracts a single dynamic factor, constrained by an
identification restriction that fixes its loading on GDP to one, so the
factor is directly interpretable as weekly GDP growth rather than a
generic activity index. Three features let it combine heterogeneous,
incomplete high-frequency data with official GDP figures:

- **Data augmentation** treats missing and mixed-frequency observations
  as latent states, so series can enter with different starting dates,
  publication lags and frequencies (weekly, monthly, quarterly).

- **Stochastic volatility** in the factor state equation lets the
  variance of common shocks vary over time, so crisis-period swings
  (e.g. the COVID-19 pandemic) are not mechanically smoothed away.

- **Quasi-differencing** (Chib & Greenberg, 1994) removes serial
  correlation in the measurement errors, preventing persistent
  idiosyncratic noise in individual indicators from contaminating the
  common factor.

Estimation is by Gibbs sampling using the precision sampler of Chan and
Jeliazkov (2009), with temporal aggregation of flow variables following
the geometric-mean approximation of Mariano and Murasawa (2003).

The measurement and state equations, the mixed-frequency aggregation
weights, and how the scale is identified in each of the two models are
set out in
[`vignette("methodology", package = "mfbdfm")`](https://philippkronenberg.github.io/mfbdfm/articles/methodology.md).

## Status of the algorithms implemented here

The samplers in this package are **not** novel algorithms, and are not
presented as an improvement on any existing R implementation. They are
the **first packaged R implementation** of two published estimators that
previously existed only as the authors' own unpackaged replication
scripts:

- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  implements the single-factor, target-anchored model of Kronenberg
  (2026), the estimator behind the Weekly Activity Index.

- [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  implements the multi-factor model of Eckert, Kronenberg, Mikosch &
  Neuwirth (2025), which in turn builds on Assmann, Boysen-Hogrefe &
  Pape (2016).

The constituent methods are themselves established and cited to their
original sources: Gibbs sampling with the precision sampler of Chan and
Jeliazkov (2009), temporal aggregation following Mariano and Murasawa
(2003), quasi-differencing following Chib and Greenberg (1994), and (for
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md))
the Procrustes-plus-varimax rotation of Assmann et al. (2016). What is
new here is the packaging, validation, testing and documentation, not
the statistics. To our knowledge no other R package estimates either
model; where an implementation of a *related* model exists it is used as
a benchmark rather than replaced (see
`analysis/fcast/bmdfm_benchmark.R`).

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
is a fresh port rather than a copy, and it knowingly diverges from the
published multi-factor *factor* estimates in one respect – the
orientation of the VAR coefficients when `q > 1`; see the entry for \#66
in `NEWS.md` for the detail.

## Life cycle

**Experimental.** The package is distributed from GitHub only and has
not been released to CRAN. Version numbers follow `0.1.x`, and while the
model results are stable and reproducible (a seeded baseline in the
source repository guards them), the *user-facing API is not yet frozen*:
exported function and argument names may still change without a
deprecation cycle before 1.0.0. Changes that alter results or break
existing calls are recorded in `NEWS.md`. For reproducible work, pin a
fixed version (a release or a commit) rather than the moving `main`,
e.g.
`remotes::install_github("PhilippKronenberg/mfbdfm", ref = "<commit>")`.

## Getting started

The package ships
[mfbdfm_example_data](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_example_data.md),
a small self-contained dataset including the GDP target, so a nowcast is
two lines out of the box - see the example in
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
for the minimal version, or
[`vignette("mfbdfm")`](https://philippkronenberg.github.io/mfbdfm/articles/mfbdfm.md)
for an applied walkthrough. The full curated datasets
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
and
[data_ch_dataset_test](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset_test.md)
and the real-time GDP vintage database (in `inst/extdata/`) are there
for the real application. For the model itself rather than the workflow,
see
[`vignette("methodology", package = "mfbdfm")`](https://philippkronenberg.github.io/mfbdfm/articles/methodology.md).

## References

Kronenberg, P. (2026). A high-frequency GDP indicator for Switzerland.
*Swiss Journal of Economics and Statistics*, 162, 10.
[doi:10.1186/s41937-026-00157-w](https://doi.org/10.1186/s41937-026-00157-w)

Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025). Tracking
economic activity with alternative high-frequency data. *Journal of
Applied Econometrics*, 40(3), 270-290.
[doi:10.1002/jae.3104](https://doi.org/10.1002/jae.3104) (The
mixed-frequency dynamic factor model underlying `mfbdfm`; this package
estimates the single-factor, GDP-identified special case used in the
WAI.)

Assmann, C., Boysen-Hogrefe, J., & Pape, M. (2016). Bayesian analysis of
static and dynamic factor models with an unknown number of factors, and
structural instability. *Journal of Applied Econometrics*, 31(8),
1518-1533. [doi:10.1002/jae.2404](https://doi.org/10.1002/jae.2404)

A reference list of the related business-cycle-indicator literature is
in the "References" section of
[`vignette("mfbdfm")`](https://philippkronenberg.github.io/mfbdfm/articles/mfbdfm.md).

## See also

Useful links:

- <https://github.com/PhilippKronenberg/mfbdfm>

- <https://philippkronenberg.github.io/mfbdfm/>

- Report bugs at <https://github.com/PhilippKronenberg/mfbdfm/issues>

## Author

**Maintainer**: Philipp Kronenberg <philippkronenberg@gmx.ch>
\[copyright holder\]

Authors:

- Philipp Kronenberg <philippkronenberg@gmx.ch> \[copyright holder\]
