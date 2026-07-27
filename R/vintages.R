#' Read the real-time GDP vintage database
#'
#' Reads the Swiss real-time GDP vintage database and returns a table
#' of GDP growth vintages: one column per publication vintage (named by
#' its decimal publication date, rounded to a 48th of a year), one row
#' per quarter. Pre-2018Q3 vintages are taken from `gdp_file_path`,
#' later ones from `gdp_cssa_file_path`.
#'
#' @param output_type Character, `"quarterly"` for quarter-on-quarter log
#'   differences or `"annual"` for year-on-year growth rates.
#' @param gdp_file_path Path to the pre-2018Q3 vintage CSV. Defaults to
#'   the file shipped with the package.
#' @param gdp_cssa_file_path Path to the 2018Q3-onward vintage CSV.
#'   Defaults to the file shipped with the package.
#'
#' @return A data frame with a `time` column (Date, quarter start) and
#'   one numeric column per vintage.
#'
#' @examples
#' \donttest{
#' vintages <- get_real_time_gdp_vintages("quarterly")
#' vintages[1:5, 1:3]
#' }
#'
#' @export
get_real_time_gdp_vintages <- function(output_type,
                                       gdp_file_path = system.file("extdata",
                                                                   "realtime_gdp.csv",
                                                                   package = "mfbdfm"),
                                       gdp_cssa_file_path = system.file("extdata",
                                                                        "realtime_gdp_cssa.csv",
                                                                        package = "mfbdfm")){

  # Usage
  gdp_cssa_info <- read_sheet_info(gdp_cssa_file_path, has_dates = FALSE)
  gdp_info <- read_sheet_info(gdp_file_path, has_dates = TRUE)

  # Step 1: Find position of "2018q3"
  pos_2018q3 <- which(names(gdp_cssa_info$data) == "2018q3")

  # Step 2: Select columns from both lists
  # Before "2018q3" -> from gdp_info$data
  columns_before_2018q3 <- names(gdp_cssa_info$data)[1:(pos_2018q3 - 1)]
  before_2018q3_from_info <- gdp_info$data[, columns_before_2018q3, drop = FALSE]

  # From "2018q3" onward -> from gdp_cssa_info$data
  columns_from_2018q3 <- names(gdp_cssa_info$data)[pos_2018q3:length(names(gdp_cssa_info$data))]
  from_2018q3_from_cssa <- gdp_cssa_info$data[, columns_from_2018q3, drop = FALSE]

  # Step 3: Combine both parts
  combined_list <- cbind(before_2018q3_from_info, from_2018q3_from_cssa)

  GDP_gr_vintages <- combined_list

  if (output_type == "quarterly") {
    # Apply log difference to each numeric column except 'time'
    GDP_gr_vintages[ , -1] <- apply(combined_list[ , -1], 2, function(x) c(NA, diff(log(x))))
  } else if (output_type == "annual") {
    # Apply year-on-year growth rates to each numeric column except 'time'
    GDP_gr_vintages[ , -1] <- apply(combined_list[ , -1], 2, function(x) c(rep(NA, 4), x[5:length(x)] / x[1:(length(x) - 4)] - 1))
  }

  # Convert time column to Date class
  GDP_gr_vintages$time <- as.Date(GDP_gr_vintages$time)

  # Filter rows between 1990-01-01 and 2025-12-31
  GDP_gr_vintages <- GDP_gr_vintages[GDP_gr_vintages$time >= as.Date("1990-01-01") &
                                       GDP_gr_vintages$time <= as.Date("2025-12-31"), ]

  dates <- as.Date(gdp_info$dates, format = "%d.%m.%Y")

  # Calculate continuous time format
  date_vec_names <- plyr::round_any(
    x = as.numeric(format(dates, "%Y")) +
      (as.numeric(format(dates, "%m")) - 1) / 12 +
      as.numeric(format(dates, "%d")) / 365,
    accuracy = 1/48,
    f = ceiling
  )

  # Convert names (excluding 'time') to numeric and round
  date_vec_names <- round(as.numeric(date_vec_names), 3)

  names(GDP_gr_vintages) <- c("time", date_vec_names)

  return(GDP_gr_vintages)

}


