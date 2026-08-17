# Sample/output configuration and file selection helpers for the analytics
# workflow. Replaces the former initialize_plots_insample_context(), which
# assigned its results into the caller's environment.

# Create an output directory on demand, immediately before something is written
# into it. Used only by the two functions that actually write - not by
# output_figure_path(), which builds a path and nothing more.
#
# wai_sample_config() used to create all three output directories merely by being
# called, so a pure configuration query touched the file system: asking for a
# decimal date created `analysis/outputs/...` as a side effect. That contradicted
# the package's own no-side-effects-by-default rule, and with a *relative*
# default output_root it also wrote wherever the caller happened to be, which
# CRAN policy forbids outside the session temp directory. Directories are created
# at the point of writing instead.
ensure_output_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }
  invisible(path)
}

#' Build the sample configuration for an analytics run
#'
#' Returns the configuration object used by the analytics scripts: the sample
#' identifier and end date, the output directory paths, and the sample-end
#' cutoffs in decimal time. This replaces the former
#' `initialize_plots_insample_context()`, which wrote these values directly into
#' the calling environment.
#'
#' The returned `figures_dir`, `tables_dir` and `results_dir` are **paths, not
#' directories that necessarily exist**. This function has no side effects: it
#' creates nothing on disk. The directories are created when something is
#' actually written into them, by [write_table_output()], [save_result_output()]
#' and [output_figure_path()]. Earlier versions created all three on every call,
#' which meant merely asking for `sample_end_decimal` wrote to the file system.
#'
#' @param sample_id Character label for the run, e.g. `"sample_2025Q4"`.
#' @param sample_end_date Sample end as `Date` (or coercible).
#' @param output_root Directory under which the `figures/`, `tables/` and
#'   `results/` subdirectory paths are formed.
#' @param fit_root Root directory of the saved model fits.
#' @param fit_rt_dir Directory of the real-time fits.
#'
#' @return A list with elements `sample_id`, `sample_end_date`,
#'   `output_root`, `fit_root`, `fit_rt_dir`, `figures_dir`, `tables_dir`,
#'   `results_dir`, `sample_end_decimal` and `sample_end_fit_decimal`.
#'
#' @examples
#' cfg <- wai_sample_config(
#'   sample_id = "sample_2025Q4",
#'   sample_end_date = "2026-03-07",
#'   output_root = file.path(tempdir(), "plots_insample")
#' )
#' cfg$sample_end_decimal
#'
#' @export
wai_sample_config <- function(sample_id = "sample_2025Q4",
                              sample_end_date = as.Date("2026-03-07"),
                              output_root = file.path("analysis", "outputs", "plots_insample", sample_id),
                              fit_root = "fits",
                              fit_rt_dir = file.path(fit_root, "full_RT")) {

  sample_end_date <- as.Date(sample_end_date)
  figures_dir <- file.path(output_root, "figures")
  tables_dir <- file.path(output_root, "tables")
  results_dir <- file.path(output_root, "results")

  sample_end_decimal <- round(
    as.numeric(format(sample_end_date, "%Y")) +
      (as.numeric(format(sample_end_date, "%m")) - 1) / 12 +
      as.numeric(format(sample_end_date, "%d")) / 365,
    3
  )
  sample_end_fit_decimal <- round(as.numeric(format(sample_end_date, "%Y")) + 47 / 48, 3)

  list(
    sample_id = sample_id,
    sample_end_date = sample_end_date,
    output_root = output_root,
    fit_root = fit_root,
    fit_rt_dir = fit_rt_dir,
    figures_dir = figures_dir,
    tables_dir = tables_dir,
    results_dir = results_dir,
    sample_end_decimal = sample_end_decimal,
    sample_end_fit_decimal = sample_end_fit_decimal
  )
}


