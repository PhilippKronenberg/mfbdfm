# Run from the repository root.

# -----------------------------------------------------------------------------
# Reproduce the Eckert et al. (2025) evaluation figures
# -----------------------------------------------------------------------------
# Runs this repository's plotting code over the paper's own evaluation panels
# (analysis/fcast/figures/results_tab_<n>f.Rda) and writes the figure set to
# analysis/outputs/fcast/paper_repro/figures/, so each output can be held next
# to the published PDF in analysis/fcast/figures/.
#
# This is the validation step for the port: same inputs, our code, and the
# question is whether the figures come out the same. It does NOT re-estimate
# anything - reproducing the *estimates* needs the original data and a full
# vintage sweep, which is 1_backcast_fcast.R's job.
#
# Layout follows the published figures: a level panel over a log-ratio panel
# against a benchmark, faceted Crisis / Non-Crisis, horizon counted down to
# publication, shared legend between the two panels.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")
library(ggpubr)
library(tibble)
library(tidyr)

ref_dir <- "analysis/fcast/figures"
if (!dir.exists(ref_dir)) {
  stop("No reference panels at ", ref_dir, ".", call. = FALSE)
}

out_dir <- file.path("analysis", "outputs", "fcast", "paper_repro", "figures")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# LOAD --------------------------------------------------------------------
#
# Built from results_backcast.Rda + results_backcast_var.Rda - the main run,
# whose factor count is chosen by information criterion (see tab_IC_full.Rda and
# 3a_evaluation_full.R line 38ff), not one of the fixed-q results_tab_<n>f.Rda
# files. Those cover a different exercise (WAI against BMDFM/GRSDFM at a fixed
# factor count) and reproduce a different figure.
#
# The rebuild is verified exact: pooled RMSFE from this panel matches the stored
# tables_crisisvsnormal in results_evaluation.Rda on all 12 model x dataset x
# regime cells to five significant figures, with identical row counts
# (240 crisis, 564 non-crisis).

model_lbl <- c(ar = "AR", bmdfm = "BM", grsdfm = "GRS", wai = "EKMN")
data_lbl <- c(only_monthly = "Monthly", aggr_weekly = "Time Agg.", full = "Weekly")

e <- new.env(); load(file.path(ref_dir, "results_backcast.Rda"), envir = e)
v <- new.env(); load(file.path(ref_dir, "results_backcast_var.Rda"), envir = v)

# 3a_evaluation_full.R lines 192-222, verbatim in effect
gather_nested <- function(lst, val_name) {
  do.call(rbind, lapply(names(lst), function(dx)
    do.call(rbind, lapply(names(lst[[dx]]), function(mx) {
      ts_all <- do.call(cbind, lst[[dx]][[mx]])
      df <- as_tibble(ts_all) %>%
        add_column(period = time(ts_all)) %>%
        pivot_longer(-period, names_to = "date")
      df <- df[-which(is.na(df$value)), ] %>%
        add_column(model = mx, dataset = dx)
      df$date <- as.numeric(df$date)
      names(df)[names(df) == "value"] <- val_name
      df
    }))))
}

panel <- gather_nested(e$out, "value")
panel$sd <- sqrt(gather_nested(v$var, "var")$var)

load(file.path(ref_dir, "data_ch.Rda"))         # the vintage the paper evaluated against
gdp <- dat$flows$ch.seco.gdp.real.gdp.ssa
panel$realization <- as.numeric(gdp)[match(round(panel$period, 3),
                                           round(as.numeric(time(gdp)), 3))]

panel <- panel %>%
  mutate(logs = -dnorm(realization, value, sd, log = TRUE),
         error = value - realization,
         sqerror = error^2,
         observed = round(period + 1/4 + 8/48, 3),
         horizon = round((observed - date) * 48)) %>%
  # the paper's own filters, 3a_evaluation_full.R lines 225 and 230
  filter(period >= 2005, period <= 2021.5, horizon %in% 1:12) %>%
  mutate(series = paste0(model_lbl[model], " (", data_lbl[dataset], ")"),
         regime = ifelse(is_crisis_period_fcast(period),
                         "Crisis Periods", "Non-Crisis Periods"))

