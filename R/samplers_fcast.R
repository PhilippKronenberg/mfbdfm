# Gibbs / Metropolis-Hastings samplers for the multi-factor model of
# Eckert et al. (2025). All functions here are internal building blocks of
# fcast_dfm().
#
# These are deliberately kept separate from the single-factor samplers in
# samplers.R rather than generalized into them: the two models differ in
# their priors, in how phi is drawn (conjugate Gibbs vs Metropolis-Hastings),
# and above all in how the factors are identified (a restriction imposed
# during sampling vs a post-hoc rotation). The `_fcast` suffix marks the
# multi-factor variant throughout.

#' Run the multi-factor MCMC sampling loop
#'
#' Returns a matrix with one packed draw per row (see [list2theta_fcast()]).
#' The sampler runs *unidentified*: the factors and loadings are only
#' determined up to a `q x q` rotation, which is resolved afterwards by
#' [run_rotation_fcast()] and [run_identification_fcast()].
#'
#' @noRd
#' @importFrom stats ts time frequency rnorm runif
#' @importFrom utils txtProgressBar setTxtProgressBar
#' @importFrom graphics par title
run_sampling_fcast <- function(Ymat, q, n, t, p, s, length_sample, burn_in, thinning,
                            inventory, plots, Gmat_prealloc,
                            stochastic_volatility, serial_correlation){

  # preallocate chains
  chain <- matrix(NA, burn_in + thinning*length_sample, 100)
  checks <- sample(t*n, 100, replace = FALSE)

  # preallocation of output matrices
  theta_out <- matrix(NA, length_sample, n*t+n*q+q^2*p+2*n+t+s)

  # preallocations of constant parameters
  Llist <- get_distributed_lags(inventory)

  # random parameter starting values
  phi <- lapply(1:p, function(px) Diagonal(x = 0.1/(1+p), n = q))
  lambda <- Matrix(rnorm(n*q)*0.01, n, q)
  sigma <- Diagonal(x = runif(n), n = n)
  h <- matrix(0, t+s, 1)
  f <- matrix(rnorm((t+s)*q), t+s, q)
  # if serial correlation = FALSE, we set rhos to a very small number
  if(serial_correlation){
    rho <- Diagonal(x = runif(n))
  } else {
    rho <- Diagonal(x = 1e-9, n = n)
  }
  omega <- 0.05
  Xmat <- matrix(rnorm(t*n), t, n)
  indicators <- matrix(replicate(q*(t+s), sample(x = 1:7, size = 1, prob = rep(1/7,7))), t+s, q)

  # initialize progress bar
  pb <- txtProgressBar(style = 3)

  # restore the caller's graphics state once, however this function exits
  if(plots == TRUE){
    oldpar <- par(no.readonly = TRUE)
    on.exit(par(oldpar), add = TRUE)
  }

  # loop until sampling complete
  for(jx in 1:(burn_in + length_sample*thinning)){

    setTxtProgressBar(pb, jx/(burn_in + length_sample * thinning))

    Gmat <- get_gmat(Gmat_prealloc, Llist, rho, lambda, s, t, n)

    # 0. augment data
    Xmat <- draw_augmented_data_fcast(Ymat, Gmat, f, rho, sigma, n, t, return_sample = TRUE)

    # 1. draw factors (conditional on model parameters)
    f <- draw_factors_fcast(Xmat = Xmat, Gmat = Gmat, n = n, q = q, p = p, s = s, t = t,
                         lambda = lambda, phi = phi, sigma = sigma, h = h, rho = rho)

    # 2. draw stochastic volatility
    if(stochastic_volatility){

      h <- draw_volatility_fcast(f = f, phi = phi, n = n, q = q, p = p, s = s, t = t,
                              omega = omega, indicators = indicators, Ymat = Ymat)

    }

    # 3. draw model parameters (conditional on factors and volatility)
    Zmat <- get_zmat_fcast(f = f, n = n, t = t, s = s, Llist = Llist, rho = rho)
    lambda <- draw_lambda_fcast(Xmat = Xmat, Ymat = Ymat, Zmat = Zmat, sigma = sigma,
                             rho = rho, n = n, q = q, t = t, inventory = inventory)

    sigma <- draw_sigma_fcast(Xmat = Xmat, Ymat = Ymat, Gmat = Gmat, f = f, n = n, t = t,
                           inventory = inventory, rho = rho, sigma = sigma)
    phi <- draw_phi_fcast(f = f, h = h, p = p, q = q, t = t, s = s, phi_old = phi)

    # omega (the variance of h's own innovations) and the mixture indicators
    # exist solely to draw the volatility PATH, so they are pointless when
    # stochastic volatility is off - previously both were computed and thrown
    # away in that case. Each conditional is kept in its original position in
    # the sequence so that with stochastic_volatility = TRUE the RNG is
    # consumed exactly as before.
    if(stochastic_volatility) omega <- draw_omega_fcast(h, t, p, s, omega_old = omega)

    if(serial_correlation){
      rho <- draw_rho_fcast(Xmat = Xmat, f = f, n = n, t = t, s = s, sigma = sigma,
                         lambda = lambda, Llist = Llist, inventory = inventory)
    }

    if(stochastic_volatility) indicators <- draw_indicators_fcast(h, f, phi, n, p, q, s, t)

    # 4. track a fixed random subset of the augmented data as a convergence check
    check_sample <- Xmat[checks]
    if(jx == 1){
      chain[jx,] <- check_sample
    } else {
      chain[jx,] <- (chain[jx-1,]*(jx-1) + check_sample)/jx
    }

    # plot factors and stochastic volatility
    if(plots == TRUE && jx %% max(1, floor(burn_in/10)) == 0){

      pdat <- ts(cbind(f,h)[(s+1):(t+s),],
                 start = time(Ymat)[1],
                 frequency = frequency(Ymat))
      colnames(pdat) <- c(paste("Factor",1:q),"SV")
      plot(pdat, ylim = c(-2.5,1), xlab = NULL, ylab = NULL, main = NA)
      title(main = paste0("Iteration ",jx, ", (max. Eigenvalue ",
                          round(abs(eigen(companion_fcast(phi,p,q))$values[1]),4),")"),
            sub = paste0("SV process: omega ", round(omega,6)))

      # trace plots are a diagnostic nicety; coda is only a Suggests
      if(requireNamespace("coda", quietly = TRUE)){
        plot(coda::mcmc(chain[c(1:jx), sample(100,3,replace = FALSE)]))
      }

    }

    # 5. start saving draws upon convergence
    if(jx > burn_in & jx %% thinning == 0){

      theta_out[(jx - burn_in)/thinning,] <- list2theta_fcast(lambda, phi, diag(sigma), diag(rho), Xmat, h)

    }
  }

  close(pb)
  return(theta_out)

}


