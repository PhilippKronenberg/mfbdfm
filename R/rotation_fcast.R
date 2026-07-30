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
# DEVIATIONS FROM THE PUBLISHED ALGORITHM (Appendix E of the online appendix
# to Eckert et al. 2025). All are deliberate and retained; noted so nobody
# "fixes" them back into the paper's form without meaning to. See issue #46.
#
#  a) The varimax stage (step 2 above) is NOT part of the published
#     algorithm, which ends once the draws are no longer orthogonally mixed.
#     It applies the SAME rotation to every draw, so it does not affect the
#     alignment between draws - it only re-orients the identified sample into
#     a more interpretable one. Kept because that interpretability is useful.
#
#  b) Convergence. The appendix specifies "the SUM of squared deviations
#     between two successive theta* is lower than 1e-9". run_rotation_fcast()
#     tests the MEAN squared deviation against 1e-9, which over a packed
#     vector of length (nq + pq^2 + 2n + nt + t+s) is a much weaker
#     requirement, and additionally caps the loop at `max_iter` iterations
#     (the appendix has no cap). Both trade strictness for runtime and
#     neither changes the algorithm itself. Kept for now; making the stopping
#     rule selectable is tracked in issue #46.
#
# All functions here are internal.

#' Rotate every posterior draw onto a common reference
#'
#' @noRd
#' @importFrom foreach foreach %do% %dopar%
#' @importFrom parallel makeCluster stopCluster
#' @importFrom doParallel registerDoParallel
run_rotation_fcast <- function(theta_out, n, q, p, s, t, ncores = NULL,
                               control = dfm_control("fcast_dfm")){

  criterion <- control$rotation_criterion
  tol <- control$rotation_tol
  max_iter <- control$rotation_max_iter

  length_sample <- nrow(theta_out)
  check_convergence <- FALSE
  i <- 0
  rx <- NULL # silence R CMD check note for the foreach iterator

  # Initialize theta star from SVD
  theta_star <- initialize_theta_star_fcast(theta_out = theta_out,
                                      length_sample = length_sample,
                                      n = n, q = q, p = p, s = s, t = t,
                                      control = control)

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

    # 2. Compute theta star  (step (2) of the appendix algorithm)
    rlist <- lapply(1:length_sample, function(rx) apply_rotation_fcast(D_save[[rx]], theta_out[rx,], n, q, p))
    theta_star_new <- matrix(Reduce("+",rlist)/length(rlist))

    # 3. Status message
    i <- i + 1
    #    `criterion` selects the MEAN squared deviation (the long-standing
    #    default) or the SUM, which is what the appendix specifies. See
    #    dfm_control() and the deviations note at the top of this file (#46).
    sq <- (theta_star_new - theta_star)^2
    delta <- if(identical(criterion, "sum")) sum(sq) else mean(sq)
    message("Rotation iteration ", as.integer(i), ": convergence ", signif(delta, 3))

    # 4. Convergence check
    converged <- delta < tol
    check_convergence <- converged | i >= max_iter
    theta_star <- theta_star_new

  }

  # The loop also exits on the iteration cap. Say so rather than returning a
  # not-yet-converged rotation silently.
  if(!converged){
    msg <- paste0("Rotation did not converge after ", max_iter, " iterations ",
                  "(last change ", signif(delta, 3), ", criterion \"", criterion,
                  "\", tolerance ", tol, "). Factor draws may not be rotated ",
                  "onto a common reference; consider raising ",
                  "`rotation_max_iter` in dfm_control().")
    switch(control$rotation_on_failure,
           error = stop(msg, call. = FALSE),
           warning = warning(msg, call. = FALSE),
           ignore = invisible(NULL))
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

    # the varimax objective reads only the loadings, so extract that block
    # once rather than rotating every full draw on each objective evaluation
    lam_draws <- lapply(seq_len(nrow(theta_out)), function(rx){
      matrix(theta_out[rx, seq_len(n*q)], nrow = n, ncol = q)
    })

    optim_p <- optim(par = rep(1, n_pars),
                     fn = loss_sim_fcast,
                     D_save = D_save,
                     z = 1,
                     lam_draws = lam_draws,
                     n = n, q = q, p = p, s = s, t = t,
                     lower = rep(lower_bound, n_pars),
                     upper = rep(upper_bound, n_pars),
                     method = "L-BFGS-B")

    optim_n <- optim(par = rep(1, n_pars),
                     fn = loss_sim_fcast,
                     D_save = D_save,
                     z = -1,
                     lam_draws = lam_draws,
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
    matrix(apply_rotation_fcast(D_save[[rx]] %*% D_star, theta_out[rx,], n, q, p))
  })

}


