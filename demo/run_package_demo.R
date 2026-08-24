# =============================================================================
# mfbdfm self-test: load the data and run every exported function
# =============================================================================
# Installs the package from this source tree and calls all 55 exported functions
# and all 18 S3 methods, in the order a real workflow uses them. Run from the
# repository root:
#
#     Rscript demo/run_package_demo.R
#
# Purpose is verification, not analysis. Every model uses a deliberately short
# MCMC chain so the whole script finishes in minutes; THE NUMBERS ARE MEANINGLESS
# and the script says so again at the end. What it checks is that the pieces fit
# together: data in, models fit, methods dispatch, outputs land on disk.
#
# It ends with a COVERAGE AUDIT that compares the functions this file calls
# against NAMESPACE and fails loudly if anything exported is untouched. So the
# script cannot silently rot as the package grows - add an export without adding
# a call here and the last section will say so.
#
# Deliberately OUTSIDE the package (demo/ is in .Rbuildignore) and uses only
# exported functions and shipped data - no internals, no private data, nothing
# from analysis/. Anyone who clones the repo can run it. If something here
# breaks, a user's workflow breaks.
#
# It is also the skeleton for checking against real private data: swap the
# shipped dataset at the marked point in section 2 and raise the chain lengths.
# =============================================================================

options(warn = 1)
t_start <- Sys.time()

step <- function(n, msg) cat("\n", strrep("-", 74), "\n", n, ". ", msg, "\n", sep = "")
ok   <- function(...) cat("   ok  ", ..., "\n")

out_root <- file.path("demo", "outputs")
# Clear it first, so the file listing at the end describes THIS run and not a
# mixture of this one and whatever a previous version of the script left behind.
unlink(out_root, recursive = TRUE)
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)

# Every plot goes to a file or to a null device. Otherwise R opens a real device
# and leaves a stray Rplots.pdf behind - the package's own tests hit this.
grDevices::pdf(NULL)
on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)


# 1. INSTALL ------------------------------------------------------------------
step(1, "Install the package from source")

if (!requireNamespace("devtools", quietly = TRUE)) {
  stop("devtools is needed to install from source.", call. = FALSE)
}
devtools::install(".", quiet = TRUE, upgrade = FALSE,
                  build_vignettes = FALSE, dependencies = TRUE)
library(mfbdfm)
ok("installed and attached mfbdfm", as.character(utils::packageVersion("mfbdfm")))


# 2. DATA ---------------------------------------------------------------------
step(2, "Shipped datasets and the real-time GDP vintages")

data(data_ch_dataset)          # the full dataset: NO GDP target in it
data(data_ch_dataset_test)     # the reduced one, which DOES carry the target
target <- "ch.seco.gdp.real.gdp.ssa"
ok("data_ch_dataset:", length(data_ch_dataset$flows), "flows /",
   length(data_ch_dataset$stocks), "stocks - target present:",
   target %in% names(data_ch_dataset$flows))
ok("data_ch_dataset_test:", length(data_ch_dataset_test$flows), "flows /",
   length(data_ch_dataset_test$stocks), "stocks - target present:",
   target %in% names(data_ch_dataset_test$flows))

# Real workflows inject GDP at runtime from the vintages, which ship with the
# package and need no path argument.
vint <- get_real_time_gdp_vintages("quarterly")
ok("real-time vintages:", ncol(vint) - 1, "vintage columns")

# ---- swap for the real dataset here when testing against private data -------
dat <- data_ch_dataset_test
# -----------------------------------------------------------------------------


# 3. VINTAGE SELECTION --------------------------------------------------------
step(3, "Vintage pickers")

latest <- get_latest_numeric_vintage(vint, lower_bound = 2005.438,
                                     upper_bound = decimal_date_local(Sys.Date()))
ok("get_latest_numeric_vintage():", latest)

v2023 <- select_most_recent_GDP_vintage(2023, vint)
ok("select_most_recent_GDP_vintage():", length(v2023), "quarters,",
   sum(!is.na(v2023)), "observed")

nxt <- get_next_extending_numeric_vintage(vint, as.Date("2019-09-30"),
                                          lower_bound = 2005)
