
# Run from the repository root.

library(zoo)
library(tibble)
library(tidyr)
library(ggplot2)
library(reshape2)
library(dplyr)
library(scales)
library(ggpubr)
library(pammtools)
library(ggsci)
library(RColorBrewer)
 
library(mfbdfm)
source("analysis/5_plots/_setup.R")  # figures_dir / tables_dir / results_dir

fit_root <- "fits/updated"  # root of the model fits (git-ignored)


# SETTINGS -------------------------------------------------------------

# Plot settings
PlotOptions = list(
  geom_line(),
  theme_minimal(),
  theme(panel.spacing=unit(3, "lines")),
  scale_color_npg(),
  scale_color_brewer(palette = "Blues"),
  guides(col = guide_legend(ncol = 1)),
  theme(plot.title = element_blank(), 
        legend.position = "bottom",
        text = element_text(size = 12),
        legend.title=element_blank(),
        axis.text.y = element_text(size = 12),
        axis.text.x = element_text(size = 12),
        axis.title.x.bottom = element_text(size = 12),
        legend.text=element_text(size=12),
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank()))

my.cols <- c(brewer.pal(9, "Blues"))
my.cols[1] <- "#000000"


# 2. GATHER VINTAGES -----------------------------------------------------

datasets <- list("full_RT") #list("full", "aggr_weekly", "only_monthly")
start_date <- 2005
end_date <- 2025 + 47/48
date_vec <- seq(start_date, end_date, 1/48)

wd <- getwd()
dataset_used <- "full_RT"

# gather stored output
out <- lapply(datasets, function(xd){
  out_tx <- lapply(date_vec, function(xt){
    
    
    load(file.path(fit_root, dataset_used, paste0("fit_", round(xt,3), ".Rda")))

    ryear <- floor(time(mod$factor))
    rmon <- as.numeric(format(as.yearmon(time(mod$factor)), "%m"))
    if (xd == "full_RT"){
      rday <-  (round((time(mod$factor) %% 1) * frequency(mod$factor)) %% 4 + 1) * 7}
    else {
      rday <- rep(28,length(mod$factor))
    }
    
    res <- zoo(x = cbind(mod$factor,
                         mod$factor + 1.96 * sqrt(mod$factor_var),
                         mod$factor - 1.96 * sqrt(mod$factor_var)),
               order.by = as.Date(paste0(ryear,"-",sprintf("%02d", rmon),"-",sprintf("%02d", rday)), format = "%Y-%m-%d"))
    
    tab <- data.frame("mean" = as.numeric(res[,1]),
                      "max" = as.numeric(res[,2]),
                      "min" = as.numeric(res[,3]),
                      "time" = time(res))
    tab <- tab %>% pivot_longer(-c(time,min,max))
    
    return(tab)
    
  }); names(out_tx) <- as.character(round(date_vec,3)); out_tx
}); names(out) <- datasets

tab <- do.call(rbind, lapply(names(out), function(dx) do.call(rbind, lapply(names(out[[dx]]), function(mx){
  
  out_df <- out[[dx]][[mx]] %>%
    add_column("vint" = mx) %>%
    add_column("method" = dx)
  
  return(out_df)
  
}))))

tab$periods <- plyr::round_any(x = as.numeric(format(tab$time, "%Y")) +
                                 (as.numeric(format(tab$time, "%m"))-1)/12 +
                                 as.numeric(format(tab$time, "%d"))/365,
                               accuracy = 1/48,
                               f = floor)

# save list for further processing
save(tab, date_vec, file = "analysis/Rda/factor_vintages_updated.Rda")
#save(tab, date_vec, file = "analysis/Rda/factor_vintages.Rda")
#save(tab, date_vec, file = "analysis/Rda/factor_vintages_fits_20210126.Rda")

# TRANSFORM RESULTS FROM BACKCAST TO TABLE ---------------------------------------------------------------

#load("analysis/Rda/factor_vintages_fits_20210126.Rda")
#load("analysis/Rda/factor_vintages.Rda")
load("analysis/Rda/factor_vintages_updated.Rda")
tab2 <- tab[which(tab$method == "full_RT"),] # Choose Method



