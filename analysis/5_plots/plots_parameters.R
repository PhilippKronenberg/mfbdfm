
# Run from the repository root.

# PACKAGES AND FUNCTIONS --------------------------------------------------

library(dplyr)
library(ggplot2)
library(mfbdfm)
source("analysis/5_plots/_setup.R")  # figures_dir / tables_dir / results_dir

fit_root <- "fits"  # root of the model fits (git-ignored)

# PRELIM ------------------------------------------------------------------

start_date <- 2000
end_date <- 2021 + 24/48 
date_vec <- seq(start_date, end_date, 1/48)


# GATHER FORECASTS -----------------------------------------------------

# GATHER STORED FILES TO LIST
out_tx <- lapply(date_vec, function(xt){
  
  load(file.path(fit_root, "wai", "full", paste0("fit_", round(xt,3), ".Rda")))
  
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
             "time" = round(xt,3))
  
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
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_sigma.png"),width = 20, height = 8, units = "cm")

# rho
tab <- out %>% filter(grepl("rho",out$variable))
outliers <- tab %>% 
  group_by(variable) %>% 
  summarize(value = round(var(values, na.rm=T),2))
tab <- tab[-which(tab$variable %in% outliers$variable[which(outliers$value > 0.05)]),]

ggplot(data = tab, mapping = aes(x = time, y = values, group = variable, color = variable)) +
  geom_line(show.legend = F) +
  # labs(title = "Serial Correlation Coefficients of Errors in Dynamic Factor Measurement Equation (Real-Time Recursive Estimates)") +
  xlab(NULL) + 
  ylab(NULL) + 
  theme_minimal() + 
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
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
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
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
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
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
  scale_y_continuous(limits = c(0.7,0.82)) +
  theme_minimal() + 
  theme(legend.position = "bottom",
        text = element_text(size = 11),
        legend.text = element_text(size = 10),
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank())

ggsave(file.path(figures_dir, "pars_stability_phi.png"),width = 20, height = 8, units = "cm")
