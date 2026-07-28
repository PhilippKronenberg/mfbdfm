# Post-hoc rotation and identification for the multi-factor model of
# Eckert et al. (2025).
#
# run_sampling_fcast() deliberately leaves the model unidentified: with q > 1 the
# factors and loadings are only determined up to an invertible q x q rotation.
# These functions resolve that in two stages:
#
#   1. run_rotation_fcast()       - rotate every draw onto a common reference point
#                             (orthogonal Procrustes, iterated to convergence),
#                             so that draws are mutually comparable.
#   2. run_identification_fcast() - apply one further global rotation, chosen to make
#                             the average loading matrix as close as possible to
#                             its varimax rotation, i.e. to pick an
#                             interpretable orientation.
#
# All functions here are internal.

#' Rotate every posterior draw onto a common reference
#'
#' @noRd
#' @importFrom foreach foreach %do% %dopar%
#' @importFrom parallel makeCluster stopCluster
#' @importFrom doParallel registerDoParallel
run_rotation_fcast <- function(theta_out, n, q, p, s, t, ncores = NULL, max_iter = 5,
                         tol = 1e-9){

  length_sample <- nrow(theta_out)
  check_convergence <- FALSE
  i <- 0
  rx <- NULL # silence R CMD check note for the foreach iterator

  # Initialize theta star from SVD
  theta_star <- initialize_theta_star_fcast(theta_out = theta_out,
                                      length_sample = length_sample,
                                      n = n, q = q, p = p, s = s, t = t)

  if(!is.null(ncores)){
    cl <- makeCluster(ncores)
    registerDoParallel(cl)
    on.exit(stopCluster(cl), add = TRUE)
  }

  converged <- FALSE

  while(!check_convergence){

    # 1. Compute rotation matrix D for each draw
    if(!is.null(ncores)){

      D_save <- foreach(rx = 1:length_sample,
                        .packages = c("Matrix","mfbdfm")) %dopar%
        get_d_fcast(theta_out = theta_out, theta_star = theta_star, rx = rx,
             n = n, q = q, s = s, t = t, p = p)

    } else {

      D_save <- foreach(rx = 1:length_sample) %do%
        get_d_fcast(theta_out = theta_out, theta_star = theta_star, rx = rx,
             n = n, q = q, s = s, t = t, p = p)
    }

    # 2. Compute theta star
    rlist <- lapply(1:length_sample, function(rx) create_h_fcast(D = D_save[[rx]], n, q, p, s, t) %*% theta_out[rx,])
    theta_star_new <- Reduce("+",rlist)/length(rlist)

    # 3. Status message
    i <- i + 1
    delta <- mean((theta_star_new - theta_star)^2)
    message("Rotation iteration ", as.integer(i), ": convergence ", signif(delta, 3))

    # 4. Convergence check
    converged <- delta < tol
    check_convergence <- converged | i >= max_iter
    theta_star <- theta_star_new

  }

  # The loop also exits on the iteration cap. Say so rather than returning a
  # not-yet-converged rotation silently.
  if(!converged){
    warning("Rotation did not converge after ", max_iter, " iterations ",
            "(last change ", signif(delta, 3), ", tolerance ", tol, "). ",
            "Factor draws may not be rotated onto a common reference; ",
            "consider raising `max_iter`.", call. = FALSE)
  }

  return(D_save)

}


#' Choose and apply the final identifying rotation
#'
#' @noRd
#' @importFrom stats optim varimax
run_identification_fcast <- function(theta_out, D_save, n, q, p, s, t){

  if(q == 1){

    D_star <- 1

  } else {

    # optimization parameters
    lower_bound <- -pi
    upper_bound <- pi - 1e-16
    n_pars <- q*(q-1)/2

    optim_p <- optim(par = rep(1, n_pars),
                     fn = loss_sim_fcast,
                     D_save = D_save,
                     z = 1,
                     theta_out = theta_out,
                     n = n, q = q, p = p, s = s, t = t,
                     lower = rep(lower_bound, n_pars),
                     upper = rep(upper_bound, n_pars),
                     method = "L-BFGS-B")

    optim_n <- optim(par = rep(1, n_pars),
                     fn = loss_sim_fcast,
                     D_save = D_save,
                     z = -1,
                     theta_out = theta_out,
                     n = n, q = q, p = p, s = s, t = t,
                     lower = rep(lower_bound, n_pars),
                     upper = rep(upper_bound, n_pars),
                     method = "L-BFGS-B")

    # the reflection (z = +/-1) is chosen by whichever attains the lower loss_fcast
    if(optim_p$value < optim_n$value){
      D_star <- generate_d_fcast(q, 1, optim_p$par)
    } else {
      D_star <- generate_d_fcast(q, -1, optim_n$par)
    }

  }

  # apply the per-draw rotation followed by the global identifying rotation
  lapply(1:length(D_save), function(rx){
    create_h_fcast(D = D_save[[rx]] %*% D_star, n, q, p, s, t) %*% theta_out[rx,]
  })

}


