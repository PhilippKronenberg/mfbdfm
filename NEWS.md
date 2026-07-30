# mfbdfm 0.0.0.9000

First functional version of the package, converting the WAI research code
into a proper R package (#9-#19). The package (and repo) were renamed from
`waiind` to `mfbdfm` before release, since the underlying model is a
general mixed-frequency Bayesian dynamic factor model and WAI is one
application of it (#37).

## Breaking changes

* `hfdfm()` is renamed `ind_dfm()`, and its S3 class with it. There is no
  deprecated alias: calls to `hfdfm()` will fail with "could not find
  function" (#48).
* `ind_dfm()` no longer takes a `q` argument. It was accepted and silently
  ignored, so `hfdfm(q = 2)` returned a one-factor model without complaint.
  Use `fcast_dfm()` for multi-factor estimation (#48).
* Both fit classes now agree on their data components: `$data` is the prepared
  (standardized) matrix and `$data_raw` the series as supplied. Previously
  `$data` meant the prepared matrix for `ind_dfm()` but the raw input list for
  `fcast_dfm()`, so the same expression returned unrelated things -- e.g.
  `length(fit$data)` gave 1250 for one and 5 for the other, with no error.
  **`ind_dfm()` is unaffected**; for `fcast_dfm()`, `$data` changes meaning and
  `$data_missings` is renamed to `$data` (#50).

## New features

* `dfm_control()` bundles the numerical and algorithmic settings that were
  previously hard-coded inside the samplers, as an **optional** `control`
  argument on both entry points -- omit it and the published behaviour is
  reproduced exactly (verified: all four `dev/baseline.rds` configurations
  identical). Covers the rotation stopping rule, the stationarity screen on the
  measurement-error autocorrelations, the caps on `phi`/`sigma`/`omega`, and two
  numerical guards. `dfm_control("fcast_dfm", strict = TRUE)` switches the
  rotation to the algorithm as published in the online appendix to Eckert et al.
  (2025) -- the **sum** of squared deviations rather than the mean (#46).
* The rotation's iteration caps are now finite by construction. `Inf` is
  refused: an unbounded loop has no termination guarantee. The defaults are
  safety valves rather than targets -- measured convergence is 5-7 iterations at
  roughly an order of magnitude per iteration, against a strict cap of 100.
  `initialize_theta_star_fcast()`, which previously had **no cap at all**, now
  has one (#46).

* `fcast_dfm()`'s sampler is now validated by simulation recovery. Data
  generated from a known `q`-factor process is recovered at the trace R-squared
  values published for this model (Eckert et al. 2025, Table 1), with the
  paper's figure inside the 95% interval of the Monte Carlo mean in all three
  cells -- 0.717 vs 0.68, 0.856 vs 0.84, and 0.408 vs 0.39 for the misspecified
  cell that serves as a negative control. Tooling and the committed result
  snapshot are in `dev/mc_recovery.R` and `dev/mc_results.rds`; `?fcast_dfm`'s
  Maturity section is updated to say what is and is not established, since the
  rotation-invariant metric cannot validate the post-hoc rotation (#52).
* `mfbdfm_data()` assembles the model input from a long or wide data frame, an
  `mts`, or a named list of `ts`, and can be passed straight to `ind_dfm()` or
  `fcast_dfm()` as the first argument (`flows`/`stocks` keep working unchanged).
  Its real purpose is to make the flow/stock classification inspectable:
  previously a series' type was expressed by *which argument it was passed in*,
  so there was nowhere to check it, and misclassifying a lower-frequency series
  silently changed its temporal aggregation weights (a monthly series gets 7
  nonzero lags as a flow against 4 as a stock; quarterly, 23 against 12).
  `mfbdfm_data()` requires `type` for exactly the series where it can change
  the answer -- those below the highest frequency, since at the highest
  frequency the two sets of weights are provably identical -- and `print()`
  shows the resolved classification and frequencies before you commit to a run
  that takes minutes to hours (#56).
* `mfbdfm_data()` also puts weekly (52) and daily (365) series onto the
  48-periods-per-year grid the models are built on, using `daily2weekly()`.
  This is not cosmetic: `prepare_data()` matches observations onto a
  `1/max(freq)` grid by an exact join, and a frequency-52 series raises
  `max(freq)` so that shifted *monthly* observations no longer land on it. On a
  20-quarter / 60-month / 260-week panel the monthly series retained only 20 of
  its 60 observations, with no error or warning. The conversion is reported by
  `message()`, shown by `print()`, and recorded in `meta$frequency_in` (#56).
  Weekly series go **via daily**: since 48 does not divide 52, mapping weekly
  points straight onto the grid gives each slot one or two of them -- a
  nearest-point pick that leaves occasional empty slots and a few slots a year
  blending two weeks while the rest blend one. Expanding to daily first gives
  every slot 6-8 days and makes its value an overlap-weighted blend. On a linear
  ramp the direct route steps `1.5, 1.5, 1, 1, ...` against a correct constant
  rate of `52/48 = 1.083`; via daily the worst deviation falls from 0.42 to 0.18
  and the median from 0.08 to 0.04.
* `daily2weekly()` gains a `FUN` argument (default `mean`, so existing calls are
  unaffected) selecting how observations sharing a 48-week slot are combined.
* `fcast_dfm()` estimates the multi-factor mixed-frequency dynamic factor
  model of Eckert, Kronenberg, Mikosch & Neuwirth (2025), with post-hoc
  rotation and varimax identification. This is a **different model** from
  `ind_dfm()`, not a multi-factor setting of it -- the two differ in
  identification, priors and how the VAR coefficients are drawn, so
  `fcast_dfm(q = 1)` is not `ind_dfm()`. Marked experimental until validated
  by simulation recovery (#45).
* `dfm_priors()` makes the priors a first-class, inspectable object with a
  `print()` method, and distinguishes the priors that carry each model's
  identification from those that are genuinely tunable. `type` moves only the
  latter; overriding a structural prior warns (#48).
* `ind_dfm()` and `fcast_dfm()` now honour `stochastic_volatility` and
  `serial_correlation`. In `ind_dfm()` these were previously accepted and
  ignored. Note `stochastic_volatility = FALSE` means something different in
  each model, because they pin the factor scale in different places: an
  estimated constant variance in `ind_dfm()`, a variance fixed at one in
  `fcast_dfm()` (#48).
* Both fit classes support `print()`, `summary()`, `plot()`, `coef()`,
  `fitted()`, `residuals()` and `as.data.frame()`. `residuals()` returns `NA`
  for unobserved periods rather than differencing against the zeros that
  encode missingness. There is deliberately no `predict()` method (#48).
* Exported functions validate their inputs and report the offending argument
  (#48).

## Bug fixes

* `retrieve_nowcast()` and `retrieve_nowcast_var()` failed with
  "object 'ncst' not found" for any `model` other than `"ar"` or `"wai"`,
  naming neither the argument nor the expectation. Now use `match.arg()` (#48).
* `ind_dfm()`'s `pars$h` had a trailing `NA` -- it was sliced one element past
  the end of the volatility path -- and was shifted one period against
  `factor`. Estimates were unaffected; only the reported value was wrong (#49).
* `prepare_data()` keeps `zoo::na.trim(is.na = "all")` for both models. The
  alternative used by the reference multi-factor implementation silently
  dropped the most recent low-frequency observation, because it compared
  pre-shift times against a grid where low-frequency observations have been
  shifted to the end of their period (#45).
* The rotation's two convergence loops disagreed with each other:
  `initialize_theta_star_fcast()` tested the **sum** of squared deviations, as
  the appendix specifies, while the main loop in `run_rotation_fcast()` tested
  the **mean**. The default is unchanged for backwards compatibility and is now
  documented and selectable via `dfm_control()`. Separately, the default cap of
  5 iterations was measured to sit *exactly* on the observed convergence point,
  so it can bind and truncate the loop on other data; a binding cap now warns,
  or errors under `strict = TRUE` (#46).

## Converting the research scripts into a package

* `ind_dfm()` (originally `hfdfm()`) estimates the Bayesian mixed-frequency
  dynamic factor model behind the Swiss Weekly Activity Index, with exported
  data-preparation helpers `create_inventory()` and `prepare_data()` (#12).
* Backcasting and real-time vintage tooling: `run_wai_adj()`, `run_ar()`,
  `cut_data()`, `cut_data_real_time()`, `get_real_time_gdp_vintages()`
  (reads the vintage database shipped in `inst/extdata/`), frequency
  converters `week2mon()`, `daily2weekly()`, `dec2week()` (#13, #11).
* In-sample and out-of-sample evaluation suite: `get_combined_cor_table()`,
  `get_insample_fit_table()`, `get_insample_error_details()`, the
  relative-error/LaTeX table pipeline, `dm_test_modified()`, and
  `wai_sample_config()` for configuring analytics runs (#14).
* Shipped datasets `data_ch_dataset` and `data_ch_dataset_test` (#11).

## Bug fixes (relative to the pre-package scripts)

* `run_wai_adj()` no longer passes a silently ignored `extend` argument to
  the sampler (#13).
* `drop_weekly()`, `drop_financial()` and `drop_retail()` now operate on
  their argument instead of a global variable named `dat` (#13).
* `save_result_output()` now finds the object to save in the caller's
  environment (#14).

## Breaking changes (relative to the pre-package scripts)

* `run_ar()`/`run_wai_adj()` return the fit and only write to disk when
  `output_dir` is given (#13).
* The in-sample table builders require an explicit `inputs` list instead of
  reading objects from the calling environment; output-path helpers take
  their directory as an argument (#14).
* `initialize_plots_insample_context()` and `load_analytics_packages()`
  were removed; use `wai_sample_config()` and proper imports (#14, #15).
