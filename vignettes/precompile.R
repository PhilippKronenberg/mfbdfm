# Precompute the vignette.
#
# `mfbdfm.Rmd.orig` is the source to edit; `mfbdfm.Rmd` is generated from it by
# this script and committed, together with the `vignettes/mfbdfm-*.png` figures.
# The generated file contains no live chunks, so `R CMD check` and pkgdown
# render the baked-in output of real fits instead of re-running them.
#
# Run from the package root:
#
#   Rscript vignettes/precompile.R
#
# Takes a few minutes: it fits three short-chain models. Commit the resulting
# `vignettes/mfbdfm.Rmd` and `vignettes/mfbdfm-*.png`.
#
# The pattern is rOpenSci's: https://ropensci.org/blog/2019/12/08/precompute-vignettes/

if (!requireNamespace("knitr", quietly = TRUE)) {
  stop("knitr is required to precompute the vignette.")
}

# fig.path is set in the .orig's setup chunk, relative to the knitting
# directory, so knit from vignettes/ and the figures land next to the vignette.
vig_dir <- if (basename(getwd()) == "vignettes") "." else "vignettes"
owd <- setwd(vig_dir)
on.exit(setwd(owd), add = TRUE)

knitr::knit("mfbdfm.Rmd.orig", output = "mfbdfm.Rmd")

message("Wrote ", file.path(vig_dir, "mfbdfm.Rmd"),
        " and its mfbdfm-*.png figures")
