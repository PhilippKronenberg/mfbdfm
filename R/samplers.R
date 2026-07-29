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
                         stochastic_volatility = TRUE, serial_correlation = TRUE){

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

  # preallocations
  Llist <- get_distributed_lags(inventory)

  # random parameter starting values
  phi <- c(0.75,rep(0,p-1))
  lambda <- Matrix(1,n,1)
  sigma <- Diagonal(x = runif(n), n = n)
  omega <- 1e-2
  h <- matrix(-5, t+s, 1)
  f <- matrix(rnorm(t+s), t+s, 1)
  # with serial_correlation = FALSE the measurement-error autocorrelations are
  # held at (effectively) zero rather than drawn; 1e-9 rather than exactly 0 to
  # avoid singularities downstream, matching fcast_dfm()
  if(serial_correlation){
    rho <- Diagonal(x = runif(n))
  } else {
    rho <- Diagonal(x = 1e-9, n = n)
  }
  Xmat = matrix(rnorm(t*n), t, n)
  indicators = replicate(t+s, sample(x = 1:7, size = 1, prob = rep(1/7,7)))

  # precompute sparse structures that depend only on the fixed data/dimensions
  # (Ymat, n, t, s), not on any sampled parameter, so they would otherwise be
  # rebuilt identically on every one of the burn_in + length_sample*thinning
  # iterations below
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

  # initialize progress bar
  pb <- txtProgressBar(style = 3)

  # restore the caller's graphics state once, however this function exits,
  # instead of resetting it after every plotted iteration below
  if(plots == TRUE){
    oldpar <- par(no.readonly = TRUE)
    on.exit(par(oldpar), add = TRUE)
  }

  # loop until sampling complete
  for(jx in 1:(burn_in + length_sample*thinning)){

    setTxtProgressBar(pb, jx/(burn_in + length_sample * thinning))

    Gmat <- get_gmat(Gmat_prealloc, Llist, rho, lambda, s, t, n)

    # 0. augment data
    Xmat <- draw_augmented_data(Gmat = Gmat, f = f, rho = rho, sigma = sigma, n = n, t = t,
                                StV1S = StV1S, StV1SY = StV1SY, return_sample = TRUE)

    # quasi-differenced data used identically by draw_factors/draw_lambda/draw_sigma
    # below (Xmat and rho are unchanged across these three calls) - compute once
    Xmat_tilde <- Xmat[-1,] - Xmat[-nrow(Xmat),] %*% rho
    Xvec_tilde <- t(Xmat_tilde)
    dim(Xvec_tilde) <- c(n*(t-1),1)

    # 1. draw factors (conditional on model parameters)
    f <- draw_factors(Xvec_tilde = Xvec_tilde,
                      Gmat = Gmat,
                      n = n,
                      p = p,
                      s = s,
                      t = t,
                      t2 = t2,
                      phi = phi,
                      sigma = sigma,
                      h = h)

    # 2. draw the factor-innovation variance: a full stochastic volatility path,
    #    or - when it is switched off - a single constant variance, still
    #    estimated (the factor's scale is pinned by lambda[target] = 1, so the
    #    variance is the free parameter the data determines; see CLAUDE.md,
    #    "Scale identification"). Both write into `h` as log-sd, so everything
    #    downstream (draw_factors, draw_phi) is unchanged.
    if(stochastic_volatility){
      h <- draw_volatility(f = f,
                           phi = phi,
                           n = n,
                           p = p,
                           s = s,
                           t = t,
                           omega = omega,
                           indicators = indicators,
                           h_old = h,
                           NtN = NtN)
    } else {
      h <- draw_factor_variance(f = f, phi = phi, p = p, s = s, t = t)
    }

    # 3. draw model parameters (conditional on factors and volatility)
    Zmat <- get_zmat(f = f, n = n, t = t, s = s, Llist = Llist, rho = rho)
    lambda <- draw_lambda(Xvec_tilde = Xvec_tilde,
                          Zmat = Zmat,
                          sigma = sigma,
                          n = n, t = t,
                          inventory = inventory,
                          target = target)


    sigma <- draw_sigma(Xvec_tilde = Xvec_tilde, Gmat = Gmat, f = f, n = n, t = t,
                        inventory = inventory, target = target, sigma = sigma)
    phi <- draw_phi(f = f, h = h, p = p, t = t, phi_old = phi)

    # omega (the variance of h's own innovations) and the mixture indicators
    # exist solely to draw a volatility PATH; with a constant variance they are
    # meaningless. Each conditional is kept in its original position in the
    # sequence so that with the defaults the RNG is consumed exactly as before.
    if(stochastic_volatility) omega <- draw_omega(h = h, t = t, s = s, p = p)

    if(serial_correlation){
      rho <- draw_rho(Xmat = Xmat, f = f,  n = n, t = t, s = s, sigma = sigma,
                      lambda = lambda, Llist = Llist, inventory = inventory, target = target)
    }

    if(stochastic_volatility) indicators = draw_indicators(h, f, phi, n, p, s, t)

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

  close(pb)
  return(par_save)

}


#' Draw the latent factor conditional on model parameters
#'
#' @noRd
#' @importFrom stats rnorm
draw_factors <- function(Xvec_tilde, Gmat, n, p, s, t, t2, phi, sigma, h, return_sample = TRUE){

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
  Svec_sigma_inv <- Diagonal(x = Svec) %x% solve(sigma)

  # Calculate conditional posterior of the factors
  F1 <- forceSymmetric(F0 + t(Gmat) %*% Svec_sigma_inv %*% Gmat)
  f1 <- solve(F1, t(Gmat) %*% Svec_sigma_inv %*% Xvec_tilde)

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
draw_volatility <- function(f, phi, n, p, s, t, omega, indicators, h_old, NtN){

  #  See appendix A.2 Stochastic Volatility
  err <- c(rep(0,p),f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
    f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[px]})))

  # qs <- quantile(err, probs = c(0.05,0.95))
  # err[which(err<qs[1])] <- qs[1]
  # err[which(err>qs[2])] <- qs[2]

  w <- log(err^2 + 0.001)

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

  h <- as.matrix(q1 + solve(chol(Q1), rnorm((t+s))) + 1e-9)

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
draw_factor_variance <- function(f, phi, p, s, t){

  # residuals of the factor state equation, computed exactly as in
  # draw_volatility(); the first p entries are the zero padding it also uses
  err <- c(rep(0,p), f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
    f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[px]})))
  v <- err[(p+1):(t+s)]

  # uninformative prior (moves into dfm_priors() - see #48)
  c0 <- 3
  d0 <- 1e-2

  c1 <- c0 + length(v)
  d1 <- d0 + sum(v^2)

  sigma_f2 <- 1/rgamma(n = 1, shape = c1/2, rate = d1/2) + 1e-9

  matrix(0.5 * log(sigma_f2), t+s, 1)

}