#' Draw the latent factors (multi-factor)
#'
#' @noRd
#' @importFrom stats rnorm
draw_factors_fcast <- function(Xmat, Gmat, n, q, p, s, t, lambda, phi, sigma, h, rho,
                            return_sample = TRUE){

  # See section 2.5 Estimation
  Xmat_tilde <- Xmat[-1,] - Xmat[-nrow(Xmat),] %*% rho
  Xvec_tilde <- t(Xmat_tilde)
  dim(Xvec_tilde) <- c(n*(t-1),1)

  H <- Reduce("+",lapply(1:p, function(px){

    cbind(rbind(Matrix(0,q*px,q*(t+s-px)),
                kronecker(Diagonal(t+s-px), -phi[[px]])),
          Matrix(0,q*(t+s),q*px))

  })) + Diagonal(n = q*(t+s))

  # one volatility path shared by all q factors, hence rep(h, each = q)
  V <- Diagonal(x = exp(2*rep(h, each = q)))
  F0 <- t(H) %*% solve(V) %*% H

  # Calculate conditional posterior of the factors
  F1 <- forceSymmetric(F0 + t(Gmat) %*% (Diagonal(n = t-1) %x% solve(sigma)) %*% Gmat)
  f1 <- solve(F1, t(Gmat) %*% (Diagonal(n = t-1) %x% solve(sigma)) %*% Xvec_tilde)

  if(return_sample){

    f <- f1 + solve(chol(F1), rnorm(q*(t+s)))

  } else {

    f <- f1

  }

  dim(f) <- c(q,t+s)
  as.matrix(t(f))

}


