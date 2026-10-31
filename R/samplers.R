# Gibbs samplers for the high-frequency dynamic factor model.
# All functions here are internal building blocks of ind_dfm().

# Seven-component normal mixture approximating the log chi-squared
# distribution (Kim, Shephard & Chib 1998; Primiceri 2005 Appendix), used by
# both draw_volatility() and draw_indicators(). Defined once here as plain
# numeric vectors rather than rebuilt as a data.frame on every call in the
# sampling loop.
NMIX_PROB <- c(0.00730,0.10556,0.00002,0.04395,0.34001,0.24566,0.25750)
NMIX_MEAN <- c(-10.12999,-3.97281,-8.56686,2.77786,0.61942,1.79518,-1.08819)
NMIX_VAR  <- c(5.79596,2.61369,5.17950,0.16735,0.64009,0.34023,1.26261)
NMIX_SD   <- sqrt(NMIX_VAR)

#' Run the MCMC sampling loop
#'
#' @noRd
#' @importFrom stats ts time frequency rnorm runif plot.ts
#' @importFrom utils txtProgressBar setTxtProgressBar
#' @importFrom graphics par
run_sampling <- function(Ymat, target, n, t, t2, p, s, length_sample, burn_in, thinning,
                         inventory, plots,Gmat_prealloc, fdat,
                         stochastic_volatility = TRUE, serial_correlation = TRUE,
                         priors = dfm_priors("ind_dfm"),
                         control = dfm_control("ind_dfm"),
                         verbose = TRUE,
                         start = NULL){

  # fill in the priors whose published default is a rule in terms of t or p
  priors <- resolve_priors(priors, t = t, p = p)

  # preallocation of output matrices
  chain <- NULL # matrix(NA, burn_in + length_sample*thinning, 100)
  par_save <- list("f" = vector(mode = "list", length = length_sample),
                   "lambda" = vector(mode = "list", length = length_sample),
                   "phi" = vector(mode = "list", length = length_sample),
                   "h" = vector(mode = "list", length = length_sample),
                   "sigma" = vector(mode = "list", length = length_sample),
                   "omega" = vector(mode = "list", length = length_sample),
                   "rho" = vector(mode = "list", length = length_sample),
                   "Xmat" = vector(mode = "list", length = length_sample),
                   "ncast" = vector(mode = "list", length = length_sample))

  # burn-in parameter draws, kept only on request (#110). Parameters only: the
  # nowcast is a derived quantity the loop computes for retained draws, and
  # computing it for the burn-in too would change the cost of every fit for a
  # plotting convenience.
  keep_burn <- isTRUE(control$keep_draws) && isTRUE(control$keep_burn_in) &&
    burn_in > 0
  if(keep_burn){
    burn_save <- lapply(c("lambda", "phi", "h", "sigma", "omega", "rho"),
                        function(nm) vector(mode = "list", length = burn_in))
    names(burn_save) <- c("lambda", "phi", "h", "sigma", "omega", "rho")
  }

  # preallocations
  Llist <- get_distributed_lags(inventory)

  # random parameter starting values.
  #
  # Any block supplied in `start` is taken as given and its initialisation
  # below is skipped - and because `init()`'s second argument is a promise, a
  # skipped initialisation draws nothing. A complete `start` therefore consumes
  # no random numbers at all, which is what makes continuing a chain exact
  # rather than approximate; with `start = NULL` the stream is consumed exactly
  # as it always was. See dfm_control()'s "Where the chain starts" (#117).
  init <- function(nm, value) if(is.null(start[[nm]])) value else start[[nm]]

  phi <- init("phi", c(0.75,rep(0,p-1)))
  lambda <- init("lambda", Matrix(1,n,1))
  sigma <- init("sigma", Diagonal(x = runif(n), n = n))
  omega <- init("omega", 1e-2)
  h <- init("h", matrix(-5, t+s, 1))
  f <- init("f", matrix(rnorm(t+s), t+s, 1))
  # with serial_correlation = FALSE the measurement-error autocorrelations are
  # held at (effectively) zero rather than drawn; 1e-9 rather than exactly 0 to
  # avoid singularities downstream, matching fcast_dfm()
  rho <- init("rho", if(serial_correlation){
    Diagonal(x = runif(n))
  } else {
    Diagonal(x = 1e-9, n = n)
  })
  Xmat = init("Xmat", matrix(rnorm(t*n), t, n))
  indicators = init("indicators",
                    replicate(t+s, sample(x = 1:7, size = 1, prob = rep(1/7,7))))

  ctx <- sweep_context(Ymat = Ymat, target = target, n = n, t = t, t2 = t2, p = p, s = s,
                       inventory = inventory, Gmat_prealloc = Gmat_prealloc,
                       priors = priors, control = control,
                       stochastic_volatility = stochastic_volatility,
                       serial_correlation = serial_correlation)
  rho_tally <- ctx$rho_tally

  # initialize progress bar; NULL when quiet, since the bar writes with cat()
  # and so cannot be silenced from outside the call (#118)
  pb <- if(verbose) txtProgressBar(style = 3) else NULL

  # restore the caller's graphics state once, however this function exits,
  # instead of resetting it after every plotted iteration below
  if(plots == TRUE){
    oldpar <- par(no.readonly = TRUE)
    on.exit(par(oldpar), add = TRUE)
  }

  state <- list(f = f, lambda = lambda, phi = phi, sigma = sigma, rho = rho, h = h,
                omega = omega, Xmat = Xmat, indicators = indicators)

  # loop until sampling complete
  for(jx in 1:(burn_in + length_sample*thinning)){

    if(!is.null(pb)) setTxtProgressBar(pb, jx/(burn_in + length_sample * thinning))

    state <- gibbs_sweep(state, ctx)
    f <- state$f; lambda <- state$lambda; phi <- state$phi; sigma <- state$sigma
    rho <- state$rho; h <- state$h; omega <- state$omega; Xmat <- state$Xmat
    indicators <- state$indicators

    # 3. check convergence
    if(plots == TRUE){
      if(jx %% 1 == 0){
        par(mfrow = c(3,1))
        ix=which(inventory$key==target)
        plot(ts(as.matrix(f[(s+1):(t+s),]),
                start = time(Ymat)[1],
                frequency = frequency(Ymat)),
             ylim = c(-2.5,1),
             xlab = NULL,
             ylab = "factor",
             main = paste0("Iteration ",jx))
        plot(ts(exp(h),
                start = time(Ymat)[1] - s/frequency(Ymat),
                frequency = frequency(Ymat)),
             xlab = NULL,
             ylab = "stochastic volatility",
             main = NULL)
        plot.ts(cbind(Ymat[,ix],Xmat[,ix]),
                main = NULL,
                xlab = NULL,
                ylab = paste0("fitted ",inventory$key[ix]),
                lty = c(1,2),
                col = c("black","red"),
                plot.type="single")
      }
    }

    if(keep_burn && jx <= burn_in){

      burn_save$lambda[[jx]] <- lambda
      burn_save$phi[[jx]] <- phi
      burn_save$h[[jx]] <- h
      burn_save$sigma[[jx]] <- diag(sigma)
      burn_save$omega[[jx]] <- omega
      burn_save$rho[[jx]] <- diag(rho)

    }

    # 4 start sampling upon convergence
    if(jx > burn_in & jx %% thinning == 0){

      # save factor and parameter draws
      par_save$f[[(jx - burn_in)/thinning]] <- f
      par_save$h[[(jx - burn_in)/thinning]] <- h
      par_save$lambda[[(jx - burn_in)/thinning]] <- lambda
      par_save$phi[[(jx - burn_in)/thinning]] <- phi
      par_save$omega[[(jx - burn_in)/thinning]] <- omega
      par_save$sigma[[(jx - burn_in)/thinning]] <- diag(sigma)
      par_save$rho[[(jx - burn_in)/thinning]] <- diag(rho)
      par_save$Xmat[[(jx - burn_in)/thinning]] <- Xmat
      par_save$ncast[[(jx - burn_in)/thinning]] <- get_nowcast(Xmat_full = ts(Xmat,
                                                                     start = time(Ymat)[1],
                                                                     frequency = frequency(Ymat)),
                                                      inventory = inventory,
                                                      target = target,
                                                      flows = fdat)


      # GET NOWCAST -------------------------------------------------------------


    }
  }

  if(!is.null(pb)) close(pb)
  warn_rho_fallback(rho_tally, control)
  par_save$rho_fallback <- rho_tally$n

  # a new, separately named element: everything downstream reads par_save by
  # name (ind_dfm()'s averages, pars_dist_ind()), so adding one cannot disturb
  # them
  if(keep_burn) par_save$burn <- burn_save

  # the state the loop finished in, in the sampler's own types, so handing it
  # back as `start` resumes where this chain stopped (#117). `indicators` is
  # part of it even when stochastic volatility is off, where it is never drawn:
  # a state that is complete whatever the switches say is a state that consumes
  # no random numbers on the way back in.
  par_save$final_state <- list(f = f, lambda = lambda, phi = phi,
                               sigma = sigma, rho = rho, h = h,
                               omega = omega, Xmat = Xmat,
                               indicators = indicators)

  return(par_save)

}


