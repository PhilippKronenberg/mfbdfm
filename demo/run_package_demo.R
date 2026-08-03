# =============================================================================
# mfbdfm end-to-end demonstration
# =============================================================================
# Installs the package from this source tree and exercises the user-facing
# workflow from raw data to saved figures and tables. Run from the repository
# root:
#
#     Rscript demo/run_package_demo.R
#
# Purpose is verification, not analysis. Every model here uses a short MCMC
# chain so the whole thing finishes in minutes; the numbers are meaningless and
# the script says so. What it checks is that the pieces still fit together:
# data in, models fit, methods dispatch, outputs land on disk.
#
# This is deliberately OUTSIDE the package (demo/ is in .Rbuildignore) and uses
# only exported functions - no internals, and none of the replication code under
# analysis/. If something here breaks, a user's workflow breaks.
#
# It is also the skeleton for #23, verifying the workflow against real private
# data: swap the shipped dataset for the real one at the marked point and raise
# the chain lengths.
# =============================================================================

options(warn = 1)
t_start <- Sys.time()

step <- function(n, msg) cat("\n", strrep("-", 70), "\n", n, ". ", msg, "\n", sep = "")
ok <- function(...) cat("   ok  ", ..., "\n")

out_root <- file.path("demo", "outputs")
dir.create(out_root, recursive = TRUE, showWarnings = FALSE)


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
step(2, "Shipped data, and the real-time GDP vintages")

data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
ok(length(data_ch_dataset_test$flows), "flow and",
   length(data_ch_dataset_test$stocks), "stock series")

# The full dataset ships WITHOUT the GDP target; real workflows inject it from
# the real-time vintages, which travel with the package.
vint <- get_real_time_gdp_vintages("quarterly")
ok("real-time GDP vintages:", ncol(vint) - 1, "vintage columns")

latest <- get_latest_numeric_vintage(vint, lower_bound = 2005.438,
                                     upper_bound = decimal_date_local(Sys.Date()))
ok("latest usable vintage:", latest)

# ---- #23: replace the two lines below with the real dataset ----------------
dat <- data_ch_dataset_test
# ----------------------------------------------------------------------------

# Frequency and date helpers
ok("dec2week(2020):", format(dec2week(2020)))
ok("crisis flags (WAI / EKMN definitions):",
   is_crisis_period(as.Date("2020-04-01")), "/", is_crisis_period_fcast(2020.25))
ok("week2mon() gives frequency",
   stats::frequency(week2mon(dat)$flows[[1]]))
ok("subsetting helpers:",
   length(drop_weekly(dat)$flows), "monthly-only,",
   length(drop_financial(dat)$flows), "without financials,",
   length(drop_retail(dat)$flows), "without sectoral retail")


# 3. INPUT CONSTRUCTION -------------------------------------------------------
step(3, "mfbdfm_data(): assemble and check the model input")

series <- c(dat$flows[c(target, "SWISSMI")], dat$stocks[1:2])
series <- lapply(series, stats::window, start = 2018)
meta <- data.frame(series = names(series),
                   type = rep(c("flow", "stock"), each = 2))

d <- mfbdfm_data(series, meta, target = target)
print(d)
ok("classification and frequencies shown above - check before a long run")

inv <- create_inventory(flows = d$flows, stocks = d$stocks)
Y <- prepare_data(flows = d$flows, stocks = d$stocks, inventory = inv,
                  target = target)
ok("prepared matrix:", nrow(Y), "x", ncol(Y), "at frequency", stats::frequency(Y))


# 4. SPECIFICATION ------------------------------------------------------------
step(4, "dfm_priors() and dfm_control()")

pri <- dfm_priors("ind_dfm")
ctl <- dfm_control("ind_dfm")
print(ctl)
ok("priors and control resolved; defaults reproduce the published behaviour")


# 5. SINGLE-FACTOR MODEL ------------------------------------------------------
step(5, "ind_dfm(): the target-anchored single-factor model (WAI)")

set.seed(1)
fit <- ind_dfm(d, length_sample = 60, burn_in = 20, priors = pri, control = ctl)
ok("fitted;", length(fit$factor), "weekly factor periods")

print(fit)
print(summary(fit))
ok("coef() names:", paste(utils::head(names(coef(fit)), 4), collapse = ", "))
ok("fitted()/residuals() lengths:", length(fitted(fit)), "/", length(residuals(fit)))
ok("as.data.frame() rows:", nrow(as.data.frame(fit)))

