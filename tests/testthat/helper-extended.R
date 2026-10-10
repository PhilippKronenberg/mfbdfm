# Harness for the extended test suite (#122).
#
# Extended tests are the ones that cannot sit in `devtools::test()`: they take
# minutes rather than seconds, or they compare against a snapshot that is only
# meaningful on the machine that wrote it. They are skipped unless
#
#   MFBDFM_EXTENDED_TESTS=true
#
# is set in the environment. `tests/README.md` is the documentation for them -
# what each one costs, what it needs, and what has to be inspected by hand.
#
# Everything in this file is a skip or a report, never an assertion: a missing
# prerequisite must skip with a reason, not fail.

# The flag, named once so a typo cannot make the suite silently inactive.
MFBDFM_EXTENDED_FLAG <- "MFBDFM_EXTENDED_TESTS"

is_extended <- function() identical(Sys.getenv(MFBDFM_EXTENDED_FLAG), "true")

# Use this at the top of every extended test block (rOpenSci G5.10).
skip_if_not_extended <- function() {
  testthat::skip_if_not(
    is_extended(),
    paste0("extended test - set ", MFBDFM_EXTENDED_FLAG,
           "=true to run it (see tests/README.md)"))
}


# ---------------------------------------------------- the dev/ scripts ----

# Two of the extended tests wrap a script in `dev/` rather than duplicating it:
# `dev/baseline.R` (behaviour-preservation snapshot) and `dev/mc_recovery.R`
# (simulation recovery). `^dev$` is in `.Rbuildignore`, so those scripts exist
# in a source checkout and not in the built tarball - which means these tests
# can only run under `devtools::test()` from a checkout, and must skip, not
# fail, anywhere else.
#
# testthat runs with the working directory at `tests/testthat`, so the package
# root is two levels up; the loop tolerates being called from elsewhere.
mfbdfm_dev_dir <- function() {

  for (up in c(".", "..", "../..", "../../..")) {
    cand <- file.path(getwd(), up, "dev")
    if (dir.exists(cand) && file.exists(file.path(cand, "baseline.R"))) {
      return(normalizePath(cand, winslash = "/"))
    }
  }
  NULL

}

# Resolve one dev/ script, skipping with a reason when it is out of reach.
# Returns its absolute path.
dev_script <- function(file) {

  d <- mfbdfm_dev_dir()
  testthat::skip_if(
    is.null(d),
    paste0("no dev/ directory in reach: `^dev$` is in .Rbuildignore, so ",
           "dev/", file, " ships with the source checkout only"))

  p <- file.path(d, file)
  testthat::skip_if(!file.exists(p), paste0("dev/", file, " not found"))
  p

}

# The dev/ scripts address their own snapshots by paths relative to the package
# root ("dev/baseline.rds"), so they have to be evaluated from there.
with_pkg_root <- function(code) {

  root <- dirname(mfbdfm_dev_dir())
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  force(code)

}

# Source a dev/ script into a throwaway environment, from the package root.
#
# The scripts call `baseline_load()`-style helpers that would `load_all()` the
# package if it were not already attached; both test runners attach it first
# (`devtools::test()` via load_all, `tests/testthat.R` via library()), so this
# re-uses the package under test rather than reloading it.
source_dev <- function(file) {

  path <- dev_script(file)
  env <- new.env(parent = globalenv())
  with_pkg_root(sys.source(path, envir = env))
  env

}


# ------------------------------------------------------------ reporting ----

# Several extended tests assert a loose, documented bound but are mainly worth
# running for the number they measure (recovery, scaling, runtime). Print those
# so a run leaves a record; stderr, because testthat's reporters own stdout.
ext_report <- function(...) {
  cat("    [extended] ", ..., "\n", sep = "", file = stderr())
  invisible(NULL)
}

# Time an expression and report it, returning its value.
ext_timed <- function(label, expr) {

  t0 <- Sys.time()
  out <- force(expr)
  ext_report(sprintf("%-28s %6.1f s", label, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
  out

}