#' Starting value for the common rotation reference
#'
#' @noRd
initialize_theta_star_fcast <- function(theta_out, length_sample, n, q, p, s, t){

  theta_star <- matrix(theta_out[length_sample,])

  check_convergence <- TRUE

  while(check_convergence){

    lam_bar_star <- theta2list_fcast(theta_star, n, p, q, t)$lambda

    W0 <- lapply(1:n, function(ix){
      det(Reduce("+", lapply(1:length_sample, function(rx){
        lam_bar0 <- theta2list_fcast(matrix(theta_out[rx,]), n = n, p = p, q = q, t = t)$lambda
        (lam_bar0[ix,] - lam_bar_star[ix,]) %*% t(lam_bar0[ix,] - lam_bar_star[ix,])
      }))/length_sample)^(-1/q)
    })

    W <- diag(unlist(W0))

    rlist <- lapply(1:length_sample, function(rx){

      D_bar <- theta2list_fcast(theta = matrix(theta_out[rx,]), n = n, p = p, q = q, t = t)$lambda
      D_bar_star <- theta2list_fcast(theta = theta_star, n = n, p = p, q = q, t = t)$lambda

      S <- svd(t(D_bar) %*% W %*% D_bar_star)
      D <- S$u %*% t(S$v)

      create_h_fcast(D, n, q, p, s, t) %*% theta_out[rx,]

    })

    theta_star_new <- Reduce("+",rlist)/length(rlist)

    # Convergence check on the loading block only
    check_convergence <- t(theta_star_new[c(1:(n*q))] - theta_star[c(1:(n*q))]) %*%
      (theta_star_new[c(1:(n*q))] - theta_star[c(1:(n*q))]) > 1e-9

    theta_star <- theta_star_new

  }

  return(theta_star)

}


#' Rotation matrix for a single draw
#'
#' @noRd
#' @importFrom stats optim
get_d_fcast <- function(theta_out, theta_star, rx, n, q, p, s, t){

  if(q == 1){

    # with one factor only the scale/sign is free
    D <- mean(theta2list_fcast(theta_star, n, p, q, t)$lambda) /
      mean(theta2list_fcast(t(theta_out[rx,,drop=FALSE]), n, p, q, t)$lambda)

  } else {

    lower_bound <- -pi
    upper_bound <- pi - 1e-16
    n_pars <- q*(q-1)/2

    optim_p <- optim(par = rep(0,n_pars), fn = loss_fcast, z = 1,
                     n = n, q = q, p = p, s = s, t = t,
                     th = t(theta_out[rx,,drop=FALSE]), th_star = theta_star,
                     lower = rep(lower_bound, n_pars),
                     upper = rep(upper_bound, n_pars),
                     method = "L-BFGS-B")

    optim_n <- optim(par = rep(0,n_pars), fn = loss_fcast, z = -1,
                     n = n, q = q, p = p, s = s, t = t,
                     th = t(theta_out[rx,,drop=FALSE]), th_star = theta_star,
                     lower = rep(lower_bound, n_pars),
                     upper = rep(upper_bound, n_pars),
                     method = "L-BFGS-B")

    if(optim_p$value < optim_n$value){
      D <- generate_d_fcast(q, 1, optim_p$par)
    } else {
      D <- generate_d_fcast(q, -1, optim_n$par)
    }

  }

  return(D)

}


#' Squared distance between a rotated draw and the reference
#'
#' @noRd
loss_fcast <- function(par, z, th, th_star, n, q, p, s, t){

  d <- create_h_fcast(D = generate_d_fcast(n = q, z = z, gammas = par), n, q, p, s, t) %*% th - th_star
  as.numeric(t(d) %*% d)

}


#' Varimax-based loss_fcast for the final identifying rotation
#'
#' @noRd
#' @importFrom stats varimax
loss_sim_fcast <- function(par, theta_out, D_save, z, n, q, p, s, t){

  rlist <- lapply(1:length(D_save), function(rx){

    create_h_fcast(D = D_save[[rx]] %*% generate_d_fcast(q, z, gammas = par), n, q, p, s, t) %*% theta_out[rx,]

  })

  th_star <- theta2list_fcast(Reduce("+",rlist)/length(rlist), n, p, q, t)

  sum((th_star$lambda - th_star$lambda %*% varimax(x = th_star$lambda, normalize = TRUE)$rotmat)^2)

}


#' Givens rotation matrix in the (i, j) plane
#'
#' @noRd
gen_givens_fcast <- function(n, i, j, gam){

  G <- diag(n)
  G[i,i] <- cos(gam)
  G[j,j] <- cos(gam)
  G[j,i] <- -sin(gam)
  G[i,j] <- sin(gam)

  return(G)

}


#' Build a q x q rotation (optionally with a reflection) from Givens angles
#'
#' @noRd
generate_d_fcast <- function(n, z, gammas){

  Glist <- vector("list", n*(n-1)/2)

  dx <- 1

  for(i in 1:(n-1)){

    for(j in (i+1):n){

      Glist[[dx]] <- gen_givens_fcast(n, i, j, gammas[dx])
      dx <- dx + 1

    }
  }

  rota <- Reduce("%*%", Glist)

  refl <- diag(n); refl[n,n] <- z

  refl %*% rota

}


#' Lift a q x q rotation to the full packed-parameter space
#'
#' Applies `D` to the loading and VAR blocks of a packed draw and leaves the
#' remaining blocks (sigma, rho, Xmat, h) untouched.
#'
#' @noRd
create_h_fcast <- function(D, n, q, p, s, t){

  rbind(cbind(kronecker(t(D), Diagonal(n)), Matrix(0,q*n,p*q^2+2*n+t+s+n*t)),
        cbind(Matrix(0,p*q^2,q*n), kronecker(Diagonal(p), kronecker(t(D), t(D))),
              Matrix(0,p*q^2,2*n+t+s+n*t)),
        cbind(Matrix(0,2*n+t+s+n*t,q*n+p*q^2), Diagonal(2*n+t+s+n*t)))

}
