# Tests

Two suites live here.

The **default suite** is what `devtools::test()` and `R CMD check` run: 1376
assertions in about 3 minutes (measured 2026-10-04, `x86_64-pc-linux-gnu`). It
uses only synthetic fixtures or the package's own shipped data, and fits every
model at short chain lengths — it tests the code, not the sampler's mixing.

The **extended suite** is everything that cannot sit in those 3 minutes: Monte
Carlo recovery against a known data-generating process, prior and posterior
recovery, computational scaling, and the behaviour-preservation snapshot. It is
skipped unless an environment variable is set, and it is deliberately **not**
run in CI (see [Why these are not CI tests](#why-these-are-not-ci-tests)).

## Running the default suite

```r
devtools::test()                                        # all of it
testthat::test_file("tests/testthat/test-ind_dfm.R")    # one file
```

Test files mirror `R/` one-for-one (`test-<name>.R` for `R/<name>.R`), except
`samplers.R`, `samplers_fcast.R`, `globals.R` and `mfbdfm-package.R`, which have
no exported or separately testable content. The three `test-extended-*.R` files
are the other exception: they are grouped by what they verify rather than by
source file, because each one wraps a `dev/` script or a standard that cuts
across several.

Graphics-touching tests wrap in `grDevices::pdf(NULL)`; see `test-ind_dfm.R`.

## Running the extended suite

```sh
MFBDFM_EXTENDED_TESTS=true Rscript -e 'devtools::test()'
```

or, from an R session:

```r
Sys.setenv(MFBDFM_EXTENDED_TESTS = "true")
devtools::test(filter = "extended")
```

Any value other than the exact string `true` leaves them skipped. Every
extended block begins with `skip_if_not_extended()`
(`tests/testthat/helper-extended.R`), which is also where the `dev/`-script
locator and the measurement reporter live.

**It must be run from a source checkout.** `^dev$` is in `.Rbuildignore`, so
`dev/baseline.R` and `dev/mc_recovery.R` are not in the built tarball; the tests
that wrap them locate `dev/` relative to the package root and skip with a reason
when it is absent. They never fail for a missing prerequisite.

The blocks print their measurements to stderr, prefixed `[extended]`. Those
numbers are the point of several of them — the assertion is a loose documented
bound, and the measurement is what a human reads.

## What is in the extended suite

Runtimes are what the blocks reported on a 2026-10-04 run (R 4.6.1,
`x86_64-pc-linux-gnu`, OpenBLAS, 4-core CI runner).

| Test | Standards | Runtime | Needs |
| --- | --- | --- | --- |
| `test-extended-recovery.R` — factor-space recovery, 4 seeds | G5.6, G5.6a, G5.6b | 277 s | `dev/mc_recovery.R` |
| `test-extended-recovery.R` — misspecified-`q` negative control | G5.6 | 209 s | `dev/mc_recovery.R` |
| `test-extended-recovery.R` — two-factor posterior recovery | BS7.2 | 164 s | `dev/mc_recovery.R` |
| `test-extended-recovery.R` — recovery against sample length | G5.7 | 636 s | `dev/mc_recovery.R` |
| `test-extended-bayes.R` — loading-prior sweep | BS7.0 | 11 s | — |
| `test-extended-bayes.R` — prior recovery when the prior dominates | BS7.1 | 8 s | — |
| `test-extended-bayes.R` — nowcast equivariance in the target's units | BS7.4 | 5 s | — |
| `test-extended-bayes.R` — time scaling in series count and sample length | BS7.3 | 59 s | — |
| `test-extended-baseline.R` — behaviour-preservation snapshot | — | 6 s | `dev/baseline.R`, `dev/baseline.rds`, matching platform |

So budget **about 23 minutes** for the whole extended suite; the
replication-based blocks are 95% of it, at roughly 70 s per model fit. Peak
memory stays well under 1 GB — the largest fit is `n = 128` monthly series over
180 months in the BS7.3 sweep. `dfm_memory()` is the tool for bounding a real
run.

Nothing here needs a downloaded asset or a network connection (rOpenSci G5.11
and G5.11a therefore do not apply), and nothing writes outside `tempdir()`.

### Artefacts that need manual inspection

- **`test-extended-baseline.R`** asserts only the verdict. When it fails, the
  per-component report (`max abs diff`, `max rel`, per fit) is printed with the
  failure; read it, because it localises the change to a model and a component
  rather than merely saying something moved. `source("dev/baseline.R"); baseline_check()`
  reproduces the same report interactively.
- **The `[extended]` measurements** are not asserted beyond their documented
  bounds: the recovery values, the log-log timing slopes and the shrinkage
  sequence are worth comparing against the numbers recorded below and in the
  test comments. A value inside the bound but far from its recorded measurement
  is a signal the bound is too loose, not a pass to be happy about.
- **`dev/mc_results.rds`** holds the full 80-replication run reported on #52.
  The extended test uses a handful of seeds from it; `mc_report()` summarises
  the stored run against the published values without recomputing it.

## Why these are not CI tests

Three separate reasons, which is why there is no workflow and no scheduled job:

1. **MCMC output is not bit-identical across platforms.** A different BLAS sums
   in a different order, shifting the last bit, and an MCMC chain amplifies that
   to O(1) within a few iterations. `dev/baseline.rds` records the platform it
   was written on, and the test that wraps it **skips** when the current
   platform differs rather than reporting a meaningless mismatch. A committed
   golden-value test would fail across the CI matrix for reasons unrelated to
   the code.
2. **The quantities are Monte Carlo means with standard errors.** The recovery
   cells have a replication-to-replication standard deviation of 0.05–0.14 and,
   on the single-factor cell, roughly one replication in forty that is
   degenerate (trace R² of 0.000 in the stored run of 40). A pass/fail threshold
   tight enough to be informative would be flaky; the blocks therefore assert on
   the median of several seeds against a bound derived from the stored
   distribution.
3. **Runtime.** About 23 minutes, against a 30-minute CI timeout shared with
   `R CMD check` on four platforms.

## Measured values the bounds come from

Recorded on `x86_64-pc-linux-gnu`, R 4.6.1, OpenBLAS, 2026-10-04.

**Recovery** (trace R², Eckert et al. 2025 Eq. 17), against the stored run in
`dev/mc_results.rds`:

| cell | paper | stored median (n reps) | measured here (median) |
| --- | --- | --- | --- |
| `q_f = 1, q̂ = 1` | 0.68 | 0.756 (40) | 0.724 — 0.590, 0.771, 0.677, 0.792 |
| `q_f = 2, q̂ = 2` | 0.84 | 0.872 (20) | 0.867 — 0.853, 0.880 |
| `q_f = 2, q̂ = 1` (misspecified) | 0.39 | 0.426 (20) | 0.411 |

The bounds asserted are: median above 0.5 and below 0.95 for the correctly
specified single-factor cell; median below 0.6 for the misspecified one, with a
gap of at least 0.15 between them (measured 0.313); and every replication above
0.6 in the two-factor cell, whose stored 20 replications never fell below 0.726.

**Sample length** (G5.7), median of three seeds per point: trace R² 0.618 at
`T = 60`, 0.730 at `T = 120`, 0.733 at `T = 240`. The gain is a trend, not
monotone, and the reason is structural rather than noise: with the cross-section
fixed at `n = 25` the factor at time `t` is estimated from 25 observations
however long the sample is, so more `T` sharpens the parameters (O(1/√T)) and
not the per-period state (O(1/n)). An earlier two-seed pass gave 0.624 / 0.743 /
0.715 — within-point spread 0.01–0.04, and an ordering two seeds got wrong at
`T = 240`, which is why the block takes a median of three. The test asserts a
positive trend in `log T` and a first-to-last gap above 0.03 (measured 0.115).

**Prior recovery** (BS7.0/BS7.1), `mfbdfm_example_data`, 40 draws after 10
burn-in: the largest non-target loading falls 0.688 → 0.135 → 0.0038 → 2.3e-05
as the loading prior's variance `B0` goes 1 → 1e-2 → 1e-4 → 1e-8, i.e. roughly
in proportion to `B0`, which is the conjugate-update rule. With a prior sample
size of `c0 = 1e8` against `t ≈ 550` observations, every non-target measurement
variance comes back at `d0 / c0` to four decimals, and `rho` at `R0 = 1e-9`
comes back within 1.1e-05 of its prior mean of 0 (against a default-prior spread
of −0.13 to 0.95 on the same data).

**Unit equivariance** (BS7.4), extended half: multiplying the target series by
100 multiplies the nowcast by 100 to within 1.3e-15 — not exactly, since the two
chains diverge in the last bits of the standardised matrix, but far closer than
the bound of `1e-3 × sd`, because each fit reproduces its own observed target to
~1e-7 of that target's standard deviation. The default-suite half is sharper
still and cheaper: `fitted(fit, scale = "original")` reproduces every input
series at that series' own observation frequency to 2e-5 of its sd, for both
model classes.

### The BS7.1 exception, written down rather than skipped

BS7.1 asks for recovery of a prior "in the absence of any additional data". A
mixed-frequency factor model cannot be fitted to no data at all, so the
well-posed version is a prior strong enough that the likelihood carries no
weight. That is what the BS7.1 block tests — and it tests it for the **tunable**
priors only.

`ind_dfm()`'s `sigma_target` and `rho_target` priors are excluded deliberately.
They *are* the model's identification: shrinking the target series'
measurement-error variance and serial correlation toward zero is what makes the
extracted factor track the target and interpretable as its growth rate (see
`?dfm_priors`, "Structural versus tunable priors", and `?ind_dfm`). Recovering
them "without data" is not a property they are meant to have independently of
the model, and `dfm_priors()` warns when they are overridden at all. The same
holds for `fcast_dfm()`'s `lambda` prior, whose diffuseness the post-hoc
rotation depends on.

**Time scaling** (BS7.3), `ind_dfm()`, 200 draws after 20 burn-in:

| sweep | sizes | seconds | log-log slope |
| --- | --- | --- | --- |
| series count, `T_q = 60` | 8, 32, 128 | 6.5, 8.8, 18.5 | 0.38 |
| sample length, `n = 8` | 40, 160, 640 quarters | 6.4, 7.8, 11.2 | 0.20 |

Both are **sub-linear** over a 16-fold range, which is the finding worth
recording: the dominant term is per-iteration and nearly size-independent — 29
ms per iteration at `n = 8`, `T_q = 60`, against about 0.5 s of fixed cost per
fit. Chain length, not panel size, is what a user's runtime is made of.

A first version of this block measured nothing at all and passed anyway: at
`n = 4, 8, 16` with 25 iterations the three fits came out at 0.7, 0.8 and 0.8 s
— all fixed overhead — for a slope of 0.12 that was noise with a plausible
sign. The block therefore now asserts first that the largest size costs at least
1.4× the smallest (measured 2.85 and 1.75), and only then that the slope is
positive and no steeper than the input size itself.

`fcast_dfm()` is not used for this measurement because it parallelises its
rotation, which would measure the machine's core count instead. Memory scaling
is covered separately and non-experimentally by `dfm_memory()` and
`dfm_workers()`.