#' Read one sheet of the vintage database from its CSV export
#'
#' Each CSV mirrors the layout of the original spreadsheet sheet it was
#' exported from: an optional leading row of publication dates (one blank
#' placeholder for the `time` column, then one date per vintage column),
#' a row of column titles, then the data rows. `gdp_cssa`'s dates row is
#' omitted since it's never used downstream (only `gdp`'s dates feed
#' [get_real_time_gdp_vintages()]'s vintage-name calculation).
#'
#' @param file_path Path to the CSV file.
#' @param has_dates Logical, whether the file has a leading dates row.
#' @noRd
read_sheet_info <- function(file_path, has_dates) {
  raw <- utils::read.csv(file_path, header = FALSE, colClasses = "character",
                          check.names = FALSE)

  if (has_dates) {
    dates_vector <- as.character(raw[1, -1])
    titles_row <- 2
  } else {
    dates_vector <- NULL
    titles_row <- 1
  }

  column_titles <- as.character(raw[titles_row, ])
  data <- raw[(titles_row + 1):nrow(raw), , drop = FALSE]
  names(data) <- column_titles
  data[-1] <- lapply(data[-1], function(x) suppressWarnings(as.numeric(x)))

  list(
    column_titles = column_titles,
    dates = dates_vector,
    data = data
  )
}


#' Select the newest GDP vintage available at a given date
#'
#' @param current_date Numeric (decimal time), the evaluation date.
#' @param GDP_gr_vintages Vintage table from [get_real_time_gdp_vintages()].
#'
#' @return The selected vintage column (numeric vector).
#' @examples
#' \donttest{
#' vintages <- get_real_time_gdp_vintages("quarterly")
#' v <- select_most_recent_GDP_vintage(2024.5, vintages)
#' utils::tail(stats::na.omit(v))
#' }
#' @export
select_most_recent_GDP_vintage <- function(current_date, GDP_gr_vintages){

  vintage_names <- names(GDP_gr_vintages)[-1]
  column_names_numeric <- round(as.numeric(vintage_names), 3)

  target_value <- round(current_date, 3)

  # Select the newest vintage that is already available at current_date.
  valid_columns <- column_names_numeric[!is.na(column_names_numeric) & column_names_numeric <= target_value]

  if (length(valid_columns) > 0) {
    selected_value <- max(valid_columns)
    selected_column_name <- vintage_names[match(selected_value, column_names_numeric)]
    selected_column <- GDP_gr_vintages[[selected_column_name]]
  } else {
    stop("No GDP vintage is available on or before the requested current_date.")
  }

  selected_column
}


#' Cut a dataset to what was observable at a given date
#'
#' Truncates every series in the dataset at the point in time when it
#' would have been observable at `current_date`, given the publication
#' lag conventions of its frequency: weekly series appear one week after
#' the period, monthly series in the first week of the next month, and
#' the quarterly target roughly ten weeks after the end of the quarter.
#' Series that end up empty or shorter than 24 observations are dropped.
#'
#' @param dat A list with components `flows` and `stocks` (named lists of
#'   `ts` objects), e.g. [data_ch_dataset_test].
#' @param current_date Numeric (decimal time), the evaluation date.
#'
#' @return A list with components `flows` and `stocks`, truncated.
#'
#' @examples
#' data(data_ch_dataset_test)
#' cut <- cut_data(data_ch_dataset_test, current_date = 2024.5)
#' range(stats::time(cut$flows[[1]]))
#'
#' @export
cut_data <- function(dat, current_date){

  # cut time series at points in time contingent on the frequency of that specific series
  out <- list("flows" = lapply(dat$flows, function(x) cut_data_helper(x, current_date)),
              "stocks" = lapply(dat$stocks, function(x) cut_data_helper(x, current_date)))


  # drop time series containing no entries
  out$flows[which(sapply(out$flows, is.null))] <- NULL
  out$stocks[which(sapply(out$stocks, is.null))] <- NULL

  # drop time series that are shorter than 20 observations
  out$flows[which(sapply(out$flows, length) < 24)] <- NULL
  out$stocks[which(sapply(out$stocks, length) < 24)] <- NULL

  return(out)

}


