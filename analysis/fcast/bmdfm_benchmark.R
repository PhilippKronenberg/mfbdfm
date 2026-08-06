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
# That `model` argument did more than name things: its "bmdfm" branch skipped
# the standardisation entirely (verified against the original functions_model.R,
# lines 856-873). Reproducing that is what the block below does. The first
# version of this file missed it, and the resulting nowcasts were in standard
# deviations - off by two orders of magnitude, silently, because nothing
# downstream checks units.
#
# WHY the original could skip it: nowcast() standardises internally and converts
# back. method_EM.r:377-380 does
#     Mx = colMeans(X); Wx = sd(X); xNaN <- (X - Mx)/Wx
# and line 464 undoes it,
#     Res$X_sm <- Wx * x_sm + Mx
# so the EM returns output on whatever scale it was handed. It is therefore
# scale-equivariant, and pre-standardising is redundant rather than wrong -
# measured, feeding standardised data and un-standardising yfcst afterwards
# agrees with feeding raw data to 1.1e-11. What is wrong is pre-standardising and
# then NOT converting back, which is what the first version did.
#
# This also explains the vestigial `Ymat` and `inventory` arguments on the
# vendored nowcast(): they are accepted and never used anywhere in its body.
# They look like the missing rescaler and are not - the EM already handles it.
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
  #
  # And the adaptation has to undo a standardisation. The original
  # prepare_data() branched on `model`:
  #
  #     if(model == "bmdfm" || model == "grsdfm"){
  #       data_std <- data                       # NO standardisation
  #     } else{
  #       data_std <- lapply(...)                # (x - mean) / sd
  #     }
  #
  # so the BMDFM was fitted on RAW data while the WAI model was fitted on
  # standardised data. The package's prepare_data() has no `model` argument and
  # always standardises, which is right for both of its own models - so the
  # unstandardising belongs here, on the replication side.
  #
  # Inverting prepare_data()'s own arithmetic with the same inventory recovers
  # the raw series exactly, not approximately: measured max absolute difference
  # 8.7e-19 over the target series. The 0-encodes-missing marker is preserved so
  # the line below behaves as it did in the original.
  Ymat <- prepare_data(flows = flows, stocks = stocks,
                       inventory = inventory, target = target)
  miss <- Ymat == 0
  for (j in seq_len(ncol(Ymat))) {
    k <- which(inventory$key == colnames(Ymat)[j])
    Ymat[, j] <- Ymat[, j] * inventory[k, "sd"] + inventory[k, "mean"]
  }
  Ymat[miss] <- 0

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

  # No rescaling of mod$yfcst here, deliberately: the input is already on the
  # target's own scale, so nowcast() returns nowcasts on it. An earlier version
  # of this file standardised the input and un-standardised yfcst afterwards
  # instead. That gives the same nowcast - measured, the two agree to 1.1e-11,
  # the BMDFM being scale-equivariant in effect - but it left the fit object
  # internally mixed, with yfcst on one scale and factors/xfcst/Res on another.
  # Matching the original's data prep is the cleaner of two equivalent routes.
  #
  # For the record, the symptom this fixed: with standardised input and no
  # rescaling anywhere, bmdfm nowcasts ranged -6.12 to 6.57 with a median of
  # -1.90 against realisations of -0.066 to 0.059, an RMSE of 3.52 against
  # fcast_dfm's 0.021. The realisations were identical for both models, which is
  # what located the problem on the nowcast side.

  if (!is.null(output_dir)) {
    fit_dir <- file.path(output_dir, dataset_used)
    dir.create(fit_dir, recursive = TRUE, showWarnings = FALSE)
    save(mod, file = file.path(fit_dir, paste0("fit_", round(date, 3), ".Rda")))
  }

  invisible(mod)

}
