# In-sample and out-of-sample evaluation tables for the analytics workflow.

#' Modified Diebold-Mariano test
#'
#' Diebold-Mariano test of equal predictive accuracy with the
#' Harvey-Leybourne-Newbold (1997) small-sample correction.
#'
#' @param e1,e2 Numeric vectors of forecast errors of the two models.
#' @param h Forecast horizon.
#' @param power Loss function power (2 = squared error, 1 = absolute).
#' @param alternative One of `"greater"`, `"less"`, `"two.sided"`.
#'
#' @return The p-value.
#'
#' @examples
#' set.seed(1)
#' dm_test_modified(rnorm(40) + 0.3, rnorm(40))
#'
#' @importFrom stats na.omit var pnorm
#' @export
dm_test_modified <- function(e1, e2, h = 1, power = 2, alternative = "greater") {
  d <- (abs(e1)^power - abs(e2)^power)  # loss differential
  d <- na.omit(d)
  n <- length(d)
  d_bar <- mean(d)
  gamma_0 <- var(d)

  # t-statistic (standard)
  DM_stat <- d_bar / sqrt(gamma_0 / n)

  # Harvey-Leybourne-Newbold correction (1997)
  HLN_factor <- sqrt((n + 1 - 2 * h + h * (h - 1) / n) / n)
  DM_modified <- DM_stat / HLN_factor

  # One-sided p-value
  pval <- switch(alternative,
                 "greater" = 1 - pnorm(DM_modified),
                 "less"    = pnorm(DM_modified),
                 "two.sided" = 2 * min(pnorm(DM_modified), 1 - pnorm(DM_modified)))

  return(pval)
}