## Figure 5: Real-Time Version of the Weekly GDP Indicator During the Corona Crisis --------

# Real-time factor vs final factor during Corona
startdate <- "2020-01-07"
enddate <- "2022-12-31"
startperiod <- 2020
endperiod <-  max(tab$periods)

tab3 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_full <- tab[which(tab$vint == last(tab$vint) & tab$periods >= startperiod & tab$periods <= endperiod & tab$method == "full"),]

# plot only most recent months (insample vs. realtime vintage)
ggplot() +
  PlotOptions +
  geom_hline(yintercept=0, col = "grey50") +
  scale_y_continuous(breaks = seq(-80,160,40)) +
  geom_ribbon(data = tab3, aes(x = time, ymin = min, ymax = max),
              color = NA, fill = my.cols[5], alpha = 0.25) +
  geom_ribbon(data = tab_full, aes(x = time, ymin = min, ymax = max),
              color = NA, fill = my.cols[9], alpha = 0.25) +
  geom_line(data = tab3, mapping = aes(x = time, y = value, color = "Real-Time Version of Weekly GDP Indicator")) +
  geom_line(data = tab_full, mapping = aes(x = time, y = value, color = "Weekly GDP Indicator Based on Latest Vintage")) +
  xlab(NULL) + 
  scale_color_manual(values = c(my.cols[c(5,9)]),
                     labels = c("Real-Time Version of Weekly GDP Indicator","Weekly GDP Indicator Based on Latest Vintage")) +
  #ylab("Wöchentliches BIP-Wachstum (in %, annualisiert)") +
  ylab("Weekly GDP Growth (in %, annualized)") + 
  theme(legend.justification=c(0,0), 
        legend.position=c(0.4,0.1), 
        plot.margin = unit(c(1,1.1,1,1), "cm"),
        legend.text = element_text(size = 12)) +
  #scale_y_continuous(limits = c(-120,+100), expand = expansion(mult = c(0.3,0))) +
  scale_x_date(limits = as.Date(c(startdate, enddate)), breaks = date_breaks("2 months"), labels = date_format("%b-%y"))
  
ggsave(file.path(figures_dir, "first_vs_final_vintage_corona.pdf"),width = 20, height = 15, units = "cm")


