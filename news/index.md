# Changelog

## mfbdfm 0.1.0.9000

- New
  [`mfbdfm_contributions()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_contributions.md)
  answers “which series drive the factor, and by how much, in each
  period?” for both fit classes, with
  [`print()`](https://rdrr.io/r/base/print.html),
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) and
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) methods. It
  is **not** “loading × standardised series” — that product is the
  series’ reconstruction *from* the factor, the reverse direction, and
  with missing data, mixed-frequency aggregation and serially correlated
  measurement errors it does not add up to the factor at all. What does
  add up is the smoother: conditional on the posterior mean parameters,
  `E[f | y, θ] = W y` is linear in the observed data, so grouping the
  columns of `W` by series (or by a group of series, via `by = "group"`)
  partitions the factor exactly, and an observation carries weight in
  periods in which its series was not observed. `W` is never formed — it
  has one column per observation, tens of gigabytes at the WAI’s
  dimensions — the group aggregation is pushed inside the sparse solve
  instead, leaving one solve against a few dozen right-hand sides.
  Contributions to the `target`’s nowcast are carried through the
  target’s loading and the distributed-lag aggregation, and split into
  `systematic` and `idiosyncratic`. Everything is on the standardised,
  non-annualised scale the sampler works on, the scale on which the
  decomposition is linear. The gap between `E[f | y, θ̂]` and the MCMC
  posterior mean factor is reported as an explicit `residual` column
  rather than hidden: it is parameter uncertainty, and on a short chain
  over a couple of years it is not small. The joint precision is now
  built once, by an internal `dfm_joint_precision()` shared with
  [`logLik()`](https://rdrr.io/r/stats/logLik.html) (whose values are
  bit-identical) and available for the news decomposition of
  [\#101](https://github.com/PhilippKronenberg/mfbdfm/issues/101).
  Sampling is untouched
  ([\#109](https://github.com/PhilippKronenberg/mfbdfm/issues/109)).

- **Table-ready summaries of a fit, with posterior uncertainty.** Three
  new exports return plain tidy data frames for both fit classes:
  [`mfbdfm_table_loadings()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_loadings.md)
  (series, type, frequency, factor, posterior mean, sd and 95%
  interval),
  [`mfbdfm_table_parameters()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_parameters.md)
  (every parameter block — `phi`, `sigma`, `rho`, and the volatility
  parameter) and
  [`mfbdfm_table_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_table_nowcast.md)
  (time, observed, nowcast, sd, interval). Each takes
  `format = c("data.frame", "latex", "html", "markdown")`, rendered
  through the also-exported
  [`mfbdfm_kable()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_kable.md);
  the data frame is the primary output and is left **unrounded**,
  `digits` affecting the rendered formats only. Reporting uncertainty
  needed something the fits did not store — they kept posterior *means*
  only — so both entry points now summarise the parameter blocks at fit
  time into a new `$pars_dist` component holding the posterior `sd` and
  the 2.5%/97.5% quantiles. That is a few numbers per parameter rather
  than the whole chain, consumes no RNG, and changes no existing
  computation: `baseline_run()` is
  [`identical()`](https://rdrr.io/r/base/identical.html) before and
  after. The posterior *mean* is deliberately **not** duplicated into
  `$pars_dist`, so a table cannot disagree with
  [`coef()`](https://rdrr.io/r/stats/coef.html) in the last bit
  ([\#113](https://github.com/PhilippKronenberg/mfbdfm/issues/113)).

  Two columns mark what is not an estimate. `fixed` flags an imposed
  value —
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)’s
  loading on `target`, pinned at one by the identifying restriction, and
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)’s
  factor innovation variance with `stochastic_volatility = FALSE`, fixed
  at one because it carries the identification there. `structural` flags
  a value that *was* drawn but under a prior that is the model’s
  identification rather than a tuning knob — the target’s own `sigma`
  and `rho` in
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  the same two
  [`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)
  calls structural. Two blocks are **absent rather than filled in**:
  `omega` for a
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  fit, because it is drawn there but never packed into the retained draw
  vector, and `omega` with `stochastic_volatility = FALSE`, where the
  sampler never draws it and reporting its untouched start value would
  be a silent wrong answer — `factor_var` is reported instead.

