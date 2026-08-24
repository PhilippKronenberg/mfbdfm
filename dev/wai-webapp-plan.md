# WAI web app: architecture study and implementation plan

Status: **plan, not yet implemented**. Tracked in issue #70, branch
`claude/dfm-website-pipeline-i1uihw`.

Goal: a public, continuously-updated web page for the Weekly Activity Index,
modelled on the ISMI dashboard
(<https://adamshap.github.io/ismi-webapp/ism_webapp.html>), fed by an automated
pipeline that re-runs `mfbdfm` on a schedule and publishes the refreshed
results.

---

## 1. What the reference actually is

Studied from the source in `adamshap/ismi-webapp` (the rendered page itself is
unreachable from this environment — `adamshap.github.io` is blocked by the
egress proxy — so everything below comes from the repository's own files).

**The whole repository is five files:**

```
README.md          two lines
ism_webapp.html    1,901 lines, 71 KB   <- the entire application
ism_data.csv       690 rows x ~160 cols <- the entire data layer
ismi_data.xlsx     the same data for humans
preview.png        social-card image
```

No `.R`, no `.Rmd`, no `.qmd`, no `package.json`, no `.github/workflows`, no
build step, no server. 68 commits on `main`, which are essentially data updates.

### 1.1 Technology inventory

| Layer | What it uses |
| --- | --- |
| Page | Hand-written HTML5, ~700 lines of inline CSS, ~700 lines of vanilla JS. No framework. |
| Charts | Chart.js `4.4.0` + `chartjs-adapter-date-fns@3.0.0`, both from the jsDelivr CDN |
| Data load | `fetch('ism_data.csv?v=YYYY-MM-DD')` at page load, parsed by a hand-rolled `split(',')` loop |
| Hosting | GitHub Pages, served from the repository root |
| Analytics | GoatCounter (`gc.zgo.at/count.js`) — cookie-free, so no consent banner |
| Social | Open Graph + Twitter card meta, `preview.png`, inline SVG data-URI favicon |
| Caching | `Cache-Control: no-cache` meta plus a date-based query-string cache-buster on the CSV |

**Explicitly not used:** R Markdown, Quarto, flexdashboard, Shiny, plotly,
Observable, npm, any bundler, any backend. Hosting cost is zero and there is
nothing to keep running.

### 1.2 The one design decision that matters

`ism_data.csv` is a **fully pre-computed grid over every combination the UI can
select**: 6 category series x {positive, negative, combined} x 3 AR settings x
3 `k` settings, ~160 columns wide, monthly since 1969.

Every control on the page is therefore **column selection, not computation**.
The browser never models anything; it slices a wide table and redraws. That is
what lets a serious econometric product ship as one static file with no server,
and it is the property to copy.

### 1.3 UI inventory (what we would be matching)

Sidebar control panel (collapsible on mobile) with: series select, two
parameter selects (`k`, `ar`), a dual-handle date-range slider with preset
chips, a multi-select "compare series" dropdown, an overlay checkbox
(PCE inflation), and a reset button. Main pane: one time-series chart (mixed
bar + line datasets), three headline stat boxes (current index / positive /
negative), download-current-view and download-full-data buttons (client-side
`Blob`, no server), a share-chart button, and a collapsible methodology
description linking the working paper.

---

## 2. How our situation differs

Five differences drive every decision below.

1. **`gh-pages` in `mfbdfm` is already taken by pkgdown**
   (`philippkronenberg.github.io/mfbdfm/`, deployed by
   `.github/workflows/pkgdown.yaml`). **Decision: the web app gets its own
   repository.** This also keeps a high-churn data-commit history out of the
   package's history, keeps the site's deploy cadence independent of package
   releases, and keeps `R CMD check`'s file surface untouched.

2. **Weekly, not monthly.** ~1,880 observations per series since 1990 at 48
   periods/year, on the 7th/14th/21st/28th convention that `dec2week()` encodes.
   Still trivially small for a CSV — well under 1 MB.

3. **We have uncertainty bands, the reference does not.** `ind_dfm()` gives
   `factor_var`, and `extract_wai_data()` already forms `factor ± 1.96·sd`.
   Chart.js draws bands with a paired dataset and `fill: '-1'`.

4. **We already have three finished views.** `extract_wai_data()` returns
   `tab_gr_qoq` (annualised QoQ growth with bounds), `tab_gr_lv` (level index,
   normalised to the last quarter of 2019 = 100) and `tab_wai_yoy` (YoY growth).
   Plus published GDP actuals from `get_real_time_gdp_vintages()` and an AR(1)
   benchmark from `run_ar()`. So the "grid of pre-computed variants" is small
   and already produced — no new modelling is needed for v1.

5. **The blocker is data licensing, not compute.** This is the crux.
   `analysis/1_data_prep_dataset.R` reads `data/dataset/`, which is private,
   licensed, ~4.4 MB and gitignored, assembled from Datastream, a legacy
   postgres bundle, FSO, KTZH, ASTRA, Destatis, Swissgrid, Zurich Airport and
   Google Trends/mobility. **A GitHub-hosted runner cannot refresh it.**
   Compute is emphatically *not* the constraint: `run_wai_adj()` at its default
   5,000 draws runs in ~143 s, which would fit a hosted runner many times over.

   Corollary, and the legal crux of the whole project: what we publish is
   **derived aggregate model output** (a single index and its bands), not the
   licensed source series. That is publishable; the inputs are not. The
   pipeline must never push anything from `data/dataset/`.

---

## 3. Target architecture

Three stages, split exactly at the licensing boundary:

```
 PRIVATE HOST (has data/dataset/)          |   PUBLIC (GitHub)
 -----------------------------------------|--------------------------------
 (1) refresh raw sources                   |
     analysis/1_data_prep_dataset.R        |
            |                              |
            v  data_ch_dataset.Rda         |
 (2) run the model                         |
     run_wai_adj() at current vintage      |
            |                              |
            v  fit object                  |
 (3) export_wai_web(fit) ------------------> wai-webapp repo
        wai_data.csv                       |   git push
        wai_meta.json                      |        |
                                           |        v
                                           |   GitHub Pages serves
                                           |   index.html + wai_data.csv
```

The front end knows nothing about R; the R code knows nothing about the front
end. The CSV contract in §4 is the entire interface between them.

### 3.1 Where stages 1–2 run — the one decision that needs the user

| Option | How | Trade-off |
| --- | --- | --- |
| **(a) Local scheduled task** | Windows Task Scheduler / cron runs one `Rscript`, which pushes with a deploy key | Fewest moving parts; works today; failures are invisible unless we add a notification |
| **(b) Self-hosted GH Actions runner** | Runner daemon on the same machine; `schedule:` cron in a workflow | Runs, logs and failure notifications all visible in the Actions UI; needs a daemon kept alive |
| **(c) Hosted runner + stored dataset** | Keep the *prepared* dataset in a private repo, run everything on GitHub | Fully cloud-native, but only viable if the source licences permit storing the data even privately — **must be checked before considering** |

**Recommendation: start with (a), migrate to (b)** once the pipeline has run
unattended a few times. (a) and (b) differ only in the wrapper around the same
script, so the migration is cheap and nothing in §4–§6 depends on the choice.

---

## 4. The data contract

The most important artifact in the project — get this right and the two halves
can be built independently, in either order.

### `wai_data.csv` — one row per week, wide

| Column | Meaning |
| --- | --- |
| `date` | ISO date, the 7/14/21/28 weekly convention from `dec2week()` |
| `wai_qoq`, `wai_qoq_lo`, `wai_qoq_hi` | Annualised QoQ growth and 95% band |
| `wai_yoy`, `wai_yoy_lo`, `wai_yoy_hi` | Year-over-year growth and band |
| `wai_index`, `wai_index_lo`, `wai_index_hi` | Level index, 2019Q4 = 100 |
| `gdp_qoq` | Published GDP growth, on the quarter's last week; empty elsewhere |
| `ar_qoq` | AR(1) benchmark nowcast (optional; empty until phase 5) |

Rules: ISO dates, `.` decimal separator, empty string for missing (never `NA`
or `NaN` — the JS parser must not have to know R's spelling), fixed column
order, rows sorted ascending, no thousands separators, LF line endings.

### `wai_meta.json` — everything the page needs to describe itself

`vintage_date`, `run_timestamp` (UTC), `gdp_vintage`, `last_obs_date`,
`n_obs`, `current_nowcast`, `current_quarter`, `mfbdfm_version`, `git_sha`,
`length_sample`, `burn_in`. This is what powers the "as of ..." line and the
headline stat boxes without the front end recomputing anything.

### `wai_vintages.csv` — optional, phase 5

The real-time revision triangle (one column per publication date), which
`analysis/real_time_backcast.R` already knows how to produce. A "how did this
week's estimate evolve as data arrived?" chart is something the ISMI app does
not have and we have the machinery for — a genuine differentiator, deliberately
deferred out of v1.

---

## 5. Step-by-step plan

### Phase 0 — decisions and scaffolding

- [ ] Confirm the split-pipeline architecture (§3) and pick the runner option (§3.1).
- [ ] Confirm the repository name. Proposed: **`PhilippKronenberg/wai-webapp`**,
      published at `https://philippkronenberg.github.io/wai-webapp/`.
- [ ] Confirm publishing derived output is compatible with the source data
      licences (§2.5). Blocking for go-live, not for building.
- [ ] Decide the public update cadence (weekly, tied to the data refresh) and
      what the page says when a run is stale.
- [ ] Create the repository, `main` branch, MIT licence, GitHub Pages enabled
      on `main` / root.

### Phase 1 — the exporter, in `mfbdfm`

Lives in this package because it is model output, and it is what makes the whole
thing reproducible by anyone with the data.

- [ ] New `R/web-export.R` with exported `export_wai_web(fit, dir, ...)`,
      writing `wai_data.csv` + `wai_meta.json` per §4. No side effects unless
      `dir` is given, matching the `run_ar()`/`run_wai_adj()` convention.
- [ ] Build it on `extract_wai_data()` rather than duplicating the reshaping.
- [ ] **Fix `extract_wai_data()`'s hard-coded horizon first.** It builds
      `date_vec <- seq(1990, 2025 + 47/48, 1/48)` and merges the level bounds
      with `all = FALSE`, so from 2026 onward it silently drops the newest
      observations — exactly the weeks a live dashboard exists to show. This is
      a latent bug today and a fatal one for a scheduled pipeline. Derive the
      range from the fit instead. (Worth its own issue if the fix is not
      strictly behaviour-preserving.)
- [ ] Roxygen docs with a runnable `\donttest{}` example (no `\dontrun{}` —
      the package has none and keeps none).
- [ ] `tests/testthat/test-web-export.R`, per the one-test-file-per-source-file
      convention: column names, column order, row ordering, empty-string
      encoding of missing values, JSON keys present, round-trip re-read.
- [ ] `devtools::document()`, add the export to `_pkgdown.yml`'s reference index,
      `NEWS.md` entry, run `pkgdown::check_pkgdown()`.
- [ ] `R CMD check` clean before commit, and `dev/baseline.R::baseline_check()`
      to confirm nothing in the samplers moved.

### Phase 2 — the static site, in the new repository

Buildable and reviewable against a committed sample CSV before any automation
exists.

- [ ] `index.html` — one self-contained file: inline CSS, inline JS, Chart.js +
      the date adapter from a **version-pinned** CDN URL.
- [ ] Load `wai_data.csv?v=<date>` with `fetch()`; parse with a small robust
      CSV reader; render an explicit error banner on failure (the reference
      does this and it is worth copying).
- [ ] Chart: WAI line + 95% band (paired dataset with `fill: '-1'`), published
      GDP as points/bars on quarter ends, recession/crisis shading optional.
- [ ] Controls: view toggle (QoQ / YoY / level index), date-range slider with
      preset chips (last 2y / 5y / since 2015 / since 2020 / full), a
      show-bands checkbox, a show-GDP checkbox, reset.
- [ ] Stat boxes from `wai_meta.json`: latest WAI, current-quarter nowcast,
      last observation date, "data as of" line.
- [ ] Download buttons: current view and full CSV, client-side `Blob`.
- [ ] Methodology section linking Kronenberg (2026)
      (<https://doi.org/10.1186/s41937-026-00157-w>), the `mfbdfm` pkgdown site
      and the GitHub repository.
- [ ] Responsive layout, mobile control toggle, keyboard-accessible controls,
      `prefers-color-scheme` handled or a deliberate single-theme choice.
- [ ] `preview.png`, OG/Twitter meta, favicon, `<title>`, description.
- [ ] `README.md` explaining the data contract and how the CSV gets there.
- [ ] Optional: GoatCounter or Plausible — cookie-free, so no consent banner.

### Phase 3 — automation

- [ ] `analysis/update_wai_web.R`: one idempotent script — refresh data, fit at
      the current vintage, `export_wai_web()`, write into a checkout of the
      webapp repo, commit only if the content changed, push.
- [ ] Guard rails: fail loudly and **publish nothing** if the fit errors, if the
      newest observation is older than the last published one, or if any
      contract check in §4 fails.
- [ ] A deploy key (or fine-grained PAT) scoped to the webapp repo only.
- [ ] Schedule it per the chosen runner option; log each run to a file.
- [ ] Failure notification — the pipeline being silently dead for a month is
      the realistic failure mode, not a crash.
- [ ] In the webapp repo, a small CI workflow that validates `wai_data.csv`
      against the contract on every push, so a malformed publish is caught by
      GitHub rather than by a visitor.

### Phase 4 — launch

- [ ] End-to-end dry run against real data, publishing to an unlisted path first.
- [ ] Cross-browser and mobile check; Lighthouse pass.
- [ ] Verify the "stale data" state renders correctly (kill a run on purpose).
- [ ] Link the site from the `mfbdfm` README, pkgdown navbar and DESCRIPTION `URL`.
- [ ] Announce; monitor the first few scheduled runs.

### Phase 5 — extensions, explicitly out of v1

- [ ] Real-time revision triangle (`wai_vintages.csv`) and an evolution chart.
- [ ] AR(1) benchmark overlay and a live nowcast-error table.
- [ ] Factor-loading / contribution decomposition view.
- [ ] Machine-readable API surface (a stable JSON endpoint others can consume).
- [ ] English/German toggle.

---

## 6. Risks and open questions

| # | Risk | Mitigation |
| --- | --- | --- |
| 1 | Source licences forbid publishing even derived output | Settle in phase 0, before any build effort |
| 2 | Scheduled run dies silently | Explicit failure notification + a visible "data as of" line that ages badly on purpose |
| 3 | A model change silently shifts the published series | `baseline_check()` in the pipeline; record `mfbdfm_version` + `git_sha` in the metadata |
| 4 | `extract_wai_data()`'s 2025 horizon truncates new weeks | Phase 1 fixes it before anything depends on it |
| 5 | CDN outage takes the charts down | Pinned versions; vendoring Chart.js locally is a one-line change if it matters |
| 6 | Data-commit churn bloats the webapp repo | Only ~1,900 rows x 12 columns per commit; squash history if it ever matters |
| 7 | The private host is a single point of failure | Documented manual runbook so a human can publish an update by hand |

## 7. Conventions this project must not break

- `mfbdfm` stays a clean R package: `R CMD check` before every commit touching
  package code, `_pkgdown.yml` kept in sync with `NAMESPACE` (including
  `S3method()` lines), no `\dontrun{}`, one test file per source file.
- No side effects by default — `export_wai_web()` writes only when told where.
- Nothing under `data/dataset/` is ever committed or pushed anywhere.
