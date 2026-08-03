# Run from the repository root.

# -----------------------------------------------------------------------------
# Factors across factor counts (Eckert et al. 2025)
# -----------------------------------------------------------------------------
# Port of archive/factor_plot.R, which plots the estimated factors from the
# q = 1..4 runs together, grouped so that the "same" factor from each run is
# drawn in one panel.
#
# The alignment is the interesting part. The original hardcoded it:
#
#   group_1 <- ts.union(-factor_1, factor_2[,1], factor_3[,2],  factor_4[,4])
#   group_2 <- ts.union(            factor_2[,2], -factor_3[,3], factor_4[,2])
#   group_3 <- ts.union(                          -factor_3[,1], factor_4[,1])
#   group_4 <-                                                   -factor_4[,3]
#
# i.e. which column of each run matches which reference factor, and which needs
# its sign flipped - matched by eye. That is exactly the rotational
# indeterminacy documented in ?fcast_dfm: factors are identified only up to
# rotation and sign, so column 1 of the 3-factor run need not be "the same"
# factor as column 1 of the 4-factor run.
#
# This derives the alignment by correlation instead, and reports whether the
# result agrees with the hardcoded one. Hardcoded indices are specific to the
# objects they were written against; derived ones travel.
# -----------------------------------------------------------------------------

source("analysis/fcast/_setup.R")

ref_dir <- "analysis/fcast/reference/rda"
out_dir <- file.path("analysis", "outputs", "fcast", "replication", "figures")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)


# LOAD --------------------------------------------------------------------

fits <- list()
for (q in 1:4) {
  f <- file.path(ref_dir, sprintf("testlauf_%df.Rda", q))
  if (!file.exists(f)) {
    stop("Missing ", f, ".\n  These are the paper's fitted objects and are not ",
         "committed - see analysis/fcast/README.md.", call. = FALSE)
  }
  e <- new.env(); load(f, envir = e)
  fits[[q]] <- e$out
}

facs <- lapply(fits, function(x) as.matrix(x$factor))
message("factor counts loaded: ",
        paste(vapply(facs, ncol, integer(1)), collapse = ", "),
        "; ", nrow(facs[[1]]), " periods")


# ALIGN -------------------------------------------------------------------

# Reference set: the 4-factor run, which spans the most directions. Every column
# of every other run is matched to whichever reference column it correlates with
# most strongly in absolute value, and its sign flipped if that correlation is
# negative.
ref <- facs[[4]]

align <- function(mat, ref) {
  out <- lapply(seq_len(ncol(mat)), function(j) {
    r <- vapply(seq_len(ncol(ref)), function(k)
      suppressWarnings(stats::cor(mat[, j], ref[, k], use = "complete.obs")),
      numeric(1))
    k <- which.max(abs(r))
    list(col = j, ref_col = k, cor = r[k], sign = sign(r[k]))
  })
  do.call(rbind, lapply(out, as.data.frame))
}

map <- do.call(rbind, lapply(1:4, function(q)
  cbind(q = q, align(facs[[q]], ref))))

cat("\nDerived alignment (each run's columns matched to the 4-factor run):\n")
print(map, digits = 3, row.names = FALSE)

# What the original hardcoded, expressed the same way: run q, its column, the
# reference (4-factor) column it was grouped with, and whether it was negated.
hardcoded <- data.frame(
  q       = c(1, 2, 2, 3, 3, 3, 4, 4, 4, 4),
  col     = c(1, 1, 2, 1, 2, 3,  1, 2, 3, 4),
  ref_col = c(4, 4, 2, 1, 4, 2,  1, 2, 3, 4),
  sign    = c(-1, 1, 1, -1, 1, -1, 1, 1, -1, 1)
)

cmp <- merge(map[, c("q", "col", "ref_col", "sign")], hardcoded,
             by = c("q", "col"), suffixes = c("_derived", "_paper"))
cmp$same_group <- cmp$ref_col_derived == cmp$ref_col_paper
cmp$same_sign <- cmp$sign_derived == cmp$sign_paper
cat("\nDerived vs the original's hardcoded alignment:\n")
print(cmp, row.names = FALSE)
cat("  groups agree:", sum(cmp$same_group), "of", nrow(cmp),
    " | signs agree:", sum(cmp$same_sign), "of", nrow(cmp), "\n")


# PLOT --------------------------------------------------------------------

tm <- round(as.numeric(stats::time(fits[[4]]$factor)), 3)

long <- do.call(rbind, lapply(seq_len(nrow(map)), function(i) {
  r <- map[i, ]
  data.frame(time = tm,
             value = as.numeric(facs[[r$q]][, r$col]) * r$sign,
             run = paste0("q = ", r$q),
             group = paste("Factor", r$ref_col),
             stringsAsFactors = FALSE)
}))

p <- ggplot(long, aes(x = time, y = value, colour = run)) +
  geom_line(linewidth = 0.3) +
  facet_wrap(~group, ncol = 1, scales = "free_y") +
  labs(x = NULL, y = NULL,
       title = "Estimated factors across factor counts, sign- and order-aligned") +
  theme_minimal(base_size = 9) +
  theme(panel.grid.minor = element_blank(),
        legend.position = "bottom", legend.title = element_blank())

path <- file.path(out_dir, "factor_plot_wai.pdf")
ggsave(path, p, width = 20, height = 28, units = "cm")
message("\nwrote ", path)
