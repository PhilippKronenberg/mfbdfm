test_that("create_inventory describes series correctly", {
  dat <- make_synth_dat()
  inv <- create_inventory(flows = dat$flows, stocks = dat$stocks)

  expect_equal(nrow(inv), 4)
  expect_setequal(inv$key, c("gdp", "m1", "w1", "s1"))
  expect_equal(inv$freq[inv$key == "gdp"], 4)
  expect_equal(inv$freq[inv$key == "w1"], 48)
  expect_equal(as.character(inv$type[inv$key == "s1"]), "stock")
  expect_equal(as.character(inv$type[inv$key == "gdp"]), "flow")
  expect_equal(inv$mean[inv$key == "gdp"], mean(dat$flows$gdp), tolerance = 1e-12)
  expect_equal(inv$sd[inv$key == "w1"], sd(dat$flows$w1), tolerance = 1e-12)
})

test_that("prepare_data aligns, standardizes, and zero-encodes missings", {
  dat <- make_synth_dat()
  inv <- create_inventory(flows = dat$flows, stocks = dat$stocks)
  Ymat <- prepare_data(flows = dat$flows, stocks = dat$stocks,
                       inventory = inv, target = "gdp")

  expect_s3_class(Ymat, "ts")
  expect_equal(frequency(Ymat), 48)
  expect_equal(colnames(Ymat), inv$key)
  expect_false(anyNA(Ymat))

  # weekly series is standardized: mean ~0, sd ~1 on its observed entries
  w1_col <- Ymat[, "w1"]
  expect_equal(mean(w1_col[w1_col != 0]), 0, tolerance = 1e-8)
  expect_equal(sd(w1_col[w1_col != 0]), 1, tolerance = 1e-2)

  # quarterly series only has a non-zero entry once per 12 weekly periods
  gdp_col <- Ymat[, "gdp"]
  expect_lte(sum(gdp_col != 0), length(dat$flows$gdp))
})

test_that("distributed lag and system matrices have the right dimensions", {
  dat <- make_synth_dat()
  inv <- create_inventory(flows = dat$flows, stocks = dat$stocks)

  k <- max(inv$freq) / min(inv$freq) # 12
  s <- 2 * (k - 1)                   # 22
  Llist <- mfbdfm:::get_distributed_lags(inv)

  expect_length(Llist, s + 1)
  expect_named(Llist, as.character(0:s))
  expect_equal(dim(Llist[["0"]]), c(nrow(inv), nrow(inv)))

  # flow weights sum to the frequency ratio, stock weights average to 1
  wsum <- Reduce(`+`, lapply(Llist, Matrix::diag))
  expected <- ifelse(inv$type == "flow", max(inv$freq) / inv$freq, 1)
  expect_equal(unname(wsum), unname(expected), tolerance = 1e-12)

  n <- nrow(inv); t <- 100; f <- matrix(rnorm(t + s), t + s, 1)
  rho <- Matrix::Diagonal(x = runif(n)); lambda <- Matrix::Matrix(1, n, 1)
  Zmat <- mfbdfm:::get_zmat(f = f, n = n, t = t, s = s, Llist = Llist, rho = rho)
  expect_equal(dim(Zmat), c(n * (t - 1), n))
})