#' What does not change between sweeps
#'
#' Sparse structures that depend only on the fixed data and dimensions, not on
#' any sampled parameter, so they are computed once rather than on every
#' iteration.
#'
#' @noRd
sweep_context <- function(Ymat, target, n, t, t2, p, s, inventory, Gmat_prealloc,
                          priors, control, stochastic_volatility, serial_correlation){

  Smat <- Diagonal(x = sapply(1:t, function(tx) as.integer(Ymat[tx,] != 0)))
  V1 <- solve(Diagonal(x = 1e-9, n = t*n))
  StV1S <- t(Smat) %*% (t(Smat) %*% V1 %*% Smat) %*% Smat
  Yvec <- t(Ymat)
  dim(Yvec) <- c(n*t, 1)
  StV1SY <- t(Smat) %*% (t(Smat) %*% V1 %*% Smat) %*% Yvec

  N <- cbind(rbind(Matrix(0,1,t+s-1),
                   kronecker(Diagonal(t+s-1), -1)),
             Matrix(0, t+s,1)) + Diagonal(n = (t+s))
  N <- N[-1,] # diffuse (improper) prior distribution
  NtN <- t(N) %*% N

  Llist <- get_distributed_lags(inventory)
  low_ix <- which(inventory$freq < max(inventory$freq) & inventory$key != target)

  list(Gmat_prealloc = Gmat_prealloc, Llist = Llist,
       low_ix = low_ix,
       low_obs = lapply(low_ix, function(ix) series_obs(Ymat, ix, Llist, t, s)),
       inventory = inventory, target = target, n = n, t = t, t2 = t2, p = p, s = s,
       StV1S = StV1S, StV1SY = StV1SY, NtN = NtN, priors = priors, control = control,
       target_obs = series_obs(Ymat, which(inventory$key == target), Llist, t, s),
       # tally of rho stationarity-screen fallbacks, reported once after the chain
       rho_tally = new_rho_tally(),
       stochastic_volatility = stochastic_volatility,
       serial_correlation = serial_correlation)

}


