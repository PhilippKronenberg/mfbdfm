# Run from the repository root.

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Local update runner for the public WAI dashboard
#
# One idempotent pass: refresh the data, fit the model at the current vintage,
# export the two web files, check them against the published contract, and
# commit + push them to the wai-webapp repository - but only if every check
# passes and something actually changed.
#
# This is stage 1-3 of the pipeline described in dev/wai-webapp-plan.md. It runs
# HERE, on a machine that holds the licensed source data under data/dataset/,
# because a GitHub-hosted runner cannot refresh that data. Only the derived
# aggregate output is ever pushed; nothing from data/dataset/ leaves this
# machine.
#
# Usage
#   Rscript analysis/update_wai_web.R
#   Rscript analysis/update_wai_web.R --dry-run     # do everything except push
#   Rscript analysis/update_wai_web.R --skip-prep   # reuse the prepared dataset
#
# Scheduling it (once it has been run by hand a few times):
#   Windows  Task Scheduler -> weekly -> Program: Rscript.exe
#            Arguments: analysis/update_wai_web.R
#            Start in:  <path to this repository>
#   Linux    crontab -e ->  0 6 * * 1  cd /path/to/mfbdfm && Rscript analysis/update_wai_web.R
#
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


# SETTINGS ----------------------------------------------------------------

# Where the wai-webapp repository is checked out. Must be a git clone with a
# remote you can push to.
webapp_dir <- Sys.getenv("WAI_WEBAPP_DIR", unset = "../wai-webapp")

target       <- "ch.seco.gdp.real.gdp.ssa"
dataset_path <- file.path("analysis", "Rda", "data_ch_dataset_test.Rda")
fit_root     <- file.path("fits", "web")

# Chain settings. These are run_wai_adj()'s own defaults, stated explicitly so a
# scheduled run never silently changes length because a default moved.
length_sample <- 5000
burn_in       <- 1000
thinning      <- 1

# The published series is rounded to this many decimals.
digits <- 4

args     <- commandArgs(trailingOnly = TRUE)
dry_run  <- "--dry-run"  %in% args
skip_prep <- "--skip-prep" %in% args


# HELPERS -----------------------------------------------------------------

say <- function(...) message(format(Sys.time(), "[%Y-%m-%d %H:%M:%S] "), ...)

# Guard rails are deliberately fatal rather than warning: a scheduled job with
# nobody watching must not publish a half-broken file, and a loud failure is
# recoverable where a quiet bad publish is not.
must <- function(condition, ...) {
  if (!isTRUE(condition)) stop(..., call. = FALSE)
  invisible(TRUE)
}

git <- function(..., dir = webapp_dir) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(dir), ...),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0) {
    stop("git ", paste(..., collapse = " "), " failed:\n",
         paste(out, collapse = "\n"), call. = FALSE)
  }
  out
}

# Re-read what we are about to publish and hold it to the contract the front end
# relies on. Checking the written file rather than the in-memory object is the
# point: it is the file that gets served.
validate_export <- function(dir) {
  csv_path  <- file.path(dir, "wai_data.csv")
  meta_path <- file.path(dir, "wai_meta.json")
  must(file.exists(csv_path),  "export produced no wai_data.csv")
  must(file.exists(meta_path), "export produced no wai_meta.json")

  lines <- readLines(csv_path, warn = FALSE)
  must(length(lines) > 100, "wai_data.csv has only ", length(lines), " lines")

  expected <- c("date", "wai_qoq", "wai_qoq_lo", "wai_qoq_hi", "wai_yoy",
                "wai_index", "gdp_qoq", "gdp_yoy", "gdp_index")
  header <- strsplit(lines[1], ",", fixed = TRUE)[[1]]
  must(identical(header, expected),
       "wai_data.csv header is\n  ", lines[1],
       "\nbut the front end expects\n  ", paste(expected, collapse = ","))

  must(!any(grepl("\"", lines, fixed = TRUE)), "wai_data.csv contains quotes")
  must(!any(grepl("\\b(NA|NaN|Inf|NULL)\\b", lines)),
       "wai_data.csv encodes missing values as NA/NaN/Inf/NULL; the contract is the empty string")

  d <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  dates <- as.Date(d$date)
  must(!anyNA(dates), "wai_data.csv has unparseable dates")
  must(!is.unsorted(dates), "wai_data.csv rows are not sorted ascending by date")
  must(anyDuplicated(dates) == 0, "wai_data.csv has duplicate dates")
  must(!anyNA(d$wai_qoq), "wai_qoq has missing values")

  # A column that is present but entirely empty is well-formed, so every check
  # above passes it. That is exactly how an all-empty gdp_qoq nearly shipped:
  # the date units were wrong, no GDP value matched any week, and nothing
  # noticed. Every published column must carry at least one value.
  for (nm in setdiff(names(d), "date")) {
    must(any(!is.na(d[[nm]])),
         "column `", nm, "` is present but entirely empty - it would publish a ",
         "series with nothing in it")
  }
  must(all(d$wai_qoq_lo < d$wai_qoq & d$wai_qoq < d$wai_qoq_hi),
       "the 95% band does not bracket wai_qoq everywhere")

  invisible(list(n = nrow(d), last = max(dates)))
}

