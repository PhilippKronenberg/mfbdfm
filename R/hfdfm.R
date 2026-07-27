#' Estimate a high-frequency dynamic factor model
#'
#' Estimates the Bayesian mixed-frequency dynamic factor model behind the
#' Swiss Weekly Activity Index (WAI) by Markov chain Monte Carlo (Gibbs)
#' sampling. Flow and stock indicator series of different frequencies are
#' combined into a single weekly activity factor that is coherent with the
#' low-frequency target series (typically quarterly real GDP), from which
#' weekly GDP nowcasts are derived.
#'
#' @details
#' The factor is identified by fixing its loading on `target` to one and
#' shrinking the target's measurement-error variance and autocorrelation
#' toward zero (informative priors), so the extracted factor closely
#' tracks the observed growth rate of `target` rather than being merely
#' correlated with it. This resolves the usual scale/sign indeterminacy
#' of dynamic factor models and yields a directly interpretable
#' high-frequency proxy for the target series (see Kronenberg 2026,
#' Sect. 2.4). All other series are standardized and enter with
#' uninformative priors. Missing and lower-frequency observations are
#' estimated as latent states via data augmentation; the factor state
#' equation includes stochastic volatility, and measurement errors are
#' quasi-differenced to remove serial correlation (see `@references`).
#'
#' @param flows Named list of `ts` objects treated as flow variables. Must
#'   contain `target`.
#' @param stocks Named list of `ts` objects treated as stock variables.
#' @param target Character, name of the low-frequency target series in
#'   `flows` (e.g. `"ch.seco.gdp.real.gdp.ssa"`).
#' @param p Integer, number of factor lags in the factor state equation.
#' @param q Integer, number of factors. Currently ignored: the sampler
#'   always uses a single factor.
#' @param length_sample Integer, number of posterior draws to keep.
#' @param burn_in Integer, number of initial draws to discard.
#' @param thinning Integer, keep every `thinning`-th draw after burn-in.
#' @param plots Logical, if `TRUE` draw base-graphics diagnostic plots of
#'   the data and of factor/volatility convergence during sampling.
#' @param extend_to Numeric (decimal time) or `NULL`. If beyond the sample
#'   end, the dataset is extended with zeros so forecasts can be produced.
#' @param stochastic_volatility Logical. Currently ignored: the sampler
#'   always includes stochastic volatility. Kept for API compatibility.
#' @param serial_correlation Logical. Currently ignored: the sampler
#'   always models serial correlation in measurement errors. Kept for API
#'   compatibility.
#'
#' @return An object of class `"hfdfm"`: a list with components
#'   \describe{
#'     \item{factor}{`ts`, posterior mean of the annualized activity factor.}
#'     \item{factor_var}{`ts`, posterior variance of the factor.}
#'     \item{index}{`ts`, posterior mean of the cumulated activity index.}
#'     \item{nowcast}{`ts`, posterior mean nowcast of the target series.}
#'     \item{nowcast_var}{`ts`, posterior variance of the nowcast.}
#'     \item{target}{Character, the target series name.}
#'     \item{pars}{List of posterior parameter means (`h`, `lambda`, `phi`,
#'       `sigma`, `omega`, `rho`, `rho_var`).}
#'     \item{data}{`ts` matrix of the prepared (standardized) data.}
#'     \item{data_augmented}{`ts` matrix of the augmented dataset.}
#'     \item{inventory}{Data frame describing the series (see
#'       [create_inventory()]).}
#'   }
#'
#' @examples
#' \donttest{
#' data(data_ch_dataset_test)
#' target <- "ch.seco.gdp.real.gdp.ssa"
#' flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
#'                 stats::window, start = 2018)
#' stocks <- lapply(data_ch_dataset_test$stocks[1:2],
#'                  stats::window, start = 2018)
#' set.seed(1)
#' fit <- hfdfm(flows = flows, stocks = stocks, target = target,
#'              length_sample = 50, burn_in = 10)
#' fit$nowcast
#' }
#'
#' @references
#' Kronenberg, P. (2026). A high-frequency GDP indicator for
#' Switzerland. *Swiss Journal of Economics and Statistics*, 162, 10.
#' \doi{10.1186/s41937-026-00157-w}
#'
#' Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
#' Tracking economic activity with alternative high-frequency data.
#' *Journal of Applied Econometrics*, 40(3), 270-290.
#'
#' @import Matrix
#' @importFrom stats ts time frequency window var plot.ts
#' @importFrom graphics par
#' @export
hfdfm <- function(flows,
                  stocks,
                  target,
                  p = 1,
                  q = 1,
                  length_sample = 10000,
                  burn_in = 1000,
                  thinning = 1,
                  plots = FALSE,
                  extend_to = NULL,
                  stochastic_volatility = TRUE,
                  serial_correlation = TRUE){

  # create an inventory of the time series involved
  inventory <- create_inventory(flows = flows, stocks = stocks)

  # import and transform data
  Ymat <- prepare_data(flows = flows,
                       stocks = stocks,
                       inventory = inventory,
                       target = target)

  t2 <- nrow(Ymat)

  # extend dataset to allow for forecasts
  if(!(is.null(extend_to))){
    if(extend_to > as.numeric(tail(time(Ymat),1))){

      Ymat <- window(Ymat,
                     end = as.numeric(extend_to),
                     extend = TRUE)
      Ymat[which(is.na(Ymat))] <- 0

    }
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

    tsl <- c(stocks,flows)
    par(mfrow = c(length(unique(inventory$freq)), 1))
    for(x in unique(inventory$freq)){
      plot.ts(scale(do.call(cbind,tsl[inventory$key[inventory$freq == x]])),
              xlab = NULL,
              ylab = paste("frequency: ",x),
              ylim = c(-15,15),
              plot.type="single")
    }

  }

  message("preallocating..")
  Gmat_prealloc <- t(do.call(rbind,lapply(1:(t-1), function(tx){

    cbind(Matrix(0,n,tx-1),
          Matrix(1,n,s+2),
          Matrix(0,n,t-tx-1))

  })))


  # SAMPLING ----------------------------------------------------------------

  # run markov chain monte carlo sampling
  message("simulating posterior distribution..")
  par_save <- run_sampling(Ymat = Ymat,
                           target = target,
                           n = n,
                           t = t,
                           t2 = t2,
                           p = p,
                           s = s,
                           length_sample = length_sample,
                           burn_in = burn_in,
                           thinning = thinning,
                           inventory = inventory,
                           plots = plots,
                           Gmat_prealloc = Gmat_prealloc,
                           fdat = flows)

  message("processing output..")


  # EVALUATE POSTERIOR ------------------------------------------------------

  # average over parameter draws
  h_out <- Reduce("+", par_save$h)/length(par_save$h)
  lambda_out <- Reduce("+", par_save$lambda)/length(par_save$lambda)
  sigma_out <- Reduce("+", par_save$sigma)/length(par_save$sigma)
  omega_out <- Reduce("+", par_save$omega)/length(par_save$omega)
  phi_out <- Reduce("+", par_save$phi)/length(par_save$phi)
  rho_out <- Reduce("+", par_save$rho)/length(par_save$rho)
  Xmat_out <- Reduce("+", par_save$Xmat)/length(par_save$Xmat)
  rho_var <- apply(do.call(cbind,par_save$rho),1,var)

  # extract nowcasts
  ncst_mean <- ts(data = apply(do.call(cbind,par_save$ncast),1,mean),
                  start = time(par_save$ncast[[1]])[1],
                  frequency = frequency(par_save$ncast[[1]]))

  ncst_var <- ts(data = apply(do.call(cbind,par_save$ncast),1,var),
                 start = time(par_save$ncast[[1]])[1],
                 frequency = frequency(par_save$ncast[[1]]))

  # full dataset
  Xmat_full <- ts(Xmat_out,
                  start = time(Ymat)[1],
                  frequency = frequency(Ymat))



  # MEAN AND VARIANCE OF GROWTH RATES AND INDEX ------------------------------

  # cut off latent states from distributed lags and de-standardize each
  # posterior draw once; used below for both the growth-rate series (flist)
  # and the cumulated index (ilist)
  target_sd <- inventory[which(inventory$key == target),"sd"]
  target_mean <- inventory[which(inventory$key == target),"mean"]

  rescaled_list <- lapply(par_save$f, function(fx){

    f_cut <- fx[(s+1):(t+s)]
    (f_cut * target_sd) + target_mean/k

  })

  # growth rates of factor at a quarterly rate, annualized
  flist <- lapply(rescaled_list, function(f_rescaled){

    ts(((1+f_rescaled)^frequency(Ymat)-1)*100,
       start = time(Ymat)[1],
       frequency = frequency(Ymat))

  })

  f_mean <- Reduce("+", flist)/length(flist)
  f_var <- ts(apply(do.call(cbind,flist),1,var),
              start = time(f_mean)[1],
              frequency = frequency(f_mean))


  # cumulated activity index
  ilist <- lapply(rescaled_list, function(f_rescaled){

    ts(exp(cumsum(f_rescaled)),
       start = time(Ymat)[1],
       frequency = frequency(Ymat))

  })

  i_mean <- Reduce("+", ilist)/length(ilist) * 100




  # OUTPUT ------------------------------------------------------------------

  out <- list("factor" = f_mean,
              "factor_var" = f_var,
              "index" = i_mean,
              "nowcast" = ncst_mean,
              "nowcast_var" = ncst_var,
              "target" = target,
              "pars" = list("h" = h_out[(s+2):(t+s+1)],
                            "lambda" = lambda_out,
                            "phi" = phi_out,
                            "sigma" = sigma_out,
                            "omega" = omega_out,
                            "rho" = rho_out,
                            "rho_var" = rho_var),
              "data" = Ymat,
              "data_augmented" = Xmat_full,
              "inventory" = inventory)

  class(out) <- "hfdfm"

  # return results
  return(out)

}