#' One series' observations and how they load on the factor
#'
#' @return A list with the observation rows `tau`, their values `y`, their gaps
#'   `g` (the first counted from period 1), the series' index `ix`, and sparse
#'   matrices mapping `f` to the aggregated factor: `B` at `tau`, `B1` at
#'   period 1.
#'
#' @noRd
series_obs <- function(Ymat, ix, Llist, t, s){

  tau <- which(Ymat[, ix] != 0)
  w <- vapply(Llist, function(m) diag(m)[ix], numeric(1))
  lags <- which(w != 0) - 1L

  row_of <- function(tx, rw){
    list(i = rep(rw, length(lags)), j = tx + s - lags, x = w[lags + 1L])
  }
  rows <- Map(row_of, tau, seq_along(tau))
  B <- sparseMatrix(i = unlist(lapply(rows, `[[`, "i")),
                    j = unlist(lapply(rows, `[[`, "j")),
                    x = unlist(lapply(rows, `[[`, "x")),
                    dims = c(length(tau), t + s))
  first <- row_of(1L, 1L)

  list(ix = ix, tau = tau, y = Ymat[tau, ix], g = c(tau[1] - 1L, diff(tau)), B = B,
       B1 = sparseMatrix(i = first$i, j = first$j, x = first$x, dims = c(1L, t + s)))

}


#' A series' likelihood at its observation dates, latent weeks integrated out
#'
#' An AR(1) error observed `g` periods apart satisfies
#' `e[tau_j] | e[tau_{j-1}] ~ N(rho^g e[tau_{j-1}], sigma w)`, with
#' `w = (1 - rho^(2g)) / (1 - rho^2)`. In terms of the fitted values `lambda * B f`
#' that is linear in `f`. Period 1 has mean zero rather than the fitted value (see
#' the first block of `Kmat` in [draw_augmented_data()]), so the first observation
#' has mean `lambda (B[1,] - rho^g B1) f`, with `g` the distance from period 1 and
#' `w` taken over `g + 1` periods. That reduces to mean zero if period 1 is itself
#' observed.
#'
#' @return A list with `A`, `r` and `w` of the regression of `r` on `lambda * A f`,
#'   with errors of variance `sigma * w`.
#'
#' @noRd
collapsed_regression <- function(obs, rho){

  rg <- rho^obs$g
  w <- skip_weights(rho, obs$g)
  w[1] <- skip_weights(rho, obs$g[1] + 1L)

  B_lag <- rbind(obs$B1, obs$B[-nrow(obs$B), , drop = FALSE])
  A <- obs$B - Diagonal(x = rg) %*% B_lag
  r <- obs$y - rg * c(0, obs$y[-length(obs$y)])

  list(A = A, r = r, w = w)

}


#' `sum(rho^(2 * 0:(g-1)))`, stable for `rho` near zero
#'
#' @noRd
skip_weights <- function(rho, g){

  rr <- rho^2
  if(rr < 1e-12) return(rep(1, length(g)))
  (1 - rr^g)/(1 - rr)

}


#' Redraw one series' latent cells given the factor and its parameters
#'
#' Observed cells are held at their value by the same `1e-9` variance that
#' [draw_augmented_data()] uses.
#'
#' @noRd
#' @importFrom stats rnorm
draw_series_latent <- function(obs, gf_ix, rho, sigma, t){

  K <- Diagonal(n = t) + bandSparse(t, t, k = -1L, diagonals = list(rep(-rho, t - 1L)))
  mask <- numeric(t)
  mask[obs$tau] <- 1e9
  yv <- numeric(t)
  yv[obs$tau] <- obs$y * 1e9

  P <- forceSymmetric(crossprod(K)/sigma + Diagonal(x = mask))
  b <- as.numeric(crossprod(K, c(0, gf_ix))/sigma) + yv

  as.numeric(solve(P, b) + solve(chol(P), rnorm(t)))

}