# Refuse to replace a published series with one that stops earlier. A fit that
# silently lost its most recent weeks is the failure mode most likely to slip
# through everything above, because the file is perfectly well-formed.
check_not_going_backwards <- function(new_last, published_csv) {
  if (!file.exists(published_csv)) return(invisible(TRUE))
  old <- utils::read.csv(published_csv, stringsAsFactors = FALSE)
  if (!nrow(old) || is.null(old$date)) return(invisible(TRUE))
  old_last <- max(as.Date(old$date))
  must(new_last >= old_last,
       "the new export ends at ", new_last, " but the published data already ",
       "runs to ", old_last, ". Refusing to publish a shorter series.")
  invisible(TRUE)
}


# RUN ---------------------------------------------------------------------

say("update_wai_web starting", if (dry_run) " (dry run)" else "")

must(dir.exists(webapp_dir),
     "webapp_dir does not exist: ", normalizePath(webapp_dir, mustWork = FALSE),
     "\nClone it, or set WAI_WEBAPP_DIR.")
must(dir.exists(file.path(webapp_dir, ".git")),
     webapp_dir, " is not a git repository.")

suppressPackageStartupMessages({
  library(mfbdfm)
  library(zoo)
})

# 1. Refresh the prepared dataset from the private raw sources ---------------
if (!skip_prep) {
  say("preparing dataset from data/dataset/ ...")
  must(dir.exists(file.path("data", "dataset")),
       "data/dataset/ is missing - this script must run on a machine that has ",
       "the licensed source data. Use --skip-prep to reuse an existing ",
       dataset_path, ".")
  source(file.path("analysis", "1_data_prep_dataset.R"), local = new.env())
} else {
  say("skipping data preparation (--skip-prep)")
}

must(file.exists(dataset_path), "prepared dataset not found: ", dataset_path)
load(dataset_path)                      # provides `dat`
must(exists("dat"), dataset_path, " did not contain an object named `dat`")

# 2. Fit at the most recent vintage ----------------------------------------
GDP_gr_vintages <- get_real_time_gdp_vintages("quarterly")

# The evaluation date is the most recent completed weekly period in the data.
last_week <- max(vapply(c(dat$flows, dat$stocks),
                        function(x) max(as.numeric(stats::time(x))), numeric(1)))
eval_date <- round(last_week, 4)
say("fitting at ", eval_date, " (", length_sample, " draws after ", burn_in,
    " burn-in) - this takes a few minutes")

dat_rt <- cut_data_real_time(dat, eval_date, GDP_gr_vintages)
dat_rt$flows[[target]] <- zoo::na.trim(
  stats::ts(select_most_recent_GDP_vintage(eval_date, GDP_gr_vintages),
            start = c(1990, 1), frequency = 4)
)

fit <- run_wai_adj(flows = dat_rt$flows, stocks = dat_rt$stocks,
                   target = target, date = eval_date,
                   dataset_used = "web",
                   length_sample = length_sample, burn_in = burn_in,
                   thinning = thinning, output_dir = fit_root)

fit_path <- file.path(fit_root, "web", paste0("fit_", eval_date, ".Rda"))
must(file.exists(fit_path), "run_wai_adj() did not write ", fit_path)
say("fit written to ", fit_path)

# 3. Export, into a staging directory first --------------------------------
staging <- file.path(tempdir(), "wai-export")
unlink(staging, recursive = TRUE)
dir.create(staging, recursive = TRUE)

# gdp_web_series() returns official GDP as annualised QoQ growth, YoY growth and
# a level index rebased to 2019Q4 = 100 - the same three measures as the WAI
# series and on the same scale, so they can share an axis. Doing the conversion
# here by hand is what produced two earlier bugs: raw log differences (wrong by
# a factor of ~400) and Dates coerced with as.numeric() (days since 1970, so no
# GDP point matched any week).
gdp_latest <- gdp_web_series()

export_wai_web(fit_path, dir = staging, gdp = gdp_latest, digits = digits,
               vintage_date = as.character(dec2week(eval_date)))

info <- validate_export(staging)
say("export validated: ", info$n, " weeks, ending ", info$last)

check_not_going_backwards(info$last, file.path(webapp_dir, "wai_data.csv"))

# 4. Publish ---------------------------------------------------------------
file.copy(file.path(staging, c("wai_data.csv", "wai_meta.json")),
          webapp_dir, overwrite = TRUE)

changed <- length(git("status", "--porcelain", "--", "wai_data.csv", "wai_meta.json")) > 0
if (!changed) {
  say("no change in the published files - nothing to commit")
  say("done")
  quit(save = "no", status = 0)
}

if (dry_run) {
  say("dry run: files updated in ", normalizePath(webapp_dir), " but not committed")
  say("done")
  quit(save = "no", status = 0)
}

msg <- paste0("Update WAI data to ", info$last)
git("add", "--", "wai_data.csv", "wai_meta.json")
git("commit", "-m", shQuote(msg))
git("push")
say("pushed: ", msg)
say("done")
