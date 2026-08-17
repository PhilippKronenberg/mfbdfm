# cran-comments

**Status: not yet submitted.** This is version `0.1.0`, the intended first CRAN
release. The local results below are current for it. The remote checks in the
"Test environments" section — win-builder in particular — still have to be run
before this file describes a real submission.

## Test environments

Run, with results:

* local Windows 11, R 4.5.2 (2025-10-31 ucrt), x86_64-w64-mingw32,
  with pandoc 3.8.3 and MiKTeX 25.3 — so vignettes and the PDF manual are
  actually built, not skipped
* GitHub Actions (`.github/workflows/r.yml`), all four jobs green at commit
  `9d3b83b`:
  * ubuntu-latest, R release
  * ubuntu-latest, R oldrel-1
  * macos-latest, R release
  * windows-latest, R release

* **win-builder, R-devel** — `R Under development (unstable) (2026-08-15 r90413
  ucrt)`, x86_64-w64-mingw32, Windows Server 2022, gcc 14.3.0. **Status: 1 NOTE**
  (see below); every other check `OK`, including the vignette rebuild and both the
  PDF and HTML manuals.
* GitHub Actions also runs R-devel on every push now, so R-devel coverage is
  continuous rather than a one-off pre-submission act.

Not run, and not blocking:

* R-hub — `rhub::check_for_cran()` no longer exists; rhub 2.x runs checks through
  the project's own GitHub Actions, which the R-devel matrix job already covers.
* macOS builder (`devtools::check_mac_release()`) — macOS release is covered by
  the CI matrix.

## R CMD check results

`R CMD check --as-cran` on 0.1.0, with the vignette, the PDF manual and the HTML
manual (math rendering included) all built and checked: **0 errors, 0 warnings,
1 note** — and that one note is `New submission`. Test suite inside the check:
`FAIL 0 | WARN 0 | SKIP 0 | PASS 677`.

### NOTE 1 — CRAN incoming feasibility

```text
Maintainer: 'Philipp Kronenberg <philippkronenberg@gmx.ch>'

New submission
```

Correct — this is the first release. Unavoidable and explicitly acceptable.

An earlier `Version contains large components (0.0.0.9000)` line is gone: that
was an artifact of checking the development version, and the bump to `0.1.0`
cleared it, confirmed by re-running rather than assumed.

**win-builder adds a spell-check sub-NOTE to this same NOTE:**

```text
Possibly misspelled words in DESCRIPTION:
  Eckert (22:46)
  Kronenberg (21:18, 22:54)
  Mikosch (22:66)
  Neuwirth (23:9)
  WAI (17:12)
```

All five are correct as written. `Eckert`, `Kronenberg`, `Mikosch` and `Neuwirth`
are the surnames of the authors of the two cited papers — CRAN's `Description`
conventions ask for citations in `authors (year) <doi:...>` form, so the names have
to appear. `WAI` is the package's flagship indicator and the `Description` already
expands it on first use: "the Weekly Activity Index (WAI)". No spelling change is
appropriate.

### Formerly NOTE 2 — HTML version of the manual, now resolved

`--as-cran` previously reported `Skipping checking math rendering: package 'V8'
unavailable`, so the KaTeX math in the Rd files was never actually verified here.
`V8` 8.2.0 is now installed and the sub-check runs for real:

```text
* checking PDF version of manual ... OK
* checking HTML version of manual ... OK
```

Both forms of the manual therefore build and render cleanly — the PDF via
MiKTeX 25.3, the HTML with math rendering genuinely checked rather than skipped.

### A URL sub-NOTE that is a false positive

One run of `--as-cran` added this to NOTE 1:

```text
Found the following (possibly) invalid URLs:
  URL: https://github.com/PhilippKronenberg/mfbdfm/issues
    From: DESCRIPTION
          man/mfbdfm-package.Rd
    Status: 404
    Message: Not Found
```

The URL is correct. The repository is public with issues enabled, the page loads
in a browser, and an earlier run of both `urlchecker::url_check()` and a direct
check returned 200 for this exact URL.

Established by comparison rather than assumed: in the same moment, from the same
machine, `github.com/r-lib/testthat/issues` and `github.com/tidyverse/dplyr/issues`
**also returned 404**, while every repository *root* returned 200. GitHub serves
404 on `/issues` and `/pulls` to clients it has decided to throttle — this session
had made a great many requests. So the 404 describes our client, not our
`BugReports` field.

**Do not "fix" this by changing or removing the `BugReports` URL.** It is the
standard form and thousands of CRAN packages use it.

**Confirmed by win-builder**, which raised no URL sub-NOTE at all on the same
tarball. So the 404 was this machine being throttled, and the field is fine.

### One further NOTE that appears intermittently

`checking for future file timestamps ... unable to verify current time` shows up
when the machine cannot reach a network time service, and disappears when it can
— it fired on an earlier run of this same code and not on the 0.1.0 run. Purely
environmental; nothing in the package carries a future timestamp. Worth knowing
so its presence or absence between runs is not mistaken for a real change.

