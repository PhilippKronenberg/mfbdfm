# Sourced by 1_backcast_fcast.R. Run from the repository root.

# -----------------------------------------------------------------------------
# BMDFM benchmark (Banbura & Modugno, JAE 2014)
# -----------------------------------------------------------------------------
# The benchmark model of Eckert et al. (2025), so the WAIVSBMDFM comparison can
# be produced from our own estimates rather than only from the paper's stored
# panel.
#
# Port of run_bmdfm() from archive/functions_backcast.R. Everything it needs
# from the `nowcasting` package is vendored under
# analysis/benchmarks/functions_package_nowcasting/ - see _setup.R for why.
#
# ONE adaptation, and it is on this side of the boundary deliberately: the
# original called
#
#     prepare_data(flows, stocks, inventory, model = "bmdfm")
#
# and prepare_data() has no `model` argument any more - it takes `target`. The
# package function is left alone and the call is updated here, because
# prepare_data() is package API used by both models and the replication is what
# has to bend.
#
# The BMDFM is a MONTHLY model: its state equation runs at monthly frequency and
# the vendored nowcast() expects a monthly panel. Feed it monthly data. That is
# also why the paper never reports BMDFM on the weekly ("full") dataset - in the
# published panel bmdfm has zero rows there.
# -----------------------------------------------------------------------------


#' Fit the BMDFM benchmark at one evaluation date
#'
#' Mirrors run_fcast()/run_wai_adj(): returns the fit invisibly and writes only
#' when `output_dir` is given, in the same
#' `<output_dir>/<dataset_used>/fit_<date>.Rda` layout, so the same backcasting
#' loop and the same fit-discovery code drive all three.
#'
#' @param flows,stocks Named lists of `ts`. Must already be monthly or coarser;
#'   see the note above. Use `week2mon()` if they are not.
#' @param target Character, the target series name.
#' @param date Numeric decimal evaluation date.
#' @param dataset_used Character label used as the sub-directory.
#' @param n_f Integer, number of factors.
#' @param output_dir Directory to write to, or NULL to skip writing.
run_bmdfm <- function(flows, stocks, target, date, dataset_used,
                      n_f = 1, output_dir = NULL) {

  inventory <- create_inventory(flows = flows, stocks = stocks)

  if (max(inventory$freq) > 12) {
    stop("run_bmdfm() needs monthly (or coarser) input - the highest frequency ",
         "here is ", max(inventory$freq), ".\n",
         "  The BMDFM is a monthly model; aggregate with week2mon() first. ",
         "This is why the paper reports no BMDFM results on the weekly dataset.",
         call. = FALSE)
  }

  # ADAPTED: `target =`, not `model =`. See the header.
  Ymat <- prepare_data(flows = flows, stocks = stocks,
                       inventory = inventory, target = target)

  base <- window(Ymat, start = c(1990, 1), frequency = 12, extend = TRUE)
  base[base == 0] <- NA          # 0 encodes missing in the prepared data

  blocks <- matrix(1, nrow = ncol(Ymat), ncol = n_f)
  trans <- rep(0, ncol(Ymat))    # already transformed upstream

  freq <- rep(12, ncol(base))
  freq[which(colnames(base) == target)] <- 4

  data <- Bpanel(base = base, trans = trans, NA.replace = FALSE, na.prop = 1)

  mod <- nowcast(formula = stats::as.formula(paste(target, "~ .")),
                 data = data, r = n_f, p = 1, q = 1, method = "EM",
                 blocks = blocks, frequency = freq,
                 Ymat = Ymat, inventory = inventory)

  if (!is.null(output_dir)) {
    fit_dir <- file.path(output_dir, dataset_used)
    dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)
    save(mod, file = file.path(fit_dir, paste0("fit_", round(date, 3), ".Rda")))
  }

  invisible(mod)

}