#' Draw a low-frequency series' rho, sigma and lambda, latent weeks integrated out
#'
#' In this order, each from the distribution with everything drawn before it
#' integrated in and the latent weeks integrated out:
#'
#' 1. `rho | lambda, f, y`, with `sigma` integrated out analytically as well. One
#'    dimension, so an independence Metropolis step whose proposal is a
#'    histogram of the density on a grid: the grid only has to be good enough to
#'    accept often, because the accept step makes the draw exact. It can cross
#'    zero freely, where the conditional on imputed errors could not.
#' 2. `sigma | rho, lambda, f, y`.
#' 3. `lambda | rho, sigma, f, y`.
#'
#' See [collapsed_regression()] for the likelihood.
#'
#' @noRd
#' @importFrom stats rgamma rnorm runif
draw_low_frequency <- function(obs, f, lambda, rho, draw_rho, prior_sigma, prior_rho,
                               prior_lambda, control, grid_size = 401L){

  m <- length(obs$y)
  c0 <- prior_sigma$c0
  d0 <- prior_sigma$d0

  # the errors at the observation dates, and what each one follows: period 1's
  # is -lambda * B1 f, as period 1 has mean zero rather than the fitted value
  fb <- as.numeric(obs$B %*% f)
  fb1 <- as.numeric(obs$B1 %*% f)
  e <- obs$y - lambda * fb
  e0 <- c(-lambda * fb1, e[-m])

  # sufficient statistics per distinct gap, so that the density costs one
  # evaluation per gap and not one per observation
  gaps <- obs$g
  first <- seq_len(m) == 1L
  key <- paste(gaps, first)
  groups <- split(seq_len(m), key)
  stats_g <- lapply(groups, function(idx){
    list(g = gaps[idx[1]], w_g = gaps[idx[1]] + as.integer(first[idx[1]]), n = length(idx),
         s11 = sum(e[idx]^2), s10 = sum(e[idx] * e0[idx]), s00 = sum(e0[idx]^2))
  })

  rss_of <- function(r){
    rss <- numeric(length(r))
    logw <- numeric(length(r))
    rr <- r^2
    for(st in stats_g){
      rp <- r^st$g
      w <- (1 - rr^st$w_g)/(1 - rr)
      w[rr < 1e-12] <- 1
      rss <- rss + (st$s11 - 2*rp*st$s10 + rp^2*st$s00)/w
      logw <- logw + st$n*log(w)
    }
    list(rss = rss, logw = logw)
  }

  log_post <- function(r){
    q <- rss_of(r)
    -(r - prior_rho$r0)^2/(2*prior_rho$R0) - 0.5*q$logw - 0.5*(c0 + m)*log(d0 + q$rss)
  }

  if(draw_rho){

    edges <- seq(-control$rho_max, control$rho_max, length.out = grid_size)
    width <- edges[2] - edges[1]
    lp <- log_post(edges)
    dens <- exp(lp - max(lp))
    mass <- (dens[-1] + dens[-grid_size])/2
    mass <- mass/sum(mass)

    cell <- sample.int(grid_size - 1L, 1L, prob = mass)
    proposal <- edges[cell] + width*runif(1)

    old_cell <- min(findInterval(rho, edges, all.inside = TRUE), grid_size - 1L)
    log_alpha <- log_post(proposal) - log_post(rho) + log(mass[old_cell]) - log(mass[cell])

    if(log(runif(1)) < log_alpha) rho <- proposal

  }

  rss <- rss_of(rho)$rss
  sigma <- 1/rgamma(1, shape = (c0 + m)/2, rate = (d0 + rss)/2) + control$jitter
  if(sigma > control$sigma_max) sigma <- control$sigma_max

  # collapsed_regression(), on plain vectors: this runs once per series per sweep
  rg <- rho^gaps
  w <- skip_weights(rho, gaps + as.integer(first))
  x <- fb - rg * c(fb1, fb[-m])
  r <- obs$y - rg * c(0, obs$y[-m])
  prec <- 1/prior_lambda$B0 + sum(x^2/w)/sigma
  mu <- (prior_lambda$b0/prior_lambda$B0 + sum(x*r/w)/sigma)/prec
  lambda <- mu + rnorm(1)/sqrt(prec)

  list(lambda = lambda, sigma = sigma, rho = rho)

}


