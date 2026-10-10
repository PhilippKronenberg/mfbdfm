# Extended test: the behaviour-preservation snapshot (#122).
#
# This wraps `dev/baseline.R` rather than reimplementing it, so there is one
# definition of "the fits the snapshot covers" and one comparison. See
# tests/README.md for what it costs and when it can run at all.

test_that("the stored baseline snapshot still reproduces (dev/baseline.R)", {

  skip_if_not_extended()
  path <- dev_script("baseline.R")

  with_pkg_root({

    skip_if(!file.exists("dev/baseline.rds"),
            "no dev/baseline.rds to compare against; run baseline_write() first")

    snap <- readRDS("dev/baseline.rds")

    # MCMC output is not bit-identical across BLAS implementations: a different
    # summation order moves the last bit and the chain amplifies that to O(1)
    # within a few iterations. So a mismatch across a platform boundary says
    # nothing about the code, which is why this is not a CI test and why it
    # skips rather than fails here. baseline_check() itself only warns.
    skip_if_not(identical(snap$provenance$platform, R.version$platform),
                paste0("baseline snapshot was written on ",
                       snap$provenance$platform, ", this is ",
                       R.version$platform,
                       " - MCMC output is not comparable across BLAS"))

    env <- new.env(parent = globalenv())
    sys.source(path, envir = env)

    ok <- ext_timed("baseline_check()",
                    utils::capture.output(res <- env$baseline_check()))
    # capture.output() returns the report; the verdict is the returned value
    ext_report("snapshot from commit ", snap$provenance$git_sha)
    if (!isTRUE(res)) ext_report(paste(ok, collapse = "\n               "))

    expect_true(res)

  })

})
