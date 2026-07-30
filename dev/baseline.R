# Baseline snapshots for fast before/after verification.
#
# Most changes to this package are meant to leave results untouched - the
# refactors in #40/#42/#43/#44/#48 all had to be bit-identical. Verifying that
# by checking out the parent commit into a git worktree and running two full
# fits takes minutes. This stores the numbers once so a later check is a single
# fit and a comparison.
#
#   source("dev/baseline.R")
#   baseline_check()     # compare the current code against the stored snapshot
#   baseline_write()     # regenerate it, when a change is MEANT to alter results
#
# NOT a CI test, deliberately. MCMC output is not bit-identical across
# platforms: a different BLAS sums in a different order, which shifts the last
# bit, and an MCMC chain amplifies that into an O(1) difference within a few
# iterations. A committed golden-value test would therefore fail on the CI
# matrix for reasons that have nothing to do with the code. The snapshot
# records the platform it was generated on, and baseline_check() warns if you
# compare across a boundary where a mismatch would be meaningless.

BASELINE_PATH <- "dev/baseline.rds"


#' Make the package available, whether or not it is installed
#'
#' So `source("dev/baseline.R"); baseline_check()` works from a bare session in
#' the package root without a prior load_all() or install.
baseline_load <- function(){
  if("mfbdfm" %in% loadedNamespaces()) return(invisible())
  if(requireNamespace("mfbdfm", quietly = TRUE)){
    requireNamespace("mfbdfm", quietly = TRUE)
  } else {
    devtools::load_all(".", quiet = TRUE)
  }
  invisible()
}


#' The fits the snapshot covers
#'
#' Deliberately small and fast, but chosen to exercise the branches that
#' matter: both models, and the stochastic-volatility and serial-correlation
#' paths that only run when those flags are FALSE.
baseline_fits <- function(){

  baseline_load()

  e <- new.env()
  utils::data("data_ch_dataset_test", package = "mfbdfm", envir = e)
  d <- e$data_ch_dataset_test

  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(d$flows[c(target, "SWISSMI", "FINANSW")],
                  stats::window, start = 2020)
  stocks <- lapply(d$stocks[c("SWCONPRCE", "VIX")], stats::window, start = 2020)

  run_ind <- function(...){
    set.seed(2026)
    suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                             length_sample = 15, burn_in = 5, plots = FALSE, ...))
  }

  list(
    ind_default = function() run_ind(),
    ind_no_sv = function() run_ind(stochastic_volatility = FALSE),
    ind_no_serial = function() run_ind(serial_correlation = FALSE),
    fcast_q2 = function(){
      set.seed(7)
      suppressMessages(suppressWarnings(
        fcast_dfm(flows = flows, stocks = stocks, target = target, q = 2,
                  length_sample = 8, burn_in = 4, plots = FALSE)))
    }
  )

}


#' Reduce a fit to the values worth comparing
#'
#' Keeps actual numbers rather than a hash, so a failed comparison says *what*
#' moved, not merely that something did.
baseline_digest <- function(fit){

  keep <- function(x) if(is.null(x)) NULL else as.numeric(x)

  list(factor = keep(fit$factor),
       factor_var = keep(fit$factor_var),
       nowcast = keep(fit$nowcast),
       nowcast_var = keep(fit$nowcast_var),
       lambda = keep(fit$pars$lambda),
       phi = keep(unlist(fit$pars$phi)),
       sigma = keep(fit$pars$sigma),
       rho = keep(fit$pars$rho),
       h = keep(fit$pars$h))

}


#' Run every baseline fit and digest it
baseline_run <- function(){

  fns <- baseline_fits()
  out <- lapply(names(fns), function(nm){
    message("  running ", nm, " ...")
    baseline_digest(fns[[nm]]())
  })
  names(out) <- names(fns)
  out

}


#' Record where a snapshot came from
baseline_provenance <- function(){

  sha <- tryCatch(
    trimws(system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE)),
    error = function(e) NA_character_)

  list(git_sha = sha,
       created = as.character(Sys.time()),
       r_version = paste(R.version$major, R.version$minor, sep = "."),
       platform = R.version$platform,
       blas = tryCatch(sessionInfo()$BLAS, error = function(e) NA_character_))

}


#' Regenerate and save the baseline snapshot
#'
#' Run this only when a change is *meant* to alter results - it overwrites the
#' reference the next check compares against.
baseline_write <- function(path = BASELINE_PATH){

  message("Generating baseline snapshot ...")
  snap <- list(provenance = baseline_provenance(), fits = baseline_run())

  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(snap, path)

  message("Saved to ", path, "  (", round(file.size(path)/1024, 1), " KB)")
  message("  commit   : ", snap$provenance$git_sha)
  message("  platform : ", snap$provenance$platform)
  invisible(snap)

}


#' Compare the current code against the stored snapshot
#'
#' @return `TRUE` invisibly if every value matches, `FALSE` otherwise.
baseline_check <- function(path = BASELINE_PATH){

  if(!file.exists(path)){
    stop("No baseline at ", path, ". Run baseline_write() first.", call. = FALSE)
  }

  old <- readRDS(path)
  now <- baseline_provenance()

  cat("Baseline from commit ", old$provenance$git_sha,
      " (", old$provenance$platform, ")\n", sep = "")
  cat("Current  is   commit ", now$git_sha,
      " (", now$platform, ")\n\n", sep = "")

  if(!identical(old$provenance$platform, now$platform)){
    warning("Baseline was generated on a different platform (", old$provenance$platform,
            " vs ", now$platform, "). MCMC output is not bit-identical across ",
            "BLAS implementations, so a mismatch here may mean nothing.",
            call. = FALSE)
  }

  new <- baseline_run()
  cat("\n")

  ok <- TRUE
  for(nm in names(old$fits)){

    if(!nm %in% names(new)){
      cat(sprintf("  %-14s MISSING from the current run\n", nm)); ok <- FALSE; next
    }

    a <- old$fits[[nm]]; b <- new[[nm]]
    diffs <- names(a)[!vapply(names(a), function(k) identical(a[[k]], b[[k]]), logical(1))]

    if(!length(diffs)){
      cat(sprintf("  %-14s identical\n", nm))
    } else {
      ok <- FALSE
      cat(sprintf("  %-14s DIFFERS in: %s\n", nm, paste(diffs, collapse = ", ")))
      for(k in diffs){
        av <- a[[k]]; bv <- b[[k]]
        if(is.null(av) || is.null(bv) || length(av) != length(bv)){
          cat(sprintf("      %-12s length %s -> %s\n", k, length(av), length(bv)))
        } else {
          cat(sprintf("      %-12s max abs diff %.3e   max rel %.3e\n", k,
                      max(abs(av - bv), na.rm = TRUE),
                      max(abs(av - bv)/pmax(abs(av), 1e-12), na.rm = TRUE)))
        }
      }
    }
  }

  cat("\n", if(ok) "BASELINE MATCHES\n" else "BASELINE DIFFERS - see above\n", sep = "")
  invisible(ok)

}