#' One sweep of the Gibbs sampler
#'
#' A function of its own so that `dev/geweke.R` can test the sampler's actual
#' sequence of draws rather than a copy of it.
#'
#' @param state The sampler's current state, in its own types: `f`, `lambda`,
#'   `phi`, `sigma`, `rho`, `h`, `omega`, `Xmat`, `indicators`.
#' @param ctx What does not change between sweeps; see [run_sampling()].
#'
#' @return `state`, updated.
#'
#' @noRd
gibbs_sweep <- function(state, ctx){

  f <- state$f; lambda <- state$lambda; phi <- state$phi; sigma <- state$sigma
  rho <- state$rho; h <- state$h; omega <- state$omega; indicators <- state$indicators

  n <- ctx$n; t <- ctx$t; t2 <- ctx$t2; p <- ctx$p; s <- ctx$s
  Llist <- ctx$Llist; inventory <- ctx$inventory; target <- ctx$target
  priors <- ctx$priors; control <- ctx$control

  Gmat <- get_gmat(ctx$Gmat_prealloc, Llist, rho, lambda, s, t, n)

  # 0. augment data
  Xmat <- draw_augmented_data(Gmat = Gmat, f = f, rho = rho, sigma = sigma, n = n, t = t,
                              StV1S = ctx$StV1S, StV1SY = ctx$StV1SY, return_sample = TRUE)

  # quasi-differenced data used identically by draw_factors/draw_lambda/draw_sigma
  # below (Xmat and rho are unchanged across these three calls) - compute once
  Xmat_tilde <- Xmat[-1,] - Xmat[-nrow(Xmat),] %*% rho
  Xvec_tilde <- t(Xmat_tilde)
  dim(Xvec_tilde) <- c(n*(t-1),1)

  # 1. draw factors (conditional on model parameters). The factor and the
  # target's unobserved weeks are one grouped draw: f from the target's actual
  # observations, with those weeks integrated out, and then those weeks given f.
  # Conditioning f on them instead is what froze the nowcast: with sigma_target
  # about 1e-3 each pins the other, for an autocorrelation time of about 4200.
  obs <- ctx$target_obs
  tx <- obs$ix
  target_reg <- collapsed_regression(obs, diag(rho)[tx])
  target_reg$lambda <- as.numeric(lambda)[tx]
  target_reg$sigma <- diag(sigma)[tx]

  f <- draw_factors(Xvec_tilde = Xvec_tilde,
                    Gmat = Gmat,
                    n = n,
                    p = p,
                    s = s,
                    t = t,
                    t2 = t2,
                    phi = phi,
                    sigma = sigma,
                    h = h,
                    collapsed_ix = tx,
                    collapsed = list(target_reg))

  # draw_factors() does not condition on the rows past t2, so they are redrawn
  # given the new f before anything below uses them.
  if(t2 < t){
    Xmat <- draw_horizon_rows(Xmat, Gmat = Gmat, f = f, rho = rho, sigma = sigma,
                              n = n, t = t, t2 = t2)
  }

  gf <- as.numeric(Gmat %*% f)
  dim(gf) <- c(n, t - 1)
  Xmat[, tx] <- draw_series_latent(obs, gf[tx,], diag(rho)[tx], diag(sigma)[tx], t)

  Xmat_tilde <- Xmat[-1,] - Xmat[-nrow(Xmat),] %*% rho
  Xvec_tilde <- t(Xmat_tilde)
  dim(Xvec_tilde) <- c(n*(t-1),1)

  # 2. draw the factor-innovation variance: a full stochastic volatility path,
  #    or - when it is switched off - a single constant variance, still
  #    estimated (the factor's scale is pinned by lambda[target] = 1, so the
  #    variance is the free parameter the data determines; see CLAUDE.md,
  #    "Scale identification"). Both write into `h` as log-sd, so everything
  #    downstream (draw_factors, draw_phi) is unchanged.
  #
  #    The indicators are drawn directly before h, from the current f, with
  #    nothing drawn in between: they are the auxiliary variables of the
  #    Kim-Shephard-Chib step, not a block of their own. Del Negro & Primiceri
  #    (2015), Algorithm 2.
  if(ctx$stochastic_volatility){
    indicators <- draw_indicators(h, f, phi, n, p, s, t, control)
    h <- draw_volatility(f = f,
                         phi = phi,
                         n = n,
                         p = p,
                         s = s,
                         t = t,
                         omega = omega,
                         indicators = indicators,
                         h_old = h,
                         NtN = ctx$NtN,
                         control = control)
  } else {
    h <- draw_factor_variance(f = f, phi = phi, p = p, s = s, t = t,
                              prior = priors$factor_var, control = control)
  }

  # 3. draw model parameters (conditional on factors and volatility)
  Zmat <- get_zmat(f = f, n = n, t = t, s = s, Llist = Llist, rho = rho)
  lambda <- draw_lambda(Xvec_tilde = Xvec_tilde,
                        Zmat = Zmat,
                        sigma = sigma,
                        n = n, t = t,
                        inventory = inventory,
                        target = target,
                        prior = priors$lambda)

  # sigma conditions on the lambda just drawn
  Gmat <- get_gmat(ctx$Gmat_prealloc, Llist, rho, lambda, s, t, n)
  sigma <- draw_sigma(Xvec_tilde = Xvec_tilde, Gmat = Gmat, f = f, n = n, t = t,
                      x1 = Xmat[1,], inventory = inventory, target = target, sigma = sigma,
                      prior_target = priors$sigma_target,
                      prior_other = priors$sigma_other, control = control)
  phi <- draw_phi(f = f, h = h, p = p, t = t, phi_old = phi, prior = priors$phi, control = control)

  # omega (the variance of h's own innovations) exists solely to draw a
  # volatility PATH; with a constant variance it is meaningless.
  if(ctx$stochastic_volatility) omega <- draw_omega(h = h, t = t, s = s, p = p,
                                                    prior = priors$omega, control = control)

  if(ctx$serial_correlation){
    rho <- draw_rho(Xmat = Xmat, f = f,  n = n, t = t, s = s, sigma = sigma,
                    lambda = lambda, Llist = Llist, inventory = inventory, target = target,
                    prior_target = priors$rho_target, prior_other = priors$rho_other,
                    control = control, tally = ctx$rho_tally,
                    skip = ctx$low_ix, rho_old = diag(rho))
  }

  # Low-frequency series: rho, sigma and lambda again, this time from the
  # observations themselves, with their latent weeks integrated out. Given imputed
  # weekly errors rho can only take tiny steps, because the data identify it
  # through rho^4 alone. Nothing below uses this sweep's Xmat for these series, and
  # the next sweep starts by redrawing it, so this is a grouped draw of these
  # parameters and those weeks and needs no further step.
  if(length(ctx$low_ix)){
    lam <- as.numeric(lambda)
    sig <- diag(sigma)
    rh <- diag(rho)
    fv <- as.numeric(f)
    for(j in seq_along(ctx$low_ix)){
      ix <- ctx$low_ix[j]
      draw <- draw_low_frequency(ctx$low_obs[[j]], f = fv, lambda = lam[ix], rho = rh[ix],
                                 draw_rho = ctx$serial_correlation,
                                 prior_sigma = priors$sigma_other,
                                 prior_rho = priors$rho_other,
                                 prior_lambda = priors$lambda, control = control)
      lam[ix] <- draw$lambda
      sig[ix] <- draw$sigma
      rh[ix] <- draw$rho
    }
    lambda <- Matrix(lam, n, 1)
    sigma <- Diagonal(x = sig)
    rho <- Diagonal(x = rh)
  }

  list(f = f, lambda = lambda, phi = phi, sigma = sigma, rho = rho, h = h,
       omega = omega, Xmat = Xmat, indicators = indicators)

}


#' Draw the latent factor conditional on model parameters
#'
#' @noRd
#' @importFrom stats rnorm
draw_factors <- function(Xvec_tilde, Gmat, n, p, s, t, t2, phi, sigma, h, return_sample = TRUE,
                         collapsed_ix = integer(), collapsed = list()){

  # See section 2.5 Estimation
  H <- Reduce("+",lapply(1:p, function(px){

    cbind(rbind(Matrix(0,px,(t+s-px)),
                kronecker(Diagonal(t+s-px), -phi[px])),
          Matrix(0,(t+s),px))

  })) + Diagonal(n = (t+s))

  V <- Diagonal(x = exp(2*h))
  F0 <- t(H) %*% solve(V) %*% H

  # define selection vector such that latent data in forecast horizon has no more impact on factor
  Svec <- c(rep(1,t2-1),rep(0,t-t2))

  # series in collapsed_ix enter through their own observations below instead
  sigma_inv <- 1/diag(sigma)
  sigma_inv[collapsed_ix] <- 0
  Svec_sigma_inv <- Diagonal(x = Svec) %x% Diagonal(x = sigma_inv)

  # Calculate conditional posterior of the factors
  F1 <- F0 + t(Gmat) %*% Svec_sigma_inv %*% Gmat
  rhs <- t(Gmat) %*% Svec_sigma_inv %*% Xvec_tilde

  for(reg in collapsed){
    A_w <- reg$lambda * t(reg$A) %*% Diagonal(x = 1/(reg$sigma * reg$w))
    F1 <- F1 + reg$lambda * A_w %*% reg$A
    rhs <- rhs + A_w %*% reg$r
  }

  F1 <- forceSymmetric(F1)
  f1 <- solve(F1, rhs)

  if(return_sample){

    f <- as.matrix(f1 + solve(chol(F1), rnorm((t+s))))

  } else {

    f <- as.matrix(f1)

  }

  return(f)

}


