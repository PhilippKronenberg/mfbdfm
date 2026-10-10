# Shared synthetic fixtures for the test suite.

# A small mixed-frequency dataset in the flows/stocks layout the model expects:
# quarterly target + monthly + weekly flows, one weekly stock.
make_synth_dat <- function(seed = 42) {
  set.seed(seed)
  list(
    flows = list(
      gdp = stats::ts(rnorm(40, 0.4, 0.5), start = c(2014, 1), frequency = 4),
      m1  = stats::ts(rnorm(120), start = c(2014, 1), frequency = 12),
      w1  = stats::ts(rnorm(480), start = c(2014, 1), frequency = 48)
    ),
    stocks = list(
      s1 = stats::ts(rnorm(480), start = c(2014, 1), frequency = 48)
    )
  )
}

# A synthetic vintage table in the layout of get_real_time_gdp_vintages():
# a time column plus one numeric column per (decimal-named) vintage.
make_synth_vintages <- function() {
  df <- data.frame(time = seq(as.Date("2014-01-01"), by = "quarter", length.out = 40))
  df[["2023.25"]] <- c(rnorm(36), rep(NA, 4))
  df[["2023.75"]] <- c(rnorm(38), rep(NA, 2))
  df[["2024.25"]] <- rnorm(40)
  df
}

# The analytics inputs bundle. Delegates to the exported
# mfbdfm_example_inputs(), which the reference examples also use - one fixture,
# so a change in the expected input shape cannot pass the tests while breaking
# the documentation, or the reverse.
make_synth_inputs <- function(seed = 99) mfbdfm_example_inputs(seed = seed)

# A saved `ind_dfm`-shaped fit file, which is what extract_wai_data() and
# export_wai_web() read. Only `factor` and `factor_var` are consulted, so the
# fixture carries just those two - the point is the weekly time base and the
# fitted window, not a plausible MCMC result.
synth_fit_file <- function(start = 1990, end = 2024, seed = 7) {
  set.seed(seed)
  n <- length(seq(start, end, 1/48))
  mod <- list(
    factor     = stats::ts(rnorm(n, 1, 2), start = start, frequency = 48),
    factor_var = stats::ts(runif(n, 0.2, 0.5), start = start, frequency = 48)
  )
  path <- tempfile(fileext = ".Rda")
  save(mod, file = path)
  path
}

# A temp directory that cleans itself up when the calling test_that() block
# exits. withr::local_tempdir() does this, but withr is not among the package's
# declared Suggests and one helper is a poor reason to add it.
local_tempdir_base <- function(envir = parent.frame()) {
  d <- tempfile()
  dir.create(d, recursive = TRUE)
  withr_defer(unlink(d, recursive = TRUE), envir = envir)
  d
}

withr_defer <- function(expr, envir) {
  do.call(base::on.exit, list(substitute(expr), add = TRUE, after = FALSE),
          envir = envir)
}

# A single-frequency panel generated from a known number of factors, for the
# Bai-Ng criteria to recover. All series share the highest frequency on purpose:
# select_factors() keeps only that block, so a mixed-frequency fixture would
# silently test a smaller panel than the one generated.
make_synth_factor_panel <- function(q = 2, n = 20, t = 200, freq = 12,
                                    noise = 0.5, seed = 11) {
  set.seed(seed)
  f <- matrix(0, t, q)
  for (j in seq_len(q)) {
    e <- rnorm(t)
    for (i in 2:t) f[i, j] <- 0.7 * f[i - 1, j] + e[i]
  }
  # loadings bounded away from zero on purpose. With lambda ~ N(0, 1) a good
  # share of the series get a near-zero loading, and standardizing the panel
  # then blows their idiosyncratic noise up to dominate the column - which puts
  # heterogeneous, factor-like structure into the residual and makes the
  # criteria over-select. That is a property of the fixture, not of the code.
  lambda <- matrix(runif(n * q, 0.4, 1.2) * sample(c(-1, 1), n * q, TRUE), n, q)
  x <- f %*% t(lambda) + matrix(rnorm(n * t, sd = noise * sqrt(q)), t, n)

  series <- lapply(seq_len(n), function(i)
    stats::ts(x[, i], start = c(2000, 1), frequency = freq))
  names(series) <- paste0("x", seq_len(n))

  list(flows = series[seq_len(n %/% 2)],
       stocks = series[(n %/% 2 + 1):n],
       factors = stats::ts(f, start = c(2000, 1), frequency = freq))
}

# A panel with more series than time points (G5.8d). For a factor model this is
# the normal case rather than an absurd one - the whole point is to summarise
# many series with few factors - so it has to fit, not error. Deliberately
# short in time: a quarterly target plus monthly indicators, so the aligned
# high-frequency grid has t_months rows against n_series + 1 columns.
make_synth_wide_panel <- function(n_series = 30, t_months = 24, seed = 5) {
  set.seed(seed)
  flows <- list(gdp = stats::ts(rnorm(t_months %/% 3, 0.4, 0.5),
                                start = c(2014, 1), frequency = 4))
  for (i in seq_len(n_series)) {
    flows[[paste0("m", i)]] <- stats::ts(rnorm(t_months), start = c(2014, 1),
                                         frequency = 12)
  }
  list(flows = flows, target = "gdp")
}

# Every component of a fit that a user reads off the top level and would never
# expect to carry NA/NaN/Inf (G5.3). `data_raw` is excluded on purpose: it is
# the input as supplied, missings and all.
expect_all_finite <- function(fit, components) {
  for (nm in components) {
    x <- fit[[nm]]
    testthat::expect_false(is.null(x), label = paste0("fit$", nm, " exists"))
    testthat::expect_true(all(is.finite(as.numeric(unlist(x)))),
                          label = paste0("fit$", nm, " is entirely finite"))
  }
}

# Pairwise correlations between every pair in a list of numeric vectors.
pairwise_cor <- function(v) {
  ij <- utils::combn(length(v), 2)
  apply(ij, 2, function(k) stats::cor(v[[k[1]]], v[[k[2]]]))
}

# Match the columns of two factor matrices and return the matched absolute
# correlations. Factors are identified only up to rotation and sign, so the
# rule is the one analysis/fcast/6_factor_plot_fcast.R uses: pair each column
# of `a` with whichever column of `b` it correlates with most strongly in
# absolute value, greedily and without reuse.
align_factors <- function(a, b) {
  a <- as.matrix(a); b <- as.matrix(b)
  C <- abs(stats::cor(a, b))
  used <- integer(0)
  vapply(seq_len(ncol(a)), function(i) {
    j <- setdiff(order(C[i, ], decreasing = TRUE), used)[1]
    used <<- c(used, j)
    C[i, j]
  }, numeric(1))
}

# Perturb every series by noise of .Machine$double.eps scale (G5.9a). Relative
# rather than absolute, so the perturbation lands in the last couple of bits of
# each observation whatever its magnitude.
jitter_double_eps <- function(series) {
  lapply(series, function(x)
    x + stats::ts(.Machine$double.eps * abs(x) * 10,
                  start = stats::start(x), frequency = stats::frequency(x)))
}
