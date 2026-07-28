# Package index

## Models

The two Bayesian mixed-frequency dynamic factor models: the
target-anchored single-factor model behind the WAI (Kronenberg 2026) and
the rotation-identified multi-factor model (Eckert et al. 2025), plus
the helpers that prepare their input data.

- [`hfdfm()`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
  : Estimate a high-frequency dynamic factor model
- [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  : Estimate a multi-factor mixed-frequency dynamic factor model
- [`print(`*`<fcast_dfm>`*`)`](https://philippkronenberg.github.io/mfbdfm/reference/print.fcast_dfm.md)
  : Print a summary of a multi-factor dynamic factor model fit
- [`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md)
  : Build an inventory of the model input series
- [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
  : Standardize and align mixed-frequency series into one matrix

## Backcasting & real-time vintages

Fitting the AR benchmark and the WAI at a given evaluation date, and
handling real-time GDP vintages.

- [`run_ar()`](https://philippkronenberg.github.io/mfbdfm/reference/run_ar.md)
  : Fit an AR(1) benchmark model and nowcast the target
- [`run_wai_adj()`](https://philippkronenberg.github.io/mfbdfm/reference/run_wai_adj.md)
  : Fit the WAI dynamic factor model at a given evaluation date
- [`retrieve_nowcast()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast.md)
  : Extract the nowcast from a fit object
- [`retrieve_nowcast_var()`](https://philippkronenberg.github.io/mfbdfm/reference/retrieve_nowcast_var.md)
  : Extract the nowcast variance from a fit object
- [`extract_wai_data()`](https://philippkronenberg.github.io/mfbdfm/reference/extract_wai_data.md)
  : Extract WAI growth, level and year-over-year tables from a saved fit
- [`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)
  : Read the real-time GDP vintage database
- [`select_most_recent_GDP_vintage()`](https://philippkronenberg.github.io/mfbdfm/reference/select_most_recent_GDP_vintage.md)
  : Select the newest GDP vintage available at a given date
- [`cut_data()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data.md)
  : Cut a dataset to what was observable at a given date
- [`cut_data_real_time()`](https://philippkronenberg.github.io/mfbdfm/reference/cut_data_real_time.md)
  : Cut a dataset in real time, using GDP vintages for the target

## Frequency & date utilities

Converting between weekly/monthly/daily frequencies and decimal dates.

- [`week2mon()`](https://philippkronenberg.github.io/mfbdfm/reference/week2mon.md)
  : Aggregate weekly series in a dataset to monthly frequency
- [`drop_weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/drop_weekly.md)
  : Drop all weekly series from a dataset
- [`drop_financial()`](https://philippkronenberg.github.io/mfbdfm/reference/drop_financial.md)
  : Drop the financial market series from a dataset
- [`drop_retail()`](https://philippkronenberg.github.io/mfbdfm/reference/drop_retail.md)
  : Drop the non-total retail trade series from a dataset
- [`dec2week()`](https://philippkronenberg.github.io/mfbdfm/reference/dec2week.md)
  : Convert decimal weekly dates to calendar dates
- [`decimal_date_local()`](https://philippkronenberg.github.io/mfbdfm/reference/decimal_date_local.md)
  : Convert dates to decimal years (day-of-year convention)
- [`is_crisis_period()`](https://philippkronenberg.github.io/mfbdfm/reference/is_crisis_period.md)
  : Flag dates falling into the crisis periods
- [`daily2weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/daily2weekly.md)
  : Aggregate a daily series to the 48-week grid
- [`aggregate_predictor_to_quarterly()`](https://philippkronenberg.github.io/mfbdfm/reference/aggregate_predictor_to_quarterly.md)
  : Aggregate a predictor data frame to quarterly frequency
- [`get_next_target_vintage()`](https://philippkronenberg.github.io/mfbdfm/reference/get_next_target_vintage.md)
  : First target vintage after a prediction vintage

## Analytics configuration & output

Sample configuration and output-path helpers for the analytics scripts.

- [`wai_sample_config()`](https://philippkronenberg.github.io/mfbdfm/reference/wai_sample_config.md)
  : Build the sample configuration for an analytics run
- [`latest_fit_file()`](https://philippkronenberg.github.io/mfbdfm/reference/latest_fit_file.md)
  : Find the newest fit file up to a cutoff date
- [`write_table_output()`](https://philippkronenberg.github.io/mfbdfm/reference/write_table_output.md)
  : Write a table output file
- [`save_result_output()`](https://philippkronenberg.github.io/mfbdfm/reference/save_result_output.md)
  : Save a result object to the results directory
- [`output_figure_path()`](https://philippkronenberg.github.io/mfbdfm/reference/output_figure_path.md)
  : Build the full path for a figure output file
- [`filter_to_sample()`](https://philippkronenberg.github.io/mfbdfm/reference/filter_to_sample.md)
  : Filter a data frame to the evaluation sample window
- [`get_latest_numeric_vintage()`](https://philippkronenberg.github.io/mfbdfm/reference/get_latest_numeric_vintage.md)
  : Newest numeric vintage within bounds
- [`get_next_extending_numeric_vintage()`](https://philippkronenberg.github.io/mfbdfm/reference/get_next_extending_numeric_vintage.md)
  : Next vintage that extends the data beyond a reference date's vintage

## Evaluation tables & plots

In-sample and out-of-sample forecast evaluation tables and plots.

- [`rescale_to_gdp()`](https://philippkronenberg.github.io/mfbdfm/reference/rescale_to_gdp.md)
  : Rescale an indicator to GDP moments
- [`build_wai_qoq_mean_series()`](https://philippkronenberg.github.io/mfbdfm/reference/build_wai_qoq_mean_series.md)
  : Quarter-on-quarter growth from a weekly level series
- [`prepare_wai_qoq_series()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_wai_qoq_series.md)
  : Select the QoQ series for a WAI result, given the aggregation method
- [`plot_comparison()`](https://philippkronenberg.github.io/mfbdfm/reference/plot_comparison.md)
  : Plot the WAI against a comparison indicator and GDP
- [`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md)
  : Cross correlations of the WAI and benchmarks with GDP
- [`render_correlation_heatmap()`](https://philippkronenberg.github.io/mfbdfm/reference/render_correlation_heatmap.md)
  : Render the lag-correlation heatmap grid and save it
- [`dm_test_modified()`](https://philippkronenberg.github.io/mfbdfm/reference/dm_test_modified.md)
  : Modified Diebold-Mariano test
- [`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md)
  : In-sample fit metrics of the WAI and benchmarks against GDP
- [`calculate_relative_errors()`](https://philippkronenberg.github.io/mfbdfm/reference/calculate_relative_errors.md)
  : Relative RMSE/MAE tables (normalized to the WAI)
- [`annotate_relative_errors()`](https://philippkronenberg.github.io/mfbdfm/reference/annotate_relative_errors.md)
  : Annotate relative error tables with significance stars
- [`create_combined_latex_table()`](https://philippkronenberg.github.io/mfbdfm/reference/create_combined_latex_table.md)
  : Combine per-method lag tables into one LaTeX table
- [`print_evaluation_periods()`](https://philippkronenberg.github.io/mfbdfm/reference/print_evaluation_periods.md)
  : Print the evaluation period per series
- [`create_error_summary_tables()`](https://philippkronenberg.github.io/mfbdfm/reference/create_error_summary_tables.md)
  : Error summary tables with crisis/non-crisis split
- [`get_insample_error_details()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_error_details.md)
  : Per-observation in-sample errors of each series against GDP
- [`create_rel_error_tables()`](https://philippkronenberg.github.io/mfbdfm/reference/create_rel_error_tables.md)
  : Relative out-of-sample error tables across vintages

## Data

- [`data_ch_dataset`](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
  : Harmonized Swiss indicator dataset for the WAI model
- [`data_ch_dataset_test`](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset_test.md)
  : Harmonized Swiss indicator dataset (test variant)
