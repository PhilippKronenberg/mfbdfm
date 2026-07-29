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

## New features

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
