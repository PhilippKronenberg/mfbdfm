# mfbdfm 0.0.0.9000

First functional version of the package, converting the WAI research code
into a proper R package (#9-#19). The package (and repo) were renamed from
`waiind` to `mfbdfm` before release, since the underlying model is a
general mixed-frequency Bayesian dynamic factor model and WAI is one
application of it (#37).

## New features

* `hfdfm()` estimates the Bayesian mixed-frequency dynamic factor model
  behind the Swiss Weekly Activity Index, with exported data-preparation
  helpers `create_inventory()` and `prepare_data()` (#12).
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