n_factors <- "IC"   # used only in output file names

message("reference panel: ", nrow(panel), " rows, ",
        length(unique(panel$series)), " series, horizons ",
        paste(range(panel$horizon), collapse = "-"))


# METRICS -----------------------------------------------------------------

# RMSFE, MAE and the log score, matching the three figure prefixes in the
# published set (RMSFE_*, MAE_*, LOG_*).
# `rel` says how the lower panel compares a series with the benchmark. These are
# NOT a judgement call - both are taken from the paper's own plotting code:
#
#   RMSFE / MAE   old_code_fcast_dfm/plots_nowcast.R:179
#                   log(series$err_meas) - log(benchmark$err_meas)
#                 i.e. a log RATIO, which is what the published axes say.
#
#   Log score     old_code_fcast_dfm/plots_nowcast_scores.R:186
#                   mutate(rmsfe = wai$rmsfe - ar$rmsfe)
#                 where `rmsfe` holds mean(logs) (line 166), i.e. a plain
#                 DIFFERENCE, and their panel is labelled "Log Score
#                 Difference" to match.
#
# The distinction is not cosmetic: the log score is negative, so log(value/base)
# is NaN wherever the two straddle zero - taking a ratio there produced 72 such
# rows on the first run and silently dropped them from the figure.
#
# One deviation, deliberate: their score panel draws its reference line at
# y = 1 (plots_nowcast_scores.R:204) on what is a difference, where the neutral
# value is 0. That looks like a leftover from a ratio panel; we use 0.
metrics <- list(
  RMSFE = list(fn = function(d) sqrt(mean(d$sqerror, na.rm = TRUE)),
               lab = "RMSFE", rel = "log_ratio"),
  MAE   = list(fn = function(d) mean(abs(d$error), na.rm = TRUE),
               lab = "MAE", rel = "log_ratio"),
  LOG   = list(fn = function(d) mean(d$logs, na.rm = TRUE),
               lab = "Log Score", rel = "difference")
)

# The comparisons the published figures make, and the benchmark each
# log-ratio panel is taken against.
comparisons <- list(
  FullVsAR = list(
    series = c("AR (Weekly)", "EKMN (Weekly)"),
    base = "AR (Weekly)"),
  FullVsOnlyMonthly = list(
    series = c("EKMN (Weekly)", "EKMN (Monthly)"),
    base = "EKMN (Monthly)"),
  FullVsTemporarilyAggregated = list(
    series = c("EKMN (Weekly)", "EKMN (Time Agg.)"),
    base = "EKMN (Time Agg.)")
)


# BUILD -------------------------------------------------------------------

theme_paper <- function() {
  theme_minimal(base_size = 9) +
    theme(panel.grid.minor = element_blank(),
          legend.position = "bottom",
          legend.title = element_blank(),
          strip.text = element_text(size = 9))
}

# One fixed colour per series, applied to BOTH panels. Without this the lower
# panel - which drops the benchmark series - remaps colours to whatever levels
# it still has, so under ggarrange's shared legend every series in that panel is
# mislabelled by one position. A legend that is confidently wrong is worse than
# no legend, and this is exactly the kind of error a figure carries silently.
SERIES_PALETTE <- c(
  "AR (Monthly)"     = "#7f7f7f", "AR (Time Agg.)"   = "#bdbdbd",
  "AR (Weekly)"      = "#000000",
  "BM (Monthly)"     = "#000000", "BM (Time Agg.)"   = "#9ecae1",
  "GRS (Monthly)"    = "#e6550d", "GRS (Time Agg.)"  = "#fdae6b",
  "EKMN (Monthly)"   = "#6baed6", "EKMN (Time Agg.)" = "#3182bd",
  "EKMN (Weekly)"    = "#08519c"
)