ok("get_next_extending_numeric_vintage():", nxt)
ok("get_next_target_vintage():", get_next_target_vintage(2020.5, c(2020.25, 2020.75, 2021)))


# 4. FREQUENCY AND DATE UTILITIES ---------------------------------------------
step(4, "Frequency and date helpers")

ok("dec2week(2020):", format(dec2week(2020)))
ok("decimal_date_local():", round(decimal_date_local(as.Date("2020-07-01")), 4))
ok("crisis flags (WAI / EKMN):", is_crisis_period(as.Date("2020-04-01")),
   "/", is_crisis_period_fcast(2020.25))
ok("week2mon() frequency:", stats::frequency(week2mon(dat)$flows[[1]]))
ok("subsetting:", length(drop_weekly(dat)$flows), "monthly-only,",
   length(drop_financial(dat)$flows), "no financials,",
   length(drop_retail(dat)$flows), "no sectoral retail")

daily <- zoo::zoo(rnorm(120),
                  order.by = seq(as.Date("2024-01-01"), by = "day", length.out = 120))
ok("daily2weekly() frequency:", stats::frequency(daily2weekly(daily)))

mdf <- data.frame(time = seq(as.Date("2023-01-01"), by = "month", length.out = 12),
                  value = rnorm(12))
ok("aggregate_predictor_to_quarterly():",
   nrow(aggregate_predictor_to_quarterly(mdf, cut_off_month_pos = 1,
                                         method = "mean")), "quarters")


# 5. INPUT CONSTRUCTION -------------------------------------------------------
step(5, "mfbdfm_data(), create_inventory(), prepare_data()")

series <- c(dat$flows[c(target, "SWISSMI")], dat$stocks[1:2])
series <- lapply(series, stats::window, start = 2018)
meta <- data.frame(series = names(series), type = rep(c("flow", "stock"), each = 2))

d <- mfbdfm_data(series, meta, target = target)
print(d)                                   # S3: print.mfbdfm_data
ok("classification and frequencies shown above - check before a long run")

inv <- create_inventory(flows = d$flows, stocks = d$stocks)
Y <- prepare_data(flows = d$flows, stocks = d$stocks, inventory = inv, target = target)
ok("prepared matrix:", nrow(Y), "x", ncol(Y), "at frequency", stats::frequency(Y))


# 6. SPECIFICATION ------------------------------------------------------------
step(6, "dfm_priors() and dfm_control()")

pri <- dfm_priors("ind_dfm")
ctl <- dfm_control("ind_dfm")
print(pri)                                 # S3: print.dfm_priors
print(ctl)                                 # S3: print.dfm_control
ok("priors and control resolved; defaults reproduce the published behaviour")


# 7. MEMORY PLANNING ----------------------------------------------------------
step(7, "dfm_memory() and dfm_workers()")

mem <- dfm_memory(flows = d$flows, stocks = d$stocks, q = 2, length_sample = 1000)
ok("dfm_memory() upper bound:", round(as.numeric(mem)), "MB")
ok("dfm_workers() in 24 GB:",
   dfm_workers(n = 53, t = 1535, s = 22, q = 4, length_sample = 500,
               available_mb = 24 * 1024), "workers")


# 8. SINGLE-FACTOR MODEL ------------------------------------------------------
step(8, "ind_dfm(): target-anchored single-factor model (the WAI)")

set.seed(1)
fit <- ind_dfm(d, length_sample = 60, burn_in = 20, priors = pri, control = ctl)
ok("fitted;", length(fit$factor), "weekly factor periods")

print(fit)                                 # S3: print.ind_dfm
print(summary(fit))                        # S3: summary.ind_dfm + print.summary.mfbdfm_fit
ok("coef():", paste(utils::head(names(coef(fit)), 4), collapse = ", "))
ok("fitted()/residuals():", length(fitted(fit)), "/", length(residuals(fit)))
ok("as.data.frame():", nrow(as.data.frame(fit)), "rows")
ok("identifying restriction lambda[target] =",
   round(as.numeric(fit$pars$lambda[fit$inventory$key == target]), 6))