# 
# # Figure 6: Real-Time Version of the GDP indicator for Different D --------
# 
# # Real-time factor during Corona for all model types
# 
# startperiod <- 2020
# endperiod <-  max(tab$periods)
# 
# tab_rt_full <- tab[which((tab$periods - as.numeric(tab$vint)) >= -0.022 & (tab$periods - as.numeric(tab$vint)) <= -0.020 & tab$periods >= startperiod & tab$periods <= endperiod & tab$method == "full"),]
# tab_rt_only <- tab[which((tab$periods - as.numeric(tab$vint)) >= -0.084 & (tab$periods - as.numeric(tab$vint)) <= -0.082 & tab$periods >= startperiod & tab$periods <= endperiod & tab$method == "only_monthly"),]
# tab_rt_aggr <- tab[which((tab$periods - as.numeric(tab$vint)) >= -0.084 & (tab$periods - as.numeric(tab$vint)) <= -0.082 & tab$periods >= startperiod & tab$periods <= endperiod & tab$method == "aggr_weekly"),]
# tab_rt <- tab_rt_full
# tab_rt <- add_row(tab_rt,tab_rt_only )
# tab_rt <- add_row(tab_rt,tab_rt_aggr )
# 
# tab_rt$method <- factor(tab_rt$method,levels=c("full","aggr_weekly","only_monthly")
#                                      , labels=c("MF-DFM With Alternative High−Frequency Data","MF-DFM With Temporarily Aggregated Data", "MF-DFM Without Alternative High−Frequency Data"))
# 
# tab_rt_full$method <- factor(tab_rt_full$method,levels=c("full","aggr_weekly","only_monthly")
#                              , labels=c("MF-DFM With Alternative High−Frequency Data","MF-DFM With Temporarily Aggregated Data", "MF-DFM Without Alternative High−Frequency Data"))
# tab_rt_only$method <- factor(tab_rt_only$method,levels=c("full","aggr_weekly","only_monthly")
#                              , labels=c("MF-DFM With Alternative High−Frequency Data","MF-DFM With Temporarily Aggregated Data", "MF-DFM Without Alternative High−Frequency Data"))
# tab_rt_aggr$method <- factor(tab_rt_aggr$method,levels=c("full","aggr_weekly","only_monthly")
#                              , labels=c("MF-DFM With Alternative High−Frequency Data","MF-DFM With Temporarily Aggregated Data", "MF-DFM Without Alternative High−Frequency Data"))
# 
# tab_rt_full <- tab_rt_full %>% filter(periods <= last(tab_rt_only$periods) & periods >= first(tab_rt_only$periods))
# 
# a <- ggplot() +
#   PlotOptions +
#   geom_step(data = tab_rt_full, mapping = aes(x = time, y = value, group = method, color = method)) +
#   geom_step(data = tab_rt_aggr, mapping = aes(x = time, y = value, group = method, color = method)) +
#   geom_stepribbon(data = tab_rt_full, aes(x = time, ymin = min, ymax = max),
#               color = NA, fill = my.cols[7], alpha = 0.25) +
#   geom_stepribbon(data = tab_rt_aggr, aes(x = time, ymin = min, ymax = max),
#               color = NA, fill = my.cols[9], alpha = 0.25) +
#   scale_x_date(breaks = date_breaks("3 months"), labels = date_format("%b-%y")) +
#   scale_y_continuous(limits = c(-60,140), breaks = seq(-60,120,30)) +
#   scale_color_manual(values=c(my.cols[7], my.cols[9])) +
#   theme(legend.justification=c(0,0), 
#         legend.position=c(0.4,0.05), 
#         legend.text = element_text(size = 12),
#         axis.text.x = element_blank()) +
#   ylab("Weekly GDP Growth (in %, annualized)") + 
#   geom_hline(yintercept=0, col = "grey50") +
#   xlab(NULL)
# 
# b <- ggplot() +
#   PlotOptions +
#   geom_step(data = tab_rt_aggr, mapping = aes(x = time, y = value, group = method, color = method)) +
#   geom_step(data = tab_rt_only, mapping = aes(x = time, y = value, group = method, color = method)) +
#   geom_stepribbon(data = tab_rt_aggr, aes(x = time, ymin = min, ymax = max),
#               color = NA, fill = my.cols[9], alpha = 0.2) +
#   geom_stepribbon(data = tab_rt_only, aes(x = time, ymin = min, ymax = max),
#               color = NA, fill = my.cols[4], alpha = 0.3) +
#   scale_x_date(breaks = date_breaks("3 months"), labels = date_format("%b-%y")) +
#   #scale_y_continuous(limits = c(-90,90), breaks = seq(-90,90,30)) +
#   scale_color_manual(values=c(my.cols[9], my.cols[4])) +
#   theme(legend.justification=c(0,0), 
#         legend.position=c(0.4,0.05), 
#         legend.text = element_text(size = 12),) +
#   ylab("Weekly GDP Growth (in %, annualized)") + 
#   geom_hline(yintercept=0, col = "grey50") +
#   xlab(NULL)
# 
# ggarrange(a, b, ncol = 1, nrow = 2, heights = c(1,1), align = "hv")
# 
# ggsave("figures/first_vintage_corona_all_models.pdf",width = 20, height = 20, units = "cm")



# # CREATE REAL-TIME FACTOR REVISIONS-----------------------------------

# use the last x observations of each vintage to create a "real-time" factors

vintages <- 30
startdate <- 2005
enddate <-  2025.979