#' Draw the mixture indicators for the log chi-squared approximation
#'
#' @noRd
#' @importFrom stats dnorm
draw_indicators <- function(h, f, phi, n, p, s, t){

  #  See appendix A.2 Stochastic Volatility
  err <- c(rep(0,p),f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
    f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[px]})))

  w <- log(err^2 + 0.001)

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


#' Draw the factor loadings
#'
#' @noRd
#' @importFrom stats rnorm
draw_lambda <- function(Xvec_tilde, Zmat, sigma, n, t, inventory, target){

  # See appendix A.4 Conditional distributions of Remaining Parameters: Factor Loadings

  # uninformative priors
  b0 <- Matrix(0,n,1)
  B0 <- Diagonal(x = 1, n = n)

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
draw_sigma <- function(Xvec_tilde, Gmat, f, n, t, inventory, target, sigma){
  # See appendix A.4 Conditional distributions of Remaining Parameters: Measurement Error Covariance Matrix

  # get errors
  Xfit <- Gmat %*% f
  U <- Xvec_tilde - Xfit
  dim(U) <- c(n,t-1)
  U <- t(U)

  # draw measurement equation variance
  sigma = Diagonal(x = sapply(1:n, function(ix){

    if(ix == which(inventory$key == target)){

      # the prior choice for the target variable shrinks the measurement error variance
      # strongly towards zero. this ensures that the high frequency factor
      # is approximatively coherent with the low frequency target variable

      c0 <- t
      d0 <- t * 1e-3 # Different for in-sample run than for out-of-sample run

    } else {

      # this prior choice is uninformative

      c0 <- 3
      d0 <- 5e-2

    }

    c1 <- c0 + t
    d1 <- d0 + t(U[,ix]) %*% U[,ix]

    # sample from inverse gamma distribution
    1/rgamma(n = 1,
             shape = c1/2,
             rate = d1/2) + 1e-9 # add tiny amount of noise to avoid singularities

  }))

  # numerical stability in beginning
  diag(sigma)[which(diag(sigma) > 5)] <- 5

  return(sigma)

}


#' Draw the serial correlation of measurement errors
#'
#' @noRd
#' @importFrom stats rnorm
draw_rho <- function(Xmat, f, n, t, s, sigma, lambda, Llist, inventory, target){

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

    if(nx == target_ix){

      r0 = 0
      R0 = 1e-9

    } else {

      r0 = 0
      R0 = 5
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
      rho_i = rnorm(1, r1, sqrt(R1)) + 1e-9 # add tiny amount of noise to avoid zeros
      count <- count + 1

      # run checks
      if(count > 10) {
        rho_i <- 0.98
        #print(paste0("rho adjusted: ",inventory$key[nx]))
      }
      check = abs(rho_i) < 0.99

    }

    return(rho_i)

  }))
}