grDevices::pdf(file.path(out_root, "ind_dfm_plot.pdf"), width = 8, height = 5)
plot(fit)
grDevices::dev.off()
ok("wrote", file.path(out_root, "ind_dfm_plot.pdf"))


# 6. MULTI-FACTOR MODEL -------------------------------------------------------
step(6, "fcast_dfm(): the multi-factor model (Eckert et al. 2025)")

set.seed(2)
mfit <- suppressWarnings(
  fcast_dfm(d, q = 2, length_sample = 30, burn_in = 10,
            control = dfm_control("fcast_dfm")))
print(mfit)
ok("factors:", paste(dim(mfit$factor), collapse = " x "),
   "| nowcasts for", length(mfit$ncst$mean), "series")


# 7. BACKCASTING --------------------------------------------------------------
step(7, "run_ar() / run_wai_adj() / run_fcast() at one evaluation date")

fit_dir <- file.path(out_root, "fits")
eval_date <- 2023

ar <- run_ar(flows = d$flows, stocks = d$stocks, target = target,
             date = eval_date, dataset_used = "demo", output_dir = fit_dir)
ok("AR benchmark nowcast:", round(retrieve_nowcast(ar, "ar"), 5),
   "variance", signif(retrieve_nowcast_var(ar, "ar"), 3))

set.seed(3)
wai <- run_wai_adj(flows = d$flows, stocks = d$stocks, target = target,
                   date = eval_date, dataset_used = "demo",
                   output_dir = fit_dir)
ok("WAI nowcast:", round(retrieve_nowcast(wai, "wai"), 5))

set.seed(4)
fc <- suppressWarnings(
  run_fcast(flows = d$flows, stocks = d$stocks, target = target,
            date = eval_date, dataset_used = "demo_fcast", q = 2,
            length_sample = 20, burn_in = 8, output_dir = fit_dir))
ok("multi-factor nowcast written;", length(list.files(fit_dir, recursive = TRUE)),
   "fit files on disk")

ok("latest_fit_file():",
   basename(latest_fit_file(file.path(fit_dir, "demo"),
                            cutoff_decimal = eval_date + 1)))
ok("extract_wai_data() tables:",
   paste(names(extract_wai_data(file.path(fit_dir, "demo",
                                          paste0("fit_", eval_date, ".Rda")))),
         collapse = ", "))


# 8. REAL-TIME CUTS -----------------------------------------------------------
step(8, "cut_data() and the vintage pickers")

rt <- cut_data(dat, current_date = 2023)
ok("cut_data() leaves", length(rt$flows) + length(rt$stocks), "series")
# note the argument order: current_date first, then the vintage table. It
# returns the vintage COLUMN, not its name.
v2023 <- select_most_recent_GDP_vintage(2023, vint)
ok("select_most_recent_GDP_vintage(): a vector of", length(v2023),
   "quarters,", sum(!is.na(v2023)), "observed")


# 9. OUTPUT PATHS AND EVALUATION ----------------------------------------------
step(9, "wai_sample_config(), output helpers, evaluation tables")

cfg <- wai_sample_config(sample_id = "demo",
                         output_root = file.path(out_root, "sample"))
ok("figures/tables/results dirs created under", cfg$output_root)

set.seed(5)
e1 <- rnorm(60); e2 <- rnorm(60) * 1.4
ok("dm_test_modified() p-value:",
   signif(dm_test_modified(e1, e2, alternative = "less"), 3))

write_table_output("demo_table.csv",
                   utils::capture.output(
                     utils::write.csv(data.frame(a = 1:3, b = letters[1:3]),
                                      row.names = FALSE)),
                   cfg$tables_dir)
save_result_output(fit, "demo_fit.Rda", cfg$results_dir)
ok("wrote a table and a result object via the package helpers")

p <- output_figure_path("demo_figure.pdf", cfg$figures_dir)
grDevices::pdf(p, width = 6, height = 4); plot(fit$factor); grDevices::dev.off()
ok("wrote", p)


# SUMMARY ---------------------------------------------------------------------
cat("\n", strrep("=", 70), "\n", sep = "")
files <- list.files(out_root, recursive = TRUE)
cat("DEMO COMPLETE in ",
    round(as.numeric(difftime(Sys.time(), t_start, units = "mins")), 1),
    " min\n", sep = "")
cat(length(files), " files written under ", out_root, "\n", sep = "")
print(files)
cat("\nThe chains here are far too short for inference - this checks that the\n")
cat("workflow runs, not that the numbers are right.\n")