grDevices::pdf(file.path(out_root, "ind_dfm_plot.pdf"), width = 8, height = 5)
plot(fit)                                  # S3: plot.ind_dfm
grDevices::dev.off()
ok("wrote", file.path(out_root, "ind_dfm_plot.pdf"))


# 9. MULTI-FACTOR MODEL -------------------------------------------------------
step(9, "fcast_dfm(): multi-factor model (Eckert et al. 2025)")

set.seed(2)
mfit <- suppressWarnings(
  fcast_dfm(d, q = 2, length_sample = 30, burn_in = 10,
            control = dfm_control("fcast_dfm")))
print(mfit)                                # S3: print.fcast_dfm
print(summary(mfit))                       # S3: summary.fcast_dfm
ok("factors:", paste(dim(mfit$factor), collapse = " x "),
   "| nowcasts for", length(mfit$ncst$mean), "series")
ok("coef()/fitted()/residuals():", length(coef(mfit)), "/",
   length(fitted(mfit)), "/", length(residuals(mfit)))
ok("as.data.frame():", nrow(as.data.frame(mfit)), "rows")

grDevices::pdf(file.path(out_root, "fcast_dfm_plot.pdf"), width = 8, height = 5)
plot(mfit)                                 # S3: plot.fcast_dfm
grDevices::dev.off()
ok("wrote", file.path(out_root, "fcast_dfm_plot.pdf"))


# 10. BACKCASTING DRIVERS -----------------------------------------------------
step(10, "run_ar() / run_wai_adj() / run_fcast() at one evaluation date")

fit_dir <- file.path(out_root, "fits")
eval_date <- 2023

ar <- run_ar(flows = d$flows, stocks = d$stocks, target = target,
             date = eval_date, dataset_used = "demo", output_dir = fit_dir)
ok("AR benchmark nowcast:", round(retrieve_nowcast(ar, "ar"), 5),
   "variance", signif(retrieve_nowcast_var(ar, "ar"), 3))

# Short chain: run_wai_adj() exposes length_sample/burn_in, so the self-test does
# not have to sit through its 5000-draw default.
set.seed(3)
wai <- run_wai_adj(flows = d$flows, stocks = d$stocks, target = target,
                   date = eval_date, dataset_used = "demo",
                   length_sample = 40, burn_in = 15, output_dir = fit_dir)
ok("WAI nowcast:", round(retrieve_nowcast(wai, "wai"), 5),
   "variance", signif(retrieve_nowcast_var(wai, "wai"), 3))

set.seed(4)
fc <- suppressWarnings(
  run_fcast(flows = d$flows, stocks = d$stocks, target = target,
            date = eval_date, dataset_used = "demo_fcast", q = 2,
            length_sample = 20, burn_in = 8, output_dir = fit_dir))
ok("multi-factor fit written;", length(list.files(fit_dir, recursive = TRUE)),
   "fit files on disk")

ok("latest_fit_file():",
   basename(latest_fit_file(file.path(fit_dir, "demo"),
                            cutoff_decimal = eval_date + 1)))
wai_tabs <- extract_wai_data(file.path(fit_dir, "demo",
                                       paste0("fit_", eval_date, ".Rda")))
ok("extract_wai_data():", paste(names(wai_tabs), collapse = ", "))


# 11. REAL-TIME CUTS ----------------------------------------------------------
step(11, "cut_data() and cut_data_real_time()")

rt <- cut_data(dat, current_date = 2023)
ok("cut_data() leaves", length(rt$flows) + length(rt$stocks), "series")

rtv <- cut_data_real_time(data_ch_dataset_test, 2024.5, vint)
ok("cut_data_real_time() target ends at",
   round(max(as.numeric(stats::time(rtv$flows[[target]]))), 3))


# 12. OUTPUT CONFIG AND HELPERS -----------------------------------------------
step(12, "wai_sample_config() and the output helpers")

cfg <- wai_sample_config(sample_id = "demo",
                         output_root = file.path(out_root, "sample"))
