# Run from the repository root.

# -----------------------------------------------------------------------------
# Multi-factor evaluation figures (Eckert et al. 2025)
# -----------------------------------------------------------------------------
# Reads the panel from 2_evaluation_fcast.R and the fits from
# 1_backcast_fcast.R, and writes the figure families to figures_dir.
#
# ONE script rather than the five in old_code_fcast_dfm/, by decision on #53.
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

oos <- tab %>% filter(!in_sample, !is.na(realization))
message("panel: ", nrow(tab), " rows, ", nrow(oos), " out-of-sample, ",
        length(unique(tab$dataset)), " dataset(s)")


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
    facet_wrap(~dataset) +
    scale_colour_manual(values = c(nowcast = "steelblue", realised = "black")) +
    labs(x = NULL, y = "GDP growth", title = "Nowcast vs realisation") +
    theme_fcast()
})


# 2. ERROR BY HORIZON -----------------------------------------------------
# RMSE against the number of weeks before publication - the shape the paper
# uses to show information accumulating as the quarter progresses.

by_h <- oos %>%
  group_by(dataset, horizon) %>%
  summarise(rmse = sqrt(mean(sqerror, na.rm = TRUE)),
            mae = mean(abs(error), na.rm = TRUE),
            logs = mean(logs, na.rm = TRUE),
            n = n(), .groups = "drop")

emit("rmse_by_horizon", by_h, function(d) {
  d %>%
    ggplot(aes(x = horizon, y = rmse, colour = dataset)) +
    geom_line() + geom_point(size = 1) +
    scale_x_reverse() +          # count down to publication
    labs(x = "weeks before GDP publication", y = "RMSE",
         title = "Nowcast accuracy by horizon") +
    theme_fcast()
})

emit("logscore_by_horizon", by_h, function(d) {
  d %>%
    ggplot(aes(x = horizon, y = logs, colour = dataset)) +
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

crisis <- oos
if (nrow(crisis)) {
  crisis$regime <- ifelse(is_crisis_period(dec2week(crisis$date)),
                          "crisis", "normal")
}

emit("rmse_crisis_vs_normal",
     if (nrow(crisis)) {
       crisis %>%
         group_by(dataset, regime, horizon) %>%
         summarise(rmse = sqrt(mean(sqerror, na.rm = TRUE)),
                   .groups = "drop")
     } else crisis,
     function(d) {
       d %>%
         ggplot(aes(x = horizon, y = rmse, colour = dataset)) +
         geom_line() +
         facet_wrap(~regime) +
         scale_x_reverse() +
         labs(x = "weeks before GDP publication", y = "RMSE",
              title = "Accuracy in crisis and normal periods") +
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
    fac <- en$mod$factor
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
