# Run from the repository root.

# -----------------------------------------------------------------------------
# plots_measures.R - tables and figures for the fit-level measures
# -----------------------------------------------------------------------------
# Per-series R-squared (#99), factor loadings and parameter tables (#113),
# contributions of each series to the factor and the nowcast (#109), MCMC
# convergence diagnostics (#110) and the standardised fit plots (#112), all
# from ONE fit: the latest-vintage baseline.
#
# Why that fit and not fits/updated/full_RT/: the full_RT fits restored from
# refs/pull/29/head (#102) predate the hfdfm -> ind_dfm rename and #110, so
# they are class `hfdfm` without posterior draws, and every function used here
# rejects them. fits/updated/full/fit_2025.979.Rda was fitted with current code
# (analysis/2_backcast.R settings, default chain). A measure tracked ACROSS
# vintages would need full_RT refitted with current code first.
#
# Section 5 adds the news decomposition (#101) of the move from this fit's
# vintage to the next weekly one.
# -----------------------------------------------------------------------------

source(file.path("analysis", "5_plots", "_setup.R"))

fit_file <- file.path(sample_config$fit_root, "updated", "full", "fit_2025.979.Rda")
if (!file.exists(fit_file)) {
  stop("No fit at ", fit_file, ".\n",
       "  It is produced by analysis/2_backcast.R (variant `full`, date 2025 + 47/48).",
       call. = FALSE)
}
e <- new.env()
load(fit_file, envir = e)          # the fit files save their object as `mod`
fit <- e$mod
if (!inherits(fit, "ind_dfm")) {
  stop(fit_file, " holds a `", class(fit)[1], "`, not an `ind_dfm` fit; ",
       "refit it with the current package.", call. = FALSE)
}

# Readable names and categories from data-raw/data_meta.csv (the source of the
# README data dictionary), keyed like the fit's inventory. A series it lacks
# keeps its key as name and goes into an "Other" category.
meta <- utils::read.csv(file.path("data-raw", "data_meta.csv"), stringsAsFactors = FALSE)
keys <- fit$inventory$key
series_name <- stats::setNames(ifelse(keys %in% meta$keys, meta$Name[match(keys, meta$keys)], keys), keys)
series_group <- stats::setNames(ifelse(keys %in% meta$keys, meta$Category[match(keys, meta$keys)], "Other"), keys)
# GDP is the anchor (its loading is fixed to 1), so in-sample it IS the factor and
# the nowcast. Kept in its own group so it does not hide inside "Production".
series_group["ch.seco.gdp.real.gdp.ssa"] <- "GDP (target)"

save_plot <- function(p, name, width = 20, height = 15) {
  ggsave(output_figure_path(name, figures_dir), p, width = width, height = height, units = "cm")
}

# The contributions and diagnostics plot() methods draw with base graphics and
# return their input invisibly, so they cannot go through ggsave().
save_base_plot <- function(draw, name, width = 30, height = 15) {
  grDevices::pdf(output_figure_path(name, figures_dir), width = width / 2.54, height = height / 2.54)
  on.exit(grDevices::dev.off())
  draw()
}


# 1. Per-series R-squared (#99) ------------------------------------------------
rsq <- summary(fit)$r_squared
rsq <- data.frame(Series = series_name[rsq$series], Category = series_group[rsq$series],
                  Frequency = rsq$freq, Observations = rsq$n_obs, R2 = rsq$r_squared,
                  row.names = NULL)
rsq <- rsq[order(-rsq$R2), ]
write_table_output("table_measures_r2.tex",
                   mfbdfm_kable(rsq, format = "latex", digits = 3,
                                caption = "Per-series R-squared of the baseline fit"),
                   tables_dir)

p_rsq <- ggplot(transform(rsq, Series = factor(Series, levels = rev(Series))),
                aes(x = R2, y = Series, fill = Category)) +
  geom_col() +
  scale_x_continuous(limits = c(0, 1), expand = expansion(mult = c(0, 0.03))) +
  labs(x = "R-squared", y = NULL, fill = NULL) +
  theme_minimal() +
  theme(legend.position = "bottom")
save_plot(p_rsq, "measures_r2.pdf", height = 4 + 0.45 * nrow(rsq))