#' Draw the (common) stochastic volatility path (multi-factor)
#'
#' @noRd
#' @importFrom stats rnorm quantile
draw_volatility_fcast <- function(f, phi, n, q, p, s, t, omega, indicators, Ymat){

  #  See appendix A.2 Stochastic Volatility
  err <- rbind(matrix(0,p,q),
               f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
                 f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[[px]]})))

  w <- log(matrix(t(err))^2 + 0.001)

  # maps the single volatility path onto all q factor errors
  W <- Diagonal(n = (t+s)) %x% Matrix(2,q,1)

  N <- cbind(rbind(Matrix(0,1,t+s-1),
                   kronecker(Diagonal(t+s-1), -1)),
             Matrix(0, t+s,1)) + Diagonal(n = (t+s))

  Q0 <- t(N) %*% solve(Diagonal(x = rep(omega,t+s))) %*% N # precision matrix

  # simulate from approximated chi-log square distribution using the mixture
  # constants defined in samplers.R
  nx <- indicators
  xi <- Diagonal(x = NMIX_VAR[nx])
  mu <- Matrix(NMIX_MEAN[nx] - 1.2704, q*(t+s), 1)

  # Calculate conditional posterior of the stochastic volatility (Appendix A.2)
  Q1 <- forceSymmetric(Q0 + t(W) %*% solve(xi) %*% W)
  q1 <- solve(Q1, t(W) %*% solve(xi) %*% (w - mu))

  h <- as.matrix(q1 + solve(chol(Q1), rnorm((t+s))) + 1e-9)

  # center and scale volatility which is necessary for identification
  h <- (h - quantile(h)[2]) * (0.01 / (quantile(h)[4] - quantile(h)[2]))

  return(h)

}


#' Draw the mixture indicators (multi-factor)
#'
#' @noRd
#' @importFrom stats dnorm
draw_indicators_fcast <- function(h, f, phi, n, p, q, s, t){

  #  See appendix A.2 Stochastic Volatility
  err <- rbind(matrix(0,p,q),
               f[seq(1+p,t+s),] - Reduce('+', lapply(1:p, function(px){
                 f[seq(from = 1+p-px, t+s-px),,drop=FALSE] %*% phi[[px]]})))

  w <- log(matrix(t(err))^2 + 0.001)

  # component densities as a (q*(t+s)) x 7 matrix, built with one vectorized
  # dnorm() call per mixture component. h is indexed by ceiling(tx/q) because
  # the single volatility path is shared across the q factors.
  wv <- as.numeric(w)
  base_mean <- 2 * as.numeric(h)[ceiling(seq_len(q*(t+s))/q)]
  dens <- vapply(seq_len(7), function(px){
    NMIX_PROB[px] * dnorm(x = wv, mean = base_mean + NMIX_MEAN[px] - 1.2704, sd = NMIX_SD[px])
  }, numeric(q*(t+s)))

  vapply(seq_len(q*(t+s)), function(tx){
    sample(x = 1:7, size = 1, prob = dens[tx,])
  }, integer(1))

}


#' Draw the augmented (latent) dataset (multi-factor)
#'
#' @noRd
#' @importFrom stats rnorm
draw_augmented_data_fcast <- function(Ymat, Gmat, f, rho, sigma, n, t, return_sample = TRUE){

  Yvec <- t(Ymat)
  dim(Yvec) <- c(n*t,1)

  # propose dataset
  Smat <- Diagonal(x = sapply(1:t, function(tx) as.integer(Ymat[tx,] != 0)))
  Kmat <- cbind(rbind(Matrix(0,n, n*(t-1)),
                      kronecker(Diagonal(t-1), -rho)),
                Matrix(0,(t)*n,n)) + Diagonal(n = n*t)

  P0 <- t(Kmat) %*% solve(Diagonal(n = t) %x% sigma) %*% Kmat

  V1 <- solve(Diagonal(x = 1e-9, n = t*n))

  # Calculate conditional posterior of the factors, see Appendix A.3
  P1 <- forceSymmetric(P0 + t(Smat) %*% (t(Smat) %*% V1 %*% Smat) %*% Smat)
  p1 <- solve(P1, t(Kmat) %*% solve(Diagonal(n = t) %x% sigma) %*%
                rbind(Matrix(0,n,1), Gmat %*% matrix(t(f))) +
                t(Smat) %*% (t(Smat) %*% V1 %*% Smat) %*% Yvec)

  Xvec <- as.matrix(p1 + solve(chol(P1), rnorm((t*n))))

  dim(Xvec) <- c(n,t)
  t(Xvec)

}