### Two NOTEs that earlier drafts of this file listed, now resolved

Both were pandoc artifacts, not package defects, and both are gone now that
pandoc is on `PATH`:

* *"Package has a VignetteBuilder field but no prebuilt vignette index"* — the
  vignette now builds (`* creating vignettes ... OK`), so there is a real index.
* *"Files 'README.md' or 'NEWS.md' cannot be checked without 'pandoc'"* —
  `* checking top-level files ... OK`.

Worth recording because the earlier absence of pandoc made the package look as
though it had a vignette problem when it did not.

## URL and DOI check

`urlchecker::url_check()`: **"All URLs are correct!"** — 0 flagged, no dead links
and no redirects to update. All URLs are `https`.

Separately checked every DOI by resolution, since `urlchecker` does not treat
`<doi:...>` entries in `DESCRIPTION` as URLs:

* `doi:10.1186/s41937-026-00157-w` (Kronenberg 2026) — resolves via `doi.org` to
  `link.springer.com`, 200.
* `doi:10.1002/jae.3104` (Eckert et al. 2025) — `doi.org` redirects correctly to
  `onlinelibrary.wiley.com`, which returns **403 to any non-browser client**,
  including one sending a full desktop browser user agent. This is Wiley's bot
  protection, not a bad DOI: `api.crossref.org` returns 200 for it, so it is
  registered and resolvable. `R CMD check --as-cran` raised no DOI NOTE. If a
  reviewer's link checker flags it, that is the explanation — the DOI is correct
  and should not be changed or removed.

## CRAN policy points checked explicitly

* **Two cores maximum.** `fcast_dfm()` and `run_fcast()` both default
  `ncores = NULL`, which takes the sequential `%do%` branch, and no example,
  test or vignette sets it — so nothing CRAN runs starts a cluster. Note for
  reviewers: `dfm_workers()` calls `parallel::detectCores(logical = FALSE)`, but
  only to size a *recommendation* it returns to the user; it never spawns
  workers.
* **No writing outside the session temp directory.** Model fitting returns its
  result and writes nothing unless given an explicit `output_dir`; no path is
  ever inferred from `getwd()`. Every example and test that touches disk uses
  `tempfile()`/`tempdir()`, and a check of the `.Rcheck` tree afterwards confirms
  no example created a directory outside it. `wai_sample_config()` used to call
  `dir.create()` on the output tree it merely *describes*, with a relative default
  `output_root`; it now creates nothing, and the directories are made at the point
  of writing instead.
* **Size.** `inst/extdata` is 335 KB (two CSV vintage files), `data/` is 292 KB
  (two `.rda`). Well inside the 5 MB data/documentation limit and the 10 MB
  tarball preference. An earlier 3.3 MB `.xlsx` vintage database that would have
  breached the data preference is no longer shipped.
* **Citations.** In `authors (year) <doi:...>` form in `DESCRIPTION`, no space
  after the protocol.
* **Licence.** MIT, on CRAN's approved list, with `LICENSE` naming the year
  (2026) and the copyright holder, who also carries the `cph` role in
  `Authors@R`.
* **Runtimes.** win-builder measured `checking tests ... [404s]`, examples 25s,
  vignette rebuild 21s — about 8.5 minutes of check time in total, uncomfortably
  close to CRAN's ~10 minute preference. Traced to a single cause rather than
  guessed at: one test called `run_wai_adj()` with its default 5000-draw chain
  while asserting something about a *warning*, and that one call was 143s of the
  suite's 179s locally. It now runs a 10-draw chain — possible only because
  `run_wai_adj()` stopped hard-coding the chain length — and the local suite is
  **42s, down from 179s**. Expect `checking tests` on win-builder to fall to
  roughly 100s.
* **`skip_on_cran()` is deliberately still not used anywhere.** It was the
  obvious lever for the runtime above, and it would have hidden the problem
  instead of fixing it: the expensive test was expensive by accident, not by
  necessity. Every test therefore still runs on CRAN.

## Points a reviewer may still raise

* **No `\dontrun{}` anywhere.** Previously two topics used it, `run_wai_adj()`
  and `extract_wai_data()`, because `run_wai_adj()` hard-coded a 5000-draw MCMC
  chain that could not be checked inside CRAN's limits. It now takes
  `length_sample`/`burn_in`/`thinning` — defaulting to exactly the chain it always
  ran, so results are unchanged — and both examples run a short chain under
  `\donttest{}`. Every example in the package is therefore executed by
  `R CMD check`.
* **18 non-default `Imports`** — below the 20-package NOTE threshold but close.
  Moving the rendering tail (`kableExtra`, `knitr`, `ggpubr`) to `Suggests` is the
  headroom play if it ever trips.
* **Test suite runtime** is dominated by short seeded MCMC chains. If CRAN
  timings become tight, those smoke tests are the ones to gate behind
  `skip_on_cran()`.

## Downstream dependencies

None — first release, nothing depends on this package. `revdepcheck` applies from
the second release onward.