- [`fitted()`](https://rdrr.io/r/stats/fitted.values.html) and
  [`residuals()`](https://rdrr.io/r/stats/residuals.html) gain
  `scale = c("standardized", "original")` on both fit classes. The
  default and the NA-masking of unobserved periods are unchanged;
  `"original"` puts each column back in its own units, inverting
  [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)’s
  `(x - mean)/sd`. Residuals rescale by the standard deviation only, the
  series mean cancelling in a difference
  ([\#113](https://github.com/PhilippKronenberg/mfbdfm/issues/113)).

- [`summary()`](https://rdrr.io/r/base/summary.html) now carries
  `loadings_table` and `parameters_table` and its
  [`print()`](https://rdrr.io/r/base/print.html) method prints from
  them, so a printed summary and a tabulated one cannot report different
  numbers. The existing `$loadings`/`$phi`/`$sigma`/ `$rho` fields are
  kept. One visible change: the printed measurement-error block is the
  **variance** `sigma` with its interval, where it used to be the square
  root of the mean — printing
  [`sqrt()`](https://rdrr.io/r/base/MathFun.html) of a tabulated value
  is exactly the disagreement this was meant to remove
  ([\#113](https://github.com/PhilippKronenberg/mfbdfm/issues/113)).

- [`summary()`](https://rdrr.io/r/base/summary.html) on either fit class
  now reports a **per-series R-squared**, so the question “which of my
  series does the factor actually explain?” has an answer in the fit
  object (`$r_squared`: `series`, `freq`, `n_obs`, `r_squared`, sorted
  best-first). It is `1 - Var(residual)/Var(observed)` over the periods
  where each series was observed, with the fitted value taken to be the
  **common component** - loadings times factors, temporally aggregated -
  so it measures what the factor explains rather than the idiosyncratic
  AR part. Deliberately not computed from
  [`residuals()`](https://rdrr.io/r/stats/residuals.html):
  [`fitted()`](https://rdrr.io/r/stats/fitted.values.html) is the
  augmented dataset, whose observed entries the sampler pins to the
  observed values with a 1e-9 measurement prior, so every R-squared
  derived from it would be ~1. Read the ranking across series rather
  than the level - the common component is built from posterior *mean*
  parameters, and in
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  the factor’s scale is pinned to the target, which caps how much of a
  high-frequency series it can account for.
  [`print()`](https://rdrr.io/r/base/print.html) flags the target’s own
  ~1 as identification rather than a finding
  ([\#99](https://github.com/PhilippKronenberg/mfbdfm/issues/99)).

- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  gains a `$factor_std` component: the posterior mean factor on the
  model’s own standardized scale, over the `2*(k - 1)` latent periods
  the distributed-lag aggregation reaches back into as well as the
  sample. This is the quantity the observation equation multiplies by
  the loadings, and it is not recoverable from `$factor`, which is
  de-standardized and annualized through a convex transform.
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  already returns exactly this as its `$factor`
  ([\#99](https://github.com/PhilippKronenberg/mfbdfm/issues/99)).

- New
  [`mfbdfm_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_nowcast.md),
  an exported generic with methods for both fit classes, returns the
  stored nowcasts of the target series as a data frame of `time`,
  `nowcast`, `sd` and `level` credible bounds; `last = TRUE` returns
  only the most recent period. Previously the nowcasts were reachable
  only as `fit$nowcast`/`fit$nowcast_var` or through
  [`retrieve_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast.md),
  which takes a `model` string, returns a single value and is really a
  helper for the
  [`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md)/[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
  backcast workflow. Those two are unchanged and keep serving the AR
  benchmark. There is still **no**
  [`predict()`](https://rdrr.io/r/stats/predict.html) method, for the
  reason recorded in
  [`?ind_dfm_methods`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md):
  the nowcasts are computed while the model is fitted, so a
  [`predict()`](https://rdrr.io/r/stats/predict.html) returning stored
  values would advertise a capability the model does not have
  ([\#104](https://github.com/PhilippKronenberg/mfbdfm/issues/104)).

- [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
  gains `verbose`, which turns the samplers quiet. Both models honour
  it, and it silences the
  [`utils::txtProgressBar`](https://rdrr.io/r/utils/txtProgressBar.html)
  as well as the progress
  [`message()`](https://rdrr.io/r/base/message.html)s — the bar writes
  with [`cat()`](https://rdrr.io/r/base/cat.html), so
  [`suppressMessages()`](https://rdrr.io/r/base/message.html) never
  reached it and a scripted or parallel sweep had no way to run quietly
  at all
  ([\#118](https://github.com/PhilippKronenberg/mfbdfm/issues/118)).

- The warnings a fit can raise repeatedly over a sweep now carry
  condition classes, so one kind can be muffled without hiding the rest:
  `mfbdfm_warning_rho_fallback`, `mfbdfm_warning_rotation_cap` and
  `mfbdfm_warning_fit_failed`, all inheriting from `mfbdfm_warning`.
  [`?dfm_control`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
  documents the
  [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)
  idiom. The rho stationarity-screen fallback did not warn at all before
  this — it had a commented-out
  [`print()`](https://rdrr.io/r/base/print.html) where the substitution
  happens — so it is a **new** warning, raised once per fit with a count
  rather than once per series per MCMC draw
  ([\#118](https://github.com/PhilippKronenberg/mfbdfm/issues/118)).

- [`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)
  gains `on_error`. The default `"stop"` is unchanged; with `"warn"`, a
  vintage whose fit fails becomes a warning naming the vintage and
  returns `NULL`, so an expanding-window loop does not discard the
  vintages it has already estimated
  ([\#118](https://github.com/PhilippKronenberg/mfbdfm/issues/118)).

- Both fit classes gain a
  [`logLik()`](https://rdrr.io/r/stats/logLik.html) method, so
  [`AIC()`](https://rdrr.io/r/stats/AIC.html) and
  [`BIC()`](https://rdrr.io/r/stats/AIC.html) work on them. Neither
  sampler computes a likelihood and there is no Kalman filter in the
  package, so the quantity had to be *defined*: it is the Gaussian log
  density of the **observed** entries of the prepared data, at the
  posterior mean parameters and volatility path, with the factors and
  the unobserved entries marginalised out. It is computed exactly from
  the stacked Gaussian form the samplers already use — the factor prior
  precision from `draw_factors()` and the quasi-differenced measurement
  block from `draw_augmented_data()` — rather than by adding a filter,
  and it agrees with a dense brute-force evaluation to ~3e-12. Missing
  observations are encoded as `0` in the prepared data and are excluded,
  the same caveat that makes
  [`residuals()`](https://rdrr.io/r/stats/residuals.html) return `NA`
  there; `nobs` counts genuinely observed values only.
  **[`AIC()`](https://rdrr.io/r/stats/AIC.html)/[`BIC()`](https://rdrr.io/r/stats/AIC.html)
  are approximate for this model class** — the value is a plug-in
  likelihood at one parameter value rather than a posterior quantity, it
  conditions on the volatility path rather than integrating over it, and
  `df` is a raw parameter count that ignores the shrinkage the
  (structural) priors impose.
  [`?ind_dfm_methods`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
  says so plainly; prefer DIC or WAIC when the posterior matters.
  Sampling is untouched
  ([\#97](https://github.com/PhilippKronenberg/mfbdfm/issues/97)).

- [`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md)
  compounds the level index with `(1 + gr)` rather than `exp(gr)`. `gr`
  is already a net per-period rate, so the gross growth factor is
  `1 + gr`; `exp(x) > 1 + x` for every `x != 0`, which made the error
  one-signed - it could only push the level up - and it compounded. Its
  size is ~`gr^2/2` per period, so it was invisible in normal times and
  not invisible when the weekly factor swings by tens of percent:
  `sum(gr^2/2)` over 2020 alone was 0.00078 against 0.00044 for all 35
  other years combined, and the index stepped ~0.08 index points above
  published GDP during 2020 and never came back. **This changes
  `tab_gr_lv`, `tab_gr_lv_full` and `tab_wai_yoy`, and any plot built on
  them, by up to ~0.1 index points.** Nowcast-based results are
  untouched - the nowcast path never goes through this cumulation, which
  is why the paper’s replication never showed it
  ([\#92](https://github.com/PhilippKronenberg/mfbdfm/issues/92)).

- The same slip is corrected in four further places found by sweeping
  the codebase for it:
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)’s
  returned `$index` (`exp(cumsum(f))` where `f` is a net rate, so
  `cumprod(1 + f)`), and three loops in the analysis scripts - the WAI
  level index in `analytics_data.R` and `analytics_out-of-sample.R`, and
  the historical GDP level path in `analytics_data.R`. The GDP one bites
  hardest per period, being a quarterly rate: `gr^2/2` for 2020Q4 alone
  is 0.002. Two cumulations in that same file were already correct,
  which is what marks the others as slips rather than a convention
  ([\#92](https://github.com/PhilippKronenberg/mfbdfm/issues/92)).

- [`aggregate_predictor_to_quarterly()`](https://philippkronenberg.github.io/mfbdfm/reference/aggregate_predictor_to_quarterly.md)
  no longer defaults `method` to `"cut_off"`, a value no branch
  implements - calling the function with its own default always errored,
  and the error message named `'cut_off'` as valid while omitting
  `'last_month'`, which is. `method` is now required, validated before
  the legacy `"AR"`-name dispatch so the requirement holds on every
  path. The only production caller already passed it explicitly
  ([\#91](https://github.com/PhilippKronenberg/mfbdfm/issues/91)).

- [`aggregate_predictor_to_quarterly()`](https://philippkronenberg.github.io/mfbdfm/reference/aggregate_predictor_to_quarterly.md)
  also requires `cut_off_month_pos` for the `"last_month"` and `"last"`
  methods. Left `NULL`, it reached `month %% 3 == (NULL %% 3)`, which is
  `logical(0)`, so [`filter()`](https://rdrr.io/r/stats/filter.html)
  dropped every row and the function returned an empty frame instead of
  complaining
  ([\#91](https://github.com/PhilippKronenberg/mfbdfm/issues/91)).

- [`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md)
  gains `wai_qoq_q` and `wai_yoy_q`: the WAI aggregated to quarterly
  frequency the way GDP is actually measured. Quarterly GDP is a
  *flow* - the quarter’s average activity - so the like-for-like
  aggregate is the quarterly mean of the level index, with growth taken
  between those means. Compared that way the WAI matches published GDP
  at a correlation of 1.000 and an RMSE of 0.04pp over 143 quarters;
  compared against quarter *endpoints* it appears to miss 2020Q2
  entirely, because activity collapsed and recovered inside that
  quarter.

- New
  [`gdp_web_series()`](https://philippkronenberg.github.io/mfbdfm/reference/gdp_web_series.md),
  which returns published GDP as annualised QoQ growth, YoY growth and a
  level index rebased to 2019Q4 = 100 - the same three measures as the
  exported WAI series and on the same scale, so they share an axis. The
  conversion lives in one tested place because doing it by hand is what
  produced two bugs: raw log differences plotted against annualised
  percentages (wrong by a factor of ~400), and
  [`as.numeric()`](https://rdrr.io/r/base/numeric.html) on a `Date`
  (days since 1970, so no GDP point matched any week)
  ([\#76](https://github.com/PhilippKronenberg/mfbdfm/issues/76)).

- [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
  gains `output_type = "level"`, validates `output_type` with
  [`match.arg()`](https://rdrr.io/r/base/match.arg.html), and takes
  `start_date`/`end_date`. An unmatched `output_type` used to fall
  through both branches and return the untransformed levels *silently*,
  so a typo produced levels labelled as growth. The levels are a
  documented option now rather than an accident
  ([\#76](https://github.com/PhilippKronenberg/mfbdfm/issues/76)).

- [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
  no longer hard-codes a `2025-12-31` upper bound. It removed nothing
  while the shipped vintage files ended in 2025, and would have silently
  truncated the newest quarter the moment a 2026 vintage arrived -
  exactly when a live indicator needs it
  ([\#76](https://github.com/PhilippKronenberg/mfbdfm/issues/76)).

- [`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md)
  accepts a `gdp` frame carrying any of `qoq`, `yoy` and `index` and
  writes `gdp_qoq`, `gdp_yoy` and `gdp_index` accordingly, so official
  GDP can be shown against all three WAI views. The older `time`/`value`
  shape still works and still lands in `gdp_qoq`
  ([\#76](https://github.com/PhilippKronenberg/mfbdfm/issues/76)).

- New
  [`export_wai_web()`](https://philippkronenberg.github.io/mfbdfm/reference/export_wai_web.md),
  which turns a saved WAI fit into the wide `wai_data.csv` and
  `wai_meta.json` pair consumed by the public dashboard. The CSV
  contract (column names and order, empty string for missing, ISO dates,
  LF endings) is the whole interface to the front end, and is what the
  new tests pin down
  ([\#71](https://github.com/PhilippKronenberg/mfbdfm/issues/71)).

- [`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md)
  no longer dates the level index against a hard-coded 1990-2025 weekly
  grid. `zoo()` silently recycles its data to the length of `order.by`,
  so any fit shorter than that grid had its index wrapped around and
  re-dated, and the level bounds were computed from the wrong values.
  The grid now comes from the fit. The bounds were never returned, so no
  previously returned table changes; they are returned now, as
  `tab_gr_lv_full`
  ([\#71](https://github.com/PhilippKronenberg/mfbdfm/issues/71)).

- [`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md)
  warns and rebases to the first observation when the fit does not span
  the 2019Q4 base window, instead of silently returning a level index of
  all `NaN` - which is what this function’s own documented example,
  fitting from 2021, had been producing
  ([\#71](https://github.com/PhilippKronenberg/mfbdfm/issues/71)).

## mfbdfm 0.1.0

First functional version of the package, converting the WAI research
code into a proper R package
([\#9](https://github.com/PhilippKronenberg/mfbdfm/issues/9)-#19). The
package (and repo) were renamed from `waiind` to `mfbdfm` before
release, since the underlying model is a general mixed-frequency
Bayesian dynamic factor model and WAI is one application of it
([\#37](https://github.com/PhilippKronenberg/mfbdfm/issues/37)).

### Breaking changes

- `hfdfm()` is renamed
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  and its S3 class with it. There is no deprecated alias: calls to
  `hfdfm()` will fail with “could not find function”
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).
- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  no longer takes a `q` argument. It was accepted and silently ignored,
  so `hfdfm(q = 2)` returned a one-factor model without complaint. Use
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  for multi-factor estimation
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).
- Both fit classes now agree on their data components: `$data` is the
  prepared (standardized) matrix and `$data_raw` the series as supplied.
  Previously `$data` meant the prepared matrix for
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  but the raw input list for
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
  so the same expression returned unrelated things – e.g.
  `length(fit$data)` gave 1250 for one and 5 for the other, with no
  error.
  **[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  is unaffected**; for
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
  `$data` changes meaning and `$data_missings` is renamed to `$data`
  ([\#50](https://github.com/PhilippKronenberg/mfbdfm/issues/50)).

### New features

- [`mfbdfm_example_inputs()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_example_inputs.md)
  builds the synthetic `inputs` bundle the analytics table builders
  expect. Their examples were previously `\dontrun{}` sketches referring
  to objects that did not exist, so `R CMD check` never executed them;
  nine topics now run and are checked. The test suite uses the same
  fixture, so the examples and the tests cannot drift onto different
  input shapes
  ([\#20](https://github.com/PhilippKronenberg/mfbdfm/issues/20)).

- [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
  bundles the numerical and algorithmic settings that were previously
  hard-coded inside the samplers, as an **optional** `control` argument
  on both entry points – omit it and the published behaviour is
  reproduced exactly (verified: all four `dev/baseline.rds`
  configurations identical). Covers the rotation stopping rule, the
  stationarity screen on the measurement-error autocorrelations, the
  caps on `phi`/`sigma`/`omega`, and two numerical guards.
  `dfm_control("fcast_dfm", strict = TRUE)` switches the rotation to the
  algorithm as published in the online appendix to Eckert et al.

  2025. – the **sum** of squared deviations rather than the mean
        ([\#46](https://github.com/PhilippKronenberg/mfbdfm/issues/46)).

- The rotation’s iteration caps are now finite by construction. `Inf` is
  refused: an unbounded loop has no termination guarantee. The defaults
  are safety valves rather than targets – measured convergence is 5-7
  iterations at roughly an order of magnitude per iteration, against a
  strict cap of 100. `initialize_theta_star_fcast()`, which previously
  had **no cap at all**, now has one
  ([\#46](https://github.com/PhilippKronenberg/mfbdfm/issues/46)).

- [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)’s
  sampler is now validated by simulation recovery. Data generated from a
  known `q`-factor process is recovered at the trace R-squared values
  published for this model (Eckert et al. 2025, Table 1), with the
  paper’s figure inside the 95% interval of the Monte Carlo mean in all
  three cells – 0.717 vs 0.68, 0.856 vs 0.84, and 0.408 vs 0.39 for the
  misspecified cell that serves as a negative control. Tooling and the
  committed result snapshot are in `dev/mc_recovery.R` and
  `dev/mc_results.rds`;
  [`?fcast_dfm`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)’s
  Maturity section is updated to say what is and is not established,
  since the rotation-invariant metric cannot validate the post-hoc
  rotation
  ([\#52](https://github.com/PhilippKronenberg/mfbdfm/issues/52)).

- [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  assembles the model input from a long or wide data frame, an `mts`, or
  a named list of `ts`, and can be passed straight to
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  or
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  as the first argument (`flows`/`stocks` keep working unchanged). Its
  real purpose is to make the flow/stock classification inspectable:
  previously a series’ type was expressed by *which argument it was
  passed in*, so there was nowhere to check it, and misclassifying a
  lower-frequency series silently changed its temporal aggregation
  weights (a monthly series gets 7 nonzero lags as a flow against 4 as a
  stock; quarterly, 23 against 12).
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  requires `type` for exactly the series where it can change the answer
  – those below the highest frequency, since at the highest frequency
  the two sets of weights are provably identical – and
  [`print()`](https://rdrr.io/r/base/print.html) shows the resolved
  classification and frequencies before you commit to a run that takes
  minutes to hours
  ([\#56](https://github.com/PhilippKronenberg/mfbdfm/issues/56)).

- [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  also puts weekly (52) and daily (365) series onto the
  48-periods-per-year grid the models are built on, using
  [`daily2weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/daily2weekly.md).
  This is not cosmetic:
  [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
  matches observations onto a `1/max(freq)` grid by an exact join, and a
  frequency-52 series raises `max(freq)` so that shifted *monthly*
  observations no longer land on it. On a 20-quarter / 60-month /
  260-week panel the monthly series retained only 20 of its 60
  observations, with no error or warning. The conversion is reported by
  [`message()`](https://rdrr.io/r/base/message.html), shown by
  [`print()`](https://rdrr.io/r/base/print.html), and recorded in
  `meta$frequency_in`
  ([\#56](https://github.com/PhilippKronenberg/mfbdfm/issues/56)).
  Weekly series go **via daily**: since 48 does not divide 52, mapping
  weekly points straight onto the grid gives each slot one or two of
  them – a nearest-point pick that leaves occasional empty slots and a
  few slots a year blending two weeks while the rest blend one.
  Expanding to daily first gives every slot 6-8 days and makes its value
  an overlap-weighted blend. On a linear ramp the direct route steps
  `1.5, 1.5, 1, 1, ...` against a correct constant rate of
  `52/48 = 1.083`; via daily the worst deviation falls from 0.42 to 0.18
  and the median from 0.08 to 0.04.

- [`daily2weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/daily2weekly.md)
  gains a `FUN` argument (default `mean`, so existing calls are
  unaffected) selecting how observations sharing a 48-week slot are
  combined.

- [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  estimates the multi-factor mixed-frequency dynamic factor model of
  Eckert, Kronenberg, Mikosch & Neuwirth (2025), with post-hoc rotation
  and varimax identification. This is a **different model** from
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  not a multi-factor setting of it – the two differ in identification,
  priors and how the VAR coefficients are drawn, so `fcast_dfm(q = 1)`
  is not
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).
  Marked experimental until validated by simulation recovery
  ([\#45](https://github.com/PhilippKronenberg/mfbdfm/issues/45)).

- [`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)
  makes the priors a first-class, inspectable object with a
  [`print()`](https://rdrr.io/r/base/print.html) method, and
  distinguishes the priors that carry each model’s identification from
  those that are genuinely tunable. `type` moves only the latter;
  overriding a structural prior warns
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).

- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  and
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  now honour `stochastic_volatility` and `serial_correlation`. In
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  these were previously accepted and ignored. Note
  `stochastic_volatility = FALSE` means something different in each
  model, because they pin the factor scale in different places: an
  estimated constant variance in
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  a variance fixed at one in
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).

- Both fit classes support
  [`print()`](https://rdrr.io/r/base/print.html),
  [`summary()`](https://rdrr.io/r/base/summary.html),
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html),
  [`coef()`](https://rdrr.io/r/stats/coef.html),
  [`fitted()`](https://rdrr.io/r/stats/fitted.values.html),
  [`residuals()`](https://rdrr.io/r/stats/residuals.html) and
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html).
  [`residuals()`](https://rdrr.io/r/stats/residuals.html) returns `NA`
  for unobserved periods rather than differencing against the zeros that
  encode missingness. There is deliberately no
  [`predict()`](https://rdrr.io/r/stats/predict.html) method
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).

- Exported functions validate their inputs and report the offending
  argument
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).

### Performance

- [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)’s
  peak memory drops by about 315 MB at 500 retained draws, with
  bit-identical results. `get_nowcast_fcast()` built a full unpacked
  copy of every retained draw’s augmented-data block, read it once (one
  column per series) and then held it for the rest of the call; it now
  scatters each draw straight into the per-series matrices, indexing
  into the packed vector so no block is unpacked at all. Measured
  full-function peak 1307 MB to 992 MB at `n = 53`, `t = 1535`, `q = 2`,
  500 draws. Verified
  [`identical()`](https://rdrr.io/r/base/identical.html) against the
  previous implementation, and all four `dev/baseline.rds`
  configurations unchanged
  ([\#64](https://github.com/PhilippKronenberg/mfbdfm/issues/64)).

- [`dfm_memory()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md)
  estimates the peak memory of a
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  fit from the data dimensions and the chain length, and
  [`dfm_workers()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md)
  turns that into a worker count for a parallel sweep. Vintage sweeps
  are memory-bound rather than core-bound, and the failure mode is an
  opaque `CHOLMOD error 'out of memory'` hours into a run, so the worker
  count is now derived rather than guessed. Fitted to six measured fits
  (adjusted R-squared 0.98) and validated against a fit on different
  data and a different code version to within 7%. Worth knowing: peak
  memory is **linear** in the factor count `q`, not quadratic – the
  sparse Cholesky term that would make it quadratic is an order of
  magnitude smaller than the observation matrix’s working set
  ([\#64](https://github.com/PhilippKronenberg/mfbdfm/issues/64)).

- Peak memory during a fit is lower, without changing any result. All
  four `dev/baseline.rds` configurations remain identical after each of
  the changes below
  ([\#64](https://github.com/PhilippKronenberg/mfbdfm/issues/64)):

  - The observation matrix’s sparsity pattern, `Gmat_prealloc`, is built
    directly from index vectors instead of by `rbind`-ing one block per
    period. The old form allocated roughly ten times the size of the
    finished object: at the WAI’s dimensions it took the high-water mark
    from 168 MB to 285 MB to produce a 35 MB matrix, against 117 MB of
    transient allocation now. This cost is *fixed* – it does not scale
    with `length_sample` – so it set the floor under every fit
    regardless of chain length. Measured end to end on a two-factor fit
    with 200 retained draws, peak memory fell from 884 MB to 744 MB.
  - The rotation accumulates its running sums instead of materialising a
    list of per-draw matrices first, and
    [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
    releases the raw draws and the rotation matrices once identification
    is done. Both are bit-identical (`Reduce("+", ...)` sums in the same
    order as the accumulator), but be aware that **neither moved the
    measured peak** on its own – the peak was set elsewhere, by
    `Gmat_prealloc` above.

### Bug fixes

- [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
  now forwards `p`, `stochastic_volatility` and `serial_correlation` to
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  instead of hard-coding the first two and ignoring nothing silently but
  documenting `stochastic_volatility` as reaching the model “without
  effect there”, which was false.
  [`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)
  had exposed all of these all along, so this closes the last of the
  [\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48) parity
  gaps between the two wrappers. Defaults are unchanged (`p = 1`, both
  flags `TRUE`), so no existing result moves.
- [`output_figure_path()`](https://philippkronenberg.github.io/mfbdfm/reference/output_figure_path.md)
  creates nothing on disk again. It briefly created the directory it was
  handed, on the reasoning that the caller writes to the returned path
  immediately; that turned a path builder into a function with a side
  effect, and a caller passing a relative directory started leaving
  empty directories behind. Directory creation belongs to the two
  functions that actually write,
  [`write_table_output()`](https://philippkronenberg.github.io/mfbdfm/reference/write_table_output.md)
  and
  [`save_result_output()`](https://philippkronenberg.github.io/mfbdfm/reference/save_result_output.md),
  and to the analysis preludes.
- [`wai_sample_config()`](https://philippkronenberg.github.io/mfbdfm/reference/wai_sample_config.md)
  no longer creates its three output directories merely by being called.
  Asking it for a sample-end date used to write to the file system, and
  because its default `output_root` is a relative path, it wrote
  wherever the caller happened to be.
- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  now returns `pars$h` as a `ts` on the factor’s own index, as
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  always has. It was a bare numeric, so the same quantity carried a date
  axis from one entry point and an integer index from the other, and
  windowing it by calendar year silently matched nothing rather than
  erroring. Values are unchanged – this adds the time attribute only
  ([\#67](https://github.com/PhilippKronenberg/mfbdfm/issues/67)).
- [`dfm_memory()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md)
  under-predicted peak memory by 27% at the chain length the sweeps
  actually use, and so
  [`dfm_workers()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md)
  handed out too many workers: 1128 MB estimated against 1538 MB
  measured at 500 retained draws. The cause is that peak memory is
  **convex** in `length_sample` – the peak per MB of retained draws
  rises from 1.35 to 3.94 across the measured range, because which phase
  binds changes with chain length – so the linear fit could not span it,
  and a least-squares line under-predicts exactly where it matters. The
  estimate is now scaled to an **upper bound** over all measured points
  instead of a best fit. This is very likely why the 2019-2020 sweep
  lost two dates to `R_Calloc` out-of-memory
  ([\#64](https://github.com/PhilippKronenberg/mfbdfm/issues/64)).
- [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)’s
  `factor`, `factor_var` and `pars$phi` were computed from a transposed
  VAR coefficient matrix when `q > 1`. The internal packer writes each
  `q x q` block column-major and the unpacker read it back row-major, so
  the two callers of the factor-drawing step disagreed about the
  orientation. **Results change for `q > 1`**; `lambda`, `sigma`, `rho`
  and all nowcasts are unaffected, as is
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
  and `q = 1` was never affected because a 1x1 block is its own
  transpose
  ([\#66](https://github.com/PhilippKronenberg/mfbdfm/issues/66)).
- [`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)
  and
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
  returned a fit one period short whenever the evaluation date rounded
  down. Dates travel through the workflow rounded to three decimals,
  while the series’ grid points do not: at frequency 48 the last week of
  2021 is 2021.979167, which rounds to 2021.979, and the internal
  `trim_to()` compared exactly and dropped the observation the date
  names. Silent by construction, since `trim_to()` exists so that
  [`window()`](https://rdrr.io/r/stats/window.html)’s “‘end’ value not
  changed” warning does not fire. It affected `$factor` only –
  `$nowcast` is trimmed against the target series, not the date, so
  evaluation results are unchanged. `trim_to()` now carries a tolerance
  of a tenth of a period
  ([\#65](https://github.com/PhilippKronenberg/mfbdfm/issues/65)).
- [`retrieve_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast.md)
  and
  [`retrieve_nowcast_var()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast_var.md)
  failed with “object ‘ncst’ not found” for any `model` other than
  `"ar"` or `"wai"`, naming neither the argument nor the expectation.
  Now use [`match.arg()`](https://rdrr.io/r/base/match.arg.html)
  ([\#48](https://github.com/PhilippKronenberg/mfbdfm/issues/48)).
- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)’s
  `pars$h` had a trailing `NA` – it was sliced one element past the end
  of the volatility path – and was shifted one period against `factor`.
  Estimates were unaffected; only the reported value was wrong
  ([\#49](https://github.com/PhilippKronenberg/mfbdfm/issues/49)).
- [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
  keeps `zoo::na.trim(is.na = "all")` for both models. The alternative
  used by the reference multi-factor implementation silently dropped the
  most recent low-frequency observation, because it compared pre-shift
  times against a grid where low-frequency observations have been
  shifted to the end of their period
  ([\#45](https://github.com/PhilippKronenberg/mfbdfm/issues/45)).
- The rotation’s two convergence loops disagreed with each other:
  `initialize_theta_star_fcast()` tested the **sum** of squared
  deviations, as the appendix specifies, while the main loop in
  `run_rotation_fcast()` tested the **mean**. The default is unchanged
  for backwards compatibility and is now documented and selectable via
  [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md).
  Separately, the default cap of 5 iterations was measured to sit
  *exactly* on the observed convergence point, so it can bind and
  truncate the loop on other data; a binding cap now warns, or errors
  under `strict = TRUE`
  ([\#46](https://github.com/PhilippKronenberg/mfbdfm/issues/46)).

### Converting the research scripts into a package

- [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  (originally `hfdfm()`) estimates the Bayesian mixed-frequency dynamic
  factor model behind the Swiss Weekly Activity Index, with exported
  data-preparation helpers
  [`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md)
  and
  [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
  ([\#12](https://github.com/PhilippKronenberg/mfbdfm/issues/12)).
- Backcasting and real-time vintage tooling:
  [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md),
  [`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md),
  [`cut_data()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data.md),
  [`cut_data_real_time()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data_real_time.md),
  [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
  (reads the vintage database shipped in `inst/extdata/`), frequency
  converters
  [`week2mon()`](https://philippkronenberg.github.io/mfbdfm/reference/week2mon.md),
  [`daily2weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/daily2weekly.md),
  [`dec2week()`](https://philippkronenberg.github.io/mfbdfm/reference/dec2week.md)
  ([\#13](https://github.com/PhilippKronenberg/mfbdfm/issues/13),
  [\#11](https://github.com/PhilippKronenberg/mfbdfm/issues/11)).
- In-sample and out-of-sample evaluation suite:
  [`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md),
  [`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md),
  [`get_insample_error_details()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_error_details.md),
  the relative-error/LaTeX table pipeline,
  [`dm_test_modified()`](https://philippkronenberg.github.io/mfbdfm/reference/dm_test_modified.md),
  and
  [`wai_sample_config()`](https://philippkronenberg.github.io/mfbdfm/reference/wai_sample_config.md)
  for configuring analytics runs
  ([\#14](https://github.com/PhilippKronenberg/mfbdfm/issues/14)).
- Shipped datasets `data_ch_dataset` and `data_ch_dataset_test`
  ([\#11](https://github.com/PhilippKronenberg/mfbdfm/issues/11)).

### Bug fixes (relative to the pre-package scripts)

- [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
  no longer passes a silently ignored `extend` argument to the sampler
  ([\#13](https://github.com/PhilippKronenberg/mfbdfm/issues/13)).
- [`drop_weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/drop_weekly.md),
  [`drop_financial()`](https://philippkronenberg.github.io/mfbdfm/reference/drop_financial.md)
  and
  [`drop_retail()`](https://philippkronenberg.github.io/mfbdfm/reference/drop_retail.md)
  now operate on their argument instead of a global variable named `dat`
  ([\#13](https://github.com/PhilippKronenberg/mfbdfm/issues/13)).
- [`save_result_output()`](https://philippkronenberg.github.io/mfbdfm/reference/save_result_output.md)
  now finds the object to save in the caller’s environment
  ([\#14](https://github.com/PhilippKronenberg/mfbdfm/issues/14)).

### Breaking changes (relative to the pre-package scripts)

- [`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md)/[`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
  return the fit and only write to disk when `output_dir` is given
  ([\#13](https://github.com/PhilippKronenberg/mfbdfm/issues/13)).
- The in-sample table builders require an explicit `inputs` list instead
  of reading objects from the calling environment; output-path helpers
  take their directory as an argument
  ([\#14](https://github.com/PhilippKronenberg/mfbdfm/issues/14)).
- `initialize_plots_insample_context()` and `load_analytics_packages()`
  were removed; use
  [`wai_sample_config()`](https://philippkronenberg.github.io/mfbdfm/reference/wai_sample_config.md)
  and proper imports
  ([\#14](https://github.com/PhilippKronenberg/mfbdfm/issues/14),
  [\#15](https://github.com/PhilippKronenberg/mfbdfm/issues/15)).