#' Starting value for the common rotation reference
#'
#' @noRd
initialize_theta_star_fcast <- function(theta_out, length_sample, n, q, p, s, t,
                                        control = dfm_control("fcast_dfm")){

  tol <- control$rotation_init_tol
  max_iter <- control$rotation_init_max_iter

  theta_star <- matrix(theta_out[length_sample,])

  check_convergence <- TRUE
  i <- 0

  while(check_convergence){

    i <- i + 1

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

      apply_rotation_fcast(D, theta_out[rx,], n, q, p)

    })

    theta_star_new <- matrix(Reduce("+",rlist)/length(rlist))

    # Convergence check on the loading block only. Note this test is the SUM of
    # squared deviations (t(d) %*% d), i.e. the criterion the appendix specifies
    # - so this loop has always matched the paper while the main loop above did
    # not. Kept as-is; `rotation_init_tol` exposes the threshold.
    check_convergence <- t(theta_star_new[c(1:(n*q))] - theta_star[c(1:(n*q))]) %*%
      (theta_star_new[c(1:(n*q))] - theta_star[c(1:(n*q))]) > tol

    theta_star <- theta_star_new

    # This loop was previously uncapped, so it had no termination guarantee.
    # The cap is a safety valve, not a target: 100 against 7 observed.
    if(i >= max_iter && check_convergence){
      warning("Rotation initialization did not converge after ", max_iter,
              " iterations (tolerance ", tol, "). Raise ",
              "`rotation_init_max_iter` in dfm_control() if this is expected.",
              call. = FALSE)
      break
    }

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
#' Eq. (44) of the online appendix. The residual is formed over the whole
#' packed vector, exactly as the appendix defines it - only the application
#' of H(D) is done structurally (see [apply_rotation_fcast()]) rather than by
#' building the matrix, which was the dominant cost of the rotation step.
#'
#' @noRd
loss_fcast <- function(par, z, th, th_star, n, q, p, s, t){

  d <- apply_rotation_fcast(generate_d_fcast(n = q, z = z, gammas = par), th, n, q, p) -
    as.numeric(th_star)
  sum(d^2)

}


#' Varimax-based loss for the final identifying rotation
#'
#' The objective reads only the loading block of the averaged draw, so only
#' that block needs rotating and averaging - the remaining
#' `2n + nt + t+s` components of every draw were previously rotated and
#' averaged on each objective evaluation and then thrown away. `lam_draws`
#' holds the per-draw loading matrices, extracted once by the caller.
#'
#' The association `Lambda %*% (D_save %*% D)` and the averaging order are
#' kept exactly as in the original formulation.
#'
#' @noRd
#' @importFrom stats varimax
loss_sim_fcast <- function(par, lam_draws, D_save, z, n, q, p, s, t){

  D <- generate_d_fcast(q, z, gammas = par)

  lam_bar <- Reduce("+", lapply(seq_along(D_save), function(rx){

    lam_draws[[rx]] %*% (D_save[[rx]] %*% D)

  })) / length(D_save)

  sum((lam_bar - lam_bar %*% varimax(x = lam_bar, normalize = TRUE)$rotmat)^2)

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
#' This is H(D) of Eq. (44) in the paper's online appendix, written out
#' explicitly:
#'
#' \preformatted{
#'          [ D' (x) I_n            0                0        ]
#'   H(D) = [ 0            I_p (x) (D' (x) D')       0        ]
#'          [ 0                     0        I_(2n + nt + t+s) ]
#' }
#'
#' so that `H(D) theta` equals
#' `[vec(Lambda D)', vec(D' Phi_1 D)', ..., diag(Sigma)', diag(P)', vec(X)', h']'`.
#'
#' Note the third block is the identity: the measurement-error parameters,
#' the augmented data and the volatility path are outside the rotational
#' indeterminacy and pass through untouched. [apply_rotation_fcast()]
#' exploits exactly that and should be preferred in any hot path; this
#' function is retained because it states the structure explicitly and
#' serves as the reference the fast version is tested against.
#'
#' @noRd
create_h_fcast <- function(D, n, q, p, s, t){

  rbind(cbind(kronecker(t(D), Diagonal(n)), Matrix(0,q*n,p*q^2+2*n+t+s+n*t)),
        cbind(Matrix(0,p*q^2,q*n), kronecker(Diagonal(p), kronecker(t(D), t(D))),
              Matrix(0,p*q^2,2*n+t+s+n*t)),
        cbind(Matrix(0,2*n+t+s+n*t,q*n+p*q^2), Diagonal(2*n+t+s+n*t)))

}


#' Apply H(D) to a packed draw without materializing H(D)
#'
#' Equivalent to `create_h_fcast(D, n, q, p, s, t) %*% theta`, but exploits
#' the block structure documented there: only the loading block
#' (`vec(Lambda) -> vec(Lambda D)`, i.e. `Lambda %*% D`) and the VAR block
#' (`vec(Phi_j) -> vec(D' Phi_j D)`) are transformed; everything after them
#' is copied unchanged.
#'
#' This matters because H(D) is
#' `(nq + pq^2 + 2n + nt + t+s)` square - on a realistic problem roughly
#' 11,750 x 11,750 - while only `nq + pq^2` of those rows (about 0.3%) do
#' anything. Building it inside an optimizer's objective was the dominant
#' cost of the rotation step.
#'
#' @noRd
apply_rotation_fcast <- function(D, theta, n, q, p){

  out <- as.numeric(theta)
  nq <- n * q
  npq <- nq + p * q^2

  # loading block: vec(Lambda D) = (D' %x% I_n) vec(Lambda)
  out[seq_len(nq)] <- as.numeric(matrix(out[seq_len(nq)], nrow = n, ncol = q) %*% D)

  # VAR block: (I_p %x% (D' %x% D')) applied blockwise, i.e. Phi_j -> D' Phi_j D
  if(p > 0){
    for(j in seq_len(p)){
      ix <- (nq + (j-1)*q^2 + 1):(nq + j*q^2)
      out[ix] <- as.numeric(t(D) %*% matrix(out[ix], nrow = q, ncol = q) %*% D)
    }
  }

  # everything from npq+1 onwards is outside the rotational indeterminacy
  out

}