# First vintage by hand
tab_rev <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022 & (tab2$periods - as.numeric(tab2$vint)) <= -0.01 & tab2$periods >= startdate & tab2$periods <= enddate),]
tab_rev <- tab_rev %>% add_column(Releases = 1)
rev_count <- 1
for (sx in seq(0.021,(vintages-1)*0.021,0.021)){
  rev_count <- rev_count + 1
  temptab <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-sx & (tab2$periods - as.numeric(tab2$vint)) <= -0.01-sx & tab2$periods >= startdate & tab2$periods <= enddate),]
  temptab <- temptab %>% add_column(Releases = rev_count)
  tab_rev <- bind_rows(tab_rev, temptab)
}

blank_data3 <- tab_rev[dim(tab_rev)[1],] %>%
  mutate(value = -60, time = as.Date(2025-01-07))
blank_data4 <- tab_rev[dim(tab_rev)[1],] %>%
  mutate(value = 60, time = as.Date(2025-01-07))
blank_data <- rbind(blank_data3,blank_data4)


startdate <- "2005-01-07"
enddate <- "2025-12-28"

ggplot(tab_rev, aes(x = time, y = value, group = Releases, color = Releases)) +
  scale_color_gradient2(low = 'yellow', mid = 'red', high = 'blue', midpoint =14) +
  geom_line(size = 0.1) +
  geom_blank(data = blank_data, aes(x = time, y = value, group = Releases, color = Releases)) +
  #geom_hline(yintercept = 0) +
  xlab(NULL) +
  ylab("Weekly GDP Growth (in %, annualized)") + 
  scale_x_date(limits = as.Date(c(startdate,enddate)), 
               breaks = as.Date(as.yearmon(c(seq(from = 2005, to = 2026, by = 2)))), date_labels = "%Y") +
  scale_y_continuous(limits = c(-60,80), breaks = seq(-80,100,20)) +
  theme_minimal() +
  theme(plot.title = element_blank(), 
        legend.position = "bottom",
        text = element_text(size = 12),
        axis.text.y = element_text(size = 12),
        axis.text.x = element_text(size = 12),
        axis.title.x.bottom = element_text(size = 12),
        legend.text=element_text(size=12),
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank()) +
  guides(color=guide_colourbar(barwidth=20, barheight = 0.25))

ggsave(file.path(figures_dir, "real_time_factor_revisions.pdf"),width = 20, height = 15, units = "cm")



# Multiple Revisons facets ------------------------------------------------

tab_rev_facets <- tab_rev %>%
  mutate(
    Period = case_when(
      time >= as.Date("2005-01-07") & time <= as.Date("2010-01-07") ~ "2005–2010",
      time >  as.Date("2010-01-07") & time <= as.Date("2019-12-28") ~ "2010–2019",
      time >  as.Date("2019-12-28") & time <= as.Date("2021-12-28") ~ "2020–2021",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(Period))  # optional: drop rows outside the 3 periods

blank_data <- bind_rows(
  tab_rev %>% filter(Period == "2005–2010") %>% slice_tail(n = 1) %>%
    mutate(value = c(-60, 60), time = as.Date("2009-12-31"), Period = "2005–2010"),
  
  tab_rev %>% filter(Period == "2010–2019") %>% slice_tail(n = 1) %>%
    mutate(value = c(-60, 60), time = as.Date("2019-12-28"), Period = "2010–2019"),
  
  tab_rev %>% filter(Period == "2020–2021") %>% slice_tail(n = 1) %>%
    mutate(value = c(-60, 60), time = as.Date("2021-12-28"), Period = "2020–2021")
)

ggplot(tab_rev_facets, aes(x = time, y = value, group = Releases, color = Releases)) +
  geom_line(size = 0.1) +
  #geom_blank(data = blank_data, aes(x = time, y = value, group = Releases, color = Releases)) +
  scale_color_gradient2(low = 'yellow', mid = 'red', high = 'blue', midpoint = 15) +
  facet_wrap(~ Period, ncol = 1, scales = "free") +
  xlab(NULL) +
  ylab("Weekly GDP Growth (in %, annualized)") + 
  scale_y_continuous(expand = expansion(mult = c(0.15, 0.15))) +
  theme_minimal() +
  theme(
    plot.title = element_blank(), 
    legend.position = "bottom",
    text = element_text(size = 12),
    axis.text = element_text(size = 12),
    axis.title.x.bottom = element_text(size = 12),
    legend.text = element_text(size = 12),
    panel.grid.major = element_line(size = 0.2),
    panel.grid.minor = element_blank(),
    strip.text = element_text(size = 14, face = "bold")
  ) +
  guides(color = guide_colourbar(barwidth = 20, barheight = 0.25))

ggsave(file.path(figures_dir, "vintages_subperiods.pdf"),width = 33, height = 44, units = "cm")


# CREATE REAL-TIME FACTOR REVISIONS EXCLUDING CORONA-----------------------------------

## Figure 4: Revisions of the Weekly GDP Indicator. -------------------------

vintages <- 30
startdate <- 2005
enddate <-  2019+43/48 #2020#2019.979

# First vintage by hand
tab_rev <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022 & (tab2$periods - as.numeric(tab2$vint)) <= -0.01 & tab2$periods >= startdate & tab2$periods <= enddate),]
tab_rev <- tab_rev %>% add_column(Releases = 1)
rev_count <- 1
for (sx in seq(0.021,(vintages-1)*0.021,0.021)){
  rev_count <- rev_count + 1
  temptab <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-sx & (tab2$periods - as.numeric(tab2$vint)) <= -0.01-sx & tab2$periods >= startdate & tab2$periods <= enddate),]
  temptab <- temptab %>% add_column(Releases = rev_count)
  tab_rev <- bind_rows(tab_rev, temptab)
}

