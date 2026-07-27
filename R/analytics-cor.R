# Correlation and comparison-plot helpers for the in-sample analytics.

#' Rescale an indicator to GDP moments
#'
#' Standardizes an indicator over a reference window and rescales it to
#' the mean and standard deviation of GDP over the same window.
#'
#' @param indicator_df Data frame with `time` (Date) and `value` columns.
#' @param gdp_hist_df Data frame with GDP history: column `value` holds
#'   the observation `Date` and column `y` the GDP value (legacy layout).
#' @param ref_start,ref_end Reference window (`Date`).
#'
#' @return `indicator_df` with the `value` column rescaled.
#'
#' @importFrom dplyr filter pull mutate %>%
#' @importFrom stats sd
#' @examples
#' ind <- data.frame(time = seq(as.Date("2010-01-07"), by = "week", length.out = 200),
#'                   value = rnorm(200, 5, 2))
#' gdp <- data.frame(value = seq(as.Date("2010-01-01"), by = "quarter", length.out = 40),
#'                   y = rnorm(40, 1, 1))
#' head(rescale_to_gdp(ind, gdp))
#' @export
rescale_to_gdp <- function(indicator_df, gdp_hist_df,
                           ref_start = as.Date("2005-01-01"),
                           ref_end   = as.Date("2025-12-31")) {

  # GDP moments (over reference window)
  gdp_ref <- gdp_hist_df %>%
    filter(value >= ref_start, value <= ref_end) %>%
    pull(y)

  mu_gdp <- mean(gdp_ref, na.rm = TRUE)
  sd_gdp <- sd(gdp_ref,  na.rm = TRUE)

  # Indicator moments (over reference window)
  ind_ref <- indicator_df %>%
    filter(time >= ref_start, time <= ref_end) %>%
    pull(value)

  mu_ind <- mean(ind_ref, na.rm = TRUE)
  sd_ind <- sd(ind_ref,  na.rm = TRUE)

  # safeguard
  if (is.na(sd_ind) || sd_ind == 0) {
    return(indicator_df %>% mutate(value = (value - mu_ind) + mu_gdp))
  }

  indicator_df %>%
    mutate(value = (value - mu_ind) / sd_ind * sd_gdp + mu_gdp)
}


#' Quarter-on-quarter growth from a weekly level series
#'
#' Averages the level index by quarter and computes annualized
#' quarter-on-quarter growth in percent.
#'
#' @param level_df Data frame with `time` (Date) and `value` (level).
#'
#' @return Data frame with quarterly `time` and growth `value`.
#'
#' @importFrom dplyr select mutate group_by summarise arrange lag transmute filter %>%
#' @importFrom lubridate floor_date
#' @examples
#' lv <- data.frame(time = seq(as.Date("2020-01-07"), by = "week", length.out = 150),
#'                  value = 100 * cumprod(1 + rnorm(150, 0, 0.002)))
#' head(build_wai_qoq_mean_series(lv))
#' @export
build_wai_qoq_mean_series <- function(level_df) {
  level_df %>%
    select(time, value) %>%
    mutate(quarter = floor_date(time, unit = "quarter")) %>%
    group_by(quarter) %>%
    summarise(level_value = mean(value, na.rm = TRUE), .groups = "drop") %>%
    arrange(quarter) %>%
    mutate(value = ((level_value / lag(level_value))^4 - 1) * 100) %>%
    transmute(time = quarter, value = value) %>%
    filter(!is.na(value))
}


#' Select the QoQ series for a WAI result, given the aggregation method
#'
#' @param wai_result List with elements `tab_gr_qoq` and `tab_gr_lv` (as
#'   produced by [extract_wai_data()]).
#' @param method Aggregation method; `"mean"` derives QoQ growth from the
#'   level index, anything else returns the stored QoQ table.
#'
#' @return Data frame with `time` and `value`.
#' @examples
#' res <- list(tab_gr_qoq = data.frame(time = as.Date("2020-01-07"), value = 1),
#'             tab_gr_lv = data.frame(time = seq(as.Date("2020-01-07"), by = "week",
#'                                               length.out = 150),
#'                                    value = cumprod(1 + rnorm(150, 0, 0.002))))
#' prepare_wai_qoq_series(res, method = "last")
#' @export
prepare_wai_qoq_series <- function(wai_result, method) {
  if (method == "mean") {
    return(build_wai_qoq_mean_series(wai_result$tab_gr_lv))
  }
  wai_result$tab_gr_qoq
}