#' In-sample fit metrics of the WAI and benchmarks against GDP
#'
#' Regresses GDP growth on each (quarterly-aggregated) series at lags -4
#' to 0 and reports RMSE, MAE and R-squared, plus Diebold-Mariano
#' p-values of each series against the WAI.
#'
#' @inheritParams get_combined_cor_table
#'
#' @return A list of wide tables: `RMSE`, `MAE`, `R2`, `PVAL_RMSE`,
#'   `PVAL_MAE`.
#'
#' @importFrom dplyr mutate group_by summarise ungroup select rename
#'   inner_join arrange bind_rows filter slice_max lead across where
#'   starts_with everything %>%
#' @importFrom tidyr nest unnest pivot_wider
#' @importFrom purrr map2 map_dfr
#' @importFrom tibble tibble
#' @importFrom lubridate floor_date
#' @importFrom broom glance
#' @importFrom Metrics rmse mae
#' @importFrom stats lm predict
#' @importFrom rlang .data
#' @examples
#' # A minimal `inputs` bundle. The real one is built by the scripts in
#' # analysis/5_plots/ from fitted models; this is the same shape with synthetic
#' # numbers, so the example runs and is checked rather than being a sketch.
#' insample_inputs <- mfbdfm_example_inputs()
#' fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = insample_inputs)
#' fit_tabs$RMSE
#' @export
get_insample_fit_table <- function(method = c("mean", "last", "last_month"),
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

  # --- Store WAI prediction errors for p-value comparisons
  wai_error_store <- list()

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
        summarise(monthly_mean = mean(value, na.rm = TRUE), .groups = "drop") %>%
        mutate(quarter = floor_date(month, unit = "quarter")) %>%
        group_by(Series, quarter) %>%
        slice_max(order_by = month, with_ties = FALSE) %>%
        ungroup() %>%
        rename(value = monthly_mean) %>%
        select(Series, quarter, value)
    }
  }

  # Build the in-sample comparison panel for either the WAI variants or the
  # benchmark indicators.
  if (analysis_set == "indicators") {
    plot_df_yoy <- bind_rows(
      tab_wai_yoy %>% mutate(Series = "WAI"),
      wwa_gr_df %>% mutate(Series = "SECO-WWA"),
      fcurve_gr_df %>% mutate(Series = "F-CURVE"),
      tab_kss %>% mutate(Series = "SECO-SEC"),
      tab_snb %>% mutate(Series = "SNB-BCI"),
      tab_baro %>% mutate(Series = "KOF-BARO")
    )
  } else {
    plot_df_yoy <- bind_rows(
      result_wai$tab_wai_yoy %>% mutate(Series = "WAI"),
      result_wai_no_sv$tab_wai_yoy %>% mutate(Series = "WAI-SV"),
      result_wai_only_monthly_no_sv$tab_wai_yoy %>% mutate(Series = "WAI-(SV+HF)"),
      result_wai_no_hf$tab_wai_yoy %>% mutate(Series = "WAI-HF"),
      result_wai_no_financial$tab_wai_yoy %>% mutate(Series = "WAI-FIN")
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

  base_wai_result <- list(
    tab_gr_qoq = tab_gr %>% select(time, name, value),
    tab_gr_lv = tab_gr_lv
  )
  tab_gr_qoq <- prepare_wai_qoq_series(base_wai_result, method)

  if (analysis_set == "indicators") {
    plot_df_qoq <- bind_rows(
      tab_gr_qoq %>% mutate(Series = "WAI"),
      wwa_gr_df_qoq %>% mutate(Series = "SECO-WWA"),
      fcurve_gr_df %>% mutate(Series = "F-CURVE"),
      tab_kss %>% mutate(Series = "SECO-SEC"),
      tab_snb %>% mutate(Series = "SNB-BCI"),
      tab_baro %>% mutate(Series = "KOF-BARO")
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

  # Lags
  lags <- -4:0

  compute_metrics <- function(df, target_var, frequency, series_name) {
    map_dfr(lags, function(l) {
      df_lag <- df %>%
        mutate(gdp_lag = lead(.data[[target_var]], n = -l)) %>%
        filter(!is.na(gdp_lag) & !is.na(series_value))

      if (nrow(df_lag) >= 12) {
        fit <- lm(gdp_lag ~ series_value, data = df_lag)
        preds <- predict(fit, df_lag)
        errors <- df_lag$gdp_lag - preds

        if (series_name == "WAI") {
          if (is.null(wai_error_store[[frequency]])) {
            wai_error_store[[frequency]] <- list()
          }
          wai_error_store[[frequency]][[as.character(l)]] <<- errors
        }

        p_dm_rmse <- NA_real_
        p_dm_mae  <- NA_real_

        if (series_name != "WAI" && !is.null(wai_error_store[[frequency]][[as.character(l)]])) {
          errors_wai <- wai_error_store[[frequency]][[as.character(l)]]
          n <- min(length(errors), length(errors_wai))
          e1 <- errors[1:n]
          e2 <- errors_wai[1:n]

          p_dm_rmse <- tryCatch({
            dm_test_modified(e1, e2, h = 1, power = 2, alternative = "greater")
          }, error = function(e) NA_real_)

          p_dm_mae <- tryCatch({
            dm_test_modified(e1, e2, h = 1, power = 1, alternative = "greater")
          }, error = function(e) NA_real_)
        }

        tibble(
          Lag = l,
          RMSE = rmse(df_lag$gdp_lag, preds),
          MAE = mae(df_lag$gdp_lag, preds),
          R2 = glance(fit)$r.squared,
          P_DM_RMSE = p_dm_rmse,
          P_DM_MAE = p_dm_mae
        )
      } else {
        tibble(
          Lag = l,
          RMSE = NA_real_, MAE = NA_real_, R2 = NA_real_,
          P_DM_RMSE = NA_real_, P_DM_MAE = NA_real_
        )
      }
    })
  }

  # --- Process WAI first ---
  wai_yoy <- joined_df_yoy %>% filter(Series == "WAI")
  other_yoy <- joined_df_yoy %>% filter(Series != "WAI")

  wai_qoq <- joined_df_qoq %>% filter(Series == "WAI")
  other_qoq <- joined_df_qoq %>% filter(Series != "WAI")

  fit_lag_results_yoy <- bind_rows(
    wai_yoy %>% group_by(Series) %>% nest() %>%
      mutate(metrics = map2(data, Series, ~ compute_metrics(.x, "GDP_yoy", "YoY", .y))) %>%
      select(-data) %>% unnest(metrics),
    other_yoy %>% group_by(Series) %>% nest() %>%
      mutate(metrics = map2(data, Series, ~ compute_metrics(.x, "GDP_yoy", "YoY", .y))) %>%
      select(-data) %>% unnest(metrics)
  )

  fit_lag_results_qoq <- bind_rows(
    wai_qoq %>% group_by(Series) %>% nest() %>%
      mutate(metrics = map2(data, Series, ~ compute_metrics(.x, "GDP_qoq", "QoQ", .y))) %>%
      select(-data) %>% unnest(metrics),
    other_qoq %>% group_by(Series) %>% nest() %>%
      mutate(metrics = map2(data, Series, ~ compute_metrics(.x, "GDP_qoq", "QoQ", .y))) %>%
      select(-data) %>% unnest(metrics)
  )

  fit_lag_results_yoy_wide <- fit_lag_results_yoy %>%
    pivot_wider(names_from = Lag, values_from = c(RMSE, MAE, R2, P_DM_RMSE, P_DM_MAE), names_glue = "{.value}_Lag_{Lag}") %>%
    mutate(Frequency = "YoY")

  fit_lag_results_qoq_wide <- fit_lag_results_qoq %>%
    pivot_wider(names_from = Lag, values_from = c(RMSE, MAE, R2, P_DM_RMSE, P_DM_MAE), names_glue = "{.value}_Lag_{Lag}") %>%
    mutate(Frequency = "QoQ")

  combined_table <- bind_rows(fit_lag_results_yoy_wide, fit_lag_results_qoq_wide)

  desired_order <- if (analysis_set == "indicators") {
    c("WAI", "SECO-WWA", "F-CURVE", "SECO-SEC", "SNB-BCI", "KOF-BARO")
  } else {
    c("WAI", "WAI-SV", "WAI-(SV+HF)", "WAI-HF", "WAI-FIN")
  }

  combined_table <- combined_table %>%
    mutate(
      Frequency = factor(Frequency, levels = c("QoQ", "YoY")),
      Series = factor(Series, levels = desired_order)
    ) %>%
    arrange(Frequency, Series)

  # Extract output tables
  rmse_table <- combined_table %>% select(Frequency, Series, starts_with("RMSE_Lag_"))
  mae_table  <- combined_table %>% select(Frequency, Series, starts_with("MAE_Lag_"))
  r2_table   <- combined_table %>% select(Frequency, Series, starts_with("R2_Lag_")) %>% mutate(across(where(is.numeric), ~ round(.x, 2))) %>% mutate(across(where(is.numeric), ~ sprintf("%.2f", .)))
  pval_rmse  <- combined_table %>% select(Frequency, Series, starts_with("P_DM_RMSE_Lag_"))
  pval_mae   <- combined_table %>% select(Frequency, Series, starts_with("P_DM_MAE_Lag_"))

  return(list(
    RMSE = rmse_table,
    MAE = mae_table,
    R2 = r2_table,
    PVAL_RMSE = pval_rmse,
    PVAL_MAE = pval_mae
  ))
}


#' Relative RMSE/MAE tables (normalized to the WAI)
#'
#' @param fit_tables Output of [get_insample_fit_table()].
#'
#' @return A list with `RMSE_relative` and `MAE_relative` wide tables.
#'
#' @importFrom dplyr ungroup filter select mutate left_join across where
#'   starts_with %>%
#' @importFrom tidyr pivot_longer pivot_wider
#' @examples
#' inputs <- mfbdfm_example_inputs()
#' fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
#' rel <- calculate_relative_errors(fit_tabs)
#' rel$RMSE_relative
#' @export
calculate_relative_errors <- function(fit_tables) {
  rmse_table <- fit_tables$RMSE %>% ungroup()
  mae_table  <- fit_tables$MAE %>% ungroup()

  # Pivot to long format
  rmse_long <- rmse_table %>%
    pivot_longer(cols = starts_with("RMSE_Lag_"), names_to = "Lag", values_to = "RMSE")

  mae_long <- mae_table %>%
    pivot_longer(cols = starts_with("MAE_Lag_"), names_to = "Lag", values_to = "MAE")

  # Confirm Series column exists
  if (!"Series" %in% names(rmse_long)) stop("Column 'Series' is missing from RMSE table")
  if (!"Series" %in% names(mae_long))  stop("Column 'Series' is missing from MAE table")

  # Extract WAI for normalization
  rmse_wai_long <- rmse_long %>%
    filter(Series == "WAI") %>%
    select(Frequency, Lag, RMSE_WAI = RMSE)

  mae_wai_long <- mae_long %>%
    filter(Series == "WAI") %>%
    select(Frequency, Lag, MAE_WAI = MAE)

  # Join and compute relative values
  rmse_relative <- rmse_long %>%
    left_join(rmse_wai_long, by = c("Frequency", "Lag")) %>%
    mutate(RMSE_relative = RMSE / RMSE_WAI) %>%
    select(Frequency, Series, Lag, RMSE_relative) %>%
    pivot_wider(names_from = Lag, values_from = RMSE_relative, names_prefix = "RMSE_rel_") %>%
    mutate(across(where(is.numeric), ~ round(.x, 2))) %>%
    mutate(across(where(is.numeric), ~ ifelse(is.na(.x), "", .x))) %>%
    mutate(across(where(is.numeric), ~ sprintf("%.2f", .)))

  mae_relative <- mae_long %>%
    left_join(mae_wai_long, by = c("Frequency", "Lag")) %>%
    mutate(MAE_relative = MAE / MAE_WAI) %>%
    select(Frequency, Series, Lag, MAE_relative) %>%
    pivot_wider(names_from = Lag, values_from = MAE_relative, names_prefix = "MAE_rel_") %>%
    mutate(across(where(is.numeric), ~ round(.x, 2))) %>%
    mutate(across(where(is.numeric), ~ ifelse(is.na(.x), "", .x))) %>%
    mutate(across(where(is.numeric), ~ sprintf("%.2f", .)))

  return(list(RMSE_relative = rmse_relative, MAE_relative = mae_relative))
}


#' Annotate relative error tables with significance stars
#'
#' @param rel_table Relative error table from [calculate_relative_errors()].
#' @param pval_table Matching p-value table from [get_insample_fit_table()].
#' @param metric_prefix `"RMSE"` or `"MAE"`.
#'
#' @return Wide table of annotated values.
#'
#' @importFrom dplyr mutate left_join select case_when starts_with %>%
#' @importFrom tidyr pivot_longer pivot_wider
#' @examples
#' inputs <- mfbdfm_example_inputs()
#' fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
#' rel <- calculate_relative_errors(fit_tabs)
#' annotate_relative_errors(rel$RMSE_relative, fit_tabs$PVAL_RMSE, "RMSE")
#' @export
annotate_relative_errors <- function(rel_table, pval_table, metric_prefix) {
  # Remove prefix to get lag names
  rel_long <- rel_table %>%
    pivot_longer(cols = starts_with(metric_prefix),
                 names_to = "Lag",
                 values_to = "Value")

  pval_long <- pval_table %>%
    pivot_longer(cols = starts_with(paste0("P_DM_", metric_prefix)),
                 names_to = "Lag",
                 values_to = "PValue")

  # Normalize Lag names
  rel_long <- rel_long %>%
    mutate(Lag = gsub(".*Lag_", "", Lag))

  pval_long <- pval_long %>%
    mutate(Lag = gsub(".*Lag_", "", Lag))

  # Join and annotate
  annotated <- rel_long %>%
    left_join(pval_long, by = c("Frequency", "Series", "Lag")) %>%
    mutate(
      Stars = case_when(
        is.na(PValue)       ~ "",
        PValue < 0.01       ~ "***",
        PValue < 0.05       ~ "**",
        PValue < 0.10       ~ "*",
        TRUE                ~ ""
      ),
      Annotated = paste0(Value, Stars)
    ) %>%
    select(Frequency, Series, Lag, Annotated) %>%
    pivot_wider(names_from = Lag, values_from = Annotated,
                names_prefix = paste0(metric_prefix, "_rel_"))

  return(annotated)
}


#' Combine per-method lag tables into one LaTeX table
#'
#' @param combined_tables_list Named list of lag tables (one per
#'   aggregation method), e.g. from [get_combined_cor_table()].
#' @param caption LaTeX table caption.
#' @param include_period If `TRUE`, keep a `Period` column.
#' @param measure_label_map Named character vector mapping method names
#'   to LaTeX section labels.
#'
#' @return A list with `combined_wide` (the assembled data frame) and
#'   `table_tex` (the LaTeX code).
#'
#' @importFrom dplyr mutate select filter bind_rows rename_with ungroup
#'   across everything all_of any_of starts_with %>%
#' @importFrom knitr kable
#' @importFrom kableExtra add_header_above kable_styling row_spec column_spec
#' @examples
#' inputs <- mfbdfm_example_inputs()
#' cor_tab <- get_combined_cor_table("mean", "indicators", inputs = inputs)
#' out <- create_combined_latex_table(list(mean = cor_tab))
#' cat(substr(out$table_tex, 1, 300))
#' @export
create_combined_latex_table <- function(combined_tables_list,
                                        caption = "Cross Correlation with GDP for Different Lags and Aggregation Methods",
                                        include_period = FALSE,
                                        measure_label_map = NULL) {

  normalize_table <- function(tbl) {
    lag_cols <- grep(".*_-?[0-9]+$", names(tbl), value = TRUE)
    lag_numbers <- suppressWarnings(as.numeric(sub("^.*_(-?[0-9]+)$", "\\1", lag_cols)))
    lag_cols <- lag_cols[!is.na(lag_numbers)]
    lag_numbers <- lag_numbers[!is.na(lag_numbers)]
    lag_cols <- lag_cols[order(lag_numbers)]

    tbl <- tbl %>%
      rename_with(~ paste0("Lag_", sub("^.*_(-?[0-9]+)$", "\\1", .x)), .cols = all_of(lag_cols))

    if (include_period && "Period" %in% names(tbl)) {
      tbl %>% select(Period, Frequency, Series, starts_with("Lag_"))
    } else {
      tbl %>% select(Frequency, Series, starts_with("Lag_"))
    }
  }

  combined_tables_list <- lapply(combined_tables_list, normalize_table)

  if (is.null(measure_label_map)) {
    measure_label_map <- c(
      mean = "\\textbf{Mean}",
      last = "\\textbf{Last}",
      last_month = "\\textbf{Last Month}",
      lastmonth = "\\textbf{Last Month}"
    )
  }

  measure_names <- names(combined_tables_list)
  if (is.null(measure_names) || any(measure_names == "")) {
    stop("combined_tables_list must be a named list.")
  }

  # 1. Add measure labels
  combined_tables_list <- Map(function(tbl, measure_name) {
    tbl$Measure <- measure_name
    tbl
  }, combined_tables_list, measure_names)

  # 2. Reorder columns
  first_table <- combined_tables_list[[1]]
  cols <- c(if (include_period && "Period" %in% names(first_table)) "Period",
            "Frequency", "Measure", "Series", "Lag_-4", "Lag_-3", "Lag_-2", "Lag_-1", "Lag_0")
  combined_tables_list <- lapply(combined_tables_list, function(tbl) tbl[, cols])

  # 3. Combine long-format tables
  combined_table2 <- bind_rows(combined_tables_list)
  combined_table2 <- combined_table2[order(combined_table2$Frequency), ]

  # 4. Helper: rename lag columns with suffix
  suffix_cols <- function(df, suffix) {
    df %>%
      rename_with(~ paste0(., "_", suffix), .cols = starts_with("Lag_"))
  }

  # 5. Split and widen
  df_qoq <- combined_table2 %>%
    filter(Frequency == "QoQ") %>%
    suffix_cols("QoQ")

  df_yoy <- combined_table2 %>%
    filter(Frequency == "YoY") %>%
    suffix_cols("YoY")

  qoq_drop_cols <- c("Series", "Frequency", "Measure")
  if (include_period && "Period" %in% names(df_qoq)) {
    qoq_drop_cols <- c(qoq_drop_cols, "Period")
  }

  combined_wide <- cbind(
    df_yoy,
    df_qoq %>% ungroup() %>% select(-all_of(qoq_drop_cols))
  )

  empty_row <- function(label) {
    combined_wide[1, , drop = FALSE] %>%
      mutate(across(everything(), ~NA)) %>%
      mutate(Series = label, Frequency = NA)
  }

  get_measure_label <- function(method_name) {
    label <- measure_label_map[[method_name]]
    if (is.null(label) || is.na(label) || label == "") {
      paste0("\\textbf{", method_name, "}")
    } else {
      unname(label)
    }
  }

  ordered_measures <- unique(measure_names)
  present_methods <- ordered_measures[ordered_measures %in% unique(combined_wide$Measure)]
  combined_with_labels <- bind_rows(lapply(present_methods, function(method_name) {
    bind_rows(
      empty_row(get_measure_label(method_name)),
      combined_wide %>% filter(Measure == method_name)
    )
  }))

  # 8. Clean table
  combined_table_clean <- combined_with_labels %>%
    ungroup() %>%
    select(-any_of(c("Frequency", "Measure"))) %>%
    mutate(across(everything(), as.character)) %>%
    mutate(across(everything(), ~ ifelse(is.na(.), "", .)))

  section_labels <- vapply(present_methods, get_measure_label, character(1))
  section_rows <- which(combined_table_clean$Series %in% section_labels)
  add_lines <- list(pos = section_rows - 1, command = rep("\\midrule\n", length(section_rows)))

  # 9. Generate LaTeX table
  table_tex <- kable(
    combined_table_clean,
    format = "latex",
    booktabs = TRUE,
    escape = FALSE,
    col.names = if (include_period && "Period" %in% names(combined_table_clean)) {
      c("Period", "Lags", rep(c("-4", "-3", "-2", "-1", "0"), 2))
    } else {
      c("Lags", rep(c("-4", "-3", "-2", "-1", "0"), 2))
    },
    align = if (include_period && "Period" %in% names(combined_table_clean)) "llrrrrrrrrrr" else "lrrrrrrrrrr",
    caption = caption,
    add.to.row = add_lines
  ) %>%
    add_header_above(if (include_period && "Period" %in% names(combined_table_clean)) {
      c(" " = 2, "YoY" = 5, "QoQ" = 5)
    } else {
      c(" " = 1, "YoY" = 5, "QoQ" = 5)
    }) %>%
    kable_styling(latex_options = "hold_position", full_width = TRUE) %>%
    row_spec(section_rows, bold = TRUE) %>%
    column_spec(1, width = "2.3cm") %>%
    column_spec(if (include_period && "Period" %in% names(combined_table_clean)) 2:12 else 2:11, width = "0.9cm")

  # Remove auto-added addlinespace
  table_tex <- gsub("\\\\addlinespace\n?", "", table_tex)

  return(list(combined_wide = combined_wide, table_tex = table_tex))
}


#' Print the evaluation period per series
#'
#' @param data Data frame with a series and a date column.
#' @param series_col,date_col Column names.
#' @param context_label Label printed above the summary.
#' @param frequency_label,method_label Optional annotation columns.
#'
#' @return Invisibly, the period summary data frame.
#'
#' @importFrom dplyr filter group_by summarise mutate %>%
#' @importFrom zoo as.yearqtr
#' @importFrom rlang .data
#' @examples
#' df <- data.frame(Series = "WAI",
#'                  date = seq(as.Date("2010-01-01"), by = "quarter", length.out = 8))
#' print_evaluation_periods(df, "Series", "date", context_label = "example")
#' @export
print_evaluation_periods <- function(data, series_col, date_col, context_label, frequency_label = NULL, method_label = NULL) {
  if (is.null(data) || nrow(data) == 0) {
    return(invisible(NULL))
  }

  period_summary <- data %>%
    filter(!is.na(.data[[series_col]]), !is.na(.data[[date_col]])) %>%
    group_by(Series = .data[[series_col]]) %>%
    summarise(
      start_quarter = as.character(as.yearqtr(min(.data[[date_col]], na.rm = TRUE))),
      end_quarter = as.character(as.yearqtr(max(.data[[date_col]], na.rm = TRUE))),
      .groups = "drop"
    )

  if (!is.null(frequency_label)) {
    period_summary <- period_summary %>%
      mutate(Frequency = frequency_label, .before = start_quarter)
  }

  if (!is.null(method_label)) {
    period_summary <- period_summary %>%
      mutate(Method = method_label, .before = start_quarter)
  }

  message("")
  message(paste0("Evaluation periods: ", context_label))
  print(period_summary, row.names = FALSE)

  invisible(period_summary)
}


#' Error summary tables with crisis/non-crisis split
#'
#' Aggregates in-sample error details, computes RMSE/MAE per model with
#' Diebold-Mariano tests against the WAI, and returns annotated relative
#' and absolute error tables per aggregation method.
#'
#' @param error_data Long error table from [get_insample_error_details()].
#' @param model_order Character vector of models in display order.
#' @param date_col Name of the date column (e.g. `"observation_date"`).
#' @param lag_range Integer lags covered.
#' @param include_period If `TRUE`, split by crisis/non-crisis periods.
#'
#' @return A list: `rel_rmse`, `rel_mae`, `abs_rmse`, `abs_mae` (each a
#'   per-method list of tables) and `summary`.
#'
#' @importFrom dplyr mutate group_by summarise ungroup filter select
#'   arrange left_join bind_rows case_when across all_of group_map pull %>%
#' @importFrom tidyr pivot_wider
#' @importFrom purrr map
#' @importFrom rlang .data
#' @examples
#' inputs <- mfbdfm_example_inputs()
#' details <- get_insample_error_details("mean", "indicators", inputs = inputs)
#' tabs <- create_error_summary_tables(details,
#'                                     model_order = c("WAI", "KOF-BARO"),
#'                                     date_col = "observation_date")
#' names(tabs)
#' @export
create_error_summary_tables <- function(error_data, model_order, date_col, lag_range = -4:0, include_period = FALSE) {

  rmse_rel_cols <- paste0("RMSE_rel_", lag_range)
  mae_rel_cols <- paste0("MAE_rel_", lag_range)
  rmse_abs_cols <- paste0("RMSE_", lag_range)
  mae_abs_cols <- paste0("MAE_", lag_range)

  aggregated_errors <- error_data %>%
    mutate(
      Period = ifelse(is_crisis_period(.data[[date_col]]), "Crisis Periods", "Non-Crisis Periods")
    ) %>%
    group_by(.data[[date_col]], Period, model, method, lag_number, frequency) %>%
    summarise(error = mean(error, na.rm = TRUE), .groups = "drop")

  grouping_vars <- c("method", "lag_number", "frequency")
  if (include_period) grouping_vars <- c(grouping_vars, "Period")

  dm_summary <- aggregated_errors %>%
    group_by(across(all_of(grouping_vars))) %>%
    group_map(~ {
      group_data <- .x
      group_keys <- .y

      errors_wai <- group_data %>%
        filter(model == "WAI") %>%
        arrange(.data[[date_col]]) %>%
        pull(error)

      if (length(errors_wai) == 0) return(NULL)

      all_models_stats <- group_data %>%
        group_by(model) %>%
        summarise(
          RMSE = sqrt(mean(error^2, na.rm = TRUE)),
          MAE = mean(abs(error), na.rm = TRUE),
          .groups = "drop"
        )

      dm_results <- group_data %>%
        filter(model != "WAI") %>%
        group_by(model) %>%
        arrange(.data[[date_col]], .by_group = TRUE) %>%
        summarise(
          p_dm_rmse = {
            e1 <- error
            n <- min(length(e1), length(errors_wai))
            e1 <- e1[1:n]
            e2 <- errors_wai[1:n]
            tryCatch(dm_test_modified(e1, e2, h = 1, power = 2, alternative = "greater"), error = function(e) NA_real_)
          },
          p_dm_mae = {
            e1 <- error
            n <- min(length(e1), length(errors_wai))
            e1 <- e1[1:n]
            e2 <- errors_wai[1:n]
            tryCatch(dm_test_modified(e1, e2, h = 1, power = 1, alternative = "greater"), error = function(e) NA_real_)
          },
          .groups = "drop"
        )

      out <- all_models_stats %>%
        left_join(dm_results, by = "model") %>%
        mutate(
          method = group_keys$method,
          lag_number = group_keys$lag_number,
          frequency = group_keys$frequency
        )
      if (include_period) out$Period <- group_keys$Period
      out
    }) %>%
    bind_rows() %>%
    group_by(across(all_of(grouping_vars))) %>%
    mutate(
      RMSE_WAI = RMSE[model == "WAI"],
      MAE_WAI = MAE[model == "WAI"],
      rel_RMSE = RMSE / RMSE_WAI,
      rel_MAE = MAE / MAE_WAI
    ) %>%
    ungroup() %>%
    mutate(
      Stars_RMSE = case_when(
        is.na(p_dm_rmse) ~ "",
        p_dm_rmse < 0.01 ~ "***",
        p_dm_rmse < 0.05 ~ "**",
        p_dm_rmse < 0.10 ~ "*",
        TRUE ~ ""
      ),
      Stars_MAE = case_when(
        is.na(p_dm_mae) ~ "",
        p_dm_mae < 0.01 ~ "***",
        p_dm_mae < 0.05 ~ "**",
        p_dm_mae < 0.10 ~ "*",
        TRUE ~ ""
      ),
      RMSE_rel_annotated = paste0(formatC(rel_RMSE, format = "f", digits = 2), Stars_RMSE),
      MAE_rel_annotated = paste0(formatC(rel_MAE, format = "f", digits = 2), Stars_MAE),
      RMSE_abs_annotated = paste0(formatC(RMSE, format = "f", digits = 2), Stars_RMSE),
      MAE_abs_annotated = paste0(formatC(MAE, format = "f", digits = 2), Stars_MAE)
    )

  build_metric_list <- function(summary_df, annotated_col, lag_prefix, expected_cols) {
    summary_df %>%
      filter(model %in% model_order) %>%
      split(.$method) %>%
      map(~ {
        table_data <- .x %>%
          mutate(
            Frequency = factor(frequency, levels = c("QoQ", "YoY")),
            Series = factor(model, levels = model_order),
            lag_number = ifelse(lag_number > 0, -lag_number, lag_number),
            lag_label = paste0(lag_prefix, lag_number)
          )

        if (include_period) {
          table_data <- table_data %>%
            mutate(Period = factor(Period, levels = c("Non-Crisis Periods", "Crisis Periods"))) %>%
            select(Period, Frequency, Series, lag_label, value = all_of(annotated_col)) %>%
            pivot_wider(names_from = lag_label, values_from = value) %>%
            select(Period, Frequency, Series, all_of(expected_cols)) %>%
            arrange(Period, Frequency, Series)
        } else {
          table_data <- table_data %>%
            select(Frequency, Series, lag_label, value = all_of(annotated_col)) %>%
            pivot_wider(names_from = lag_label, values_from = value) %>%
            select(Frequency, Series, all_of(expected_cols)) %>%
            arrange(Frequency, Series)
        }

        table_data
      })
  }

  list(
    rel_rmse = build_metric_list(dm_summary, "RMSE_rel_annotated", "RMSE_rel_", rmse_rel_cols),
    rel_mae = build_metric_list(dm_summary, "MAE_rel_annotated", "MAE_rel_", mae_rel_cols),
    abs_rmse = build_metric_list(dm_summary, "RMSE_abs_annotated", "RMSE_", rmse_abs_cols),
    abs_mae = build_metric_list(dm_summary, "MAE_abs_annotated", "MAE_", mae_abs_cols),
    summary = dm_summary
  )
}


#' Per-observation in-sample errors of each series against GDP
#'
#' Runs the lag regressions of [get_insample_fit_table()] but returns the
#' full error series per observation date, model, method, lag and
#' frequency, for use in [create_error_summary_tables()].
#'
#' @inheritParams get_combined_cor_table
#'
#' @return A long data frame with columns `observation_date`, `error`,
#'   `model`, `method`, `lag_number`, `frequency`.
#'
#' @importFrom dplyr mutate group_by summarise ungroup select rename
#'   inner_join arrange bind_rows filter slice_max lead %>%
#' @importFrom tidyr nest unnest
#' @importFrom purrr map2 map_dfr
#' @importFrom tibble tibble
#' @importFrom lubridate floor_date
#' @importFrom stats lm predict
#' @importFrom rlang .data
#' @examples
#' # Same synthetic `inputs` bundle as [get_insample_fit_table()]; see there for
#' # what the real one is built from.
#' insample_inputs <- mfbdfm_example_inputs()
#' details <- get_insample_error_details("mean", "indicators", inputs = insample_inputs)
#' head(details)
#' @export
get_insample_error_details <- function(method = c("mean", "last", "last_month"),
                                       analysis_set = c("wai_versions", "indicators"),
                                       inputs) {
  method <- match.arg(method)
  analysis_set <- match.arg(analysis_set)

  required_inputs <- c(
    "x_hist_gr_yoy", "x_hist_gr_ann",
    if (analysis_set == "indicators") {
      c("tab_gr", "tab_gr_lv", "tab_wai_yoy", "wwa_gr_df", "wwa_gr_df_qoq",
        "fcurve_gr_df", "tab_kss", "tab_snb", "tab_baro")
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
    } else {
      df %>%
        mutate(month = floor_date(time, unit = "month")) %>%
        group_by(Series, month) %>%
        summarise(monthly_mean = mean(value, na.rm = TRUE), .groups = "drop") %>%
        mutate(quarter = floor_date(month, unit = "quarter")) %>%
        group_by(Series, quarter) %>%
        slice_max(order_by = month, with_ties = FALSE) %>%
        ungroup() %>%
        rename(value = monthly_mean) %>%
        select(Series, quarter, value)
    }
  }

  if (analysis_set == "indicators") {
    base_wai_result <- list(
      tab_gr_qoq = tab_gr %>% select(time, name, value),
      tab_gr_lv = tab_gr_lv
    )
    plot_df_yoy <- bind_rows(
      tab_wai_yoy %>% mutate(Series = "WAI"),
      wwa_gr_df %>% mutate(Series = "SECO-WWA"),
      fcurve_gr_df %>% mutate(Series = "F-CURVE"),
      tab_kss %>% mutate(Series = "SECO-SEC"),
      tab_snb %>% mutate(Series = "SNB-BCI"),
      tab_baro %>% mutate(Series = "KOF-BARO")
    )

    plot_df_qoq <- bind_rows(
      prepare_wai_qoq_series(base_wai_result, method) %>% mutate(Series = "WAI"),
      wwa_gr_df_qoq %>% mutate(Series = "SECO-WWA"),
      fcurve_gr_df %>% mutate(Series = "F-CURVE"),
      tab_kss %>% mutate(Series = "SECO-SEC"),
      tab_snb %>% mutate(Series = "SNB-BCI"),
      tab_baro %>% mutate(Series = "KOF-BARO")
    )
  } else {
    plot_df_yoy <- bind_rows(
      result_wai$tab_wai_yoy %>% mutate(Series = "WAI"),
      result_wai_no_sv$tab_wai_yoy %>% mutate(Series = "WAI-SV"),
      result_wai_only_monthly_no_sv$tab_wai_yoy %>% mutate(Series = "WAI-(SV+HF)"),
      result_wai_no_hf$tab_wai_yoy %>% mutate(Series = "WAI-HF"),
      result_wai_no_financial$tab_wai_yoy %>% mutate(Series = "WAI-FIN")
    )

    plot_df_qoq <- bind_rows(
      prepare_wai_qoq_series(result_wai, method) %>% mutate(Series = "WAI"),
      prepare_wai_qoq_series(result_wai_no_sv, method) %>% mutate(Series = "WAI-SV"),
      prepare_wai_qoq_series(result_wai_only_monthly_no_sv, method) %>% mutate(Series = "WAI-(SV+HF)"),
      prepare_wai_qoq_series(result_wai_no_hf, method) %>% mutate(Series = "WAI-HF"),
      prepare_wai_qoq_series(result_wai_no_financial, method) %>% mutate(Series = "WAI-FIN")
    )
  }

  joined_df_yoy <- aggregate_to_quarter(plot_df_yoy) %>%
    rename(date = quarter, series_value = value) %>%
    inner_join(
      tibble(date = seq.Date(as.Date("1991-01-01"), by = "3 months", length.out = length(x_hist_gr_yoy)),
             GDP_yoy = as.numeric(x_hist_gr_yoy)),
      by = "date"
    )

  print_evaluation_periods(
    joined_df_yoy,
    series_col = "Series",
    date_col = "date",
    context_label = paste("In-sample error evaluation,", analysis_set, "YoY"),
    frequency_label = "YoY",
    method_label = method
  )

  joined_df_qoq <- aggregate_to_quarter(plot_df_qoq) %>%
    rename(date = quarter, series_value = value) %>%
    inner_join(
      tibble(date = seq.Date(as.Date("1990-01-01"), by = "3 months", length.out = length(x_hist_gr_ann)),
             GDP_qoq = as.numeric(x_hist_gr_ann)),
      by = "date"
    )

  print_evaluation_periods(
    joined_df_qoq,
    series_col = "Series",
    date_col = "date",
    context_label = paste("In-sample error evaluation,", analysis_set, "QoQ"),
    frequency_label = "QoQ",
    method_label = method
  )

  collect_errors <- function(df, target_var, frequency) {
    df %>%
      group_by(Series) %>%
      nest() %>%
      mutate(details = map2(data, Series, ~ {
        map_dfr(-4:0, function(l) {
          df_lag <- .x %>%
            arrange(date) %>%
            mutate(gdp_lag = lead(.data[[target_var]], n = -l)) %>%
            filter(!is.na(gdp_lag) & !is.na(series_value))
          tibble(
            observation_date = df_lag$date,
            error = df_lag$gdp_lag - predict(lm(gdp_lag ~ series_value, data = df_lag), df_lag),
            model = .y,
            method = method,
            lag_number = l,
            frequency = frequency
          )
        })
      })) %>%
      select(details) %>%
      unnest(details)
  }

  bind_rows(
    collect_errors(joined_df_yoy, "GDP_yoy", "YoY"),
    collect_errors(joined_df_qoq, "GDP_qoq", "QoQ")
  )
}


#' Relative out-of-sample error tables across vintages
#'
#' Aggregates out-of-sample errors per target vintage, computes relative
#' RMSE/MAE against the WAI with Diebold-Mariano significance stars, and
#' returns per-method wide tables.
#'
#' @param combined_results Long data frame of out-of-sample errors with
#'   columns `target_vintage`, `model`, `method`, `lag_number`,
#'   `GDP_type`, `frequency`, `error`.
#' @param model_order Character vector of models in display order.
#' @param lag_range Integer lags covered.
#'
#' @return A list with `rel_rmse` and `rel_mae` (per-method lists).
#'
#' @importFrom dplyr mutate group_by summarise ungroup filter select
#'   arrange left_join bind_rows case_when across where all_of group_map
#'   pull everything %>%
#' @importFrom tidyr pivot_wider
#' @importFrom purrr map
#' @examples
#' # `combined_results` is the long out-of-sample error table that
#' # analysis/5_plots/analytics_out-of-sample.R builds; this is the same shape.
#' set.seed(1)
#' combined_results <- expand.grid(
#'   target_vintage = seq(2015, 2019.75, by = 0.25),
#'   model = c("WAI", "AR"), method = "mean", lag_number = -4:0,
#'   GDP_type = "ssa", frequency = "QoQ", stringsAsFactors = FALSE)
#' combined_results$error <- rnorm(nrow(combined_results), 0, 0.5)
#'
#' rel <- create_rel_error_tables(combined_results, model_order = c("WAI", "AR"))
#' rel$rel_rmse
#' @export
create_rel_error_tables <- function(combined_results, model_order, lag_range = -4:0) {

   rmse_cols <- paste0("RMSE_rel_", lag_range)
   mae_cols  <- paste0("MAE_rel_", lag_range)

   # Step 1: Aggregate errors
   aggregated_errors <- combined_results %>%
     group_by(target_vintage, model, method, lag_number, GDP_type, frequency) %>%
     summarise(
       error = mean(error, na.rm = TRUE),
       .groups = "drop"
     )

   # Step 2: Compute summary stats with DM tests
   dm_summary <- aggregated_errors %>%
     group_by(method, lag_number, frequency) %>%
     group_map(~ {
       group_data <- .x
       group_keys <- .y

       errors_wai <- group_data %>%
         filter(model == "WAI") %>%
         pull(error)

       if (length(errors_wai) == 0) return(NULL)

       all_models_stats <- group_data %>%
         group_by(model) %>%
         summarise(
           RMSE = sqrt(mean(error^2, na.rm = TRUE)),
           MAE = mean(abs(error), na.rm = TRUE),
           .groups = "drop"
         )

       dm_results <- group_data %>%
         filter(model != "WAI") %>%
         group_by(model) %>%
         summarise(
           p_dm_rmse = {
             e1 <- error
             n <- min(length(e1), length(errors_wai))
             e1 <- e1[1:n]
             e2 <- errors_wai[1:n]
             tryCatch(dm_test_modified(e1, e2, h = 1, power = 2, alternative = "greater"), error = function(e) NA_real_)
           },
           p_dm_mae = {
             e1 <- error
             n <- min(length(e1), length(errors_wai))
             e1 <- e1[1:n]
             e2 <- errors_wai[1:n]
             tryCatch(dm_test_modified(e1, e2, h = 1, power = 1, alternative = "greater"), error = function(e) NA_real_)
           },
           .groups = "drop"
         )

       full_stats <- all_models_stats %>%
         left_join(dm_results, by = "model") %>%
         mutate(
           method = group_keys$method,
           lag_number = group_keys$lag_number,
           frequency = group_keys$frequency
         ) %>%
         select(method, model, lag_number, frequency, everything())
     }) %>%
     bind_rows()

   # Step 3: Relative RMSE/MAE
   dm_summary <- dm_summary %>%
     group_by(method, lag_number, frequency) %>%
     mutate(
       RMSE_WAI = RMSE[model == "WAI"],
       MAE_WAI = MAE[model == "WAI"],
       rel_RMSE = RMSE / RMSE_WAI,
       rel_MAE = MAE / MAE_WAI
     ) %>%
     mutate(across(where(is.numeric), ~ round(.x, 2))) %>%
     ungroup() %>%
     select(-RMSE_WAI, -MAE_WAI)

   # Step 4: Significance stars and annotation
   dm_summary <- dm_summary %>%
     mutate(
       Stars_RMSE = case_when(
         is.na(p_dm_rmse) ~ "",
         p_dm_rmse < 0.01 ~ "***",
         p_dm_rmse < 0.05 ~ "**",
         p_dm_rmse < 0.10 ~ "*",
         TRUE             ~ ""
       ),
       Stars_MAE = case_when(
         is.na(p_dm_mae) ~ "",
         p_dm_mae < 0.01 ~ "***",
         p_dm_mae < 0.05 ~ "**",
         p_dm_mae < 0.10 ~ "*",
         TRUE            ~ ""
       ),
       RMSE_annotated = paste0(formatC(rel_RMSE, format = "f", digits = 2), Stars_RMSE),
       MAE_annotated  = paste0(formatC(rel_MAE,  format = "f", digits = 2), Stars_MAE)
     )

   # Step 5: Create RMSE tables
   rel_rmse_list <- dm_summary %>%
     filter(model %in% model_order) %>%
     split(.$method) %>%
     map(~ {
       .x %>%
         mutate(
           Frequency = factor(frequency, levels = c("QoQ", "YoY")),
           Series = factor(model, levels = model_order),
           lag_number = ifelse(lag_number > 0, -lag_number, lag_number),
           lag_label = paste0("RMSE_rel_", lag_number)
         ) %>%
         select(Frequency, Series, lag_label, RMSE_annotated) %>%
         pivot_wider(names_from = lag_label, values_from = RMSE_annotated) %>%
         select(Frequency, Series, all_of(rmse_cols)) %>%
         arrange(Frequency, Series)
     })

   # Step 6: Create MAE tables
   rel_mae_list <- dm_summary %>%
     filter(model %in% model_order) %>%
     split(.$method) %>%
     map(~ {
       .x %>%
         mutate(
           Frequency = factor(frequency, levels = c("QoQ", "YoY")),
           Series = factor(model, levels = model_order),
           lag_number = ifelse(lag_number > 0, -lag_number, lag_number),
           lag_label = paste0("MAE_rel_", lag_number)
         ) %>%
         select(Frequency, Series, lag_label, MAE_annotated) %>%
         pivot_wider(names_from = lag_label, values_from = MAE_annotated) %>%
         select(Frequency, Series, all_of(mae_cols)) %>%
         arrange(Frequency, Series)
     })

   # Return both lists
   list(rel_rmse = rel_rmse_list, rel_mae = rel_mae_list)
 }
