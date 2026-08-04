# The packing helpers behind fcast_dfm(). All internal, and all pure - which is
# what makes them worth testing directly: the rotation applies a matrix to a
# whole packed draw at once (create_h_fcast()), so an error in the packing order
# would not surface as a crash, only as silently rotated-wrong parameters.

test_that("list2theta_fcast and theta2list_fcast round-trip", {

  n <- 4; q <- 2; p <- 2; t <- 6; s <- 3

  lambda <- matrix(seq_len(n * q) + 0.5, nrow = n, ncol = q)
  phi <- lapply(seq_len(p), function(px) matrix(px * 10 + seq_len(q^2), q, q))
  sigma <- seq_len(n) + 0.25
  rho <- seq_len(n) / 10
  Xmat <- matrix(seq_len(n * t) * 2, nrow = t, ncol = n)
  h <- seq_len(t + s) / 100

  theta <- list2theta_fcast(lambda, phi, sigma, rho, Xmat, h)

  # one column, and exactly as long as the packing order says it should be
  expect_equal(ncol(theta), 1L)
  expect_equal(nrow(theta), n * q + p * q^2 + n + n + n * t + (t + s))

  back <- theta2list_fcast(theta, n = n, p = p, q = q, t = t)

  expect_equal(back$lambda, lambda)
  expect_equal(back$sigma, sigma)
  expect_equal(back$rho, rho)
  expect_equal(back$Xmat, Xmat)
  expect_equal(back$h, h)

  # phi included. It used to come back transposed for q > 1 (#66): the packer
  # writes each block column-major, the unpacker read the whole region with
  # byrow = TRUE. The transposed copy reached draw_factors_fcast() through
  # run_evaluation_fcast() while the sampler passed the untransposed one, so
  # this is the assertion that keeps the two callers agreeing.
  expect_equal(back$phi, phi)

  # asymmetric on purpose - a symmetric block would pass either way
  expect_false(isTRUE(all.equal(phi[[1]], t(phi[[1]]))))
})


test_that("the round-trip holds exactly at q = 1, phi included", {

  # the degenerate corner, and the reason #66 went unnoticed for so long: a 1x1
  # phi block cannot transpose, so q = 1 was correct even before the fix. Every
  # WAI workflow runs at q = 1.
  n <- 3; q <- 1; p <- 1; t <- 5; s <- 2

  lambda <- matrix(c(1.5, 2.5, 3.5), nrow = n, ncol = q)
  phi <- list(matrix(0.7, q, q))
  sigma <- c(1, 2, 3)
  rho <- c(0.1, 0.2, 0.3)
  Xmat <- matrix(seq_len(n * t) + 0.5, nrow = t, ncol = n)
  h <- seq_len(t + s) / 10

  theta <- list2theta_fcast(lambda, phi, sigma, rho, Xmat, h)
  back <- theta2list_fcast(theta, n = n, p = p, q = q, t = t)

  expect_equal(as.numeric(back$lambda), as.numeric(lambda))
  expect_equal(as.numeric(back$phi[[1]]), as.numeric(phi[[1]]))
  expect_equal(back$sigma, sigma)
  expect_equal(back$Xmat, Xmat)
  expect_equal(back$h, h)
})


test_that("vec2list_fcast and list2vec_fcast are inverses", {

  q <- 3; p <- 2
  phi <- lapply(seq_len(p), function(px) matrix(px * 100 + seq_len(q^2), q, q))

  v <- list2vec_fcast(phi)
  expect_equal(length(v), p * q^2)
  expect_equal(vec2list_fcast(v, p = p, q = q), phi)

  # and the other direction, starting from a vector
  v2 <- matrix(seq_len(p * q^2) + 0.5)
  expect_equal(list2vec_fcast(vec2list_fcast(v2, p = p, q = q)), v2)
})


test_that("companion_fcast stacks the lag matrices with an identity block", {

  q <- 2; p <- 3
  phi <- lapply(seq_len(p), function(px) matrix(px, q, q))

  cm <- companion_fcast(phi, p = p, q = q)

  expect_equal(dim(cm), c(p * q, p * q))
  # top row block is the lag matrices side by side
  expect_equal(cm[seq_len(q), ], do.call(cbind, phi), ignore_attr = TRUE)
  # the rest is [I | 0], which is what makes the eigenvalues the VAR's roots
  expect_equal(cm[(q + 1):(p * q), seq_len((p - 1) * q)],
               diag(1, (p - 1) * q), ignore_attr = TRUE)
  expect_true(all(cm[(q + 1):(p * q), ((p - 1) * q + 1):(p * q)] == 0))

  # a stationary VAR(1) must give eigenvalues inside the unit circle, since
  # draw_phi_fcast() screens on exactly this
  cm1 <- companion_fcast(list(matrix(c(0.5, 0, 0, 0.3), 2, 2)), p = 1, q = 2)
  expect_true(all(Mod(eigen(cm1, only.values = TRUE)$values) < 1))
})
