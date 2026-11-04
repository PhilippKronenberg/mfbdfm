# Run from the repository root.
#
# Brent diagnostics at a single evaluation date ---------------------------
#
# The cheap half of issue #173. analysis/brent_evaluation.R is the full
# pseudo-real-time comparison and takes days; this script answers the
# diagnostic question - "does the factor load on Brent at all, and what share
# of the nowcast does it carry?" - from a handful of fits at one date, so the
# answer does not have to wait for the evaluation.
#
# It fits `full_RT` and `with_brent` at one date, on two seeds each, and reports
#   - the Brent loading (posterior mean, and the posterior interval)
#   - Brent's share of the nowcast via mfbdfm_contributions()
#   - the nowcast difference between the two variants, next to the
#     seed-to-seed difference within each variant
# The last pairing is the point: a between-variant difference no larger than the
# within-variant seed spread is not evidence of anything.

suppressMessages({
  library(zoo)
  library(mfbdfm)
})

source("analysis/brent_oil.R")
source("analysis/brent_evaluation_setup.R")

out_dir <- file.path("analysis", "out")
cache_dir <- file.path("analysis", "Rda", "brent_diag")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

# SETTINGS ----------------------------------------------------------------

eval_date <- BRENT_EVAL_DATES[length(BRENT_EVAL_DATES)]
seeds <- as.integer(trimws(strsplit(Sys.getenv("BRENT_SEEDS", "1,2"), ",",
                                    fixed = TRUE)[[1]]))

# Shorter than run_wai_adj()'s 5000/1000 default, deliberately: these are
# diagnostics, and the seed pair is what guards against reading noise as signal.
# Raise them (and re-run) before quoting a number anywhere final.
env_num <- function(name, default) {
  v <- Sys.getenv(name, "")
  if (!nzchar(v)) default else as.numeric(v)
}
length_sample <- env_num("BRENT_LENGTH_SAMPLE", 1000)
burn_in <- env_num("BRENT_BURN_IN", 200)

# DATA --------------------------------------------------------------------

datasets <- brent_variant_datasets()
GDP_gr_vintages <- get_real_time_gdp_vintages("quarterly")


# CO-MOVEMENT WITH GDP, BEFORE ANY FITTING --------------------------------

# ind_dfm() is a single factor anchored on GDP, so a series helps only to the
# extent that it moves with Swiss real GDP growth. That can be read off the data
# directly, which is worth doing first: it costs nothing and it is the thing the
# fits then have to be consistent with. Brent is shown next to the equity
# indices already in the panel, which are the closest comparison - other daily
# price series, same transformation, same weekly treatment.
#
# The pandemic is reported separately rather than pooled in, because 2020 Q2
# dominates any correlation computed over a sample containing it.

sum_to_quarterly <- function(x) {
  q <- floor(as.numeric(stats::time(x)) * 4) / 4
  agg <- tapply(as.numeric(x), q, function(v) sum(v, na.rm = TRUE))
  stats::ts(as.numeric(agg), start = as.numeric(names(agg))[1], frequency = 4)
}

gdp_comovement <- function(x, label, gdp) {
  m <- stats::ts.intersect(sum_to_quarterly(x), gdp)
  d <- data.frame(t = as.numeric(stats::time(m)), x = m[, 1], y = m[, 2])
  one <- function(k, excl) {
    n <- nrow(d)
    if (n <= k + 3) return(NA_real_)
    xx <- d$x[seq_len(n - k)]
    yy <- d$y[seq(1 + k, n)]
    ty <- d$t[seq(1 + k, n)]
    keep <- if (excl) (ty < 2020 | ty >= 2022) else rep(TRUE, length(ty))
    if (sum(keep) < 8) return(NA_real_)
    stats::cor(xx[keep], yy[keep])
  }
  data.frame(series = label, n_quarters = nrow(d),
             cor_same_quarter = one(0, FALSE), cor_one_quarter_lead = one(1, FALSE),
             cor_same_quarter_ex2020_21 = one(0, TRUE),
             cor_one_quarter_lead_ex2020_21 = one(1, TRUE),
             stringsAsFactors = FALSE)
}

local({
  base <- datasets$full_RT
  gdp <- base$flows[[BRENT_TARGET]]
  brent <- datasets$with_brent$flows[[BRENT_KEY]]
  peers <- c("SWISSMI", "FINANSW", "INDUSSW")
  rows <- c(
    list(gdp_comovement(brent, BRENT_KEY, gdp)),
    lapply(peers, function(k) {
      if (is.null(base$flows[[k]])) NULL else gdp_comovement(base$flows[[k]], k, gdp)
    })
  )
  tab <- do.call(rbind, Filter(Negate(is.null), rows))
  cat("\n== co-movement with quarterly real GDP growth (levels, not fits) ==\n")
  print(tab, digits = 3, row.names = FALSE)
  utils::write.csv(tab, file.path(out_dir, "brent_gdp_comovement.csv"),
                   row.names = FALSE)
})

message("date ", round(eval_date, 3), "; variants: ",
        paste(names(datasets), collapse = ", "),
        "; seeds: ", paste(seeds, collapse = ", "),
        "; ", length_sample, " draws after ", burn_in, " burn-in")

