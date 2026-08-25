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

test_that("prepare_data keeps the final low-frequency observation", {
  # Regression guard for the trim in prepare_data(), which is
  # zoo::na.trim(is.na = "all") deliberately. The reference multi-factor
  # implementation trimmed with window(start = min(raw times), end = max(raw
  # times)) instead, and that variant silently drops the most recent quarterly
  # observation: prepare_data() shifts a low-frequency observation to the *end*
  # of its period, while the raw times window() would be handed are pre-shift.
  #
  # The shape of this fixture is the entire point of the test, so do not
  # "simplify" it. The weekly series must stop at or before the quarterly
  # series' *raw* end, so that the latest raw time anywhere in the inputs
  # (2015.75) falls short of the quarterly series' *shifted* end
  # (2015.75 + 11/48). On the shipped dataset the weekly series run past that
  # point and the two rules coincide -- which is exactly why the bug went
  # unnoticed there, and why make_synth_dat() cannot be used here.
  gdp <- stats::ts(seq(0.1, 0.8, by = 0.1), start = c(2014, 1), frequency = 4)
  w1 <- stats::ts(sin(seq_len(85)), start = c(2014, 1), frequency = 48)

  # the premise the discrimination rests on: no series reaches the shifted end
  shifted_end <- 2015.75 + 11 / 48
  expect_lt(max(time(gdp)), shifted_end)
  expect_lt(max(time(w1)), shifted_end)

  inv <- create_inventory(flows = list(gdp = gdp, w1 = w1), stocks = NULL)
  Ymat <- prepare_data(flows = list(gdp = gdp, w1 = w1), stocks = NULL,
                       inventory = inv, target = "gdp")

  # the trimmed matrix must extend to the shifted end, and every quarterly
  # observation must survive -- the window() variant loses the last one
  expect_equal(max(time(Ymat)), shifted_end, tolerance = 1e-6)
  expect_equal(sum(Ymat[, "gdp"] != 0), length(gdp))
  expect_equal(unname(Ymat[nrow(Ymat), "gdp"]),
               (gdp[length(gdp)] - mean(gdp)) / sd(gdp),
               tolerance = 1e-12)
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