#' Find the newest fit file up to a cutoff date
#'
#' @param folder Directory containing `fit_<decimal-date>.Rda` files.
#' @param cutoff_decimal Numeric decimal date; only fits at or before this
#'   cutoff are considered. Defaults to `Inf`, i.e. no cutoff -- the most recent
#'   fit in `folder`, which is what the name promises and what a one-argument
#'   call should give.
#'
#' @return Full path of the selected fit file.
#' @examples
#' dir <- tempfile(); dir.create(dir)
#' mod <- list()
#' save(mod, file = file.path(dir, "fit_2020.5.Rda"))
#' save(mod, file = file.path(dir, "fit_2021.25.Rda"))
#' latest_fit_file(dir, cutoff_decimal = 2020.9)
#' @export
latest_fit_file <- function(folder, cutoff_decimal = Inf) {

  if (!is.numeric(cutoff_decimal) || length(cutoff_decimal) != 1 ||
      is.na(cutoff_decimal)) {
    stop("`cutoff_decimal` must be a single number (decimal time, e.g. 2024.5), ",
         "or `Inf` for no cutoff.", call. = FALSE)
  }

  files <- list.files(folder, pattern = "^fit_[0-9.]+\\.Rda$", full.names = TRUE)
  if (length(files) == 0) {
    stop(sprintf("No fit files found in '%s'.", folder))
  }
  file_decimals <- suppressWarnings(as.numeric(gsub("^fit_|\\.Rda$", "", basename(files))))
  valid_idx <- which(!is.na(file_decimals) & file_decimals <= cutoff_decimal)
  if (length(valid_idx) == 0) {
    stop(sprintf("No fit file found in '%s' up to cutoff %.3f.", folder, cutoff_decimal))
  }
  files[valid_idx[which.max(file_decimals[valid_idx])]]
}


#' Write a table output file
#'
#' @param filename File name (without directory).
#' @param contents Character vector written via [writeLines()].
#' @param tables_dir Directory to write into (e.g.
#'   `wai_sample_config()$tables_dir`).
#'
#' @return Invisibly, the full path written.
#' @examples
#' dir <- tempfile(); dir.create(dir)
#' write_table_output("example.tex", "\\textbf{table}", tables_dir = dir)
#' readLines(file.path(dir, "example.tex"))
#' @export
write_table_output <- function(filename, contents, tables_dir) {
  ensure_output_dir(tables_dir)
  path <- file.path(tables_dir, filename)
  writeLines(contents, path)
  invisible(path)
}


#' Save a result object to the results directory
#'
#' @param object Object to save (stored under its own name).
#' @param filename File name (without directory).
#' @param results_dir Directory to write into (e.g.
#'   `wai_sample_config()$results_dir`).
#'
#' @return Invisibly, the full path written.
#' @examples
#' dir <- tempfile(); dir.create(dir)
#' results_example <- data.frame(x = 1:3)
#' save_result_output(results_example, "results_example.rda", results_dir = dir)
#' load(file.path(dir, "results_example.rda"))
#' @export
save_result_output <- function(object, filename, results_dir) {
  ensure_output_dir(results_dir)
  path <- file.path(results_dir, filename)
  save(list = deparse(substitute(object)), file = path, envir = parent.frame())
  invisible(path)
}


#' Build the full path for a figure output file
#'
#' Purely a path: this creates nothing on disk. `figures_dir` is expected to
#' exist already — the analytics preludes (`analysis/5_plots/_setup.R`,
#' `analysis/fcast/_setup.R`) create the whole output tree up front, and so does
#' any caller that has written a table or result through
#' [write_table_output()]/[save_result_output()].
#'
#' It did briefly create the directory, on the reasoning that the returned path
#' is written to immediately afterwards. That was a mistake worth recording: a
#' path builder with a side effect surprised a test that passed it the relative
#' path `"outputs/figures"`, which had been harmless for as long as the function
#' was a plain [file.path()] call, and the suite started leaving
#' `tests/testthat/outputs/figures` behind in the source tree.
#'
#' @param filename File name (without directory).
#' @param figures_dir Directory the figure belongs in (e.g.
#'   `wai_sample_config()$figures_dir`). Must already exist; not created here.
#'
#' @return The full file path.
#' @examples
#' output_figure_path("history.pdf", figures_dir = file.path(tempdir(), "figures"))
#' @export
output_figure_path <- function(filename, figures_dir) {
  file.path(figures_dir, filename)
}