# 2. Factor loadings and parameters (#113) -------------------------------------
write_table_output("table_measures_loadings.tex",
                   mfbdfm_table_loadings(fit, format = "latex", digits = 3,
                                         caption = "Factor loadings of the baseline fit"),
                   tables_dir)
write_table_output("table_measures_parameters.tex",
                   mfbdfm_table_parameters(fit, format = "latex", digits = 3,
                                           caption = "Posterior parameter summary of the baseline fit"),
                   tables_dir)
save_plot(plot(fit, type = "loadings"), "measures_loadings.pdf",
          height = 4 + 0.45 * nrow(fit$inventory))


# 3. Contributions to the factor and the nowcast (#109) ------------------------
# Grouped by data_meta.csv's Category: 46 series in one stacked chart is not
# readable. The per-series decomposition is still written out in full as CSV.
contrib_group <- mfbdfm_contributions(fit, by = "group", groups = series_group)
save_base_plot(function() plot(contrib_group, what = "factor"),  "measures_contributions_factor.pdf")
save_base_plot(function() plot(contrib_group, what = "nowcast"), "measures_contributions_nowcast.pdf")

contrib_series <- as.data.frame(mfbdfm_contributions(fit, by = "series"))
contrib_series$name <- series_name[contrib_series$series]
utils::write.csv(contrib_series, file.path(tables_dir, "table_measures_contributions_series.csv"),
                 row.names = FALSE)
utils::write.csv(as.data.frame(contrib_group),
                 file.path(tables_dir, "table_measures_contributions_group.csv"), row.names = FALSE)


# 4. Fit views (#112) and convergence diagnostics (#110) -----------------------
for (ty in c("factor", "nowcast", "fit", "residuals", "volatility")) {
  save_plot(plot(fit, type = ty), paste0("measures_fit_", ty, ".pdf"), width = 30)
}

diag <- mfbdfm_diagnostics(fit)
write_table_output("table_measures_diagnostics.tex",
                   mfbdfm_kable(as.data.frame(diag), format = "latex", digits = 3,
                                caption = "MCMC convergence diagnostics of the baseline fit"),
                   tables_dir)
save_base_plot(function() plot(diag), "measures_diagnostics.pdf", width = 25, height = 20)

# 5. News: what the next week's releases did to the nowcast (#101) ------------
# The fit is the OLD vintage. The new one is the same data, prepared exactly as
# analysis/2_backcast.R prepared the fit's own (same GDP vintage, same cap), cut
# one week later - so the difference between them is one week of releases.
# Parameters are held at the fit's (no `new_fit`), so the `parameter` term is
# NA and the impacts add up to the revision exactly.
target <- "ch.seco.gdp.real.gdp.ssa"
load("analysis/Rda/data_ch_dataset_test.Rda")   # provides `dat`
dat <- cut_data(dat, current_date = 2026)
gdp_vintages <- get_real_time_gdp_vintages("quarterly")
gdp_vintage <- get_latest_numeric_vintage(
  gdp_vintages, lower_bound = 2005.438,
  upper_bound = round(decimal_date_local(as.Date("2026-03-07")), 3))
dat$flows[[target]] <- zoo::na.trim(
  stats::ts(gdp_vintages[[as.character(gdp_vintage)]], start = c(1990, 1), frequency = 4))

fit_date <- 2025 + 47/48               # the exact grid point fit_2025.979 names (#157)
new_vintage <- cut_data(dat, fit_date + 1/48)

news <- mfbdfm_news(fit, new_data = new_vintage$flows, stocks = new_vintage$stocks,
                    by = "group", groups = series_group)
print(news)

news_obs <- as.data.frame(news, what = "observation")
news_obs$name <- unname(series_name[news_obs$series])
utils::write.csv(news_obs, file.path(tables_dir, "table_measures_news_observations.csv"),
                 row.names = FALSE)
news_grp <- as.data.frame(news, what = "component")
write_table_output("table_measures_news.tex",
                   mfbdfm_kable(news_grp, format = "latex", digits = 4,
                                caption = "News decomposition of the nowcast revision, one weekly vintage"),
                   tables_dir)
save_base_plot(function() plot(news), "measures_news.pdf", width = 25, height = 15)

message("plots_measures.R: tables in ", tables_dir, ", figures in ", figures_dir)