#' Draw the stochastic volatility path
#'
#' @noRd
#' @importFrom stats rnorm
draw_volatility <- function(f, phi, n, p, s, t, omega, indicators, h_old, NtN, control){

  #  See appendix A.2 Stochastic Volatility
  err <- c(rep(0,p),f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
    f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[px]})))

  # qs <- quantile(err, probs = c(0.05,0.95))
  # err[which(err<qs[1])] <- qs[1]
  # err[which(err>qs[2])] <- qs[2]

  w <- log(err^2 + control$sv_offset)

  W <- Diagonal(x = 2, n = t+s)

  # Diagonal(x = rep(omega,t+s-1)) is omega*I, so its solve() is exactly I/omega;
  # NtN = crossprod(N) for the (parameter-independent) first-difference operator
  # N is precomputed once in run_sampling() rather than rebuilt every iteration
  Q0 <- NtN / omega # precision matrix

  # simulate from approximated chi-loq square distribution using the
  # log chi-squared normal-mixture constants defined at the top of this file
  nx <- indicators
  xi = Diagonal(x = NMIX_VAR[nx])
  mu <- Matrix(NMIX_MEAN[nx] - 1.2704,t+s,1)

  # Calculate conditional posterior of the stochastic volatility (Appendix A.2)
  Q1 <-  forceSymmetric(Q0 + t(W) %*% solve(xi) %*% W)
  q1 <- solve(Q1,  t(W) %*% solve(xi) %*% (w - mu))

  h <- as.matrix(q1 + solve(chol(Q1), rnorm((t+s))) + control$jitter)

  # numerical stability, discard draws that are above the upper bound
  ubound <- -2.15
  h[which(h > ubound)] <- h_old[which(h > ubound)]

  return(h)

}


#' Draw a single constant factor-innovation variance
#'
#' Used in place of [draw_volatility()] when `stochastic_volatility = FALSE`.
#'
#' Switching stochastic volatility off here cannot mean "fix the variance":
#' the factor's scale is already pinned by the identifying restriction
#' `lambda[target] = 1`, so the innovation variance is the free parameter the
#' data determines, and imposing a value would fight the anchoring. (This is
#' the opposite of `fcast_dfm()`, whose loadings are unrestricted and whose
#' variance therefore *carries* the identification and is fixed at 1. See
#' CLAUDE.md, "Scale identification".)
#'
#' So the variance is still estimated, just constant over time. With
#' `eps_t ~ N(0, sigma_f^2)` in the factor state equation and an inverse-gamma
#' prior, the conditional posterior is conjugate:
#' `sigma_f^2 | . ~ IG((c0 + N)/2, (d0 + sum(v^2))/2)`, where `v` are the state
#' equation residuals.
#'
#' The result is returned on the same log-sd scale that [draw_volatility()]
#' uses, i.e. `h = 0.5 * log(sigma_f^2)` repeated over all periods, so that
#' `exp(2*h) == sigma_f^2` and every downstream consumer of `h`
#' ([draw_factors()], [draw_phi()]) works unchanged.
#'
#' @noRd
#' @importFrom stats rgamma
draw_factor_variance <- function(f, phi, p, s, t, prior, control){

  # residuals of the factor state equation, computed exactly as in
  # draw_volatility(); the first p entries are the zero padding it also uses
  err <- c(rep(0,p), f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
    f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[px]})))
  v <- err[(p+1):(t+s)]

  # uninformative prior; see dfm_priors()
  c0 <- prior$c0
  d0 <- prior$d0

  c1 <- c0 + length(v)
  d1 <- d0 + sum(v^2)

  sigma_f2 <- 1/rgamma(n = 1, shape = c1/2, rate = d1/2) + control$jitter

  matrix(0.5 * log(sigma_f2), t+s, 1)

}


#' Draw the mixture indicators for the log chi-squared approximation
#'
#' @noRd
#' @importFrom stats dnorm
draw_indicators <- function(h, f, phi, n, p, s, t, control){

  #  See appendix A.2 Stochastic Volatility
  err <- c(rep(0,p),f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
    f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[px]})))

  w <- log(err^2 + control$sv_offset)

  # component densities as a (t+s) x 7 matrix, built with one vectorized dnorm()
  # call per mixture component instead of (t+s)*7 scalar calls - dnorm is fully
  # vectorized, so the scalar version paid ~4900 R-level call overheads per
  # iteration for no reason
  base_mean <- 2 * as.numeric(h)
  wv <- as.numeric(w)
  dens <- vapply(seq_len(7), function(px){
    NMIX_PROB[px] * dnorm(x = wv, mean = base_mean + NMIX_MEAN[px] - 1.2704, sd = NMIX_SD[px])
  }, numeric(t+s))

  # the per-period sample() calls are deliberately kept as a loop in the same
  # order as before: this consumes the RNG stream identically, so output stays
  # bit-identical to the pre-vectorization implementation
  probs <- vapply(seq_len(t+s), function(tx){
    sample(x = 1:7, size = 1, prob = dens[tx,])
  }, integer(1))

  return(probs)
}