#' Filter a data frame to the evaluation sample window
#'
#' @param df Data frame with a date column.
#' @param time_col Name of the date column.
#' @param start_date Window start (`Date`).
#' @param end_date Window end (`Date`), e.g.
#'   `wai_sample_config()$sample_end_date`.
#'
#' @return The filtered data frame.
#' @examples
#' df <- data.frame(time = seq(as.Date("2019-01-01"), by = "quarter", length.out = 12),
#'                  value = rnorm(12))
#' filter_to_sample(df, end_date = as.Date("2020-12-31"))
#' @export
filter_to_sample <- function(df, time_col = "time", start_date = as.Date("1990-01-01"), end_date) {
  df[df[[time_col]] >= start_date & df[[time_col]] <= end_date, , drop = FALSE]
}


#' Newest numeric vintage within bounds
#'
#' @param df Vintage table whose column names (except the first) are
#'   decimal vintage dates, e.g. from [get_real_time_gdp_vintages()].
#' @param lower_bound Numeric lower bound (inclusive).
#' @param upper_bound Numeric upper bound (inclusive), e.g.
#'   `wai_sample_config()$sample_end_decimal`.
#'
#' @return The newest vintage as a numeric decimal date.
#' @examples
#' vintages <- data.frame(time = 1:3, "2020.25" = rnorm(3), "2020.75" = rnorm(3),
#'                        check.names = FALSE)
#' get_latest_numeric_vintage(vintages, upper_bound = 2020.5)
#' @export
get_latest_numeric_vintage <- function(df, lower_bound = -Inf, upper_bound) {
  vintages <- suppressWarnings(as.numeric(names(df)[-1]))
  vintages <- vintages[!is.na(vintages) & vintages >= lower_bound & vintages <= upper_bound]
  if (length(vintages) == 0) {
    stop("No valid vintages found for the configured sample.")
  }
  max(vintages)
}


#' Next vintage that extends the data beyond a reference date's vintage
#'
#' Finds the newest vintage available at `reference_date`, then returns
#' the first later vintage whose series reaches further into the sample.
#'
#' @param df Vintage table with a `time` column and vintage-named columns.
#' @param reference_date `Date` at which the base vintage is selected.
#' @param lower_bound Numeric lower bound on vintages considered.
#'
#' @return The extending vintage as a numeric decimal date.
#' @examples
#' vintages <- data.frame(
#'   time = seq(as.Date("2019-01-01"), by = "quarter", length.out = 4),
#'   "2019.5" = c(1, 2, NA, NA), "2020.25" = c(1, 2, 3, NA),
#'   check.names = FALSE
#' )
#' get_next_extending_numeric_vintage(vintages, as.Date("2019-09-30"))
#' @export
get_next_extending_numeric_vintage <- function(df, reference_date, lower_bound = -Inf) {
  reference_decimal <- round(decimal_date_local(reference_date), 3)
  vintage_names <- names(df)[-1]
  vintages <- suppressWarnings(as.numeric(vintage_names))
  valid_idx <- which(!is.na(vintages) & vintages >= lower_bound)

  if (length(valid_idx) == 0) {
    stop("No valid vintages found for the configured sample.")
  }

  vintages <- vintages[valid_idx]
  vintage_names <- vintage_names[valid_idx]

  earlier_idx <- which(vintages <= reference_decimal)
  if (length(earlier_idx) == 0) {
    stop("No GDP vintage is available on or before the requested reference_date.")
  }

  base_idx <- earlier_idx[which.max(vintages[earlier_idx])]
  base_series <- df[[vintage_names[base_idx]]]
  base_last_obs <- suppressWarnings(max(df$time[!is.na(base_series)], na.rm = TRUE))

  if (!is.finite(base_last_obs)) {
    stop("The latest GDP vintage available at the requested reference_date contains no observations.")
  }

  later_order <- order(vintages)
  later_idx <- later_order[vintages[later_order] > vintages[base_idx]]

  for (idx in later_idx) {
    candidate_series <- df[[vintage_names[idx]]]
    candidate_last_obs <- suppressWarnings(max(df$time[!is.na(candidate_series)], na.rm = TRUE))

    if (is.finite(candidate_last_obs) && candidate_last_obs > base_last_obs) {
      return(vintages[idx])
    }
  }

  stop("No later GDP vintage extends the series beyond the latest vintage available at the requested reference_date.")
}
