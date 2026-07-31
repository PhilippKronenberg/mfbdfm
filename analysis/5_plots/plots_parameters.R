
# Run from the repository root.

# PACKAGES AND FUNCTIONS --------------------------------------------------

library(dplyr)
library(ggplot2)
library(mfbdfm)
source("analysis/5_plots/_setup.R")  # figures_dir / tables_dir / results_dir

# Real-time vintage fits, from the shared config rather than a literal - it
# already knows where they live, and the previous hard-coded "fits/wai/full"
# had not existed since the fits/updated/ reorganisation (#59).
fit_dir <- sample_config$fit_rt_dir


# PRELIM ------------------------------------------------------------------

if (!dir.exists(fit_dir)) {
  stop("No fit directory at ", fit_dir, ".\n",
       "  These plots need the real-time vintage fits produced by ",
       "analysis/real_time_backcast.R.", call. = FALSE)
}

fit_files <- list.files(fit_dir, pattern = "^fit_.*\\.Rda$", full.names = TRUE)
if (!length(fit_files)) {
  stop("No fit_*.Rda files in ", fit_dir, ".", call. = FALSE)
}

available <- round(as.numeric(sub("^fit_(.*)\\.Rda$", "\\1",
                                  basename(fit_files))), 3)

# Take the range from what is actually on disk. The previous fixed window
# (2000 to 2021.5) matched neither end of the current set, so every iteration
# failed on a missing file - and it failed inside lapply() with a bare
# "cannot open file", naming nothing useful.
start_date <- min(available)
end_date <- max(available)
date_vec <- round(seq(start_date, end_date, 1/48), 3)

missing <- setdiff(date_vec, available)
date_vec <- intersect(date_vec, available)

message("parameter paths from ", length(date_vec), " vintages in ", fit_dir,
        " (", start_date, " to ", end_date, ")")
if (length(missing)) {
  message("  ", length(missing), " vintage(s) in that range have no fit and are ",
          "skipped, e.g. ", paste(utils::head(missing, 3), collapse = ", "))
}


# GATHER FORECASTS -----------------------------------------------------

# GATHER STORED FILES TO LIST
out_tx <- lapply(date_vec, function(xt){

  e <- new.env()
  load(file.path(fit_dir, paste0("fit_", xt, ".Rda")), envir = e)
  mod <- e$mod

  data.frame("values" = c(as.numeric(mod$pars$lambda),
                          as.numeric(mod$pars$phi),
                          as.numeric(mod$pars$omega),
                          as.numeric(mod$pars$sigma),
                          as.numeric(mod$pars$rho)),
             "variable" = c(paste0("lambda_",colnames(mod$data)),
                            paste0("phi",1:length(mod$pars$phi)),
                            paste0("omega"),
                            paste0("sigma_",colnames(mod$data)),
                            paste0("rho_",colnames(mod$data))),
             "time" = xt)

})

out <- do.call(rbind,out_tx)

# PLOT CERTAIN PARAMETERS -------------------------------------------------

# sigma
tab <- out %>% filter(grepl("sigma",out$variable))

ggplot(data = tab, mapping = aes(x = time, y = values, group = variable, color = variable)) +
  geom_line(show.legend = F) +
  # labs(title = "Error Variances of the Dynamic Factor Measurement Equation (Real-Time Recursive Estimates)") +
  xlab(NULL) + 
  ylab(NULL) + 
  theme_minimal() + 
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(linewidth = 0.2),
        panel.grid.major.y = element_line(linewidth = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_sigma.png"),width = 20, height = 8, units = "cm")

# rho
tab <- out %>% filter(grepl("rho",out$variable))
outliers <- tab %>%
  group_by(variable) %>%
  summarize(value = round(var(values, na.rm=T),2))
# Drop the most volatile series, but via a positive filter rather than
# `tab[-which(...), ]`: when nothing exceeds the threshold, which() is
# integer(0) and `tab[-integer(0), ]` returns ZERO rows, silently emptying the
# plot instead of keeping everything.
drop_vars <- outliers$variable[outliers$value > 0.05]
tab <- tab %>% filter(!variable %in% drop_vars)

ggplot(data = tab, mapping = aes(x = time, y = values, group = variable, color = variable)) +
  geom_line(show.legend = F) +
  # labs(title = "Serial Correlation Coefficients of Errors in Dynamic Factor Measurement Equation (Real-Time Recursive Estimates)") +
  xlab(NULL) + 
  ylab(NULL) + 
  theme_minimal() + 
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(linewidth = 0.2),
        panel.grid.major.y = element_line(linewidth = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_rho.png"),width = 20, height = 8, units = "cm")

# lambda
tab <- out %>% filter(grepl("lambda",out$variable))

ggplot(data = tab, mapping = aes(x = time, y = values, group = variable, color = variable)) +
  geom_line(show.legend = F) +
  # labs(title = "Factor Loadings in Dynamic Factor Measurement Equation (Real-Time Recursive Estimates)") +
  xlab(NULL) + 
  ylab(NULL) + 
  theme_minimal() + 
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(linewidth = 0.2),
        panel.grid.major.y = element_line(linewidth = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_lambda.png"),width = 20, height = 8, units = "cm")

# omega
tab <- out %>% filter(grepl("omega",out$variable))

ggplot(data = tab, mapping = aes(x = time, y = values, group = variable, color = variable)) +
  geom_line(show.legend = F) +
  # labs(title = "Variance of Stochastic Volatility State Equation (Real-Time Recursive Estimates)") +
  xlab(NULL) + 
  ylab(NULL) + 
  theme_minimal() + 
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(linewidth = 0.2),
        panel.grid.major.y = element_line(linewidth = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_omega.png"),width = 20, height = 8, units = "cm")

# phi
tab <- out %>% filter(grepl("phi",out$variable))

ggplot(data = tab, mapping = aes(x = time, y = values, group = variable, color = variable)) +
  geom_line(show.legend = F) +
  # labs(title = "Autoregressive Coefficient in Dynamic Factor State Equation (Real-Time Recursive Estimate)") +
  xlab(NULL) +
  ylab(NULL) +
  # No hard-coded y limits. They used to be c(0.7, 0.82), which no longer
  # contains the data: phi runs about 0.86-0.90 across the current vintages, so
  # ggplot dropped all 1007 rows and wrote an empty figure with only a warning.
  # The default scale already zooms to the data range, which is what the fixed
  # window was for.
  theme_minimal() +
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(linewidth = 0.2),
        panel.grid.major.y = element_line(linewidth = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_phi.png"),width = 20, height = 8, units = "cm")