#' Draw the factor loadings (multi-factor, unrestricted)
#'
#' No identifying restriction is imposed here - that is what makes the
#' post-hoc rotation in [run_rotation_fcast()] necessary.
#'
#' @noRd
#' @importFrom stats rnorm
draw_lambda_fcast <- function(Xmat, Ymat, Zmat, sigma, rho, n, q, t, inventory){

  # See appendix A.4 Conditional distributions of Remaining Parameters: Factor Loadings
  Xmat_tilde <- Xmat[-1,] - Xmat[-nrow(Xmat),] %*% rho
  Xvec_tilde <- t(Xmat_tilde)
  dim(Xvec_tilde) <- c(n*(t-1),1)

  # uninformative priors
  b0 <- Matrix(0,n*q,1)
  B0 <- Diagonal(x = 1e+9, n = n*q)

  # Conditional posterior distribution of the factor loadings lambda
  B1 <- solve(B0) + t(Zmat) %*% (Diagonal(t-1) %x% solve(sigma)) %*% Zmat
  b1 <- solve(B1, solve(B0) %*% b0 + t(Zmat) %*% (Diagonal(t-1) %x% solve(sigma)) %*% Xvec_tilde)

  lambda <- b1 + solve(chol(forceSymmetric(B1)),rnorm(n*q))
  dim(lambda) <- c(n,q)

  return(lambda)

}


#' Draw the measurement error variances (multi-factor)
#'
#' @noRd
#' @importFrom stats rgamma
draw_sigma_fcast <- function(Xmat, Ymat, Gmat, f, n, t, inventory, rho, sigma){
  # See appendix A.4: Measurement Error Covariance Matrix

  Xmat_tilde <- Xmat[-1,] - Xmat[-nrow(Xmat),] %*% rho
  Xvec_tilde <- t(Xmat_tilde)
  dim(Xvec_tilde) <- c(n*(t-1),1)

  # get errors
  Xfit <- Gmat %*% matrix(t(f))
  U <- Xvec_tilde - Xfit
  dim(U) <- c(n,t-1)
  U <- t(U)

  # draw measurement equation variance
  Diagonal(x = sapply(1:n, function(ix){

    # this prior choice is uninformative
    c0 <- 3
    d0 <- 1e-9

    # posterior
    c1 <- c0 + t
    d1 <- d0 + t(U[,ix]) %*% U[,ix]

    # sample from inverse gamma distribution
    1/rgamma(n = 1,
             shape = c1/2,
             rate = d1/2) + 1e-9 # add tiny amount of noise to avoid singularities

  }))

}


#' Draw the serial correlation of measurement errors (multi-factor)
#'
#' @noRd
#' @importFrom stats rnorm
draw_rho_fcast <- function(Xmat, f, n, t, s, sigma, lambda, Llist, inventory){

  # See appendix A.4: Autocorrelation of Measurement Errors
  Xfit <- Reduce("+", lapply(0:s, function(sx){

    f[seq(from = 1+s-sx, to = t+s-sx),] %*% t(Llist[[as.character(sx)]] %*% lambda)

  }))

  E <- Xmat - Xfit

  Diagonal(x = sapply(1:n, function(nx){

    # prior
    r0 <- 0
    R0 <- 1/t

    # posterior
    R1 <- solve(solve(R0) + solve(sigma[nx,nx]) * t(E[-nrow(E),nx]) %*% E[-nrow(E),nx])
    r1 <- R1 %*% (solve(R0) %*% r0 + solve(sigma[nx,nx]) %*% t(E[-nrow(E),nx]) %*% E[-1,nx])

    # Initialize stationarity check
    check <- FALSE
    count <- 0
    while(!check){

      # draw rho_i
      rho_i <- rnorm(1, r1, sqrt(R1)) + 1e-9 # add tiny amount of noise to avoid zeros
      count <- count + 1

      # run checks
      if(count > 10) rho_i <- 0.98
      check <- abs(rho_i) < 0.99

    }

    return(rho_i)

  }))

}


