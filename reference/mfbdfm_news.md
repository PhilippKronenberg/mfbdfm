# News decomposition of a nowcast revision between two data vintages

Answers the question every high-frequency indicator raises: the nowcast
moved this week – which release did that? Between the data vintage a fit
was estimated on and a newer one, reports for every newly released
observation its *actual* value, the *forecast* the old vintage implied
for it, the *news* (actual minus forecast), the *gain* that news carries
on the target, and the resulting *impact* on the nowcast. The impacts
add up to the revision.

## Usage

``` r
mfbdfm_news(
  fit,
  new_data,
  stocks = NULL,
  period = NULL,
  by = c("series", "group"),
  groups = NULL,
  new_fit = NULL
)

# S3 method for class 'mfbdfm_news'
print(x, n_show = 10, ...)

# S3 method for class 'mfbdfm_news'
as.data.frame(
  x,
  row.names = NULL,
  optional = FALSE,
  what = c("observation", "component"),
  ...
)

# S3 method for class 'mfbdfm_news'
plot(x, n_show = 10, ...)
```

## Arguments

- fit:

  A fitted model from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  estimated on the **old** vintage.

- new_data:

  The new data vintage: either an
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  object or a named list of `ts` objects, carrying exactly the series
  `fit` was estimated on, at the same frequencies. Pass `stocks`
  alongside to supply the flow/stock pair instead.

- stocks:

  Named list of `ts` objects treated as stock variables, or `NULL`.
  Ignored when `new_data` is an
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  object. The flow/stock split is taken from the fit's inventory in any
  case; this argument exists so the same call shape as
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  works.

- period:

  Numeric (decimal time) or `NULL`. The target period whose nowcast
  revision is decomposed. Defaults to the last target period the old
  vintage had not yet observed.

- by:

  Either `"series"` (default, one component per input series) or
  `"group"` (one component per group of series). Governs the aggregation
  in `$by_component`, [`print()`](https://rdrr.io/r/base/print.html) and
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html); the
  per-observation detail is retained whichever is chosen.

- groups:

  Optional named character vector or list mapping every series name to a
  group name, used when `by = "group"` and the inventory has no `group`
  or `category` column.

- new_fit:

  Optional fit from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  on the new vintage. Supply it to get the `parameter` term; without it
  that term is `NA`.

- x:

  An object of class `"mfbdfm_news"`.

- n_show:

  Number of components to list, ordered by absolute impact.

- ...:

  Passed on to the underlying plotting calls; ignored by
  [`print()`](https://rdrr.io/r/base/print.html) and
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html).

- row.names, optional:

  Ignored, present for consistency with the generic.

- what:

  Either `"observation"` (default) for the per-observation tidy table
  with its summary rows, or `"component"` for the impacts aggregated to
  `by`.

## Value

An object of class `"mfbdfm_news"`, a list with

- table:

  The tidy table
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  returns: one row per newly released or revised observation with
  `term`, `series`, `group`, `time`, `actual`, `forecast`, `news`,
  `gain` and `impact`, followed by summary rows for the total revision
  and the parameter term.

- news, revisions:

  The two per-observation blocks on their own.

- by_component:

  Impacts aggregated to `by`: the component column, `news`, `revision`
  and their sum `impact`.

- totals:

  One row: `nowcast_old`, `revision`, `news`, `total`, `parameter`,
  `nowcast_new`, `posterior_old`, `posterior_new`.

- period, target, by, components, n_added, n_revised, model, call:

  Metadata.

With [`print()`](https://rdrr.io/r/base/print.html),
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) and
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) (a waterfall)
methods.

## Details

Conditional on the parameters, the factor path and the unobserved data
entries are jointly Gaussian with a sparse precision `Q` (the samplers'
own matrices; see
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
which uses the same construction). Writing `z = (f, x)` and splitting it
into the entries an observation pins and the latent rest,

\$\$E\[z_L \mid y\] = -Q\_{LL}^{-1} Q\_{LO}\\ y, \qquad \mathrm{Cov}(z_L
\mid y) = Q\_{LL}^{-1}.\$\$

A new vintage observes some of those latent entries. Conditioning the
same Gaussian on them gives, for the target entry `k` and the newly
released set `N`,

\$\$\mathrm{gain} = \Sigma\_{kN}\\\Sigma\_{NN}^{-1}, \qquad
\mathrm{impact} = \mathrm{gain} \times (\mathrm{actual} -
\mathrm{forecast}),\$\$

with `Sigma = Q_LL^-1`. This is Bańbura and Modugno's (2014)
decomposition with the Kalman smoother replaced by the stacked form this
package samples in. The orthogonalisation through `Sigma_NN^-1` is what
makes the impacts add up: several series are released in the same week
and their forecast errors are correlated, so a per-observation weight
that ignored that would not sum to the revision.

Nothing is refitted and `Q` is never inverted. One sparse Cholesky
factorisation of `Q_LL` serves every quantity above, with one solve per
newly released observation – a handful for a weekly vintage update. The
cost is linear in how much the new vintage adds, so this is a tool for
consecutive vintages; handing it a vintage that adds a year of data asks
for a year's worth of solves.

