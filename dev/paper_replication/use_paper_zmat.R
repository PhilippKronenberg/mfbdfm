# Restore the paper's get_zmat() and get_zmat_fcast() in this R session (#166).
#
#   library(mfbdfm)                                # or devtools::load_all()
#   source("dev/paper_replication/use_paper_zmat.R")
#   use_paper_zmat()
#
# Run from the package root. Lasts until the session ends; nothing on disk
# changes. See README.md in this folder.

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
          "for this session only.")
  invisible(TRUE)

}