tab_rev <- tab_rev %>% add_column(Corona = 'Excluding Corona Crisis')
tab_rev <- tab_rev %>%
  mutate(Corona = ifelse(periods >= 2020, 'Corona Crisis','Excluding Corona Crisis'))
tab_rev$Corona <- factor(tab_rev$Corona, levels=c("Excluding Corona Crisis", "Corona Crisis")
                         , labels=c("Excluding Corona Crisis", "Corona Crisis")) #, "Corona Crisis"))

blank_data1 <- tab_rev[1,] %>%
  mutate(value = -20)
blank_data2 <- tab_rev[1,] %>%
  mutate(value = 10)

blank_data <- rbind(blank_data1,blank_data2)

#my_breaks <- function(x) { if (min(x) < -40) seq(-110, 50, 40) else seq(-20, 10, 10) }
#my_breaks <- seq(-30, 20, 10)

startdate <- "2005-01-07"
enddate <- "2020-01-07"

ggplot(tab_rev, aes(x = time, y = value, group = Releases, color = Releases)) +
  PlotOptions +
  scale_color_gradient2(low = 'yellow', mid = 'red', high = 'blue', midpoint = 15) +
  geom_line(size = 0.1) +
  geom_blank(data = blank_data, aes(x = time, y = value, group = Releases, color = Releases)) +
  #facet_wrap(~Corona, nrow = 2, scales = "free") +
  xlab(NULL) +
  ylab("Weekly GDP Growth (in %, annualized)") + 
  theme_minimal() +
 # geom_blank(data = blank_data, aes(x = time, y = value, group = Releases, color = Releases)) +
#  scale_y_continuous(breaks = my_breaks) +
  scale_y_continuous(limits = c(-30,10), breaks = seq(-30,10,5)) +
  scale_x_date(limits = as.Date(c(startdate,enddate)), 
               breaks = as.Date(as.yearmon(c(seq(from = 2000, to = 2020, by = 3)))), date_labels = "%Y") +
  #geom_hline(yintercept=0, linetype=1, color = "grey50", size = 0.1) +
  theme(plot.title = element_blank(), 
        legend.position = "bottom",
        text = element_text(size = 12),
        axis.text.y = element_text(size = 12),
        axis.text.x = element_text(size = 12),
        axis.title.x.bottom = element_text(size = 12),
        legend.text=element_text(size=12),
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank()) +
  guides(color=guide_colourbar(barwidth=20, barheight = 0.25))

ggsave(file.path(figures_dir, "real_time_factor_revisions_excl_corona.pdf"),width = 20, height = 15, units = "cm")


