# Run from the repository root.

# PACKAGES AND FUNCTIONS --------------------------------------------------

library(dplyr)
library(tidyr)
library(tibble)
library(purrr)
library(readr)
library(ggplot2)
library(zoo)
library(readxl)

library(mfbdfm)

sample_config <- wai_sample_config(sample_id = "mcmc_stability",
                                    output_root = file.path("analysis", "outputs", "mcmc_stability"))
figures_dir <- sample_config$figures_dir
tables_dir <- sample_config$tables_dir


# SETTINGS ----------------------------------------------------------------

# The model uses a 48-period yearly grid. The closest supported end-of-2025
# evaluation point is 2025 + 47/48, i.e. the last weekly step in 2025.
test_date <- 2025 + 47 / 48
test_date_label <- "2025-12-31 (mapped to 2025 + 47/48 on the model grid)"
target <- "ch.seco.gdp.real.gdp.ssa"

# Reference run: treated as the benchmark posterior summary
reference_burn_in <- 1000
reference_length_sample <- 10000

# Candidate settings to compare against the reference run
grid_settings <- expand.grid(
  burn_in = c(50, 100, 250, 500, 1000),
  length_sample = c(250, 500, 1000, 2500, 5000),
  KEEP.OUT.ATTRS = FALSE
) %>%
  as_tibble() %>%
  arrange(burn_in, length_sample)

# Decision thresholds against the reference run
thresholds <- list(
  decision_max_rel_diff = 0.05,
  decision_median_rel_diff = 0.01,
  parameter_max_rel_diff = 0.10,
  parameter_median_rel_diff = 0.02
)


# HELPERS -----------------------------------------------------------------

extract_component_table <- function(mod, burn_in, length_sample, label) {
  parameter_table <- tibble(
    value = c(
      as.numeric(mod$pars$lambda),
      as.numeric(mod$pars$phi),
      as.numeric(mod$pars$omega),
      as.numeric(mod$pars$sigma),
      as.numeric(mod$pars$rho)
    ),
    variable = c(
      paste0("lambda_", colnames(mod$data)),
      paste0("phi", seq_along(mod$pars$phi)),
      "omega",
      paste0("sigma_", colnames(mod$data)),
      paste0("rho_", colnames(mod$data))
    ),
    family = "parameter"
  )

  latent_summary_table <- tibble(
    value = c(
      mean(mod$pars$h, na.rm = TRUE),
      sd(mod$pars$h, na.rm = TRUE),
      tail(mod$pars$h, 1),
      mean(mod$pars$sigma, na.rm = TRUE),
      max(mod$pars$sigma, na.rm = TRUE),
      mean(abs(mod$pars$rho), na.rm = TRUE),
      max(abs(mod$pars$rho), na.rm = TRUE)
    ),
    variable = c(
      "h_mean",
      "h_sd",
      "h_last",
      "sigma_mean",
      "sigma_max",
      "abs_rho_mean",
      "abs_rho_max"
    ),
    family = "latent_summary"
  )

  decision_table <- tibble(
    value = c(
      tail(mod$nowcast, 1),
      tail(mod$nowcast_var, 1),
      tail(mod$factor, 1),
      tail(mod$factor_var, 1),
      tail(mod$index, 1)
    ),
    variable = c(
      "nowcast_last",
      "nowcast_var_last",
      "factor_last",
      "factor_var_last",
      "index_last"
    ),
    family = "decision"
  )

  bind_rows(parameter_table, latent_summary_table, decision_table) %>%
    mutate(
      burn_in = burn_in,
      length_sample = length_sample,
      setting = label
    )
}


run_one_setting <- function(flows, stocks, burn_in, length_sample, target) {
  timing <- system.time({
    mod <- ind_dfm(
      flows = flows,
      stocks = stocks,
      target = target,
      burn_in = burn_in,
      length_sample = length_sample,
      thinning = 1,
      p = 1,
      q = 1,
      plots = FALSE,
      stochastic_volatility = TRUE,
      serial_correlation = TRUE
    )
  })

  list(
    mod = mod,
    timing_seconds = unname(timing["elapsed"]),
    components = extract_component_table(
      mod = mod,
      burn_in = burn_in,
      length_sample = length_sample,
      label = paste0("b", burn_in, "_s", length_sample)
    )
  )
}


compare_to_reference <- function(candidate_tab, reference_tab) {
  candidate_tab %>%
    left_join(
      reference_tab %>%
        select(variable, family, reference_value = value),
      by = c("variable", "family")
    ) %>%
    mutate(
      abs_diff = abs(value - reference_value),
      rel_diff = abs_diff / pmax(abs(reference_value), 1e-8)
    )
}


