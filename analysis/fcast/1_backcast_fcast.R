# Run from the repository root.

# -----------------------------------------------------------------------------
# Multi-factor backcast driver (Eckert, Kronenberg, Mikosch & Neuwirth 2025)
# -----------------------------------------------------------------------------
# The fcast_dfm() counterpart of analysis/2_backcast.R, and the prerequisite for
# everything else in analysis/fcast/: the evaluation and plotting scripts read
# the fits this produces, so it has to run before any of them (#53).
#
# Writes one fit per (factor count, evaluation date) to
#   <fcast_fit_root>/<dataset label>/fit_<date>.Rda
# which is the same layout run_wai_adj() uses, so the existing fit-discovery
# code works unchanged.
#
# Cost warning: fcast_dfm() is considerably more expensive than ind_dfm() - the
# post-hoc rotation scales with the number of retained draws, on top of the
# sampler itself. A full vintage sweep is an overnight job. Start with
# `quick_check <- TRUE` below to confirm the wiring on a short chain first.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")

# Set TRUE for a fast wiring check (minutes, meaningless numbers);
# FALSE for a real run (hours).
quick_check <- TRUE

# Also fit the BMDFM benchmark of Banbura & Modugno (JAE 2014), which is what
# the WAIVSBMDFM figures compare against. Roughly 150 s per fit on top of
# fcast_dfm, so it is opt-out for a quick wiring check.
run_benchmark <- TRUE

if (run_benchmark) {
  source_bmdfm_functions()
  source("analysis/fcast/bmdfm_benchmark.R")
}


# IMPORT DATA -------------------------------------------------------------

load("analysis/Rda/data_ch_dataset_test.Rda")

sample_end_indicator_date <- 2026
dat <- cut_data(dat, current_date = sample_end_indicator_date)

# Inject the GDP target from the real-time vintages, exactly as
# analysis/2_backcast.R does - the shipped dataset deliberately ships without
# it. Note this matters less here than for the WAI: fcast_dfm()'s `target` only
# selects which nowcast is surfaced, it does not identify the factors.
sample_end_gdp_vintage_decimal <- round(
  decimal_date_local(as.Date("2026-03-07")), 3)
GDP_gr_vintages_quarterly <- get_real_time_gdp_vintages("quarterly")
sample_end_gdp_vintage <- get_latest_numeric_vintage(
  GDP_gr_vintages_quarterly,
  lower_bound = 2005.438,
  upper_bound = sample_end_gdp_vintage_decimal
)
x_hist_gr <- na.trim(ts(
  GDP_gr_vintages_quarterly[[as.character(sample_end_gdp_vintage)]],
  start = c(1990, 1), frequency = 4
))
dat$flows[[target]] <- x_hist_gr


# SETTINGS ----------------------------------------------------------------

# Where the WAI sweep varies the dataset, the multi-factor sweep varies the
# factor count: the single-factor model has one factor by construction, so `q`
# is the setting with no counterpart there.
factor_counts <- c(2, 3)

if (quick_check) {
  # enough to exercise every code path, not enough to mean anything
  dat <- drop_financial(dat)

  # Not a plain lapply(window, start = ): some series in this dataset were
  # discontinued before the cut-off (anz_kktrans_ch ends 2020.979), and
  # window(start = ) errors with "'start' cannot be after 'end'" rather than
  # returning an empty series. Drop those - they carry no observations in this
  # window anyway - and window the rest.
  keep_from <- function(lst, from) {
    lst <- lst[vapply(lst, function(z) max(as.numeric(time(z))) > from,
                      logical(1))]
    lapply(lst, window, start = from)
  }
  # 2018, not something later: cut_data() drops any series with fewer than 24
  # observations, and the quarterly target only reaches that from about 2020
  # back. Windowing to 2021 leaves GDP with 20 quarters, so cut_data() removes
  # it in the loop below and fcast_dfm() then fails on a missing `target`.
  quick_start <- 2018
  dat$flows <- keep_from(dat$flows, quick_start)
  dat$stocks <- keep_from(dat$stocks, quick_start)
  stopifnot(target %in% names(dat$flows),
            length(dat$flows[[target]]) >= 24)

  factor_counts <- 2
  mcmc <- list(length_sample = 20, burn_in = 5)
  date_vec <- 2025 + 47/48
} else {
  mcmc <- list(length_sample = 1000, burn_in = 1000)
  # NOTE: start in the first week of a quarter (0/48, 12/48, 24/48, 36/48),
  # as in analysis/2_backcast.R, or the quarterly evaluation misaligns.
  start_date <- 2025 + 47/48
  end_date <- 2025 + 47/48
  date_vec <- seq(start_date, end_date, 1/48)
}


# BACKCASTING -------------------------------------------------------------

for (ix in date_vec) {
  for (q_x in factor_counts) {

    dataset_name <- paste0("q", q_x)
    message("fcast_dfm: q = ", q_x, ", date = ", round(ix, 3))

    # real-time cut: only data that would have been available at `ix`
    dat_realtime <- cut_data(dat, ix)

    run_fcast(flows = dat_realtime$flows,
              stocks = dat_realtime$stocks,
              target = target,
              date = ix,
              dataset_used = dataset_name,
              q = q_x,
              length_sample = mcmc$length_sample,
              burn_in = mcmc$burn_in,
              output_dir = fcast_fit_root)

    # BMDFM benchmark, for the WAIVSBMDFM comparison. Monthly by construction,
    # so the weekly series are aggregated first - which is also why the paper
    # reports no BMDFM on the weekly dataset.
    if (run_benchmark) {
      message("bmdfm:     q = ", q_x, ", date = ", round(ix, 3))
      mon <- week2mon(dat_realtime)
      run_bmdfm(flows = mon$flows,
                stocks = mon$stocks,
                target = target,
                date = ix,
                dataset_used = paste0("bmdfm_q", q_x),
                n_f = q_x,
                output_dir = fcast_fit_root)
    }

  }
}

message("fits written to ", fcast_fit_root)