# CREATE REAL-TIME FACTOR REVISIONS FOR CORONA CRISIS -----------------------------------

# use the last x observations of each vintage to create a "real-time" factors

vintages <- 30
startdate <- 2020
enddate <-  2022#2019.979

# First vintage by hand
tab_rev <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022 & (tab2$periods - as.numeric(tab2$vint)) <= -0.01 & tab2$periods >= startdate & tab2$periods <= enddate),]
tab_rev <- tab_rev %>% add_column(Releases = 1)
rev_count <- 1
for (sx in seq(0.021,(vintages-1)*0.021,0.021)){
  rev_count <- rev_count + 1
  temptab <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-sx & (tab2$periods - as.numeric(tab2$vint)) <= -0.01-sx & tab2$periods >= startdate & tab2$periods <= enddate),]
  temptab <- temptab %>% add_column(Releases = rev_count)
  tab_rev <- bind_rows(tab_rev, temptab)
}

blank_data5 <- tab_rev[dim(tab_rev)[1],] %>%
  mutate(value = -100)
blank_data6 <- tab_rev[dim(tab_rev)[1],] %>%
  mutate(value = 200)
blank_data <- rbind(blank_data5,blank_data6)


ggplot(tab_rev, aes(x = time, y = value, group = Releases, color = Releases)) +
  PlotOptions +
  scale_color_gradient2(low = 'yellow', mid = 'red', high = 'blue', midpoint = 15) +
  geom_line(size = 0.1) +
  geom_blank(data = blank_data, aes(x = time, y = value, group = Releases, color = Releases)) +
  #facet_wrap(~Corona, nrow = 2, scales = "free") +
  xlab(NULL) +
  ylab("Weekly GDP Growth (in %, annualized)") + 
  theme_minimal() +
  # geom_blank(data = blank_data, aes(x = time, y = value, group = Releases, color = Releases)) +
  #  scale_y_continuous(breaks = my_breaks) +
  scale_y_continuous(limits = c(-80,170), breaks = seq(-80,170,20)) +
  scale_x_date(breaks = date_breaks("2 month"), labels = date_format("%b-%y")) +
  #geom_hline(yintercept=0, linetype=1, color = "grey50", size = 0.1) +
  theme(plot.title = element_blank(), 
        legend.position = "bottom",
        text = element_text(size = 12),
        axis.text.y = element_text(size = 12),
        axis.text.x = element_text(size = 12),
        axis.title.x.bottom = element_text(size = 12),
        legend.text=element_text(size=12),
        panel.grid.major.x = element_line(size = 0.2),
        panel.grid.major.y = element_line(size = 0.2),
        panel.grid.minor.x = element_blank(),
        panel.grid.minor.y = element_blank()) +
  guides(color=guide_colourbar(barwidth=20, barheight = 0.25))

ggsave(file.path(figures_dir, "real_time_factor_revisions_incl_corona.pdf"),width = 20, height = 15, units = "cm")


####################################################################################

# Real-time factor during Corona for all model types ----------------------

# Figure 5: Real-Time Version of the Weekly GDP Indicator During the Corona Crisis: JAE Revision: Adjusted for mid-period Vintage! --------

# Real-time factor vs final factor during Corona
startdate <- "2020-01-07"
enddate <- "2021-12-31"
startperiod <- 2020
endperiod <-  max(tab$periods)

tab_real <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_full <- tab[which(tab$vint == last(tab$vint) & tab$periods >= startperiod & tab$periods <= endperiod & tab$method == "full_RT"),]

# Look at vintage after 1 Month, 4/48 instead of real-time vintage
tab_x1 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-3/48 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020-3/48 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_x2 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-7/48 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020-7/48 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_x3 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-11/48 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020-11/48 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_x4 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-15/48 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020-15/48 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_x5 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-19/48 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020-19/48 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
tab_x6 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022-23/48 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020-23/48 & tab2$periods >= startperiod & tab2$periods <= endperiod),]

my.cols <- c("black","yellow2","red","blue","green","orange","purple","grey")