#' Plot the WAI against a comparison indicator and GDP
#'
#' @param tab_wai WAI data frame (`time`, `value`).
#' @param comparison_df Comparison indicator data frame (`time`, `value`).
#' @param comparison_label Label for the comparison series.
#' @param crises Data frame with `Peak` and `Trough` dates for shading.
#' @param hist_tab_gdp GDP history in the legacy layout (`value` = Date,
#'   `y` = GDP value).
#' @param sample_end_date Sample end (`Date`), e.g.
#'   `wai_sample_config()$sample_end_date`.
#' @param plot_title Optional plot title.
#' @param ylim_fixed Optional fixed y-axis limits, length-2 numeric.
#'
#' @return A `ggplot` object.
#'
#' @importFrom dplyr filter mutate bind_rows %>%
#' @importFrom ggplot2 ggplot geom_line aes scale_x_date ylab xlab geom_rect
#'   scale_color_manual theme_minimal theme element_text element_blank labs
#'   coord_cartesian
#' @importFrom stats setNames
#' @examples
#' wk <- seq(as.Date("2005-01-07"), by = "week", length.out = 900)
#' wai <- data.frame(time = wk, value = rnorm(900))
#' cmp <- data.frame(time = wk, value = rnorm(900))
#' crises <- data.frame(Peak = as.Date("2008-07-07"), Trough = as.Date("2009-09-28"))
#' gdp <- data.frame(value = seq(as.Date("2005-01-01"), by = "quarter", length.out = 60),
#'                   y = rnorm(60))
#' plot_comparison(wai, cmp, "Benchmark", crises, gdp,
#'                 sample_end_date = as.Date("2021-12-31"))
#' @export
plot_comparison <- function(tab_wai, comparison_df, comparison_label,
                            crises, hist_tab_gdp, sample_end_date,
                            plot_title = NULL,
                            ylim_fixed = NULL) {
  x_start <- as.Date("2005-01-01")
  x_end <- sample_end_date

  tab_wai <- tab_wai %>%
    filter(time >= x_start, time <= x_end)

  tab_wai <- tab_wai %>%
    mutate(Series = factor("WAI", levels = c("WAI")))

  comparison_df <- comparison_df %>%
    filter(time >= x_start, time <= x_end) %>%
    mutate(Series = factor(comparison_label, levels = c(comparison_label)))

  hist_tab_gdp <- hist_tab_gdp %>%
    filter(value >= x_start, value <= x_end)

  plot_df <- bind_rows(tab_wai, comparison_df)

  color_values <- setNames(c("red", "blue"), c("WAI", comparison_label))

  p <- ggplot() +
    geom_line(data = plot_df, aes(x = time, y = value, color = Series)) +
    scale_x_date(date_breaks = "2 years", date_labels = "%Y", limits = c(x_start, x_end)) +
    ylab(NULL) +
    xlab(NULL) +
    geom_line(data = hist_tab_gdp, aes(y = y, x = value, group = y),
              color = "black") +
    geom_rect(data = crises,
              aes(xmin = Peak, xmax = Trough, ymin = -Inf, ymax = Inf),
              fill = "grey80", alpha = 0.2) +
    scale_color_manual(values = color_values) +
    theme_minimal() +
    theme(axis.text.x = element_text(),
          legend.title = element_blank(),
          legend.position = "bottom",
          plot.title = element_text(hjust = 0.5)) +
    labs(title = plot_title)

  # Apply fixed limits ONLY if requested
  if (!is.null(ylim_fixed)) {
    p <- p + coord_cartesian(ylim = ylim_fixed)
  }

  return(p)
}