summarize_setting <- function(comparison_tab, timing_tab) {
  by_family <- comparison_tab %>%
    group_by(burn_in, length_sample, setting, family) %>%
    summarize(
      max_abs_diff = max(abs_diff, na.rm = TRUE),
      median_abs_diff = median(abs_diff, na.rm = TRUE),
      max_rel_diff = max(rel_diff, na.rm = TRUE),
      median_rel_diff = median(rel_diff, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    pivot_wider(
      names_from = family,
      values_from = c(max_abs_diff, median_abs_diff, max_rel_diff, median_rel_diff)
    )

  by_family %>%
    left_join(timing_tab, by = c("burn_in", "length_sample", "setting")) %>%
    mutate(
      passes_decision = max_rel_diff_decision <= thresholds$decision_max_rel_diff &
        median_rel_diff_decision <= thresholds$decision_median_rel_diff,
      passes_parameter = max_rel_diff_parameter <= thresholds$parameter_max_rel_diff &
        median_rel_diff_parameter <= thresholds$parameter_median_rel_diff,
      passes_all = passes_decision & passes_parameter
    ) %>%
    arrange(
      desc(passes_all),
      length_sample,
      burn_in
    )
}


build_recommendation <- function(summary_tab) {
  feasible <- summary_tab %>%
    filter(passes_all) %>%
    arrange(length_sample, burn_in, elapsed_seconds)

  if (nrow(feasible) > 0) {
    feasible %>%
      slice(1) %>%
      mutate(recommendation_reason = "Smallest candidate setting passing all stability thresholds.")
  } else {
    summary_tab %>%
      arrange(
        max_rel_diff_decision,
        median_rel_diff_decision,
        max_rel_diff_parameter,
        median_rel_diff_parameter,
        elapsed_seconds
      ) %>%
      slice(1) %>%
      mutate(recommendation_reason = "No candidate passed all thresholds; selected the closest candidate to the reference run.")
  }
}


plot_heatmap <- function(summary_tab, recommendation_tab, file_name) {
  plot_tab <- summary_tab %>%
    mutate(
      burn_in = factor(burn_in, levels = sort(unique(burn_in))),
      length_sample = factor(length_sample, levels = sort(unique(length_sample))),
      score = pmax(max_rel_diff_decision, max_rel_diff_parameter)
    )

  rec_key <- recommendation_tab %>%
    transmute(
      burn_in = factor(burn_in, levels = levels(plot_tab$burn_in)),
      length_sample = factor(length_sample, levels = levels(plot_tab$length_sample))
    )

  p <- ggplot(plot_tab, aes(x = length_sample, y = burn_in, fill = score)) +
    geom_tile(color = "white") +
    geom_text(aes(label = sprintf("%.3f", score)), size = 3) +
    geom_point(
      data = rec_key,
      aes(x = length_sample, y = burn_in),
      inherit.aes = FALSE,
      shape = 21,
      size = 5,
      stroke = 1.2,
      fill = NA,
      color = "black"
    ) +
    scale_fill_viridis_c(option = "C", direction = -1) +
    xlab("length_sample") +
    ylab("burn_in") +
    labs(fill = "Worst relative gap\nvs reference") +
    theme_minimal() +
    theme(
      legend.position = "right",
      text = element_text(size = 11),
      panel.grid = element_blank()
    )

  ggsave(file_name, plot = p, width = 18, height = 12, units = "cm")
}


plot_frontier <- function(summary_tab, recommendation_tab, file_name) {
  plot_tab <- summary_tab %>%
    mutate(score = pmax(max_rel_diff_decision, max_rel_diff_parameter))

  p <- ggplot(plot_tab, aes(x = elapsed_seconds, y = score, color = factor(burn_in))) +
    geom_point(size = 2.5) +
    geom_line() +
    geom_point(
      data = recommendation_tab,
      aes(x = elapsed_seconds, y = pmax(max_rel_diff_decision, max_rel_diff_parameter)),
      inherit.aes = FALSE,
      shape = 21,
      size = 4,
      stroke = 1.2,
      fill = "white",
      color = "black"
    ) +
    xlab("Elapsed seconds") +
    ylab("Worst relative gap vs reference") +
    labs(color = "burn_in") +
    theme_minimal() +
    theme(
      legend.position = "bottom",
      text = element_text(size = 11)
    )

  ggsave(file_name, plot = p, width = 18, height = 12, units = "cm")
}


# DATA --------------------------------------------------------------------

load("analysis/Rda/data_ch_dataset.Rda")

GDP_gr_vintages <- get_real_time_gdp_vintages("quarterly") %>%
  mutate(across(-time, ~ (1 + .x)^4 - 1))

dat_realtime <- cut_data_real_time(dat, test_date, GDP_gr_vintages)
dat_realtime$flows[[target]] <- na.trim(
  ts(
    select_most_recent_GDP_vintage(test_date, GDP_gr_vintages),
    start = c(1990, 1),
    frequency = 4
  )
)


# RUN TEST ----------------------------------------------------------------

message("Running reference setting for ", test_date_label)
reference_run <- run_one_setting(
  flows = dat_realtime$flows,
  stocks = dat_realtime$stocks,
  burn_in = reference_burn_in,
  length_sample = reference_length_sample,
  target = target
)

message("Running candidate settings")
candidate_runs <- pmap(
  grid_settings,
  function(burn_in, length_sample) {
    run_one_setting(
      flows = dat_realtime$flows,
      stocks = dat_realtime$stocks,
      burn_in = burn_in,
      length_sample = length_sample,
      target = target
    )
  }
)

reference_components <- reference_run$components
candidate_components <- bind_rows(lapply(candidate_runs, `[[`, "components"))

timing_summary <- tibble(
  burn_in = grid_settings$burn_in,
  length_sample = grid_settings$length_sample,
  setting = paste0("b", grid_settings$burn_in, "_s", grid_settings$length_sample),
  elapsed_seconds = sapply(candidate_runs, `[[`, "timing_seconds")
)

comparison_table <- compare_to_reference(
  candidate_tab = candidate_components,
  reference_tab = reference_components
)

stability_summary <- summarize_setting(
  comparison_tab = comparison_table,
  timing_tab = timing_summary
)

recommendation <- build_recommendation(stability_summary)


# SAVE OUTPUTS ------------------------------------------------------------

write_csv(reference_components, file.path(tables_dir, "reference_components.csv"))
write_csv(candidate_components, file.path(tables_dir, "candidate_components.csv"))
write_csv(comparison_table, file.path(tables_dir, "component_comparison.csv"))
write_csv(stability_summary, file.path(tables_dir, "stability_summary.csv"))
write_csv(recommendation, file.path(tables_dir, "recommendation.csv"))


# PLOTS -------------------------------------------------------------------

plot_heatmap(
  summary_tab = stability_summary,
  recommendation_tab = recommendation,
  file_name = file.path(figures_dir, "mcmc_stability_heatmap.png")
)

plot_frontier(
  summary_tab = stability_summary,
  recommendation_tab = recommendation,
  file_name = file.path(figures_dir, "mcmc_stability_frontier.png")
)


# OUTPUT ------------------------------------------------------------------

cat("\nMCMC stability test date: ", test_date_label, "\n", sep = "")
cat(
  "Reference setting: burn_in = ",
  reference_burn_in,
  ", length_sample = ",
  reference_length_sample,
  "\n",
  sep = ""
)

cat(
  "\nRecommended setting: burn_in = ",
  recommendation$burn_in,
  ", length_sample = ",
  recommendation$length_sample,
  "\n",
  sep = ""
)
cat("Reason: ", recommendation$recommendation_reason, "\n", sep = "")
cat(
  "Decision metrics: max_rel_diff = ",
  signif(recommendation$max_rel_diff_decision, 4),
  ", median_rel_diff = ",
  signif(recommendation$median_rel_diff_decision, 4),
  "\n",
  sep = ""
)
cat(
  "Parameter metrics: max_rel_diff = ",
  signif(recommendation$max_rel_diff_parameter, 4),
  ", median_rel_diff = ",
  signif(recommendation$median_rel_diff_parameter, 4),
  "\n",
  sep = ""
)
cat("Elapsed seconds: ", signif(recommendation$elapsed_seconds, 5), "\n", sep = "")

print(stability_summary)

message("Saved:")
message("  ", file.path(tables_dir, "reference_components.csv"))
message("  ", file.path(tables_dir, "candidate_components.csv"))
message("  ", file.path(tables_dir, "component_comparison.csv"))
message("  ", file.path(tables_dir, "stability_summary.csv"))
message("  ", file.path(tables_dir, "recommendation.csv"))
message("  ", file.path(figures_dir, "mcmc_stability_heatmap.png"))
message("  ", file.path(figures_dir, "mcmc_stability_frontier.png"))
