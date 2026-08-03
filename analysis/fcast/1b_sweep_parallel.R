# Run from the repository root.

# -----------------------------------------------------------------------------
# Parallel vintage sweep
# -----------------------------------------------------------------------------
# 1_backcast_fcast.R fits one date at a time, which is fine for a wiring check
# and hopeless for a sweep: a fit takes about 49 minutes, so a full weekly sweep
# over 2005-2021 is 816 fits, roughly 28 days serial. This distributes the dates
# across workers.
#
# Parallelising over DATES, not within a fit. fcast_dfm()'s `ncores` only
# parallelises the post-hoc rotation, which is a minority of the runtime; the
# Gibbs sampler is inherently serial. Dates are independent, so they are the
# right axis.
#
# Default here is the year 2020 - 48 weekly evaluation dates, about 10 hours on
# 4 workers.
#
# NOTE on 2020: every target quarter it reaches (2020Q1 through 2021Q1) is
# inside the Covid window of is_crisis_period_fcast(), so a 2020-only sweep
# yields NO non-crisis rows and the crisis-vs-normal figures will have one empty
# panel. Extend `years` to include 2019 if that comparison is wanted.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")
library(foreach)
library(doParallel)

years <- 2019:2020
q_x <- 2
n_workers <- 4
run_benchmark <- TRUE
fit_root <- file.path("fits", "fcast_sweep")
mcmc <- list(length_sample = 1000, burn_in = 1000)

date_vec <- round(sort(unlist(lapply(years, function(y) seq(y, y + 47/48, 1/48)))), 3)


# DATA ------------------------------------------------------------------------
# The paper's own dataset, so the sweep is comparable with its stored panel.

e <- new.env(); load("analysis/fcast/reference/rda/data_ch.Rda", envir = e)
dat <- e$dat
stopifnot(target %in% names(dat$flows))

message(length(date_vec), " evaluation dates (", min(date_vec), " to ",
        max(date_vec), "), q = ", q_x, ", ", n_workers, " workers")
message("estimated wall-clock: ",
        round(length(date_vec) * 49.2 / 60 / n_workers, 1), " h")


# SWEEP -----------------------------------------------------------------------

dir.create(fit_root, recursive = TRUE, showWarnings = FALSE)
cl <- makeCluster(n_workers)
registerDoParallel(cl)
on.exit({ stopCluster(cl); message("cluster stopped") }, add = TRUE)

t0 <- Sys.time()

res <- foreach(ix = date_vec, .packages = c("mfbdfm", "Matrix", "zoo"),
               .errorhandling = "pass") %dopar% {

  # Skip work already on disk, so an interrupted sweep resumes instead of
  # starting over - 10 hours is long enough that this matters.
  f <- file.path(fit_root, paste0("q", q_x), paste0("fit_", round(ix, 3), ".Rda"))
  if (file.exists(f)) return(paste("skip", ix))

  rt <- cut_data(dat, ix)
  if (!target %in% names(rt$flows)) return(paste("no target at", ix))

  run_fcast(flows = rt$flows, stocks = rt$stocks, target = target,
            date = ix, dataset_used = paste0("q", q_x), q = q_x,
            length_sample = mcmc$length_sample, burn_in = mcmc$burn_in,
            output_dir = fit_root)

  if (run_benchmark) {
    source("analysis/fcast/_setup.R", local = TRUE)
    source_bmdfm_functions()
    source("analysis/fcast/bmdfm_benchmark.R", local = TRUE)
    mon <- week2mon(rt)
    try(run_bmdfm(flows = mon$flows, stocks = mon$stocks, target = target,
                  date = ix, dataset_used = paste0("bmdfm_q", q_x),
                  n_f = q_x, output_dir = fit_root), silent = TRUE)
  }

  paste("done", ix)
}

el <- round(as.numeric(difftime(Sys.time(), t0, units = "hours")), 2)
errs <- vapply(res, function(x) inherits(x, "error"), logical(1))
message("\nsweep finished in ", el, " h; ", sum(!errs), " ok, ", sum(errs), " failed")
if (any(errs)) {
  message("first failure: ", conditionMessage(res[errs][[1]]))
}
message("fits under ", fit_root, ": ",
        length(list.files(fit_root, recursive = TRUE)))
