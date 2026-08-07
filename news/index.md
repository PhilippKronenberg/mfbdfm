# Changelog

## mfbdfm 0.0.0.9000

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
