# `analysis/fcast/` — multi-factor (Eckert et al. 2025) workflow

The `fcast_dfm()` counterpart of the WAI scripts in `analysis/` and
`analysis/5_plots/`. Run everything from the repository root.

## Scripts, in order

| script | does | writes |
| --- | --- | --- |
| `_setup.R` | shared prelude (sourced by the others, not run directly) | — |
| `1_backcast_fcast.R` | fits `fcast_dfm()` over evaluation dates × factor counts | `fits/fcast/<q>/fit_<date>.Rda` |
| `2_evaluation_fcast.R` | turns fits into the scored evaluation panel | `analysis/outputs/fcast/<id>/results/` |
| `3_plots_fcast.R` | figures from that panel | `analysis/outputs/fcast/<id>/figures/` |
| `4_reproduce_paper_figures.R` | replicates the published figures from the paper's own inputs | `analysis/outputs/fcast/replication/figures/` |
| `5_error_tables_fcast.R` | RMSFE/MAE/log-score tables by subsample + Diebold-Mariano | `analysis/outputs/fcast/<id>/tables/` |
| `6_factor_plot_fcast.R` | factors from the q = 1..4 runs, aligned and overlaid | `analysis/outputs/fcast/replication/figures/` |

`1_backcast_fcast.R` has a `quick_check` switch: `TRUE` runs a short chain in
minutes to prove the wiring, `FALSE` is the real vintage sweep and is an
overnight job.

Scripts 1–3 are the pipeline for *new* estimates. Script 4 is independent of
them: it reads the paper's stored results and needs no fitting.

## `reference/` — the paper's own material (local only, **gitignored**)

Inputs for replication, not produced by anything here and **not committed** —
7.7 MB of stored results from the Eckert et al. (2025) replication package. A
clean clone will not have them, so `4_reproduce_paper_figures.R` will stop with
"No reference panels at ...". Obtain them from the paper's replication material
and place them as described below; nothing else in the workflow depends on them.

- `reference/rda/` — the paper's stored results. `results_backcast.Rda` and
  `results_backcast_var.Rda` are the main run (factor count chosen by
  information criterion, see `tab_IC_full.Rda`); `results_evaluation.Rda` holds
  its evaluation tables. The `*_<n>f.Rda` files are a **different** exercise —
  the multi-factor model against BMDFM/GRSDFM at a fixed factor count — and
  reproduce different figures. `data_ch.Rda` is the data vintage the paper
  evaluated against.
- `reference/figures/` — the published PDFs, kept so each replicated figure can
  be held against its original.

Note the `BN1f` in the published file names refers to an information criterion,
**not** to the number of factors in the panel. Reading it as a factor count
produces figures with the right layout and wrong magnitudes.

## `archive/` — superseded code (local only, **gitignored**)

The original scripts, kept locally after being replicated but **not committed**.
Their paths (`code/Rda/...`, `L:/Groups/...`) are stale and they are not
expected to run.

Comments in the scripts here cite them by line number (e.g.
`plots_nowcast_scores.R:186` for the log-score definition). Those citations
record *where a decision came from*; the file itself will not be in a clean
clone. The decisions themselves are reproduced in this README and in the
package documentation, so nothing is lost by not having them — see
`?is_crisis_period_fcast` for the crisis windows in particular.

What has been absorbed from them:

- `3a_evaluation_full.R` → the evaluation core, the 18 named subperiods, and the
  crisis/non-crisis split, now `is_crisis_period_fcast()` in the package.
- `plots_nowcast*.R` (five files, ~90% duplicated) → collapsed into
  `3_plots_fcast.R` and `4_reproduce_paper_figures.R`.

- `error_table.R` -> `5_error_tables_fcast.R`. Uses the package's
  `dm_test_modified()` (Harvey-Leybourne-Newbold correction) rather than
  `forecast::dm.test()`, so the two papers' tables stay comparable.

- `factor_plot.R` -> `6_factor_plot_fcast.R`, with the cross-run factor
  alignment derived by correlation rather than hardcoded.

Deliberately not ported:

| script | why |
| --- | --- |
| `plots_insample.R` | superseded - the in-sample figures come from the indicator paper (Kronenberg 2026) and are produced by `analysis/5_plots/`. |
| `3b_evaluation_current_edge.R` | every `ggsave()` in it is commented out, so it produces no output. |

### A note on which fitted objects to use

`6_factor_plot_fcast.R` reads `<n>f_fit_2021.979.Rda`. Those are the fits the
published figure was built from, and with them the derived alignment reproduces
the paper's hardcoded grouping exactly - 10 of 10 groups, and 10 of 10 signs
once the one presentational negation in `group_4` is set aside.

The similarly-named `testlauf_<n>f.Rda` files are a **different run** of the
same model (1611 periods against 1558) and do **not** reproduce it: 5 of 10
groups on the same informative rows. That is not a defect in either set. It is the post-hoc rotation failing
to reach uniqueness across runs, documented under `?fcast_dfm` and #46, and it
is the reason the alignment is derived here rather than hardcoded.

## BMDFM benchmark

The Banbura-Modugno (JAE 2014) mixed-frequency DFM used as the benchmark in the
paper lives in `analysis/benchmarks/functions_package_nowcasting/` (23 files).
`_setup.R` exposes `bmdfm_functions_dir` and `source_bmdfm_functions()`;
the latter is not called on load because it needs `DBI` and `RCurl`, which
nothing else here requires.

The files are vendored rather than installed from
<https://github.com/nmecsys/nowcasting> because the published package errors for
the one-factor case: line 233 of its `nowcast.R` was changed from
`colnames(factors`dollar`dynamic_factors)` to `names(...)`. That edit is present in
this copy.

Not yet wired into `1_backcast_fcast.R`. The archived `run_bmdfm()` calls
`prepare_data(flows, stocks, inventory, model = model)`, and `model` is no
longer an argument of `prepare_data()` - it takes `target`. That call needs
updating before the benchmark will run.

## Verification status

The replication in script 4 is checked against the paper's stored output:
pooled RMSFE and mean log score match `tables_crisisvsnormal` on all 12
model × dataset × regime cells to the printed precision, with identical row
counts (240 crisis, 564 non-crisis).

The relative measures follow the paper's own code, not a convention chosen
here. Recorded in full so the definitions survive without the archived files:

| measure | lower panel | source |
| --- | --- | --- |
| RMSFE, MAE | `log(series) - log(benchmark)` — a **log ratio** | `plots_nowcast.R:179` |
| log score | `series - benchmark` — a plain **difference** | `plots_nowcast_scores.R:186` |

The distinction matters: the log score is negative, so a *ratio* of it is `NaN`
wherever series and benchmark straddle zero, which silently drops rows.

The crisis/non-crisis split is `is_crisis_period_fcast()` in the package —
**not** `is_crisis_period()`, which classifies the nowcast date rather than the
target quarter and covers two episodes rather than four. On the paper's panel
the two agree on only 124 of its 240 crisis rows.