#' Draw the augmented (latent) dataset
#'
#' @noRd
#' @importFrom stats rnorm
draw_augmented_data <- function(Gmat, f, rho, sigma, n, t, StV1S, StV1SY, return_sample = TRUE){

  # StV1S/StV1SY are the "propose dataset" mask terms (originally
  # t(Smat) %*% (t(Smat) %*% V1 %*% Smat) %*% Smat and ...%*% Yvec) - these
  # depend only on Ymat/n/t, not on any sampled parameter, so they are
  # precomputed once in run_sampling() instead of rebuilt every iteration
  Kmat <- cbind(rbind(Matrix(0,n, n*(t-1)),
                      kronecker(Diagonal(t-1), -rho)),
                Matrix(0,(t)*n,n)) + Diagonal(n = n*t)

  # solve(Diagonal(n = t) %x% sigma) == Diagonal(n = t) %x% solve(sigma)
  # (Kronecker product of invertible matrices), avoiding a solve() on the
  # full (t*n)x(t*n) matrix in favor of one on the much smaller n x n sigma
  sigma_inv <- solve(sigma)
  Dt_sigma_inv <- Diagonal(n = t) %x% sigma_inv

  P0 <- t(Kmat) %*% Dt_sigma_inv %*% Kmat

  # Calculate conditional posterior of the factors, see Appendix A.3
  P1 <-  forceSymmetric(P0 + StV1S)
  p1 <- solve(P1, t(Kmat) %*% Dt_sigma_inv %*% rbind(Matrix(0,n,1),Gmat %*% f) + StV1SY)

  Xvec <- as.matrix(p1 + solve(chol(P1), rnorm((t*n))))

  dim(Xvec) <- c(n,t)
  Xmat <- t(Xvec)

  return(Xmat)

}


#' Redraw the rows past the end of the data, given the factor
#'
#' With `extend_to`, [draw_factors()] drops these rows from the factor's
#' conditional. Together with this draw that is one grouped draw of the factor
#' and those rows, given the rest. Nothing is observed there, so it is a forward
#' simulation of the measurement equation.
#'
#' @noRd
#' @importFrom stats rnorm
draw_horizon_rows <- function(Xmat, Gmat, f, rho, sigma, n, t, t2){

  gf <- as.numeric(Gmat %*% f)
  dim(gf) <- c(n, t - 1)
  rd <- diag(rho)
  sd_v <- sqrt(diag(sigma))

  for(tx in (t2 + 1):t){
    Xmat[tx,] <- gf[, tx - 1] + rd * Xmat[tx - 1,] + sd_v * rnorm(n)
  }

  Xmat

}


#' Draw the factor loadings
#'
#' @noRd
#' @importFrom stats rnorm
draw_lambda <- function(Xvec_tilde, Zmat, sigma, n, t, inventory, target, prior){

  # See appendix A.4 Conditional distributions of Remaining Parameters: Factor Loadings

  # uninformative priors (see dfm_priors())
  b0 <- Matrix(prior$b0,n,1)
  B0 <- Diagonal(x = prior$B0, n = n)

  # solve(sigma) and its Kronecker product with Diagonal(t-1) are otherwise
  # computed twice (once for B1, once for b1) for the same result
  Z_sigma_inv <- t(Zmat) %*% (Diagonal(t-1) %x% solve(sigma))

  # Conditional posterior distribution of the factor loadings lambda
  B1 <- solve(B0) + Z_sigma_inv %*% Zmat
  b1 <- solve(B1, solve(B0) %*% b0 + Z_sigma_inv %*% Xvec_tilde)

  lambda <- b1 + solve(chol(forceSymmetric(B1)),rnorm(n))

  # imposing identifying restriction
  lambda[which(inventory$key == target)] <- 1

  return(lambda)

}


#' Draw the measurement error variances
#'
#' @noRd
#' @importFrom stats rgamma
draw_sigma <- function(Xvec_tilde, Gmat, f, n, t, x1, inventory, target, sigma, control,
                       prior_target, prior_other){
  # See appendix A.4 Conditional distributions of Remaining Parameters: Measurement Error Covariance Matrix

  # get errors
  Xfit <- Gmat %*% f
  U <- Xvec_tilde - Xfit
  dim(U) <- c(n,t-1)
  U <- t(U)

  # draw measurement equation variance
  sigma = Diagonal(x = sapply(1:n, function(ix){

    if(ix == which(inventory$key == target)){

      # STRUCTURAL: the prior choice for the target variable shrinks the
      # measurement error variance strongly towards zero. This ensures that the
      # high frequency factor is approximatively coherent with the low frequency
      # target variable - i.e. it *is* the identification, not a tuning knob.
      # Defaults to c0 = t, d0 = t * 1e-3; see dfm_priors().

      c0 <- prior_target$c0
      d0 <- prior_target$d0

    } else {

      # this prior choice is uninformative

      c0 <- prior_other$c0
      d0 <- prior_other$d0

    }

    # t observations: the t-1 quasi-differenced rows and the first row, which
    # has mean zero (see the first block of Kmat in draw_augmented_data())
    c1 <- c0 + t
    d1 <- d0 + t(U[,ix]) %*% U[,ix] + x1[ix]^2

    # sample from inverse gamma distribution
    1/rgamma(n = 1,
             shape = c1/2,
             rate = d1/2) + control$jitter # avoid singularities

  }))

  # numerical stability in beginning; bound from dfm_control()
  diag(sigma)[which(diag(sigma) > control$sigma_max)] <- control$sigma_max

  return(sigma)

}