#' Draw the autoregressive coefficients of the factor
#'
#' @noRd
#' @importFrom stats rnorm
draw_phi = function(f, h, p, t, phi_old){
  # See appendix A.4 Conditional distributions of Remaining Parameters: Autoregressive Coefficients

  m = f[(p+1):(nrow(f)),]
  M = do.call(cbind, lapply(c(1:p), function(px) f[c((1+p-px):(nrow(f)-px)),]))

  V <- Diagonal(x = exp(2*h[(1+p):(nrow(h)),]))

  # uninformative prior
  a0 <- matrix(c(0,rep(0,p-1)))
  A0 <- Diagonal(x = 0.12/((1:p)^2), n = p)

  # distribution parameters
  A1 <- solve(solve(A0) + t(M) %*% solve(V) %*% M) # Formula (26)
  a1 <- A1 %*% (solve(A0) %*% a0 + t(M) %*% solve(V) %*% m) # Formula (27)

  # draw phi
  phi <- as.numeric(a1 + t(rnorm(p,0,1) %*% chol(forceSymmetric(A1))))

  # discard draw if not stationary or negatively autocorrelated
  phi[which(phi < 0)] <- 0
  if(sum(phi) > 0.9 | sum(diff(phi) > 0) > 0){

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
draw_omega <- function(h, t, s, p){
  # See appendix A.4 Conditional distributions of Remaining Parameters: Stochastic Volatility Variance
  v <- h[2:nrow(h),] - h[seq(from = 1, nrow(h)-1),,drop=FALSE]

  # informative prior
  k0 <- t
  l0 <- t * 1e-2

  # parametrize posterior
  k1 <- k0 + t + s
  l1 <- l0 + as.numeric(t(v) %*% v)

  # sample stochastic volatility state equation error variance
  omega = 1/rgamma(n = 1,
                   shape = 0.5 * k1,
                   rate = 0.5 * l1) + 1e-9 # add tiny amount of noise to avoid singularity

  # if(omega > 0.1)  omega <- 0.1

  return(omega)

}
