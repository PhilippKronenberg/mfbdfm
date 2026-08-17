# cran-comments

**Status: pre-submission draft, not yet submitted.** Written while the version is
still `0.0.0.9000`; re-check the numbers below after the release bump (issue #25),
and run the remote checks in the last section before this file describes a real
submission.

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

Not yet run — required before submission:

* win-builder, R-devel (`devtools::check_win_devel()`)
* R-hub (`rhub::check_for_cran()`) — the `rhub` package is not installed here
* macOS builder (`devtools::check_mac_release()`)

**There is no R-devel result yet. That is the remaining gap**, and it is the one
CRAN cares about most; the matrix above is all R-release or oldrel.

## R CMD check results

`R CMD check --as-cran` locally, with the vignette and the PDF manual both built:
0 errors, 0 warnings, 3 notes. Test suite inside the check: `FAIL 0 | WARN 0 |
SKIP 0 | PASS 668`.

### NOTE 1 — CRAN incoming feasibility

```text
Maintainer: 'Philipp Kronenberg <philippkronenberg@gmx.ch>'

New submission

Version contains large components (0.0.0.9000)
```

* *New submission* — correct, this is the first release. Unavoidable and
  explicitly acceptable.
* *Version contains large components* — an artifact of checking a development
  version. The release bump to `0.1.0` removes it; verify then rather than
  assuming.

### NOTE 2 — future file timestamps

```text
unable to verify current time
```

Environmental, not a package property: `R CMD check` verifies the clock against a
network time service and this machine could not reach it. Nothing in the package
carries a future timestamp. It does not appear on CRAN's machines.

### NOTE 3 — HTML version of the manual

```text
Skipping checking math rendering: package 'V8' unavailable
```

Environmental. `--as-cran` uses the optional `V8` package to verify KaTeX math
rendering in the HTML manual; `V8` is not installed here, so that sub-check is
*skipped*, not failed. CRAN's machines have it. The PDF manual builds cleanly
(446 KB) via MiKTeX 25.3.

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
* **Runtimes.** Examples 22s; examples with `--run-donttest` 39s; test suite
  ~2 min. All inside CRAN's limits.

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
