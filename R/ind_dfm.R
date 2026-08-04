#' Estimate a single-factor, target-anchored dynamic factor model
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
#' Because the factor's scale is pinned by the loading restriction, the
#' factor innovation variance is a free parameter that the data must
#' determine. Setting `stochastic_volatility = FALSE` therefore does **not**
#' fix that variance: it replaces the time-varying volatility path with a
#' single constant variance which is still estimated, drawn from its
#' conjugate inverse-gamma posterior each iteration. (This differs from
#' [fcast_dfm()], whose loadings are unrestricted and whose innovation
#' variance consequently carries the identification and *is* fixed at one
#' when its stochastic volatility is switched off. The two models pin the
#' scale in different places, so switching the same option off means
#' something different in each.)
#'
#' @param flows Either an [mfbdfm_data()] object carrying every series with its
#'   flow/stock classification -- in which case `stocks` is left empty -- or a
#'   named list of `ts` objects treated as flow variables. Must contain
#'   `target`.
#' @param stocks Named list of `ts` objects treated as stock variables, or
#'   `NULL`. Ignored when `flows` is an [mfbdfm_data()] object.
#' @param target Character, name of the low-frequency target series in
#'   `flows` (e.g. `"ch.seco.gdp.real.gdp.ssa"`).
#' @param p Integer, number of factor lags in the factor state equation.
#' @param length_sample Integer, number of posterior draws to keep.
#' @param burn_in Integer, number of initial draws to discard.
#' @param thinning Integer, keep every `thinning`-th draw after burn-in.
#' @param plots Logical, if `TRUE` draw base-graphics diagnostic plots of
#'   the data and of factor/volatility convergence during sampling.
#' @param extend_to Numeric (decimal time) or `NULL`. If beyond the sample
#'   end, the dataset is extended with zeros so forecasts can be produced.
#' @param stochastic_volatility Logical. If `TRUE` (default) the factor
#'   innovation variance follows a stochastic volatility process. If `FALSE`
#'   it is a single constant variance, **still estimated** rather than fixed
#'   -- see `@details`.
#' @param serial_correlation Logical. If `TRUE` (default) the measurement
#'   errors are allowed to be serially correlated and their autocorrelations
#'   are drawn. If `FALSE` they are held at (effectively) zero.
#' @param priors Prior specification from [dfm_priors()]. The default
#'   reproduces the published priors exactly. Note that two of them -- the
#'   target's measurement-error variance and serial correlation -- carry the
#'   identification rather than being tuning knobs; see [dfm_priors()].
#'
#' @param control Optional numerical and algorithmic settings from
#'   [dfm_control()], or a named list of them. Bundles the stability bounds and
#'   numerical guards that were previously hard-coded -- the stationarity screen
#'   on the measurement-error autocorrelations, the caps on `phi` and `sigma`,
#'   and the numerical jitter. Omit it (the default) and the published behaviour
#'   is reproduced exactly.
#'
#' @return An object of class `"ind_dfm"`: a list with components
#'   \describe{
#'     \item{factor}{`ts`, posterior mean of the annualized activity factor.}
#'     \item{factor_var}{`ts`, posterior variance of the factor.}
#'     \item{index}{`ts`, posterior mean of the cumulated activity index.}
#'     \item{nowcast}{`ts`, posterior mean nowcast of the target series.}
#'     \item{nowcast_var}{`ts`, posterior variance of the nowcast.}
#'     \item{target}{Character, the target series name.}
#'     \item{pars}{List of posterior parameter means (`h`, `lambda`, `phi`,
#'       `sigma`, `omega`, `rho`, `rho_var`).}
#'     \item{data}{`ts` matrix of the prepared (standardized) data, in which
#'       `0` encodes a missing observation.}
#'     \item{data_raw}{The input series, as supplied.}
#'     \item{data_augmented}{`ts` matrix of the augmented dataset.}
#'     \item{inventory}{Data frame describing the series (see
#'       [create_inventory()]).}
#'     \item{call}{The matched call.}
#'   }
#'
#' @seealso [fcast_dfm()] for the multi-factor model, [dfm_priors()] to vary
#'   the priors, and [ind_dfm_methods] for the `print`, `summary`, `plot`,
#'   `coef`, `fitted`, `residuals` and `as.data.frame` methods.
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
#' fit <- ind_dfm(flows = flows, stocks = stocks, target = target,
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
#' @family model fitting functions
#' @import Matrix
#' @importFrom stats ts time frequency window var plot.ts
#' @importFrom graphics par
#' @export
ind_dfm <- function(flows = NULL,
                    stocks = NULL,
                    target,
                    p = 1,
                    length_sample = 10000,
                    burn_in = 1000,
                    thinning = 1,
                    plots = FALSE,
                    extend_to = NULL,
                    stochastic_volatility = TRUE,
                    serial_correlation = TRUE,
                    priors = dfm_priors("ind_dfm"),
                    control = NULL){

  # accept either an mfbdfm_data object as the first argument, or the original
  # flows/stocks pair
  if(missing(target)) target <- NULL
  .d <- resolve_data_arg(flows, stocks, target)
  flows <- .d$flows; stocks <- .d$stocks; target <- .d$target

  # validate inputs early, naming the offending argument
  validate_model_inputs(flows = flows, stocks = stocks, target = target,
                        p = p, length_sample = length_sample, burn_in = burn_in,
                        thinning = thinning, call = "ind_dfm")
  check_priors(priors, "ind_dfm")
  control <- resolve_control(control, "ind_dfm")

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
  # q = 1 for this model
  Gmat_prealloc <- get_gmat_prealloc(n = n, q = 1, s = s, t = t)


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
                           fdat = flows,
                           stochastic_volatility = stochastic_volatility,
                           serial_correlation = serial_correlation,
                           priors = priors,
                       control = control)

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
              # h spans t+s periods, of which the first s are the latent states
              # carried by the distributed lags. Drop those and keep the t
              # in-sample periods, using the same slice as the factor above -
              # h_t describes the innovation to f_t, so the two must share an
              # index. The previous (s+2):(t+s+1) ran one past the end of h,
              # leaving a trailing NA, and was shifted one period against the
              # factor (#49).
              "pars" = list("h" = h_out[(s+1):(t+s)],
                            "lambda" = lambda_out,
                            "phi" = phi_out,
                            "sigma" = sigma_out,
                            "omega" = omega_out,
                            "rho" = rho_out,
                            "rho_var" = rho_var),
              # `data` is the prepared matrix and `data_raw` the series as
              # supplied. Both fit classes use these names for these meanings
              # (#50); `data_raw` is new here, added so the two agree.
              "data" = Ymat,
              "data_raw" = c(flows, stocks),
              "data_augmented" = Xmat_full,
              "inventory" = inventory)

  out$call <- match.call()
  class(out) <- "ind_dfm"

  # return results
  return(out)

}
