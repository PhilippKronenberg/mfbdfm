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
fit holds about **6.2 live copies of `Gmat`** and **1.9 copies of the
draw matrix**, over a fixed **267 MB** of R and package overhead.

**Memory is linear in `q`, not quadratic.** The natural guess is that
the sparse Cholesky of the `q(t+s)` square factor precision matrix
dominates, which would scale with `q^2`. Measured, it does not: adding
that term to the regression does not improve it, because the `Gmat`
working set is an order of magnitude larger. Doubling the factor count
costs roughly one extra `Gmat` worth of working set, not four.

## Calibration

Fitted to six fits measured one per fresh R process (the GC high-water
mark is per process, so several in one session would report only their
maximum) at `n = 53`, `t = 1559`, `s = 22`: `q = 1..4` at
`length_sample = 30`, and `q = 2` at `length_sample = 30, 120, 240`.
Adjusted R-squared 0.98, largest residual 34 MB.

Validated out of sample against a fit on a **different** dataset and a
different version of the code (`n = 43`, `t = 1464`, `q = 2`,
`length_sample = 200`): 690 MB predicted against 744 MB measured, a 7%
error.

Treat it as accurate to roughly 10%, which is why `dfm_workers()`
applies a safety factor rather than dividing exactly. The constants are
specific to this package's samplers; they were measured on x86_64
Windows and will drift if the samplers' allocation pattern changes.
`dev/calibrate-memory.R` regenerates them.

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
#> [1] 1128.27

# the whole point: how many workers fit in 24 GB
dfm_workers(n = 53, t = 1535, s = 22, q = 4, length_sample = 500,
            available_mb = 24 * 1024)
#> [1] 4
#> attr(,"per_fit_mb")
#> [1] 1430.12
#> attr(,"available_mb")
#> [1] 24576
#> attr(,"budget_mb")
#> [1] 17203.2

# from the data itself
data(data_ch_dataset_test)
dfm_memory(flows = data_ch_dataset_test$flows,
           stocks = data_ch_dataset_test$stocks,
           q = 2, length_sample = 1000)
#> [1] 1664.424
```