#' @noRd
#' @importFrom stats window frequency
cut_data_helper <- function(x, current_date){

  out <- tryCatch({

    if(frequency(x) == 48){

      # weekly series are observed in the next week
      # e.g. W1 2020 = 2020.000, observed in 2020.000 + 1/48
      suppressWarnings(window(x, end = current_date - 1/48))

    } else if((frequency(x) == 12)){

      # monthly series are observed in the first week of the next month
      # e.g. Jan 2020 = 2020.000, observed in 2020.000 + 4/48 (= 2019.979 + 5/48))
      suppressWarnings(window(x, end = current_date - 4/48))

    } else {

      # quarterly series (= GDP) are observed in the first week of the third month after the end of the quarter
      # e.g. Q4 2019 = 2019.75, observed in 2020.000 + 8/48 (= 2019.979 + 9/48)
      suppressWarnings(window(x, end = current_date - 1/4 - 8/48))
    }
  }, error=function(cond) {

    NULL

  })
}


#' Cut a dataset in real time, using GDP vintages for the target
#'
#' Like [cut_data()], but instead of truncating the quarterly target
#' series, replaces it with the newest GDP vintage that was available at
#' `current_date`.
#'
#' @inheritParams cut_data
#' @param GDP_gr_vintages Vintage table from [get_real_time_gdp_vintages()].
#'
#' @return A list with components `flows` and `stocks`.
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' vintages <- get_real_time_gdp_vintages("quarterly")
#' cut <- cut_data_real_time(data_ch_dataset_test, 2024.5, vintages)
#' utils::tail(cut$flows[["ch.seco.gdp.real.gdp.ssa"]])
#' }
#' @export
cut_data_real_time <- function(dat, current_date, GDP_gr_vintages){

  # cut time series at points in time contingent on the frequency of that specific series
  out <- list("flows" = lapply(dat$flows, function(x) cut_data_helper_real_time(x, current_date, GDP_gr_vintages)),
              "stocks" = lapply(dat$stocks, function(x) cut_data_helper_real_time(x, current_date, GDP_gr_vintages)))


  # drop time series containing no entries
  out$flows[which(sapply(out$flows, is.null))] <- NULL
  out$stocks[which(sapply(out$stocks, is.null))] <- NULL

  # drop time series that are shorter than 20 observations
  out$flows[which(sapply(out$flows, length) < 24)] <- NULL
  out$stocks[which(sapply(out$stocks, length) < 24)] <- NULL

  return(out)

}


#' @noRd
#' @importFrom stats window frequency ts
#' @importFrom zoo na.trim
cut_data_helper_real_time <- function(x, current_date, GDP_gr_vintages){

  out <- tryCatch({

    if(frequency(x) == 48){

      # weekly series are observed in the next week
      # e.g. W1 2020 = 2020.000, observed in 2020.000 + 1/48
      suppressWarnings(window(x, end = current_date - 1/48))

    } else if((frequency(x) == 12)){

      # monthly series are observed in the first week of the next month
      # e.g. Jan 2020 = 2020.000, observed in 2020.000 + 4/48 (= 2019.979 + 5/48))
      suppressWarnings(window(x, end = current_date - 4/48))

    } else {

      # quarterly series (= GDP): use the newest vintage available at current_date
      na.trim(ts(select_most_recent_GDP_vintage(current_date, GDP_gr_vintages), start = c(1990,1), frequency = 4))

    }
  }, error=function(cond) {

    NULL

  })
}
