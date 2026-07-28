# The rotation machinery for fcast_dfm(). The key invariant tested here is
# that apply_rotation_fcast() - the fast path used inside the optimizer -
# agrees with create_h_fcast(), which writes out H(D) of Eq. (44) of the
# online appendix explicitly. create_h_fcast() is retained precisely to serve
# as that oracle.

make_theta <- function(n, q, p, t, s, seed = 1) {
  set.seed(seed)
  matrix(stats::rnorm(n*q + p*q^2 + 2*n + n*t + t + s))
}

test_that("apply_rotation_fcast agrees with the explicit H(D)", {
  for (q in 2:4) for (p in 1:2) {
    n <- 6L; t <- 30L; s <- 4L
    theta <- make_theta(n, q, p, t, s, seed = 10*q + p)
    set.seed(q * p)
    D <- generate_d_fcast(q, sample(c(-1, 1), 1), stats::runif(q*(q-1)/2, -pi, pi))

    ref <- as.numeric(create_h_fcast(D, n, q, p, s, t) %*% theta)
    fast <- apply_rotation_fcast(D, theta, n, q, p)

    # one ULP of slack: the sparse and dense products sum in different orders
    expect_equal(fast, ref, tolerance = 1e-12)
  }
})

test_that("apply_rotation_fcast leaves the non-rotated blocks untouched", {
  n <- 6L; q <- 3L; p <- 2L; t <- 30L; s <- 4L
  theta <- make_theta(n, q, p, t, s)
  set.seed(3)
  D <- generate_d_fcast(q, 1, stats::runif(q*(q-1)/2, -pi, pi))

  out <- apply_rotation_fcast(D, theta, n, q, p)
  npq <- n*q + p*q^2

  # sigma, rho, Xmat and h are outside the rotational indeterminacy
  expect_identical(out[(npq + 1):length(out)], as.numeric(theta)[(npq + 1):length(theta)])
  # ... while the loading/VAR block does change
  expect_false(isTRUE(all.equal(out[seq_len(npq)], as.numeric(theta)[seq_len(npq)])))
})

test_that("generate_d_fcast returns an orthogonal matrix with the expected determinant", {
  for (q in 2:4) {
    set.seed(q)
    gam <- stats::runif(q*(q-1)/2, -pi, pi)

    Dp <- generate_d_fcast(q, 1, gam)
    Dn <- generate_d_fcast(q, -1, gam)

    expect_equal(t(Dp) %*% Dp, diag(q), tolerance = 1e-12)
    expect_equal(t(Dn) %*% Dn, diag(q), tolerance = 1e-12)
    # the reflection flips the sign of the determinant
    expect_gt(det(Dp) * det(Dn), -1.0001)
    expect_lt(det(Dp) * det(Dn), -0.9999)
  }
})

test_that("rotating by D then by its inverse recovers the draw", {
  n <- 5L; q <- 2L; p <- 1L; t <- 20L; s <- 2L
  theta <- make_theta(n, q, p, t, s)
  set.seed(8)
  D <- generate_d_fcast(q, 1, stats::runif(1, -pi, pi))

  once <- apply_rotation_fcast(D, theta, n, q, p)
  back <- apply_rotation_fcast(t(D), matrix(once), n, q, p)

  expect_equal(back, as.numeric(theta), tolerance = 1e-10)
})
