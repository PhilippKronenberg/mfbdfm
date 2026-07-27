#' mfbdfm: A Mixed-Frequency Bayesian Dynamic Factor Model
#'
#' Estimates a Bayesian mixed-frequency dynamic factor model ([hfdfm()])
#' that combines indicators observed at weekly, monthly and quarterly
#' frequencies into a single dynamic factor. The package ships a
#' flagship application, the Weekly Activity Index (WAI): a weekly GDP
#' indicator for Switzerland derived from conventional macroeconomic
#' indicators combined with alternative high-frequency data (mobility,
#' transactions, search trends, and similar series).
#'
#' @section Model in brief:
#' The model extracts a single dynamic factor, constrained by an
#' identification restriction that fixes its loading on GDP to one, so
#' the factor is directly interpretable as weekly GDP growth rather than
#' a generic activity index. Three features let it combine
#' heterogeneous, incomplete high-frequency data with official GDP
#' figures:
#' \itemize{
#'   \item **Data augmentation** treats missing and mixed-frequency
#'     observations as latent states, so series can enter with
#'     different starting dates, publication lags and frequencies
#'     (weekly, monthly, quarterly).
#'   \item **Stochastic volatility** in the factor state equation lets
#'     the variance of common shocks vary over time, so crisis-period
#'     swings (e.g. the COVID-19 pandemic) are not mechanically smoothed
#'     away.
#'   \item **Quasi-differencing** (Chib & Greenberg, 1994) removes
#'     serial correlation in the measurement errors, preventing
#'     persistent idiosyncratic noise in individual indicators from
#'     contaminating the common factor.
#' }
#' Estimation is by Gibbs sampling using the precision sampler of Chan
#' and Jeliazkov (2009), with temporal aggregation of flow variables
#' following the geometric-mean approximation of Mariano and Murasawa
#' (2003).
#'
#' @section Getting started:
#' The package ships the curated indicator datasets [data_ch_dataset]
#' and [data_ch_dataset_test], plus the real-time GDP vintage database
#' (in `inst/extdata/`), so a small nowcast can be estimated out of the
#' box - see `vignette("mfbdfm")` for a worked walkthrough, or the
#' example in [hfdfm()] for the minimal version.
#'
#' @references
#' Kronenberg, P. (2026). A high-frequency GDP indicator for
#' Switzerland. *Swiss Journal of Economics and Statistics*, 162, 10.
#' \doi{10.1186/s41937-026-00157-w}
#'
#' Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
#' Tracking economic activity with alternative high-frequency data.
#' *Journal of Applied Econometrics*, 40(3), 270-290. (The mixed-frequency
#' dynamic factor model underlying `mfbdfm`; this package estimates the
#' single-factor, GDP-identified special case used in the WAI.)
#'
#' A reference list of the related business-cycle-indicator literature
#' is in the "References" section of `vignette("mfbdfm")`.
#'
#' @keywords internal
"_PACKAGE"