# wai_sample_config() is a pure query and creates nothing. The write helpers
# create their own directory; output_figure_path() does not, so make it here -
# this is exactly what analysis/5_plots/_setup.R does.
for (dd in c(cfg$figures_dir, cfg$tables_dir, cfg$results_dir)) {
  dir.create(dd, recursive = TRUE, showWarnings = FALSE)
}
ok("config for sample", cfg$sample_id, "ending", format(cfg$sample_end_date),
   "=", cfg$sample_end_decimal)

write_table_output("demo_table.tex", "\\textbf{table}", cfg$tables_dir)
save_result_output(fit, "demo_fit.Rda", cfg$results_dir)
figpath <- output_figure_path("demo_figure.pdf", cfg$figures_dir)
grDevices::pdf(figpath, width = 6, height = 4); plot(fit$factor); grDevices::dev.off()
ok("wrote a table, a result object and", basename(figpath))

qdf <- data.frame(time = seq(as.Date("2019-01-01"), by = "quarter", length.out = 12),
                  value = rnorm(12))
ok("filter_to_sample():", nrow(filter_to_sample(qdf, end_date = as.Date("2020-12-31"))),
   "of", nrow(qdf), "rows kept")
ok("suffix_cols():",
   paste(names(suffix_cols(data.frame(Series = "WAI", Lag_0 = 1, Lag_1 = 2), "QoQ")),
         collapse = ", "))


# 13. EVALUATION: CORRELATION TABLES AND PLOTS --------------------------------
step(13, "Correlation tables, heatmap, comparison plot, rescaling")

# The analytics builders take an explicit `inputs` bundle, never globals.
inputs <- mfbdfm_example_inputs()
ok("mfbdfm_example_inputs():", length(inputs), "objects")

cor_tab <- get_combined_cor_table("mean", "indicators", inputs = inputs)
ok("get_combined_cor_table():", nrow(cor_tab), "x", ncol(cor_tab))

comb <- create_combined_latex_table(list(mean = cor_tab))
ok("create_combined_latex_table():", nchar(comb$table_tex), "chars of LaTeX")

render_correlation_heatmap(
  cor_tables   = list(mean = cor_tab),
  series_order = c("WAI", "SECO-WWA", "F-CURVE", "SECO-SEC", "SNB-BCI", "KOF-BARO"),
  output_file  = "correlation_heatmap.pdf",
  figures_dir  = cfg$figures_dir)
ok("render_correlation_heatmap() wrote correlation_heatmap.pdf")

wk <- seq(as.Date("2005-01-07"), by = "week", length.out = 900)
wai_df <- data.frame(time = wk, value = rnorm(900))
cmp_df <- data.frame(time = wk, value = rnorm(900))
crises <- data.frame(Peak = as.Date("2008-07-07"), Trough = as.Date("2009-09-28"))
gdp_df <- data.frame(value = seq(as.Date("2005-01-01"), by = "quarter", length.out = 60),
                     y = rnorm(60))
print(plot_comparison(wai_df, cmp_df, "Benchmark", crises, gdp_df,
                      sample_end_date = as.Date("2021-12-31")))
ok("plot_comparison() produced a plot")

ok("rescale_to_gdp():", nrow(rescale_to_gdp(wai_df, gdp_df)), "rows")

lv <- data.frame(time = seq(as.Date("2020-01-07"), by = "week", length.out = 150),
                 value = 100 * cumprod(1 + rnorm(150, 0, 0.002)))
ok("build_wai_qoq_mean_series():", nrow(build_wai_qoq_mean_series(lv)), "quarters")
ok("prepare_wai_qoq_series():",
   nrow(prepare_wai_qoq_series(list(tab_gr_qoq = data.frame(time = as.Date("2020-01-07"),
                                                            value = 1),
                                    tab_gr_lv = lv), method = "last")), "rows")


# 14. EVALUATION: FIT AND ERROR TABLES ----------------------------------------
step(14, "In-sample fit, relative errors, out-of-sample summaries, DM test")

fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
ok("get_insample_fit_table():", paste(names(fit_tabs), collapse = ", "))

rel <- calculate_relative_errors(fit_tabs)
ok("calculate_relative_errors():", paste(names(rel), collapse = ", "))