# FIT ---------------------------------------------------------------------

# Each fit is cached on its own, so a crash in the reporting below - or a run
# that has to be interrupted - does not throw away the hour of sampling that
# produced it. Delete cache_dir to force a refit.
fits <- list()
for (variant in names(datasets)) {
  prepared <- brent_prepare_realtime(datasets[[variant]], eval_date, GDP_gr_vintages)
  for (sd in seeds) {
    key <- paste0(variant, "_seed", sd)
    cache_file <- file.path(cache_dir, paste0(key, "_", round(eval_date, 3), "_",
                                             length_sample, "_", burn_in, ".rds"))
    if (file.exists(cache_file)) {
      message("cached  ", key)
      fits[[key]] <- readRDS(cache_file)
      next
    }
    message("fitting ", key)
    set.seed(sd)
    fits[[key]] <- run_wai_adj(
      flows = prepared$flows,
      stocks = prepared$stocks,
      target = BRENT_TARGET,
      date = eval_date,
      dataset_used = variant,
      length_sample = length_sample,
      burn_in = burn_in
    )
    saveRDS(fits[[key]], cache_file)
  }
}

# REPORT ------------------------------------------------------------------

nowcast_at <- function(fit) as.numeric(utils::tail(fit$nowcast, 1))

summary_rows <- do.call(rbind, lapply(names(fits), function(key) {
  data.frame(fit = key, nowcast = nowcast_at(fits[[key]]), stringsAsFactors = FALSE)
}))

cat("\n== nowcast at the evaluation date ==\n")
print(summary_rows, row.names = FALSE)

within <- vapply(names(datasets), function(variant) {
  v <- vapply(seeds, function(sd) nowcast_at(fits[[paste0(variant, "_seed", sd)]]), numeric(1))
  abs(diff(range(v)))
}, numeric(1))
between <- vapply(seeds, function(sd) {
  abs(nowcast_at(fits[[paste0("with_brent_seed", sd)]]) -
        nowcast_at(fits[[paste0("full_RT_seed", sd)]]))
}, numeric(1))

cat("\n== is the variant difference bigger than seed noise? ==\n")
print(data.frame(
  quantity = c(paste0("seed spread within ", names(datasets)),
               paste0("with_brent - full_RT, seed ", seeds)),
  value = c(unname(within), between),
  stringsAsFactors = FALSE
), row.names = FALSE)

# Brent's loading and contribution, from the with_brent fits only.
#
# NOTE on "posterior interval": ind_dfm() stores only the posterior *mean* of
# lambda (R/ind_dfm.R averages par_save$lambda over draws and keeps nothing
# else), so a credible interval for the loading is not recoverable from a fit
# object. What is reported instead is the mean loading per seed, so its spread
# across seeds is visible, plus the loading's size relative to the other
# series' loadings - which is the comparison that actually answers "does the
# factor load on Brent at all".
cat("\n== Brent loading and nowcast contribution ==\n")
for (sd in seeds) {
  fit <- fits[[paste0("with_brent_seed", sd)]]
  cf <- coef(fit)                     # named numeric vector, names = series keys
  lam <- unname(cf[[BRENT_KEY]])
  cat("seed ", sd, ": Brent loading (posterior mean) = ", signif(lam, 5),
      "\n", sep = "")
  others <- abs(cf[names(cf) != BRENT_TARGET])
  cat("  rank among |loadings| (excl. the target, whose loading is fixed to 1): ",
      rank(-others)[BRENT_KEY], " of ", length(others),
      "; median |loading| = ", signif(stats::median(others), 4), "\n", sep = "")

  contrib <- as.data.frame(mfbdfm_contributions(fit), what = "nowcast")
  last_period <- max(contrib$time)
  here <- contrib[contrib$time == last_period, , drop = FALSE]
  tot <- sum(abs(here$contribution), na.rm = TRUE)
  here$share_abs <- abs(here$contribution) / tot
  here <- here[order(-here$share_abs), , drop = FALSE]
  cat("  contribution shares to the nowcast at time ", round(last_period, 3),
      " (top 8 of ", nrow(here), ")\n", sep = "")
  print(utils::head(here[, c("series", "contribution", "share_abs")], 8),
        row.names = FALSE)
  brent_row <- here[here$series == BRENT_KEY, , drop = FALSE]
  if (nrow(brent_row)) {
    cat("  Brent: contribution ", signif(brent_row$contribution, 4),
        ", share of total absolute contribution ",
        round(100 * brent_row$share_abs, 2), "%, rank ",
        which(here$series == BRENT_KEY), " of ", nrow(here), "\n", sep = "")
  } else {
    cat("  Brent: not present in the contribution table\n")
  }
}

saveRDS(
  list(date = eval_date, seeds = seeds, length_sample = length_sample,
       burn_in = burn_in, summary = summary_rows,
       within = within, between = between,
       fits = fits),
  file = file.path(out_dir, "brent_diagnostics.rds")
)
message("wrote ", file.path(out_dir, "brent_diagnostics.rds"))