#' Draw the VAR coefficients by Metropolis-Hastings (multi-factor)
#'
#' Unlike the conjugate Gibbs step used by the single-factor model, the
#' multi-factor VAR coefficients are updated one at a time with a Beta
#' random-walk proposal, rejecting draws that would make the companion_fcast
#' matrix non-stationary (or a diagonal element negative).
#'
#' @noRd
#' @importFrom stats rbeta runif
#' @importFrom methods as
draw_phi_fcast <- function(f, h, p, q, t, s, phi_old){

  # dependent variable
  m <- matrix(t(f[(1+p):nrow(f),]))

  # construct independent variables
  Mx <- do.call(cbind, lapply(c(1:p), function(px) f[c((p+1-px):(t+s-px)),]))
  M <- as(kronecker(Matrix(1,t+s-p,1), kronecker(Diagonal(q), Matrix(1,1,q*p))), "TsparseMatrix")
  M@x <- as.vector(t(Mx[rep(1:nrow(Mx), each = q),]))

  # covariance matrix
  V <- Diagonal(x = exp(2*rep(h[(1+p):(nrow(h)),], each = q)))

  diag_elements <- list2vec_fcast(lapply(1:p, function(px) diag(q)))

  # propose coefficients
  a_old <- list2vec_fcast(phi_old) # old vector
  a_new <- list2vec_fcast(phi_old) # proposal

  # draw proposals for each autoregressive coefficient and evaluate
  for(ix in 1:(p*q^2)){

    # propose new coefficient from random walk
    if(diag_elements[ix] == 1){
      a_new[ix] <- (rbeta(1,p^2,p^2)-0.5)*2
    } else {
      a_new[ix] <- (rbeta(1,(p*q)^2,(p*q)^2)-0.5)*2
    }

    # get fitted values and errors
    err_new <- m - M %*% a_new
    err_old <- m - M %*% a_old

    # evaluate density
    cj <- -0.5 * (t(err_new) %*% solve(V) %*% err_new)/t
    dj <- -0.5 * (t(err_old) %*% solve(V) %*% err_old)/t

    # we accept the proposal according to the following acceptance probability
    lratio <- min(exp(cj-dj), 1)

    # check if its finite, otherwise set to one (accept new draw)
    if(!is.finite(lratio)) lratio <- 1

    # stationarity check
    a_check <- a_new
    dim(a_check) <- c(q*p,q)
    stat_check <- abs(eigen(companion_fcast(vec2list_fcast(a_check, p, q), p, q))$values)[1] > 1

    # positivity check
    pos_check <- ((a_new[ix] < 0) & (diag_elements[ix] == 1))

    # we reject the proposed value if the likelihood ratio is lower than a
    # uniformly drawn value, or the new phi is not stationary
    if((runif(1) > lratio) | stat_check | pos_check){

      a_new[ix] <- a_old[ix]

    }
  }

  dim(a_new) <- c(q*p,q)
  vec2list_fcast(a_new, p, q)

}


#' Draw the stochastic volatility state equation variance (multi-factor)
#'
#' @noRd
#' @importFrom stats rgamma
draw_omega_fcast <- function(h, t, p, s, omega_old){

  m <- matrix(h[(s+1):nrow(h),] - h[s:(nrow(h)-1),])

  # this prior choice is uninformative
  c0 <- 3
  d0 <- 1

  # posterior
  c1 <- c0 + t
  d1 <- d0 + t(m) %*% m

  # sample from inverse gamma distribution
  omega <- 1/rgamma(n = 1,
                    shape = c1/2,
                    rate = d1/2) + 1e-9 # add tiny amount of noise to avoid singularities

  if(omega > 1) omega <- 1

  return(omega)

}


#' Regressor matrix for the multi-factor loading draw
#'
#' The single-factor [get_zmat()] is specialized to `q = 1` (see #43); this
#' is the general form.
#'
#' @noRd
get_zmat_fcast <- function(f, n, t, s, Llist, rho){

  Reduce("+", lapply(0:(s+1), function(sx){

    if(sx == 0){
      aux <- Llist[[as.character(0)]]
    } else if(sx == s+1){
      aux <- -rho %*% Llist[[as.character(s)]]
    } else {
      aux <- Llist[[as.character(sx-1)]] - rho %*% Llist[[as.character(sx)]]
    }

    f[seq(from = 2+s-sx, to = t+s-sx),] %x% aux

  }))

}
