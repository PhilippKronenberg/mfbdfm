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