#' Cross correlations of the WAI and benchmarks with GDP
#'
#' Computes lagged correlations of the WAI (and either the benchmark
#' indicators or the WAI model variants) with GDP growth, for YoY and QoQ
#' frequencies, at lags -4 to 0.
#'
#' @param method Quarterly aggregation method: `"mean"`, `"last"`, or
#'   `"last_month"`.
#' @param analysis_set `"wai_versions"` to compare WAI model variants, or
#'   `"indicators"` to compare against the benchmark indicators.
#' @param inputs Named list of the input data objects (formerly free
#'   variables in the calling script). Always required: `tab_gr`,
#'   `tab_gr_lv`, `x_hist_gr_yoy`, `x_hist_gr_ann`. For
#'   `analysis_set = "indicators"` additionally: `tab_wai_yoy`,
#'   `wwa_gr_df`, `wwa_gr_df_qoq`, `fcurve_gr_df`, `tab_kss`, `tab_snb`,
#'   `tab_baro`. For `"wai_versions"`: `result_wai`, `result_wai_no_sv`,
#'   `result_wai_only_monthly_no_sv`, `result_wai_no_hf`,
#'   `result_wai_no_financial`.
#'
#' @return A data frame of correlations by `Frequency`, `Series` and lag.
#'
#' @importFrom dplyr mutate group_by summarise ungroup select rename
#'   inner_join arrange bind_rows filter slice_max lead %>%
#' @importFrom tidyr nest unnest pivot_wider
#' @importFrom purrr map map_dfr
#' @importFrom tibble tibble
#' @importFrom lubridate floor_date
#' @importFrom stats cor
#' @examples
#' \dontrun{
#' # inputs is the bundle of data objects built by analysis/5_plots scripts:
#' cor_tab <- get_combined_cor_table("mean", "indicators", inputs = insample_inputs)
#' }
#' @export
get_combined_cor_table <- function(method = c("mean", "last", "last_month"),
                                   analysis_set = c("wai_versions", "indicators"),
                                   inputs) {
  method <- match.arg(method)
  analysis_set <- match.arg(analysis_set)

  required_inputs <- c(
    "tab_gr", "tab_gr_lv", "x_hist_gr_yoy", "x_hist_gr_ann",
    if (analysis_set == "indicators") {
      c("tab_wai_yoy", "wwa_gr_df", "wwa_gr_df_qoq", "fcurve_gr_df",
        "tab_kss", "tab_snb", "tab_baro")
    } else {
      c("result_wai", "result_wai_no_sv", "result_wai_only_monthly_no_sv",
        "result_wai_no_hf", "result_wai_no_financial")
    }
  )
  missing_inputs <- setdiff(required_inputs, names(inputs))
  if (length(missing_inputs) > 0) {
    stop("Missing required inputs: ", paste(missing_inputs, collapse = ", "))
  }
  list2env(inputs[required_inputs], envir = environment())

  # Helper to aggregate one dataset
  aggregate_to_quarter <- function(df) {
    if (method == "mean") {
      df %>%
        mutate(quarter = floor_date(time, unit = "quarter")) %>%
        group_by(Series, quarter) %>%
        summarise(value = mean(value, na.rm = TRUE), .groups = "drop")
    } else if (method == "last") {
      df %>%
        mutate(quarter = floor_date(time, unit = "quarter")) %>%
        group_by(Series, quarter) %>%
        slice_max(order_by = time, with_ties = FALSE) %>%
        ungroup() %>%
        select(Series, quarter, value)
    } else if (method == "last_month") {
      df %>%
        mutate(month = floor_date(time, unit = "month")) %>%
        group_by(Series, month) %>%
        summarise(monthly_mean = mean(value, na.rm = TRUE), .groups = "drop") %>%  # monthly average
        mutate(quarter = floor_date(month, unit = "quarter")) %>%
        group_by(Series, quarter) %>%
        slice_max(order_by = month, with_ties = FALSE) %>%  # last month in quarter
        ungroup() %>%
        rename(value = monthly_mean) %>%
        select(Series, quarter, value)
    }
  }

  # --- YOY Analysis ---
  if (analysis_set == "indicators") {
    plot_df_yoy <- bind_rows(
      tab_wai_yoy   %>% mutate(Series = "WAI"),
      wwa_gr_df     %>% mutate(Series = "SECO-WWA"),
      fcurve_gr_df  %>% mutate(Series = "F-CURVE"),
      tab_kss       %>% mutate(Series = "SECO-SEC"),
      tab_snb       %>% mutate(Series = "SNB-BCI"),
      tab_baro      %>% mutate(Series = "KOF-BARO")
    )
  } else {
    plot_df_yoy <- bind_rows(
      result_wai$tab_wai_yoy   %>% mutate(Series = "WAI"),
      result_wai_no_sv$tab_wai_yoy   %>% mutate(Series = "WAI-SV"),
      result_wai_only_monthly_no_sv$tab_wai_yoy     %>% mutate(Series = "WAI-(SV+HF)"),
      result_wai_no_hf$tab_wai_yoy     %>% mutate(Series = "WAI-HF"),
      result_wai_no_financial$tab_wai_yoy  %>% mutate(Series = "WAI-FIN")
    )
  }


  quarterly_df_yoy <- aggregate_to_quarter(plot_df_yoy)

  GDP_yoy_tab <- tibble(
    date = seq.Date(as.Date("1991-01-01"), by = "3 months", length.out = length(x_hist_gr_yoy)),
    GDP_yoy = as.numeric(x_hist_gr_yoy)
  )

  series_start_dates_yoy <- quarterly_df_yoy %>%
    group_by(Series) %>%
    summarise(series_start = max(min(quarter), min(GDP_yoy_tab$date)), .groups = "drop")

  aligned_start_yoy <- max(series_start_dates_yoy$series_start)

  quarterly_df_yoy_aligned <- quarterly_df_yoy %>%
    inner_join(series_start_dates_yoy, by = "Series") %>%
    select(-series_start)

  GDP_yoy_tab_aligned <- GDP_yoy_tab

  joined_df_yoy <- quarterly_df_yoy_aligned %>%
    rename(date = quarter, series_value = value) %>%
    inner_join(GDP_yoy_tab_aligned, by = "date")

  print_evaluation_periods(
    joined_df_yoy,
    series_col = "Series",
    date_col = "date",
    context_label = paste("In-sample fit table,", analysis_set, "YoY"),
    frequency_label = "YoY",
    method_label = method
  )

  lags <- -4:0
  cor_lag_results_yoy <- joined_df_yoy %>%
    group_by(Series) %>%
    arrange(date) %>%
    nest() %>%
    mutate(cor_lags = map(data, ~ {
      df <- .
      map_dfr(lags, function(l) {
        df_lag <- df %>%
          mutate(gdp_lag = lead(GDP_yoy, n = -l))
        tibble(
          Lag = l,
          Correlation = cor(df_lag$series_value, df_lag$gdp_lag, use = "complete.obs")
        )
      })
    })) %>%
    select(-data) %>%
    unnest(cor_lags)

  cor_lag_results_yoy_wide <- cor_lag_results_yoy %>%
    pivot_wider(names_from = Lag, values_from = Correlation, names_prefix = "Lag_") %>%
    mutate(Frequency = "YoY") %>%
    select(Frequency, everything())

  # --- QOQ Analysis ---
  base_wai_result <- list(
    tab_gr_qoq = tab_gr %>% select(time, name, value),
    tab_gr_lv = tab_gr_lv
  )
  tab_gr_qoq <- prepare_wai_qoq_series(base_wai_result, method)

  if (analysis_set == "indicators") {
    plot_df_qoq <- bind_rows(
      tab_gr_qoq      %>% mutate(Series = "WAI"),
      wwa_gr_df_qoq   %>% mutate(Series = "SECO-WWA"),
      fcurve_gr_df    %>% mutate(Series = "F-CURVE"),
      tab_kss         %>% mutate(Series = "SECO-SEC"),
      tab_snb         %>% mutate(Series = "SNB-BCI"),
      tab_baro        %>% mutate(Series = "KOF-BARO")
    )
  } else {
    plot_df_qoq <- bind_rows(
      prepare_wai_qoq_series(result_wai, method) %>% mutate(Series = "WAI"),
      prepare_wai_qoq_series(result_wai_no_sv, method) %>% mutate(Series = "WAI-SV"),
      prepare_wai_qoq_series(result_wai_only_monthly_no_sv, method) %>% mutate(Series = "WAI-(SV+HF)"),
      prepare_wai_qoq_series(result_wai_no_hf, method) %>% mutate(Series = "WAI-HF"),
      prepare_wai_qoq_series(result_wai_no_financial, method) %>% mutate(Series = "WAI-FIN")
    )
  }

  quarterly_df_qoq <- aggregate_to_quarter(plot_df_qoq)

  GDP_qoq_tab <- tibble(
    date = seq.Date(as.Date("1990-01-01"), by = "3 months", length.out = length(x_hist_gr_ann)),
    GDP_qoq = as.numeric(x_hist_gr_ann)
  )

  series_start_dates_qoq <- quarterly_df_qoq %>%
    group_by(Series) %>%
    summarise(series_start = max(min(quarter), min(GDP_qoq_tab$date)), .groups = "drop")

  aligned_start_qoq <- max(series_start_dates_qoq$series_start)

  quarterly_df_qoq_aligned <- quarterly_df_qoq %>%
    inner_join(series_start_dates_qoq, by = "Series") %>%
    select(-series_start)

  GDP_tab_aligned <- GDP_qoq_tab

  joined_df_qoq <- quarterly_df_qoq_aligned %>%
    rename(date = quarter, series_value = value) %>%
    inner_join(GDP_tab_aligned, by = "date")

  print_evaluation_periods(
    joined_df_qoq,
    series_col = "Series",
    date_col = "date",
    context_label = paste("In-sample fit table,", analysis_set, "QoQ"),
    frequency_label = "QoQ",
    method_label = method
  )

  cor_lag_results_qoq <- joined_df_qoq %>%
    group_by(Series) %>%
    arrange(date) %>%
    nest() %>%
    mutate(cor_lags = map(data, ~ {
      df <- .
      map_dfr(lags, function(l) {
        df_lag <- df %>%
          mutate(gdp_lag = lead(GDP_qoq, n = -l))
        tibble(
          Lag = l,
          Correlation = cor(df_lag$series_value, df_lag$gdp_lag, use = "complete.obs")
        )
      })
    })) %>%
    select(-data) %>%
    unnest(cor_lags) %>%
    ungroup()

  cor_lag_results_qoq_wide <- cor_lag_results_qoq %>%
    pivot_wider(names_from = Lag, values_from = Correlation, names_prefix = "Lag_") %>%
    mutate(Frequency = "QoQ") %>%
    select(Frequency, everything())

  desired_order <- if (analysis_set == "indicators") {
    c("WAI", "SECO-WWA", "F-CURVE", "SECO-SEC", "SNB-BCI", "KOF-BARO")
  } else {
    c("WAI", "WAI-SV", "WAI-(SV+HF)", "WAI-HF", "WAI-FIN")
  }

  cor_lag_results_yoy_wide <- cor_lag_results_yoy_wide %>%
    arrange(factor(Series, levels = desired_order))

  cor_lag_results_qoq_wide <- cor_lag_results_qoq_wide %>%
    arrange(factor(Series, levels = desired_order))

  # --- Combine ---
  combined_cor_table <- bind_rows(cor_lag_results_yoy_wide, cor_lag_results_qoq_wide)

  return(combined_cor_table)
}