tab_full_test <- tab_full %>% mutate(type = "tab_full")
tab_real_test <- tab_real %>% mutate(type = "tab_real")
tab_x1_test <- tab_x1 %>% mutate(type = "tab_x1")

tab_test <- rbind(tab_full_test,tab_real_test,tab_x1_test)
tab_test$type <- factor(tab_test$type, levels = c("tab_real","tab_x1","tab_full"), labels = c("Real-Time Version of Weekly GDP Indicator","Weekly GDP Indicator Based on Release after 1 Month","Weekly GDP Indicator Based on Latest Vintage"))

# plot only most recent months (insample vs. realtime vintage)
ggplot(tab_test, aes(x = time, y = value, color = type, fill = type)) +
  PlotOptions +
  geom_hline(yintercept=0, col = "grey50") +
  scale_color_manual(values = c(my.cols[2:4])) +
  scale_y_continuous(limits = c(-60,60), breaks = seq(-60,100,20)) +
  xlab(NULL) + 
  ylab("Weekly GDP Growth (in %, annualized)") +
  #scale_y_continuous(limits = c(-120,+100), expand = expansion(mult = c(0.3,0))) +
  scale_x_date(limits = as.Date(c(startdate, enddate)), breaks = date_breaks("3 months"), labels = date_format("%b-%y")) +
  geom_ribbon(aes(ymin = min, ymax = max), color = NA, alpha = 0.25)+
  scale_fill_manual(values = c(my.cols[2:4])) +
  theme(legend.justification=c(0,0), 
      legend.position=c(0.3,0.01), 
      plot.margin = unit(c(1,1.1,1,1), "cm"),
      legend.text = element_text(size = 12)) + 
  guides(color=guide_legend(override.aes=list(fill=NA)))


ggsave(file.path(figures_dir, "mid_period1m__vs_finalvs_real_vintage_corona.pdf"),width = 20, height = 15, units = "cm")


