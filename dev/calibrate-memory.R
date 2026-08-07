# Regenerate the constants behind dfm_memory().
#
# Run from the repository root, against an INSTALLED package, with nothing else
# heavy running. Takes about 20 minutes.
#
#   Rscript dev/calibrate-memory.R
#
# Why one fresh process per configuration: gc()'s high-water mark is per
# process, so measuring several fits in one session reports the maximum of all
# of them and flattens exactly the differences being measured. The script below
# shells out per point for that reason - it is not accidental.
#
# The model is
#     peak_MB ~ a + b * gmat_MB + c * draws_MB
# where gmat_MB is the observation matrix's nonzero footprint and draws_MB is
# the retained draw matrix's. Note there is deliberately NO q^2 term: the sparse
# Cholesky of the q(t+s) factor precision matrix is the obvious candidate, but
# adding it does not improve the fit, because it is an order of magnitude
# smaller than the Gmat working set. Memory is linear in q. Do not "restore" a
# quadratic term on the strength of the algebra alone - measure it.

WORKER <- tempfile(fileext = ".R")
writeLines(c(
  'args <- commandArgs(trailingOnly = TRUE)',
  'q <- as.integer(args[1]); L <- as.integer(args[2]); B <- as.integer(args[3])',
  'suppressMessages(library(mfbdfm))',
  'e <- new.env(); load("analysis/fcast/reference/rda/data_ch.Rda", envir = e)',
  'dat <- cut_data(e$dat, 2021 + 47/48)',
  'target <- "ch.seco.gdp.real.gdp.ssa"',
  'inv <- create_inventory(flows = dat$flows, stocks = dat$stocks)',
  'Ymat <- prepare_data(dat$flows, dat$stocks, inv, target = target)',
  'n <- ncol(Ymat); t0 <- nrow(Ymat)',
  'k <- max(inv$freq)/min(inv$freq); s <- 2*(k - 1)',
  'invisible(gc(reset = TRUE, full = TRUE))',
  'suppressWarnings(suppressMessages(fcast_dfm(flows = dat$flows, stocks = dat$stocks,',
  '  target = target, q = q, length_sample = L, burn_in = B, extend = 0.5)))',
  'g <- gc()',
  'cat(sprintf("RESULT\\t%d\\t%d\\t%d\\t%d\\t%d\\t%.0f\\n", q, L, n, t0, s, sum(g[, 6])))'
), WORKER)

# The last two are the settings the sweeps actually run. They are what caught
# dfm_memory() under-predicting by 27%, so do not drop them to save time - they
# are also the slowest (about 45 and 155 minutes), which is why the grid is
# ordered cheapest first.
grid <- list(c(1, 30), c(2, 30), c(3, 30), c(4, 30), c(2, 120), c(2, 240),
             c(2, 500), c(4, 500))
rows <- list()
for (g in grid) {
  message("measuring q = ", g[1], ", length_sample = ", g[2], " ...")
  out <- system2("Rscript", c(shQuote(WORKER), g[1], g[2], 10), stdout = TRUE)
  hit <- grep("^RESULT", out, value = TRUE)
  if (!length(hit)) { warning("no result for q = ", g[1], ", L = ", g[2]); next }
  f <- strsplit(hit[1], "\t")[[1]]
  rows[[length(rows) + 1]] <- data.frame(
    q = as.integer(f[2]), L = as.integer(f[3]), n = as.integer(f[4]),
    t = as.integer(f[5]), s = as.integer(f[6]), peak = as.numeric(f[7]))
}
d <- do.call(rbind, rows)
print(d)

p <- 1
d$t_eff <- d$t + round(0.5 * 48)                        # the fits use extend = 0.5
d$gmat  <- d$q * (d$t_eff - 1) * d$n * (d$s + 2) * 12 / 1e6
d$draws <- d$L * (d$n*d$q + p*d$q^2 + 2*d$n + d$n*d$t_eff + (d$t_eff + d$s)) * 8 / 1e6

# Fit the LINE on the short and mid chains only, then scale it to cover
# everything: the relationship is convex in length_sample, so a least-squares fit
# over the whole range under-predicts the long chains, which is the direction that
# kills a sweep. See ?dfm_memory.
m <- lm(peak ~ gmat + draws, data = d[d$L <= 240, ])
d$fitted_line <- predict(m, newdata = d)
safety <- max(d$peak / d$fitted_line)
cat("\nadj R2 ", round(summary(m)$adj.r.squared, 4),
    " | max |resid| ", round(max(abs(resid(m)))), " MB\n", sep = "")
cat("\nPaste into R/memory.R:\n")
cat(sprintf("MEM_FIXED_MB     <- %.0f\n",  coef(m)[1]))
cat(sprintf("MEM_GMAT_COPIES  <- %.2f\n", coef(m)[2]))
cat(sprintf("MEM_DRAW_COPIES  <- %.2f\n", coef(m)[3]))
cat(sprintf("MEM_SAFETY_FACTOR <- %.2f\n", safety))
cat("\ncoverage after scaling (all must be >= 1.00):\n")
print(round(safety * d$fitted_line / d$peak, 3))
cat("\nAlso update the calibration paragraph in ?dfm_memory and the measured\n",
    "points pinned in tests/testthat/test-memory.R.\n", sep = "")