scale_series <- function() {
  scale_colour_manual(values = SERIES_PALETTE, drop = FALSE, limits = force)
}

summarise_metric <- function(d, metric, by_regime = TRUE) {
  grp <- if (by_regime) c("series", "regime", "horizon") else c("series", "horizon")
  d %>%
    group_by(across(all_of(grp))) %>%
    group_modify(~ tibble(value = metrics[[metric]]$fn(.x))) %>%
    ungroup()
}

make_figure <- function(cmp_name, metric, by_regime = TRUE) {

  cmp <- comparisons[[cmp_name]]
  d <- panel %>% filter(series %in% cmp$series) %>%
    mutate(series = factor(series, levels = cmp$series))
  if (!nrow(d)) { message("  skip ", cmp_name, "/", metric, ": no rows"); return(NULL) }

  lev <- summarise_metric(d, metric, by_regime)

  p_top <- ggplot(lev, aes(x = horizon, y = value, colour = series)) +
    geom_line(linewidth = 0.5) +
    scale_x_reverse(breaks = seq(12, 2, by = -2)) +
    scale_series() +
    labs(x = NULL, y = metrics[[metric]]$lab) +
    theme_paper()
  if (by_regime) p_top <- p_top + facet_wrap(~regime)

  # log-ratio panel: below zero means better than the benchmark
  key <- if (by_regime) c("regime", "horizon") else "horizon"
  base <- lev %>% filter(series == cmp$base) %>%
    select(all_of(key), base_value = value)
  rel <- metrics[[metric]]$rel
  ratio <- lev %>% filter(series != cmp$base) %>%
    inner_join(base, by = key) %>%
    mutate(relative = if (rel == "log_ratio") log(value / base_value)
                      else value - base_value)

  p_bot <- ggplot(ratio, aes(x = horizon, y = relative, colour = series)) +
    geom_hline(yintercept = 0, colour = "grey40", linewidth = 0.3) +
    geom_line(linewidth = 0.5) + geom_point(size = 0.8) +
    scale_x_reverse(breaks = seq(12, 2, by = -2)) +
    scale_series() +
    labs(x = "Nowcast Horizon (in Weeks)",
         y = paste(metrics[[metric]]$lab,
                   if (rel == "log_ratio") "log-ratio" else "difference")) +
    theme_paper()
  if (by_regime) p_bot <- p_bot + facet_wrap(~regime)

  p <- ggarrange(p_top, p_bot, ncol = 1, nrow = 2,
                 common.legend = TRUE, legend = "bottom", heights = c(1, 1))

  tag <- if (by_regime) "CrisisAndNormal" else "FullSample"
  path <- file.path(out_dir,
                    sprintf("%s_%s_%s_%s.pdf", metric, tag, cmp_name, n_factors))
  ggsave(path, p, width = 20, height = 14, units = "cm")
  message("  wrote ", basename(path))
  path

}

message("\nbuilding figures into ", out_dir)
written <- character(0)

for (metric in names(metrics)) {
  for (cmp_name in names(comparisons)) {
    written <- c(written, make_figure(cmp_name, metric, by_regime = TRUE))
  }
}
# the one full-sample (no crisis split) figure in the published set
written <- c(written, make_figure("FullVsAR", "RMSFE", by_regime = FALSE))


# HEADLINE NUMBERS --------------------------------------------------------

cat("\nRMSFE by regime, pooled over horizons (compare with the published PDFs):\n")
panel %>%
  filter(model %in% c("ar","wai")) %>%
  group_by(series, regime) %>%
  summarise(rmsfe = sqrt(mean(sqerror, na.rm = TRUE)), n = n(), .groups = "drop") %>%
  arrange(regime, series) %>% as.data.frame() %>% print(digits = 3)

message("\n", length(written), " figures written to ", out_dir)