################### CODE GRAVEYARD ###########################----------------------------------------------------------
# 
# # PLOT REVISION HISTORY: FULL SAMPLE, FULL SCALE -----------------------------------
# 
# startdate <- "2005-01-07"
# enddate <- "2020-10-28"
# 
# ggplot(tab2, aes(x = time, y = value, group = as.numeric(vint), color = as.numeric(vint))) +
#   geom_line(size = 0.1) +
#   geom_hline(yintercept = 0) +
#   xlab(NULL) +
#   ylab("Factor value") +
#   scale_colour_distiller(name = "Vintages      ", type = "seq", 
#                          palette = 1, 
#                          direction = 1,
#                          values = NULL, space = "Lab",
#                          breaks = seq(2005, 2021, 5),
#                          guide = "colourbar") +
#   theme_minimal() +
#   scale_x_date(limits = as.Date(c(startdate,enddate)),breaks = function(x) seq.Date(from = min(x), to = max(x), by = "2 years"), date_labels = "%Y") +
#   scale_y_continuous(breaks = seq(-150,150,25)) +
#   coord_cartesian(ylim = c(-150,50)) +
#   theme(legend.position="bottom",
#         panel.grid.major.x = element_blank(),
#         text = element_text(size=12),
#         panel.grid.minor.x = element_blank(),
#         panel.grid.minor.y = element_blank()) +
#   guides(color=guide_colourbar(barwidth=20, barheight = 0.25))
# 
# ggsave("figures/revisions_factor_full_scale.pdf",width = 20, height = 15, units = "cm")
# 
# # PLOT REVISION HISTORY: NO CORONA, REDUCED SCALE -----------------------------------
# 
# startdate <- "2005-01-07"
# enddate <- "2019-12-28"
# 
# ggplot(tab2, aes(x = time, y = value, group = as.numeric(vint), color = as.numeric(vint))) +
#   geom_line(size = 0.1) +
#   geom_hline(yintercept = 0) +
#   xlab(NULL) +
#   ylab("Factor value") +
#   scale_colour_distiller(name = "Vintages      ", type = "seq", 
#                          palette = 1, 
#                          direction = 1,
#                          values = NULL, space = "Lab",
#                          breaks = seq(2005, 2021, 5),
#                          guide = "colourbar") +
#   theme_minimal() +
#   scale_x_date(limits = as.Date(c(startdate,enddate)),breaks = function(x) seq.Date(from = min(x), to = max(x), by = "2 years"), date_labels = "%Y") +
#   scale_y_continuous(breaks = seq(-150,150,25)) +
#   coord_cartesian(ylim = c(-30,30)) +
#   theme(legend.position="bottom",
#         panel.grid.major.x = element_blank(),
#         text = element_text(size=12),
#         panel.grid.minor.x = element_blank(),
#         panel.grid.minor.y = element_blank()) +
#   guides(color=guide_colourbar(barwidth=20, barheight = 0.25))
# 
# ggsave("figures/revisions_factor_reduced_scale.pdf",width = 20, height = 15, units = "cm")
# 
# # PLOT INSAMPLE RESULTS ALL MODELS UNTIL CORONA --------------------------
# 
# startdate <- "2005-01-07"
# enddate <- "2019-12-28"
# startperiod <- 2005
# endperiod <-  2019.979
# tab_full <- tab[which(tab$vint == last(tab$vint) & tab$periods >= startperiod & tab$periods <= endperiod),]
# 
# # plot entire history
# ggplot() +
#   PlotOptions +
#   geom_line(data = tab_full, mapping = aes(x = time, y = value, group = method, color = method)) +
#   scale_x_date(limits = as.Date(c(startdate,enddate)),breaks = function(x) seq.Date(from = min(x), to = max(x), by = "2 years"), date_labels = "%Y") +
#   scale_y_continuous(breaks = seq(-170,150,20)) +
#   ylab("%-Change (Annualized)") +
#   xlab(NULL) 
# 
# # GRAPH INSAMPLE RESULTS ALL MODELS DURING CORONA ----------------------
# 
# startdate <- "2020-01-07"
# enddate <- "2020-12-28"
# startperiod <- 2020
# endperiod <-  max(tab$periods)
# tab_full <- tab[which(tab$vint == last(tab$vint) & tab$periods >= startperiod & tab$periods <= endperiod),]
# 
# # plot entire history
# ggplot() +
#   PlotOptions +
#   geom_line(data = tab_full, mapping = aes(x = time, y = value, group = method, color = method)) +
#   scale_x_date(limits = as.Date(c(startdate,enddate)),breaks = function(x) seq.Date(from = min(x), to = max(x), by = "2 years"), date_labels = "%Y") +
#   scale_y_continuous(breaks = seq(-170,150,20)) +
#   ylab("%-Change (Annualized)") +
#   xlab(NULL)
# 
# # CREATE REAL-TIME FACTOR -----------------------------------
# 
# # only use the last observation of each vintage to create a "real-time" factor
# 
# # Real-time factor vs final factor until Corona
# startdate <- "2005-01-07"
# enddate <- "2019-12-28"
# 
# startperiod <- 2005
# endperiod <-  2019.979
# tab3 <- tab2[which((tab2$periods - as.numeric(tab2$vint)) >= -0.022 & (tab2$periods - as.numeric(tab2$vint)) <= -0.020 & tab2$periods >= startperiod & tab2$periods <= endperiod),]
# tab_full <- tab[which(tab$vint == last(tab$vint) & tab$periods >= startperiod & tab$periods <= endperiod & tab$method == "full"),]
# 
# # plot entire history
# ggplot() +
#   PlotOptions +
#   geom_line(data = tab3, mapping = aes(x = time, y = value, color = "Real-Time Vintage")) +
#   geom_line(data = tab_full, mapping = aes(x = time, y = value, color = "Final Vintage")) +
#   scale_x_date(limits = as.Date(c(startdate,enddate)),breaks = function(x) seq.Date(from = min(x), to = max(x), by = "2 years"), date_labels = "%Y") +
#   ylab(NULL) +
#   xlab(NULL) 
# 
# ggsave("figures/first_vs_final_vintage_full_history_excl_Cororna.pdf",width = 20, height = 15, units = "cm")
# 
# 