Two things are deliberately *not* carried over from the sampler. The
factor draw masks the forecast horizon with a selection vector, because
it conditions on the sampler's own augmented data and has to stop the
extension periods' imputed values from feeding back into the factor.
Here only genuine observations are conditioned on and everything else is
left latent, which is the correct marginal and needs no mask. And the
sampler pins observed entries with a `1e-9` observation variance; this
conditions on them exactly, which is the limit that nugget approximates
(the two agree to `O(1e-9)`, asserted in `tests/testthat/test-news.R`).

### What is held fixed, and where the rest of the revision goes

The decomposition is exact *at fixed parameters*, which is standard
practice and is also what makes it exact. Three things are therefore
held at the old vintage's values:

- the posterior mean parameters `theta` from `fit`;

- the volatility path `h`, extended over any periods the new vintage
  adds by holding its last value – the posterior mean extension of a
  random walk;

- **the standardisation.**
  [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
  standardises each series with moments computed from the vintage in
  hand, so the new vintage is re-prepared with the *fit's* inventory.
  Using the new vintage's own moments would make the nowcast a nonlinear
  function of the data and nothing would add up. The consequence is that
  the change in standardisation is part of the parameter term below, not
  of any series' impact. This looks like a bug later if it is not
  written down, so it is written down here.

What is left over is reported rather than folded in:

- `news`:

  Per newly released observation, as above. Exact by construction.

- `revision`:

  Per observation present in *both* vintages whose value changed. Also
  exact and also additive per observation: at a fixed observation set
  the plug-in nowcast is linear in the data, so a revised value
  contributes its own weight times its own change. (The plan for this
  feature expected only a block total here; it is finer than that.)

- `parameter`:

  `nowcast(theta_new) - nowcast(theta_old)`, the part of the revision
  that comes from re-estimating the model rather than from new data. It
  needs a fit on the new vintage, so it is `NA` unless `new_fit` is
  supplied.

### The nowcast reported here is the plug-in one

`nowcast_old` and `nowcast_new` are `E[x_target | y, theta-hat]`, the
nowcast with the posterior mean parameters plugged in. `fit$nowcast` is
the mean of the nowcast *over* the posterior of `theta`, which is a
different number; it is carried alongside as `posterior_old` so the two
can be compared rather than confused. The decomposition adds up to the
plug-in revision, which is the only revision it can add up to.

### Which period

One target period at a time: the gain is a row of the smoother's weight
matrix and that row belongs to one period. `period` defaults to the last
target period the old vintage had *not* yet observed – the nowcast, in
other words. Pass a decimal time to pick another. A period whose target
value the old vintage already observed is an error: its nowcast is
pinned to the observation and no amount of news can move it.

### [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md) is deferred

Deliberately, and not for want of algebra – the same derivation applies.
The target is not identified in that model:
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)'s
`target` argument only selects which series' nowcast is surfaced, and
the factors are pinned by a post-hoc Procrustes plus varimax rotation
rather than during sampling. A gain computed at a fixed `theta` would be
a gain in a rotation the new vintage's fit does not reproduce, so "the
impact of this release on the factor" needs a rule for aligning
rotations across vintages first. That is a second methodological
question, tracked separately; an `fcast_dfm` fit is an informative error
here rather than a plausible-looking number.

## References

