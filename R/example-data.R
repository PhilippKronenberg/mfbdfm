#' Synthetic input bundle for the analytics table builders
#'
#' Builds a small, self-contained `inputs` bundle of the shape
#' [get_insample_fit_table()], [get_combined_cor_table()] and
#' [get_insample_error_details()] expect, filled with synthetic numbers.
#'
#' @details
#' The real bundle is assembled by the scripts under `analysis/5_plots/` from
#' fitted models and the private real-time GDP vintages, so none of the analytics
#' functions could previously be demonstrated in a runnable example -- their
#' examples were unevaluated sketches referring to objects that did not exist,
#' which meant `R CMD check` never executed them. That is exactly how two
#' analysis scripts came to read files nothing produced (#59, #63). This exists so
#' those examples run and are checked.
#'
#' It is **not** a model of Swiss data. The series are random walks and white
#' noise of the right shape and frequency; use it to exercise the code paths and
#' to see the argument shapes, not to interpret numbers.
#'
#' The same bundle backs the analytics tests, so the examples and the tests
#' exercise identical input.
#'
#' @param seed Integer, the random seed, so a bundle is reproducible. Pass
#'   `NULL` to draw from the current state of the RNG instead.
#'
#' @return A named list of 11 elements: nine weekly `data.frame`s with `time`
#'   and `value` columns (three of them also carrying `name`), and two quarterly
#'   `ts` objects (`x_hist_gr_yoy`, `x_hist_gr_ann`) standing in for realised GDP
#'   growth.
#'
#' @examples
#' inputs <- mfbdfm_example_inputs()
#' names(inputs)
#' head(inputs$tab_gr)
#'
#' # what it is for
#' fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
#' fit_tabs$RMSE
#'
#' @seealso [get_insample_fit_table()], [get_combined_cor_table()],
#'   [get_insample_error_details()]
#' @family data preparation functions
#' @importFrom stats rnorm ts
#' @export
mfbdfm_example_inputs <- function(seed = 99){

  if(!is.null(seed)){
    if(!is_count(seed)) stop("`seed` must be a single whole number, or NULL.",
                             call. = FALSE)
    set.seed(seed)
  }

  wk <- seq(as.Date("2010-01-07"), as.Date("2024-12-28"), by = "week")
  n_wk <- length(wk)

  # a random walk at the weekly frequency, which is what the indicator series
  # look like to the table builders
  mkdf <- function() data.frame(time = wk,
                                value = cumsum(rnorm(n_wk, 0, 0.3)))

  list(
    tab_wai_yoy = data.frame(time = wk, name = "mean",
                             value = cumsum(rnorm(n_wk, 0, 0.3))),
    wwa_gr_df     = mkdf(),
    wwa_gr_df_qoq = mkdf(),
    fcurve_gr_df  = mkdf(),
    tab_kss       = mkdf(),
    tab_snb       = mkdf(),
    tab_baro      = mkdf(),
    tab_gr    = data.frame(time = wk, name = "mean",
                           value = rnorm(n_wk, 0.5, 1)),
    tab_gr_lv = data.frame(time = wk,
                           value = 100 * cumprod(1 + rnorm(n_wk, 0, 0.002))),
    x_hist_gr_yoy = ts(rnorm(100, 1.5, 1), start = c(1991, 1), frequency = 4),
    x_hist_gr_ann = ts(rnorm(104, 0.4, 0.5), start = c(1990, 1), frequency = 4)
  )

}