#' Render the lag-correlation heatmap grid and save it
#'
#' @param cor_tables Named list of correlation tables from
#'   [get_combined_cor_table()], one per aggregation method.
#' @param series_order Character vector giving the series display order.
#' @param output_file File name for the saved figure.
#' @param figures_dir Directory the figure is written to (e.g.
#'   `wai_sample_config()$figures_dir`).
#'
#' @return Invisibly, the assembled plot.
#'
#' @importFrom dplyr filter select %>%
#' @importFrom tidyr pivot_longer
#' @importFrom ggplot2 ggplot aes geom_tile geom_text scale_fill_gradient2
#'   theme_minimal theme element_text element_blank labs ggsave
#' @importFrom ggpubr ggarrange
#' @importFrom scales squish
#' @examples
#' \dontrun{
#' render_correlation_heatmap(
#'   cor_tables = list(mean = cor_tab_mean, last = cor_tab_last),
#'   series_order = c("WAI", "SECO-WWA", "KOF-BARO"),
#'   output_file = "correlation_heatmap.pdf",
#'   figures_dir = cfg$figures_dir
#' )
#' }
#' @export
render_correlation_heatmap <- function(cor_tables, series_order, output_file, figures_dir) {
  method_labels <- c(
    mean = "Mean",
    last = "Last",
    lastmonth = "Last Month",
    last_month = "Last Month"
  )


  # Store all plots
  all_plots <- list()

  # Loop through each table and frequency
  for (method in names(cor_tables)) {
    for (freq in c("YoY", "QoQ")) {

      # Subset table
      df <- cor_tables[[method]] %>%
        filter(Frequency == freq) %>%
        select(-Frequency)

      # Pivot longer
      cor_table <- df %>%
        pivot_longer(cols = starts_with("Lag_"), names_to = "Lag", values_to = "Correlation")

      # Factor levels
      lag_levels <- paste0("Lag_", -4:0, "_", method)
      cor_table$Lag <- factor(cor_table$Lag, levels = lag_levels)
      cor_table$Series <- factor(cor_table$Series, levels = rev(series_order))

      # Factor levels for Lag
      cor_table$Lag <- gsub(paste0("_", method), "", cor_table$Lag)
      cor_table$Lag <- gsub("Lag_", "", cor_table$Lag)
      cor_table$Lag <- factor(cor_table$Lag, levels = as.character(-4:0))

      # Set factor levels for Series
      cor_table$Series <- factor(cor_table$Series, levels = rev(series_order))

      # Create plot
      p <- ggplot(cor_table, aes(x = Lag, y = Series, fill = Correlation)) +
        geom_tile(color = "white") +
        geom_text(aes(label = round(Correlation, 2)), color = "black", size = 5) +
        scale_fill_gradient2(low = "blue", mid = "white", high = "red", midpoint = 0,
                             limits = c(-1, 1), oob = squish) +
        theme_minimal() +
        theme(
          axis.text.x = element_text(size = 10),
          axis.text.y = element_text(size = 10),
          axis.title.y = element_blank(),
          legend.title = element_text(size = 10),
          legend.text = element_text(size = 8)
        ) +
        labs(
          title = paste("Correlation Heatmap with GDP -", freq, "(", method, ")"),
          x = "Lag", y = NULL, fill = "Corr"
        )

      # Save plot in list
      all_plots[[paste(freq, method, sep = "_")]] <- p
    }
  }

  # Arrange all 6 plots in a 2x3 grid
  heatmap_plot <- ggarrange(
    plotlist = all_plots,
    ncol = 2,
    nrow = 3,
    common.legend = TRUE,
    legend = "right"
  )

  ggsave(output_figure_path(output_file, figures_dir), heatmap_plot, width = 33, height = 44, units = "cm")

  invisible(heatmap_plot)
}


#' Suffix the lag columns of a table
#'
#' @noRd
#' @importFrom dplyr rename_with starts_with %>%
suffix_cols <- function(df, suffix) {
  df %>%
    rename_with(~ paste0(., "_", suffix), .cols = starts_with("Lag_"))
}