Bańbura, M., & Modugno, M. (2014). Maximum likelihood estimation of
factor models on datasets with arbitrary pattern of missing data.
*Journal of Applied Econometrics*, 29(1), 133-160.
[doi:10.1002/jae.2306](https://doi.org/10.1002/jae.2306)

Kronenberg, P. (2026). A weekly activity index for Switzerland. *Swiss
Journal of Economics and Statistics*, 162:10.
[doi:10.1186/s41937-026-00157-w](https://doi.org/10.1186/s41937-026-00157-w)

## See also

[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md)
for the decomposition of the *level* of the factor and nowcast (the same
weight matrix, applied to the data rather than to the news),
[`cut_data_real_time()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data_real_time.md)
to build vintage pairs, and
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).

Other model functions:
[`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md),
[`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md),
[`mfbdfm_draws`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)

## Examples

``` r
# \donttest{
data(mfbdfm_example_data)

# two consecutive vintages of the shipped example data: the old one stops
# four weeks earlier, so the new one brings four weeks of releases
new <- mfbdfm_example_data
old <- new
old$flows <- lapply(old$flows, function(x)
  if(stats::frequency(x) > 4) stats::window(x, end = stats::time(x)[length(x) - 4])
  else x)
old$stocks <- lapply(old$stocks, function(x)
  stats::window(x, end = stats::time(x)[length(x) - 4]))

set.seed(1)
fit <- ind_dfm(old, length_sample = 50, burn_in = 10)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |=                                                                     |   2%  |                                                                              |==                                                                    |   3%  |                                                                              |====                                                                  |   5%  |                                                                              |=====                                                                 |   7%  |                                                                              |======                                                                |   8%  |                                                                              |=======                                                               |  10%  |                                                                              |========                                                              |  12%  |                                                                              |=========                                                             |  13%  |                                                                              |==========                                                            |  15%  |                                                                              |============                                                          |  17%  |                                                                              |=============                                                         |  18%  |                                                                              |==============                                                        |  20%  |                                                                              |===============                                                       |  22%  |                                                                              |================                                                      |  23%  |                                                                              |==================                                                    |  25%  |                                                                              |===================                                                   |  27%  |                                                                              |====================                                                  |  28%  |                                                                              |=====================                                                 |  30%  |                                                                              |======================                                                |  32%  |                                                                              |=======================                                               |  33%  |                                                                              |========================                                              |  35%  |                                                                              |==========================                                            |  37%  |                                                                              |===========================                                           |  38%  |                                                                              |============================                                          |  40%  |                                                                              |=============================                                         |  42%  |                                                                              |==============================                                        |  43%  |                                                                              |================================                                      |  45%  |                                                                              |=================================                                     |  47%  |                                                                              |==================================                                    |  48%  |                                                                              |===================================                                   |  50%  |                                                                              |====================================                                  |  52%  |                                                                              |=====================================                                 |  53%  |                                                                              |======================================                                |  55%  |                                                                              |========================================                              |  57%  |                                                                              |=========================================                             |  58%  |                                                                              |==========================================                            |  60%  |                                                                              |===========================================                           |  62%  |                                                                              |============================================                          |  63%  |                                                                              |==============================================                        |  65%  |                                                                              |===============================================                       |  67%  |                                                                              |================================================                      |  68%  |                                                                              |=================================================                     |  70%  |                                                                              |==================================================                    |  72%  |                                                                              |===================================================                   |  73%  |                                                                              |====================================================                  |  75%  |                                                                              |======================================================                |  77%  |                                                                              |=======================================================               |  78%  |                                                                              |========================================================              |  80%  |                                                                              |=========================================================             |  82%  |                                                                              |==========================================================            |  83%  |                                                                              |============================================================          |  85%  |                                                                              |=============================================================         |  87%  |                                                                              |==============================================================        |  88%  |                                                                              |===============================================================       |  90%  |                                                                              |================================================================      |  92%  |                                                                              |=================================================================     |  93%  |                                                                              |==================================================================    |  95%  |                                                                              |====================================================================  |  97%  |                                                                              |===================================================================== |  98%  |                                                                              |======================================================================| 100%
#> processing output..

nw <- mfbdfm_news(fit, new)
nw
#> News decomposition of a nowcast revision (ind_dfm)
#> Call: mfbdfm_news(fit = fit, new_data = new)
#> 
#>   target            : ch.seco.gdp.real.gdp.ssa
#>   period            : 2026
#>   new observations  : 28
#>   revised           : 0
#>   by                : series
#> 
#>   nowcast, old vintage         0.0040
#>     + news                     0.0003
#>     + data revisions           0.0000
#>   nowcast, new vintage         0.0043
#>     parameter revision            not computed (supply `new_fit`)
#> 
#> Impact on the nowcast, by series:
#> 
#>   electricity_out                               0.00020
#>   SWPMIPROQ                                    -0.00015
#>   ch.fso.rtt.ind.r.noga0801.sa                  0.00014
#>   traffic_PW                                    0.00012
#>   ch.ozd.e.wa.index.re.d11                     -0.00007
#>   SWISSMI                                       0.00003
#>   Arbeitsmarkt                                  0.00000
#> 
#> The nowcasts above plug in the posterior mean parameters rather than
#> averaging over them (the fit's own nowcast does not reach this period). See ?mfbdfm_news.
#> 
#> Full results: $table, $news, $revisions, $by_component, $totals;
#> as.data.frame(), plot()
head(as.data.frame(nw))
#>   term                       series group     time        actual      forecast
#> 1 news     ch.ozd.e.wa.index.re.d11  <NA> 2025.583 -0.0093429518 -0.0030329148
#> 2 news     ch.ozd.e.wa.index.re.d11  <NA> 2025.667  0.0192134823 -0.0017972170
#> 3 news ch.fso.rtt.ind.r.noga0801.sa  <NA> 2025.750  0.0009828011  0.0009637106
#> 4 news     ch.ozd.e.wa.index.re.d11  <NA> 2025.750 -0.0104906855 -0.0007584497
#> 5 news ch.fso.rtt.ind.r.noga0801.sa  <NA> 2025.833 -0.0022618882  0.0007159966
#> 6 news     ch.ozd.e.wa.index.re.d11  <NA> 2025.833 -0.0062227954 -0.0001837572
#>            news         gain        impact
#> 1 -6.310037e-03 -0.001490110  9.402649e-06
#> 2  2.101070e-02 -0.004176745 -8.775633e-05
#> 3  1.909048e-05  0.001441527  2.751944e-08
#> 4 -9.732236e-03 -0.003332334  3.243106e-05
#> 5 -2.977885e-03 -0.001544438  4.599159e-06
#> 6 -6.039038e-03  0.003581785 -2.163054e-05

# the impacts add up to the revision, by construction
d <- as.data.frame(nw)
sum(d$impact[d$term %in% c("news", "revision")]) - nw$totals$total
#> [1] 0
# }
```