#' Draw the serial correlation of measurement errors
#'
#' @noRd
#' @importFrom stats rnorm
draw_rho <- function(Xmat, f, n, t, s, sigma, lambda, Llist, inventory, target,
                    control,
                     prior_target, prior_other, tally = NULL,
                     skip = integer(), rho_old = NULL){

  # See appendix A.4 Conditional distributions of Remaining Parameters: Autocorrelation of Measurement Errors
  # construct auxiliary matrix

  # Every Llist entry is diagonal, so Llist[[sx]] %*% lambda is an elementwise
  # product and each term of the sum is an outer product - accumulate them as
  # plain dense matrices instead of building s+1 Matrix objects and folding
  # them with Matrix arithmetic. Runs in the same sx order, with the same
  # per-element multiply-then-add sequence, as the original left-folding
  # Reduce(): floating-point addition is not associative, so that ordering is
  # what keeps the result bit-identical.
  fv <- as.numeric(f)
  lam <- as.numeric(lambda)

  Xfit <- NULL
  for(sx in 0:s){

    a <- diag(Llist[[as.character(sx)]]) * lam
    term <- outer(fv[seq(from = 1+s-sx, to = t+s-sx)], a)
    Xfit <- if(is.null(Xfit)) term else Xfit + term

  }

  E <- Xmat - Xfit

  # hoisted out of the per-series loop below, where each was recomputed for
  # every one of the n series: the target lookup rescanned inventory$key, the
  # measurement variances went through ddiMatrix `[` dispatch, and the lagged
  # and led blocks of E were re-sliced by negative indexing on every use
  target_ix <- which(inventory$key == target)
  sigma_d <- diag(sigma)
  nr <- nrow(E)
  Elag <- E[-nr, , drop = FALSE]
  Elead <- E[-1, , drop = FALSE]

  rho <- Diagonal(x = sapply(1:n, function(nx){

    # drawn by draw_low_frequency() instead
    if(nx %in% skip) return(rho_old[nx])

    if(nx == target_ix){

      # STRUCTURAL: shrinking the target's serial correlation to zero is part
      # of the anchoring; see dfm_priors()
      r0 = prior_target$r0
      R0 = prior_target$R0

    } else {

      r0 = prior_other$r0
      R0 = prior_other$R0
    }

    elag <- Elag[,nx]
    inv_sigma <- 1/sigma_d[nx]

    # The two lines below deliberately keep the original association. `%*%`
    # binds tighter than `*`, so in R1 the 1/sigma scaling is applied AFTER
    # the elag'elag dot product, whereas r1's original
    # solve(sigma) %*% t(elag) %*% elead associates left to right and so
    # scales t(elag) BEFORE dotting it with elead. In floating point those
    # are not interchangeable, so both forms are preserved verbatim.
    R1 = 1/(1/R0 + inv_sigma * (t(elag) %*% elag))
    r1 = R1 %*% ((1/R0) * r0 + (inv_sigma * t(elag)) %*% Elead[,nx])


    # Initialize stationarity check
    check <- FALSE
    count <- 0
    while(!check){

      # draw rho_i
      rho_i = rnorm(1, r1, sqrt(R1)) + control$jitter # avoid exact zeros
      count <- count + 1

      # run checks
      if(count > control$rho_max_tries) {
        rho_i <- control$rho_fallback
        # Counted, not warned about here: this runs inside the per-iteration
        # loop, so a warning would fire once per series per draw. run_sampling()
        # reports the total once the chain is done (#118).
        if(!is.null(tally)) tally$n <- tally$n + 1L
      }
      check = abs(rho_i) < control$rho_max

    }

    return(rho_i)

  }))
}


#' Draw the autoregressive coefficients of the factor
#'
#' @noRd
#' @importFrom stats rnorm
draw_phi = function(f, h, p, t, phi_old, prior, control){
  # See appendix A.4 Conditional distributions of Remaining Parameters: Autoregressive Coefficients

  m = f[(p+1):(nrow(f)),]
  M = do.call(cbind, lapply(c(1:p), function(px) f[c((1+p-px):(nrow(f)-px)),]))

  V <- Diagonal(x = exp(2*h[(1+p):(nrow(h)),]))

  # uninformative prior; A0 defaults to 0.12/(lag^2), see dfm_priors()
  a0 <- matrix(rep(prior$a0, p))
  A0 <- Diagonal(x = prior$A0, n = p)

  # distribution parameters
  A1 <- solve(solve(A0) + t(M) %*% solve(V) %*% M) # Formula (26)
  a1 <- A1 %*% (solve(A0) %*% a0 + t(M) %*% solve(V) %*% m) # Formula (27)

  # draw phi
  phi <- as.numeric(a1 + t(rnorm(p,0,1) %*% chol(forceSymmetric(A1))))

  # discard draw if not stationary or negatively autocorrelated
  phi[which(phi < 0)] <- 0
  if(sum(phi) > control$phi_sum_max | sum(diff(phi) > 0) > 0){

    phi <-  phi_old
  # repeat {
  #   phi <- as.numeric(a1 + t(rnorm(p,0,1) %*% chol(forceSymmetric(A1))))
  #   phi[phi < 0] <- 0
  #
  #   if(sum(phi) <= 0.95 && sum(diff(phi) > 0) == 0) break
  }

  return(phi)

}


#' Draw the stochastic volatility state equation variance
#'
#' @noRd
#' @importFrom stats rgamma
draw_omega <- function(h, t, s, p, prior, control){
  # See appendix A.4 Conditional distributions of Remaining Parameters: Stochastic Volatility Variance
  v <- h[2:nrow(h),] - h[seq(from = 1, nrow(h)-1),,drop=FALSE]

  # informative prior; defaults to k0 = t, l0 = t * 1e-2, see dfm_priors()
  k0 <- prior$k0
  l0 <- prior$l0

  # parametrize posterior
  k1 <- k0 + t + s
  l1 <- l0 + as.numeric(t(v) %*% v)

  # sample stochastic volatility state equation error variance
  omega = 1/rgamma(n = 1,
                   shape = 0.5 * k1,
                   rate = 0.5 * l1) + control$jitter # avoid singularity

  # if(omega > 0.1)  omega <- 0.1

  return(omega)

}
