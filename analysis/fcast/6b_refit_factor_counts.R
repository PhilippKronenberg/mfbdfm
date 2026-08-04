# Run from the repository root.

# -----------------------------------------------------------------------------
# Refit q = 1..4 at 2021.979, as our own stand-in for the paper's fits
# -----------------------------------------------------------------------------
# 6_factor_plot_fcast.R needs one fit per factor count at the same date. Its
# first choice is the paper's own <n>f_fit_2021.979.Rda, which are not committed
# (analysis/fcast/reference/ is gitignored). Its fallback used to be the paper's
# testlauf_<n>f.Rda files, which are the last objects anywhere in this workflow
# still saved under the pre-rename name `out` -- and which come from yet another
# run, so they reproduce the alignment badly (5 of 10 groups against 10 of 10).
#
# This produces the fallback ourselves instead: same model, same date, same
# input data, written as `mod` like every other fit this package saves.
#
# It is a THIRD run, not a reproduction of either of the other two. The post-hoc
# rotation does not reach uniqueness across runs (#46), so the factor alignment
# derived in 6_factor_plot_fcast.R may well differ from the published one. That
# is the same caveat the testlauf fallback carried; the difference is that these
# fits are ours, reproducible from this script, and named consistently.
#
# Cost: the sweep measured 49.2 min per fit at q = 2 with these settings. q = 1
# is cheaper and q = 3, 4 more expensive, since the post-hoc rotation scales with
# the factor count -- so treat the estimate below as a lower bound.
#
# Resume-safe: a fit already on disk is skipped, so an interrupted run continues
# where it stopped.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")
library(foreach)
library(doParallel)

factor_counts <- 1:4

# NOT round(2021 + 47/48, 3). run_fcast() trims the factor with
# trim_to(mod$factor, date), and the grid point is 2021.97916..., so the rounded
# 2021.979 is *below* it and window() drops the final week: measured 1557
# periods against the paper's 1558, same start, one period short at the end.
# run_fcast() rounds for the file name itself, so the output is still
# fit_2021.979.Rda.
fit_date <- 2021 + 47/48
fit_label <- round(fit_date, 3)

n_workers <- 3          # memory-bound, not core-bound; see 1b_sweep_parallel.R
fit_root <- file.path("fits", "fcast_replication")

# Same chain as the sweep: 1000 post-burn-in iterations, half of them retained.
mcmc <- list(length_sample = 500, burn_in = 1000, thinning = 2)


# DATA ------------------------------------------------------------------------
# The paper's own dataset, so these are comparable with its stored fits. Using
# analysis/Rda/data_ch_dataset_test.Rda instead would change the inputs as well
# as the run, and measured much worse factor agreement (0.584 against 0.976).

ref_data <- "analysis/fcast/reference/rda/data_ch.Rda"
if (!file.exists(ref_data)) {
  stop("No input data at ", ref_data, ".\n",
       "  See analysis/fcast/README.md - the reference material is not ",
       "committed.", call. = FALSE)
}
e <- new.env(); load(ref_data, envir = e)
dat <- cut_data(e$dat, fit_date)
stopifnot(target %in% names(dat$flows))

message(length(factor_counts), " fits (q = ",
        paste(factor_counts, collapse = ", "), ") at ", fit_label,
        ", ", n_workers, " workers")
message("estimated wall-clock: at least ",
        round(ceiling(length(factor_counts) / n_workers) * 49.2 / 60, 1), " h")


# REFIT -----------------------------------------------------------------------

dir.create(fit_root, recursive = TRUE, showWarnings = FALSE)
cl <- makeCluster(n_workers)
registerDoParallel(cl)
on.exit({ stopCluster(cl); message("cluster stopped") }, add = TRUE)

t0 <- Sys.time()

res <- foreach(q_x = factor_counts, .packages = c("mfbdfm", "Matrix", "zoo"),
               .errorhandling = "pass") %dopar% {

  f <- file.path(fit_root, paste0("q", q_x), paste0("fit_", fit_label, ".Rda"))
  if (file.exists(f)) return(paste("skip q =", q_x))

  run_fcast(flows = dat$flows, stocks = dat$stocks, target = target,
            date = fit_date, dataset_used = paste0("q", q_x), q = q_x,
            length_sample = mcmc$length_sample, burn_in = mcmc$burn_in,
            thinning = mcmc$thinning, output_dir = fit_root)

  paste("done q =", q_x)
}

el <- round(as.numeric(difftime(Sys.time(), t0, units = "hours")), 2)
errs <- vapply(res, function(x) inherits(x, "error"), logical(1))
message("\nrefit finished in ", el, " h; ", sum(!errs), " ok, ", sum(errs),
        " failed")

# Failures go to a file, not only to the console - see 1b_sweep_parallel.R.
log_path <- file.path(fit_root, "refit_failures.log")
if (any(errs)) {
  msgs <- vapply(res[errs], conditionMessage, character(1))
  writeLines(c(paste("refit at", format(Sys.time())),
               paste(sum(errs), "of", length(res), "factor counts failed"),
               "", paste0("q = ", factor_counts[errs], ": ", msgs)), log_path)
  message("failures written to ", log_path)
} else if (file.exists(log_path)) {
  unlink(log_path)
}

message("fits under ", fit_root, ": ",
        length(list.files(fit_root, recursive = TRUE, pattern = "\\.Rda$")))
