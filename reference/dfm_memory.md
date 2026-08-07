# Estimate the peak memory of a model fit, and size a parallel run from it

`dfm_memory()` predicts the peak heap one
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit will occupy, from the dimensions of the data and the length of the
chain. `dfm_workers()` turns that into the number of parallel workers a
machine can actually carry.

## Usage

``` r
dfm_memory(
  flows = NULL,
  stocks = NULL,
  n = NULL,
  t = NULL,
  s = NULL,
  q = 2,
  p = 1,
  length_sample = 1000,
  extend = 0.5,
  frequency = NULL
)

dfm_workers(..., available_mb = NULL, safety = 0.7, max_workers = NULL)
```

## Arguments

- flows, stocks:

  Named lists of `ts` objects, or an
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  object as `flows`. Supply these to have the dimensions derived from
  the data. If `NULL`, give `n`, `t` and `s` directly.

- n:

  Integer, number of series. Derived from the data when supplied.

- t:

  Integer, number of high-frequency periods **before** `extend`. Derived
  from the data when supplied.

- s:

  Integer, `2 * (k - 1)` where `k` is the ratio of highest to lowest
  frequency. Derived from the data when supplied.

- q:

  Integer, number of factors.

- p:

  Integer, number of lags in the factor VAR.

- length_sample:

  Integer, number of posterior draws **kept** (`thinning` does not
  enter: it changes how long the chain runs, not how much is stored).

- extend:

  Numeric, the `extend` argument the fit will be given, in years.
  Lengthens the sample the sampler sees and so the memory it needs.

- frequency:

  Integer, observations per year of the highest-frequency series, used
  with `extend`. Derived from the data when supplied.

- ...:

  Passed to `dfm_memory()`.

- available_mb:

  Numeric, memory to plan against, in MB. Defaults to the machine's
  currently **free** memory, not its total – whatever else is running is
  not available to the sweep.

- safety:

  Numeric in (0, 1\], the fraction of `available_mb` to commit. The
  default 0.7 leaves room for the estimate's ~10% error, for the
  allocator's inability to reuse freed blocks immediately, and for the
  process that launched the workers.

- max_workers:

  Integer, an upper bound (defaults to the core count).

## Value

`dfm_memory()`: estimated peak memory for one fit, in MB (numeric,
length 1). `dfm_workers()`: the number of workers (integer, length 1, at
least 1), with the estimate and the budget it used attached as
attributes.

## Details

Vintage sweeps are parallelised over dates, and the binding constraint
is memory rather than cores: a machine with 16 cores runs out of RAM
long before it runs out of cores, and the failure mode is an opaque
`CHOLMOD error 'out of memory'` from deep inside the sparse solver,
hours into a run. This exists so the worker count can be derived rather
than guessed.

## The model

Peak memory is fitted as

\$\$a + b \cdot G + c \cdot D\$\$

where \\G\\ is the footprint of the observation matrix `Gmat`
(`q(t-1)n(s+2)` nonzeros at 12 bytes each) and \\D\\ is the footprint of
the retained draws (`length_sample` rows of
`nq + pq^2 + 2n + nt + t + s` doubles). The fitted coefficients say the
fit holds about **6.3 live copies of `Gmat`** and **1.65 copies of the
draw matrix**, over a fixed **270 MB** of R and package overhead.

**Memory is linear in `q`, not quadratic.** The natural guess is that
the sparse Cholesky of the `q(t+s)` square factor precision matrix
dominates, which would scale with `q^2`. Measured, it does not: adding
that term to the regression does not improve it, because the `Gmat`
working set is an order of magnitude larger. Doubling the factor count
costs roughly one extra `Gmat` worth of working set, not four.

**The relationship is convex in `length_sample`, and the linear fit is
therefore corrected upward.** Peak memory is really a *maximum* over
phases – sampling, rotation, evaluation – and which phase binds depends
on the chain length: the sampler dominates short chains, the evaluation
dominates long ones. Measured, the peak per MB of retained draws rises
from 1.35 (30 to 120 draws) through 1.97 (120 to 240) to 3.94 (240 to
500), so no single slope fits it. Refitting the line over the whole
range does not help: it still under-predicts at 500 draws while
over-predicting the middle by 15%.

Under-prediction is the harmful direction here – it hands out too many
workers and the run dies hours in – so the linear fit is multiplied by
`MEM_SAFETY_FACTOR`, chosen as the largest measured/fitted ratio over
the calibration points. That makes the estimate an **upper bound**
across the measured range rather than a best fit, at the cost of
over-estimating short chains by around a third. Short chains are cheap;
the tool exists for the long ones.

This was found the hard way. Before the correction the model predicted
1128 MB at 500 draws against **1538 MB measured** – 27% low. That is
very likely why the 2019-2020 sweep lost two dates to `R_Calloc`
out-of-memory: five workers were allocated against a budget computed
from the under-estimate. I had attributed those failures to contention
with a concurrent `R CMD check`, which was at best only part of it.

## Calibration

Fitted to seven fits measured one per fresh R process (the GC high-water
mark is per process, so several in one session would report only their
maximum) at `n = 53`, `t = 1559`, `s = 22`: `q = 1..4` at
`length_sample = 30`, and `q = 2` at
`length_sample = 30, 120, 240, 500`. The line is fitted on the first six
and then scaled by `MEM_SAFETY_FACTOR` so that it covers the seventh,
which is the setting the sweeps actually use.

Validated out of sample against a fit on a **different** dataset and a
different version of the code (`n = 43`, `t = 1464`, `q = 2`,
`length_sample = 200`): 744 MB measured, covered.

**Known gap: there is no measurement at both high `q` and long chains.**
The `q = 1..4` points are all at 30 draws and the long-chain points are
all at `q = 2`, so the interaction is assumed rather than measured, and
`q = 4` with 500 draws – what `analysis/fcast/6b_refit_factor_counts.R`
runs – is an extrapolation in both arguments.

The constants are specific to this package's samplers; they were
measured on x86_64 Windows and will drift if the samplers' allocation
pattern changes. `dev/calibrate-memory.R` regenerates them.

Calibrated on
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
is a different sampler with no post-hoc rotation and no packed draw
matrix, and has **not** been measured here.

## See also

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)

Other model fitting functions:
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)

## Examples

``` r
# from dimensions
dfm_memory(n = 53, t = 1535, s = 22, q = 2, length_sample = 500)
#> [1] 1545.73

# the whole point: how many workers fit in 24 GB
dfm_workers(n = 53, t = 1535, s = 22, q = 4, length_sample = 500,
            available_mb = 24 * 1024)
#> [1] 4
#> attr(,"per_fit_mb")
#> [1] 1959.264
#> attr(,"available_mb")
#> [1] 24576
#> attr(,"budget_mb")
#> [1] 17203.2

# from the data itself
data(data_ch_dataset_test)
dfm_memory(flows = data_ch_dataset_test$flows,
           stocks = data_ch_dataset_test$stocks,
           q = 2, length_sample = 1000)
#> [1] 2280.26
```
