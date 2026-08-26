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
