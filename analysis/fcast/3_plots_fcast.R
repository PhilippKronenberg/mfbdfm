# Run from the repository root.

# -----------------------------------------------------------------------------
# Multi-factor evaluation figures (Eckert et al. 2025)
# -----------------------------------------------------------------------------
# Reads the panel from 2_evaluation_fcast.R and the fits from
# 1_backcast_fcast.R, and writes the figure families to figures_dir.
#
# ONE script rather than the five now in analysis/fcast/archive/, by the
# collapse decision on #53.
# Measured overlap of the originals, on non-blank non-comment lines:
#
#   plots_nowcast_scores_IC.R    1 unique line of 288   (0%)
#   plots_nowcast_IC.R          14 unique lines of 304  (5%)
#   plots_nowcast.R             45 unique lines of 318  (14%)
#
# Three files that are ~90% the same script with a switch flipped. They are the
# variant, not the figure - so the variant is an argument here and the shared
# work happens once.
#
# Figures are skipped, with a message, when the panel cannot support them
# (e.g. no out-of-sample rows yet). A quick_check run legitimately produces
# almost none of them; that is not a failure.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")


# LOAD THE PANEL ----------------------------------------------------------

panel_path <- file.path(results_dir, "fcast_evaluation_tab.Rda")
if (!file.exists(panel_path)) {
  stop("No evaluation panel at ", panel_path, ".\n",
       "  Run analysis/fcast/1_backcast_fcast.R then ",
       "analysis/fcast/2_evaluation_fcast.R first.", call. = FALSE)
}
e <- new.env(); load(panel_path, envir = e)
tab <- e$tab

# tolerate a panel written before in_window existed
if (!"in_window" %in% names(tab)) tab$in_window <- tab$horizon %in% 1:12

# Group and colour by `series`, not by `dataset`. These figures compare MODELS;
# they used `dataset` and got away with it only because the sweep's fit
# directories (q2/, bmdfm_q2/) made dataset and model collinear, so the two
# models happened to land in separate "datasets". Once 2_evaluation_fcast.R
# stopped conflating them - it had to, or the Diebold-Mariano loop pairs nothing
# - colouring by dataset would have drawn both models in one colour, silently.
#
# `series` is the model on its own when there is a single dataset, and
# dataset x model when there is more than one, so both the sweep's shape and the
# paper's (three datasets x four models) read correctly.
add_series <- function(d) {
  if (length(unique(d$dataset)) > 1) {
    dplyr::mutate(d, series = paste(dataset, model))
  } else {
    dplyr::mutate(d, series = model)
  }
}
tab <- add_series(tab)

oos <- tab %>% filter(!in_sample, !is.na(realization))
message("panel: ", nrow(tab), " rows, ", nrow(oos), " out-of-sample, ",
        length(unique(tab$dataset)), " dataset(s), ",
        length(unique(tab$series)), " series: ",
        paste(sort(unique(tab$series)), collapse = ", "))


# HELPERS -----------------------------------------------------------------

# Every figure goes through this, so the skip-and-say-why behaviour is uniform
# rather than repeated per plot.
emit <- function(name, data, build, width = 20, height = 14) {

  if (is.null(data) || !nrow(data)) {
    message("  skip ", name, ": no rows to plot")
    return(invisible(NULL))
  }

  p <- build(data)
  path <- output_figure_path(paste0(name, ".pdf"), figures_dir)
  ggsave(path, p, width = width, height = height, units = "cm")
  message("  wrote ", path)
  invisible(path)

}

theme_fcast <- function() {
  theme_minimal(base_size = 10) +
    theme(panel.grid.minor = element_blank(),
          legend.position = "bottom",
          legend.title = element_blank())
}


# 1. NOWCAST PATH ---------------------------------------------------------
# The nowcast for each target period against what was realised. The core
# figure of plots_nowcast.R / plots_nowcast_multifactor.R.

emit("nowcast_vs_realisation", oos, function(d) {
  d %>%
    ggplot(aes(x = period)) +
    geom_ribbon(aes(ymin = value - 1.96 * sd, ymax = value + 1.96 * sd),
                alpha = 0.2, fill = "steelblue") +
    geom_line(aes(y = value, colour = "nowcast")) +
    geom_point(aes(y = realization, colour = "realised"), size = 1) +
    facet_wrap(~series) +
    scale_colour_manual(values = c(nowcast = "steelblue", realised = "black")) +
    labs(x = NULL, y = "GDP growth", title = "Nowcast vs realisation") +
    theme_fcast()
})


# 2. ERROR BY HORIZON -----------------------------------------------------
# RMSE against the number of weeks before publication - the shape the paper
# uses to show information accumulating as the quarter progresses.

by_h <- oos %>%
  group_by(series, horizon) %>%
  summarise(rmse = sqrt(mean(sqerror, na.rm = TRUE)),
            mae = mean(abs(error), na.rm = TRUE),
            logs = mean(logs, na.rm = TRUE),
            n = n(), .groups = "drop")

emit("rmse_by_horizon", by_h, function(d) {
  d %>%
    ggplot(aes(x = horizon, y = rmse, colour = series)) +
    geom_line() + geom_point(size = 1) +
    scale_x_reverse() +          # count down to publication
    labs(x = "weeks before GDP publication", y = "RMSE",
         title = "Nowcast accuracy by horizon") +
    theme_fcast()
})

emit("logscore_by_horizon", by_h, function(d) {
  d %>%
    ggplot(aes(x = horizon, y = logs, colour = series)) +
    geom_line() + geom_point(size = 1) +
    scale_x_reverse() +
    labs(x = "weeks before GDP publication",
         y = "mean log score (lower is better)",
         title = "Predictive density by horizon") +
    theme_fcast()
})