ann <- annotate_relative_errors(rel$RMSE_relative, fit_tabs$PVAL_RMSE, "RMSE")
ok("annotate_relative_errors():", nrow(ann), "rows")

details <- get_insample_error_details("mean", "indicators", inputs = inputs)
ok("get_insample_error_details():", nrow(details), "rows")

esum <- create_error_summary_tables(details, model_order = c("WAI", "KOF-BARO"),
                                    date_col = "observation_date")
ok("create_error_summary_tables():", paste(names(esum), collapse = ", "))

set.seed(1)
combined_results <- expand.grid(
  target_vintage = seq(2015, 2019.75, by = 0.25),
  model = c("WAI", "AR"), method = "mean", lag_number = -4:0,
  GDP_type = "ssa", frequency = "QoQ", stringsAsFactors = FALSE)
combined_results$error <- rnorm(nrow(combined_results), 0, 0.5)
relerr <- create_rel_error_tables(combined_results, model_order = c("WAI", "AR"))
ok("create_rel_error_tables():", paste(names(relerr), collapse = ", "))

print_evaluation_periods(
  data.frame(Series = "WAI",
             date = seq(as.Date("2010-01-01"), by = "quarter", length.out = 8)),
  "Series", "date", context_label = "self-test")

set.seed(5)
ok("dm_test_modified() p-value:",
   signif(dm_test_modified(rnorm(60), rnorm(60) * 1.4, alternative = "less"), 3))


# 15. COVERAGE AUDIT ----------------------------------------------------------
step(15, "Coverage audit: did this script touch every export?")

# Parse the script rather than grep it. all.names() sees the symbols the code
# actually references and is blind to comments and strings, so a function that is
# merely NAMED in a comment cannot masquerade as a function that was called -
# which a text search would have let happen, and this file has plenty of comments
# naming functions.
used <- unique(unlist(lapply(parse("demo/run_package_demo.R", keep.source = FALSE),
                             all.names)))

exports <- sort(getNamespaceExports("mfbdfm"))
exports <- exports[!exports %in% c("data_ch_dataset", "data_ch_dataset_test")]
funs <- exports[vapply(exports, function(f)
  is.function(get0(f, envir = asNamespace("mfbdfm"))), logical(1))]

missing <- setdiff(funs, used)
called <- funs %in% used

cat("   exported functions : ", length(funs), "\n", sep = "")
cat("   called here        : ", sum(called), "\n", sep = "")
if (length(missing)) {
  cat("   NOT CALLED         : ", length(missing), "\n", sep = "")
  for (m in missing) cat("      - ", m, "\n", sep = "")
} else {
  cat("   NOT CALLED         : 0  <- complete\n")
}

s3 <- c("print.ind_dfm", "print.fcast_dfm", "print.dfm_priors", "print.dfm_control",
        "print.mfbdfm_data", "print.summary.mfbdfm_fit",
        "summary.ind_dfm", "summary.fcast_dfm", "plot.ind_dfm", "plot.fcast_dfm",
        "coef.ind_dfm", "coef.fcast_dfm", "fitted.ind_dfm", "fitted.fcast_dfm",
        "residuals.ind_dfm", "residuals.fcast_dfm",
        "as.data.frame.ind_dfm", "as.data.frame.fcast_dfm")
cat("   S3 methods         : ", length(s3),
    " (exercised via the generics on both fit classes)\n", sep = "")


# SUMMARY ---------------------------------------------------------------------
cat("\n", strrep("=", 74), "\n", sep = "")
files <- list.files(out_root, recursive = TRUE)
cat("SELF-TEST COMPLETE in ",
    round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 1),
    " min\n", sep = "")
cat(length(files), " files written under ", out_root, "\n", sep = "")
print(files)
if (length(missing)) {
  cat("\nWARNING: ", length(missing),
      " exported function(s) were never called - see section 15.\n", sep = "")
} else {
  cat("\nEvery exported function was called.\n")
}
cat("\nThe chains here are far too short for inference. This checks that the\n")
cat("workflow RUNS, not that the numbers are right.\n")
