# Restore the paper's get_zmat() and get_zmat_fcast() in this R session (#166).
#
#   library(mfbdfm)                                # or devtools::load_all()
#   source("dev/paper_replication/use_paper_zmat.R")
#   use_paper_zmat()
#
# Run from the package root. Lasts until the session ends; nothing on disk
# changes. See README.md in this folder.
#
# This does NOT replicate the papers on the current code, as #168-#170 changed
# the sampler too: for that, install commit ac9c2a6 into a separate library. It
# is kept as the negative control for dev/geweke.R.

use_paper_zmat <- function(dir = "dev/paper_replication"){

  ns <- asNamespace("mfbdfm")

  restore <- function(file, name){
    e <- new.env(parent = ns)
    sys.source(file.path(dir, file), envir = e)
    fn <- e[[name]]
    environment(fn) <- ns
    unlockBinding(name, ns)
    assign(name, fn, envir = ns)
    lockBinding(name, ns)
  }

  restore("model-helpers.R", "get_zmat")
  restore("samplers_fcast.R", "get_zmat_fcast")

  message("get_zmat() and get_zmat_fcast() now have the paper's swapped indices, ",
          "for this session only. This does not replicate the papers: see README.md.")
  invisible(TRUE)

}