# 3. CRISIS VS NORMAL -----------------------------------------------------
# plots_nowcast_scores.R's crisis/normal split, using the package's own
# is_crisis_period() rather than re-hardcoding the date ranges.

# Form follows the paper's own figures (analysis/fcast/reference/figures/
# RMSFE_CrisisAndNormal_*.pdf): faceted "Crisis Periods" / "Non-Crisis Periods",
# horizon counted DOWN to publication on the x axis, and - the part that carries
# the comparison - a second panel of log-ratios against a benchmark, with a
# reference line at zero so "below the line is better" reads directly.
# is_crisis_period_fcast(), NOT is_crisis_period(). The two are different
# definitions and are not interchangeable: this one classifies the target
# QUARTER and covers four episodes, the other classifies the nowcast DATE and
# covers two. On the paper's own panel they agree on only 124 of its 240 crisis
# rows, and using the wrong one puts crisis RMSFE for the monthly benchmark at
# 0.0262 instead of the 0.0210 the paper plots. See ?is_crisis_period_fcast.
crisis <- oos %>% filter(in_window)
if (nrow(crisis)) {
  crisis$regime <- ifelse(is_crisis_period_fcast(crisis$period),
                          "Crisis Periods", "Non-Crisis Periods")
}

rmse_regime <- if (nrow(crisis)) {
  crisis %>%
    group_by(series, regime, horizon) %>%
    summarise(rmse = sqrt(mean(sqerror, na.rm = TRUE)), .groups = "drop")
} else crisis

emit("rmse_crisis_vs_normal", rmse_regime, function(d) {
  d %>%
    ggplot(aes(x = horizon, y = rmse, colour = series)) +
    geom_line() + geom_point(size = 0.9) +
    facet_wrap(~regime) +
    scale_x_reverse(breaks = seq(12, 2, by = -2)) +
    labs(x = "Nowcast Horizon (in Weeks)", y = "RMSFE") +
    theme_fcast()
})

# The log-ratio panel: this is the WAIVSBMDFM comparison, so the denominator is
# the BENCHMARK SERIES, not a dataset. Keyed on dataset it produced nothing once
# dataset stopped standing in for model - there was then only one dataset and the
# panel skipped itself. Same benchmark rule as 5_error_tables_fcast.R, so the
# figure and the table answer the same question.
baseline_series <- if ("ar" %in% rmse_regime$series) "ar" else
  sort(unique(rmse_regime$series))[1]

rmse_ratio <- if (nrow(rmse_regime) &&
                  length(unique(rmse_regime$series)) > 1) {
  base <- rmse_regime %>%
    filter(series == baseline_series) %>%
    select(regime, horizon, rmse_base = rmse)
  rmse_regime %>%
    filter(series != baseline_series) %>%
    inner_join(base, by = c("regime", "horizon")) %>%
    mutate(log_ratio = log(rmse / rmse_base))
} else {
  rmse_regime[0, ]
}

emit("rmse_log_ratio_crisis_vs_normal", rmse_ratio, function(d) {
  d %>%
    ggplot(aes(x = horizon, y = log_ratio, colour = series)) +
    geom_hline(yintercept = 0, colour = "grey40") +
    geom_line() + geom_point(size = 0.9) +
    facet_wrap(~regime) +
    scale_x_reverse(breaks = seq(12, 2, by = -2)) +
    labs(x = "Nowcast Horizon (in Weeks)",
         y = paste0("RMSFE log-ratio vs ", baseline_series)) +
    theme_fcast()
})


# 4. FACTORS --------------------------------------------------------------
# factor_plot.R's figure, read from the fits rather than the panel - the
# factors are not in the evaluation table.

factor_frame <- function(fit_root) {

  if (!dir.exists(fit_root)) return(NULL)
  out <- list()

  for (dx in list.dirs(fit_root, full.names = FALSE, recursive = FALSE)) {
    files <- list.files(file.path(fit_root, dx), pattern = "^fit_.*\\.Rda$",
                        full.names = TRUE)
    if (!length(files)) next
    # the latest vintage is the one to plot
    f <- files[which.max(as.numeric(sub("^fit_(.*)\\.Rda$", "\\1",
                                        basename(files))))]
    en <- new.env(); load(f, envir = en)
    # [["factor", exact = TRUE]] and NOT $factor. The BMDFM benchmark writes the
    # vendored nowcast() object, which has no `factor` but does have `factors` -
    # and `$` partial-matches, so `mod$factor` silently returns that list of
    # eigen/dynamic-factor objects instead of NULL. An is.null() guard therefore
    # does not catch it; the failure surfaces later as time() on a list.
    # A fit tree holding both models is the normal case whenever run_benchmark
    # is TRUE, and before the first sweep completed this loop had only ever seen
    # fcast_dfm fits.
    fac <- en$mod[["factor", exact = TRUE]]
    if (is.null(fac)) next
    out[[length(out) + 1]] <- tibble(
      dataset = dx,
      time = rep(as.numeric(time(fac)), ncol(fac)),
      factor = rep(paste0("factor ", seq_len(ncol(fac))), each = nrow(fac)),
      value = as.numeric(fac))
  }

  if (!length(out)) NULL else bind_rows(out)

}

emit("factors", factor_frame(fcast_fit_root), function(d) {
  d %>%
    ggplot(aes(x = time, y = value, colour = factor)) +
    geom_line(linewidth = 0.3) +
    facet_grid(rows = vars(dataset)) +
    labs(x = NULL, y = NULL, title = "Estimated factors") +
    theme_fcast()
}, height = 18)


message("figures written to ", figures_dir)
