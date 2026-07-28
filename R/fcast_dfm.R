#' Estimate a multi-factor mixed-frequency dynamic factor model
#'
#' Estimates the Bayesian multi-factor mixed-frequency dynamic factor model
#' of Eckert, Kronenberg, Mikosch & Neuwirth (2025) by Markov chain Monte
#' Carlo. Flow and stock indicator series of different frequencies are
#' combined into `q` common factors, from which high-frequency estimates and
#' nowcasts are derived for every input series.
#'
#' @details
#' This is a different model from [hfdfm()], not a multi-factor setting of
#' it. The two differ in how the factors are identified, in their priors,
#' and in how the autoregressive coefficients are drawn:
#'
#' \describe{
#'   \item{Identification}{[hfdfm()] identifies the factor *during* sampling,
#'     by fixing the loading on `target` to one and shrinking that series'
#'     measurement error toward zero, so the factor is directly interpretable
#'     as the target's growth rate. `fcast_dfm()` instead samples an
#'     unidentified model and resolves the rotational indeterminacy
#'     afterwards: every draw is rotated onto a common reference by
#'     orthogonal Procrustes, then one global rotation is chosen to make the
#'     average loading matrix close to its varimax rotation.}
#'   \item{Priors}{`fcast_dfm()` uses uninformative priors throughout; no
#'     series is treated specially.}
#'   \item{Factor dynamics}{The factors follow a VAR(`p`) whose coefficients
#'     are drawn by Metropolis-Hastings with a stationarity constraint,
#'     rather than the conjugate Gibbs step used by [hfdfm()]. A single
#'     stochastic volatility path is shared by all `q` factors.}
#' }
#'
#' Because identification differs, `fcast_dfm(q = 1)` is **not** equivalent to
#' [hfdfm()]. Use [hfdfm()] for the target-anchored single-factor model of
#' Kronenberg (2026), and `fcast_dfm()` for the multi-factor model.
#'
#' `target` does not enter the estimation. It names the series whose nowcast
#' is surfaced at the top level of the return value for convenience; results
#' for every series remain available in `ncst` and `data_hf`.
#'
#' @param flows Named list of `ts` objects treated as flow variables, or
#'   `NULL`. Must contain `target` if `stocks` does not.
#' @param stocks Named list of `ts` objects treated as stock variables, or
#'   `NULL`.
#' @param target Character, name of the series of interest (e.g.
#'   `"ch.seco.gdp.real.gdp.ssa"`). Must be present in `flows` or `stocks`.
#'   Does not affect estimation; see Details.
#' @param p Integer, number of lags in the factor VAR.
#' @param q Integer, number of factors. Must be smaller than the number of
#'   input series.
#' @param length_sample Integer, number of posterior draws to keep.
#' @param burn_in Integer, number of initial draws to discard.
#' @param thinning Integer, keep every `thinning`-th draw after burn-in.
#' @param plots Logical, if `TRUE` draw diagnostic plots of the factors,
#'   stochastic volatility and trace plots during sampling.
#' @param extend Numeric or `NULL`. If given, the dataset is extended by this
#'   many years with zeros so forecasts can be produced.
#' @param stochastic_volatility Logical, include stochastic volatility in the
#'   factor state equation.
#' @param serial_correlation Logical, model serial correlation in the
#'   measurement errors. If `FALSE`, the autocorrelations are fixed near zero.
#' @param ncores Integer or `NULL`. Number of cores for the rotation step,
#'   which is run in parallel via \pkg{doParallel} when supplied.
#'
#' @return An object of class `"fcast_dfm"`: a list with components
#'   \describe{
#'     \item{factor}{`ts` matrix of the `q` posterior mean factors.}
#'     \item{factor_var}{`ts` matrix of the corresponding variances.}
#'     \item{target}{Character, the series named by `target`.}
#'     \item{nowcast, nowcast_var}{`ts`, posterior mean and variance of the
#'       nowcast for `target`, extracted from `ncst`.}
#'     \item{pars}{List of posterior means (`lambda`, `phi`, `sigma`, `rho`,
#'       `rho_var`, `h`) and the model dimensions (`n`, `q`, `p`, `s`, `t`,
#'       `k`).}
#'     \item{ncst}{List with `mean` and `var`, each a named list of nowcasts
#'       for every input series at its own frequency.}
#'     \item{data}{The input series.}
#'     \item{data_missings}{`ts` matrix of the prepared (standardized) data.}
#'     \item{data_hf}{List with `mean` and `var`, each a named list of
#'       high-frequency growth-rate estimates for every input series.}
#'     \item{data_augmented}{`ts` matrix of the augmented dataset.}
#'     \item{data_augmented_rescaled}{The same, back on each series' original
#'       scale.}
#'     \item{inventory}{Data frame describing the series (see
#'       [create_inventory()]).}
#'   }
#'
#' @examples
#' \dontrun{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                 stats::window, start = 2018)
#' stocks <- lapply(data_ch_dataset_test$stocks[1:2],
#'                  stats::window, start = 2018)
#' set.seed(1)
#' fit <- fcast_dfm(flows = flows, stocks = stocks, target = target,
#'                  q = 2, length_sample = 50, burn_in = 10)
#' fit$nowcast
#' }
#'
#' @references
#' Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
#' Tracking economic activity with alternative high-frequency data.
#' *Journal of Applied Econometrics*, 40(3), 270-290.
#'
#' Kronenberg, P. (2026). A high-frequency GDP indicator for
#' Switzerland. *Swiss Journal of Economics and Statistics*, 162, 10.
#' \doi{10.1186/s41937-026-00157-w}
#'
#' @seealso [hfdfm()] for the single-factor, target-anchored model.
#'
#' @import Matrix
#' @importFrom stats ts time frequency window plot.ts
#' @importFrom graphics par
#' @export
fcast_dfm <- function(flows = NULL,
                      stocks = NULL,
                      target,
                      p = 1,
                      q = 2,
                      length_sample = 1000,
                      burn_in = 1000,
                      thinning = 1,
                      plots = FALSE,
                      extend = NULL,
                      stochastic_volatility = TRUE,
                      serial_correlation = TRUE,
                      ncores = NULL){

  # validate inputs early, naming the offending argument
  if(is.null(flows) && is.null(stocks)){
    stop("At least one of `flows` and `stocks` must be supplied.", call. = FALSE)
  }
  if(missing(target) || !is.character(target) || length(target) != 1){
    stop("`target` must be a single series name (character).", call. = FALSE)
  }
  available <- c(names(flows), names(stocks))
  if(!target %in% available){
    stop("`target` (\"", target, "\") is not among the supplied series.",
         call. = FALSE)
  }
  if(length(stocks) + length(flows) < q){
    stop("`q` (", q, ") must be smaller than the number of input series (",
         length(stocks) + length(flows), ").", call. = FALSE)
  }

  # create an inventory of the time series involved
  inventory <- create_inventory(flows = flows, stocks = stocks)

  # import and transform data
  Ymat <- prepare_data(flows = flows,
                       stocks = stocks,
                       inventory = inventory,
                       target = target)

  # extend to allow for forecasts
  if(!is.null(extend)){

    Ymat <- window(Ymat,
                   end = as.numeric(tail(time(Ymat),1) + extend),
                   extend = TRUE)
    Ymat[which(is.na(Ymat))] <- 0

  }

  # define parameters
  n <- ncol(Ymat) # Number of variables
  t <- nrow(Ymat) # Number of high-frequency periods
  k <- max(inventory$freq)/min(inventory$freq) # Fraction of high-frequency periods in lowest frequency
  s <- 2*(k - 1) # Number of periods for aggregation rule in formula (3)

  # plot the time series as a check for the user
  if(plots == TRUE){

    oldpar <- par(no.readonly = TRUE)
    on.exit(par(oldpar), add = TRUE)

    tsl <- c(stocks, flows)
    par(mfrow = c(length(unique(inventory$freq)), 1))
    for(x in unique(inventory$freq)){
      plot.ts(scale(do.call(cbind, tsl[inventory$key[inventory$freq == x]])),
              xlab = NULL,
              ylab = paste("frequency: ", x),
              ylim = c(-15,15),
              plot.type = "single")
    }

  }

  message("preallocating..")
  Gmat_prealloc <- t(do.call(rbind,lapply(1:(t-1), function(tx){

    cbind(Matrix(0,n,q*(tx-1)),
          Matrix(1,n,q*(s+2)),
          Matrix(0,n,q*(t-tx-1)))

  })))


  # SAMPLING ----------------------------------------------------------------

  message("simulating posterior distribution..")
  theta_out <- run_sampling_mf(Ymat = Ymat,
                               q = q, n = n, t = t, p = p, s = s,
                               length_sample = length_sample,
                               burn_in = burn_in,
                               thinning = thinning,
                               inventory = inventory,
                               plots = plots,
                               Gmat_prealloc = Gmat_prealloc,
                               stochastic_volatility = stochastic_volatility,
                               serial_correlation = serial_correlation)


  # ROTATION ----------------------------------------------------------------

  message("running rotation of each draw..")
  D_save <- run_rotation(theta_out, n = n, q = q, p = p, s = s, t = t, ncores = ncores)


  # IDENTIFICATION ----------------------------------------------------------

  message("running identification..")
  rlist <- run_identification(theta_out, D_save, n = n, q = q, p = p, s = s, t = t)


  # EVALUATION --------------------------------------------------------------

  message("processing output..")
  out <- run_evaluation(rlist, Ymat, Gmat_prealloc, k, n, q, p, s, t,
                        inventory, flows, stocks, target)

  class(out) <- "fcast_dfm"

  return(out)

}
