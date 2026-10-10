# Assemble and check the input data for a dynamic factor model

Converts the data you have into the form the models need, and – more
importantly – makes the flow/stock classification and the inferred
frequencies visible so they can be checked *before* committing to a run
that takes minutes to hours.

## Usage

``` r
mfbdfm_data(data, meta, target = NULL, aggregate = c("mean", "sum"))
```

## Arguments

- data:

  The input series, in any of the forms above.

- meta:

  A data frame with one row per series and at least the columns `series`
  and `type` (`"flow"` or `"stock"`). May carry further columns
  (`label`, `source`, ...), which are kept but unused. A `frequency`
  column, if present, declares the frequency instead of inferring it.

- target:

  Optional character. If given, checked to be present among the series,
  so a typo surfaces here rather than deep in the sampler. It is stored
  on the object and used as the default `target` by
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  and
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- aggregate:

  How to combine observations that fall into the same 48-week slot when
  a weekly or daily series is put on the grid, either `"mean"` (the
  default) or `"sum"`. See the "Weekly and daily series" section.

## Value

An object of class `"mfbdfm_data"`: a list with `flows`, `stocks` (named
lists of `ts`, ready to pass to a model), `meta` (the resolved
per-series table, with the frequency and observation count actually
used, the level screen's `ac1` and `df_t`, plus `frequency_in` where a
series was converted) and `target`.

## Why this exists

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
and
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
take `flows` and `stocks` as two separate named lists of `ts` objects.
That shape is necessary – mixed frequencies cannot sit in one
rectangular table without padding – but it means each series' type is
expressed by *which argument it was passed in*, so there is nowhere to
inspect or correct it.

That matters because the type selects the temporal aggregation weights:

- `"flow"`:

  A quantity accumulated over the period (GDP, sales, traffic counts).
  Gets the triangular Mariano-Murasawa weights.

- `"stock"`:

  A level observed at a point, or an average (a price index, VIX, a
  sentiment balance). Gets simple averaging weights.

For series at the **highest** frequency in the dataset the two sets of
weights are identical, so the choice cannot matter there. For
lower-frequency series they differ substantially (measured on a
weekly-highest dataset: a monthly series gets 7 nonzero lags as a flow
against 4 as a stock, a quarterly one 23 against 12), and misclassifying
one silently changes your results. `mfbdfm_data()` therefore requires
`type` for exactly the series where it can change the answer, and
[`print()`](https://rdrr.io/r/base/print.html) shows the classification
back to you.

## What it accepts

`data` may be

- a **long** data frame with columns `series`, `date` (or `time`) and
  `value` – handles ragged histories and mixed frequency with no
  padding;

- a **wide** data frame with a date/time column and one column per
  series (leading and trailing `NA`s are trimmed per series, so a ragged
  panel does not become a padded one);

- an `mts` (multivariate `ts`), for a single-frequency dataset;

- a named **list of `ts`** objects, which is what the models use
  internally, so this is a pass-through with validation.

## Frequency

For data frames the frequency is inferred from each series' own date
spacing and reported by [`print()`](https://rdrr.io/r/base/print.html),
so an inference you did not intend is visible rather than silent. Only
the frequencies this package models are recognised – 4 (quarterly), 12
(monthly), 48, 52 (weekly) and 365 (daily); anything else is an error
rather than a guess, because a wrong frequency silently corrupts the
temporal aggregation.

Frequency 48 is the four-weeks-per-month grid used by the Weekly
Activity Index, on which observations fall on the 7th, 14th, 21st and
28th of each month (see
[`dec2week()`](https://philippkronenberg.github.io/mfbdfm/reference/dec2week.md)).
It has the same ~7-day spacing as a true weekly series, so it is
identified by that day-of-month convention; a series with 7-day steps
that does not follow it is taken to be frequency 52. Supply a
`frequency` column in `meta` to declare the frequency outright and skip
the inference. Declaring one that contradicts an input that is already a
`ts` is an error rather than a silent override.

## Weekly and daily series are put on the 48-week grid

48 is not an arbitrary house convention – it is the grid the models are
built on, and a series at a finer frequency **silently loses most of the
lower-frequency data**.

[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
shifts each series' observations to the end of their period by
`(max(freq)/frequency(x) - 1)/max(freq)` and then matches them onto a
`1/max(freq)` grid by an exact join. When the highest frequency is 48
that ratio is a whole number for monthly (4) and quarterly (12) series,
so every observation lands on a grid point. When a frequency-52 series
raises the maximum to 52, `52/12` is 4.33: the shifted monthly
observations no longer fall on the grid, the join does not match them,
and they are recorded as missing. Measured on a 20-quarter / 60-month /
260-week panel, the monthly series retained **20 of its 60
observations** – and the fit completed without any error or warning.

So any series arriving at a frequency finer than 48 – 52 (weekly) or 365
(daily) – is aggregated onto the 48-week grid with
[`daily2weekly()`](https://philippkronenberg.github.io/mfbdfm/reference/daily2weekly.md),
the same function the analysis scripts use for this. A
[`message()`](https://rdrr.io/r/base/message.html) names the series
converted, [`print()`](https://rdrr.io/r/base/print.html) shows the
original frequency alongside the new one, and `meta$frequency_in`
records it.

For a weekly series this goes **via daily**: the observations are first
expanded to the calendar days their weeks cover, and those days are then
aggregated onto the 48 grid. The reason is that 48 does not divide 52,
so mapping weekly points straight onto the grid gives each slot either
one or two of them – a nearest-point pick rather than a resampling,
which leaves occasional empty slots and a handful of slots a year that
blend two weeks while the rest blend one. Routing through a common finer
grid gives every slot 7-8 days and makes its value an overlap-weighted
blend of the weeks it straddles. On a linear ramp the direct route
yields steps of `1.5, 1.5, 1, 1, ...` where the correct constant rate is
`52/48 = 1.083`, which the daily route reproduces. Daily input is
already on that grid and is passed straight through.

A weekly observation's date is taken to label the **end** of its week,
which is this package's own convention (see
[`dec2week()`](https://philippkronenberg.github.io/mfbdfm/reference/dec2week.md)).

## Near-collinear input series

[`print()`](https://rdrr.io/r/base/print.html) reports pairs of series
that are near-perfectly correlated, and
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
and
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
warn about them with condition class `mfbdfm_warning_collinear` (see
[`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)
on muffling it).

This is worth checking because in an indicator panel a duplicated series
is not hypothetical: the same underlying quantity often enters twice, as
a level and as an index, or as a total alongside its own components –
and nothing about assembling your own `flows`/`stocks` lists makes that
visible.

The statistic is the correlation of each pair **on its overlapping
observed span only**, flagged at `|r| > 0.99`, with pairs overlapping in
fewer than 24 observations skipped. The overlap restriction matters: the
matrix the models are fitted to encodes missing as `0`, so a correlation
taken over it would measure the padding as much as the data. Correlation
is unaffected by the standardization
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
applies, so the figure reported is the one the standardized matrix would
give.

**It is a warning and not an error, deliberately.** A factor model does
not break on collinear inputs – not even on exactly collinear ones. The
likelihood stays proper and the sampler still converges; what happens is
that the loading the two series share is split between them, so that
signal is silently overweighted in the factor and no later diagnostic
flags it. Which of the two to drop is a question about the data rather
than about the numerics, so there is no separate code path for the
collinear case: the warning names the pair and the choice stays yours.

Note this is one of the things you get by going through `mfbdfm_data()`:
passing `flows`/`stocks` straight to a model does no such conversion,
and a frequency-52 series there will still quietly cost you most of your
monthly observations.

`aggregate` chooses how the days falling in one slot are combined.
Because the expansion repeats each weekly value across its days rather
than dividing it, `"mean"` (the default) is exactly the overlap-weighted
average of the weekly rates – what these models want, being estimated on
growth rates – and `"sum"` is exactly proportional to the period total,
the constant being the days per period, which
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)'s
standardization removes.

## Levels or growth rates?

The models assume stationary inputs (see the "Assumptions" section of
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)),
and
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)
standardizes but does **not** difference: a series handed over in levels
stays in levels, and the fit completes without complaint. So `meta`
carries two statistics per series – `ac1`, the lag-1 autocorrelation of
the observed values, and `df_t`, a Dickey-Fuller t-ratio – and
[`print()`](https://rdrr.io/r/base/print.html) names any **flow** whose
`df_t` fails to reach `-2.86` as a possible level, suggesting a growth
rate or a difference.

It is an advisory, not a test. Nothing is changed, no warning is raised,
and the entry points do not refuse the data – the package cannot know
what you intended, and a persistent flow is not necessarily a mistake.

Three choices in it were settled by measurement on the shipped data
rather than by taste, and are worth knowing because they bound what the
screen can do for you:

- **Stocks are not screened.** A stock is documented above as a level
  observed at a point or an average, so a persistent one is *correct*
  input, and the shipped stocks confirm it: `ac1` reaches 0.995 for the
  interest-rate level in
  [data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
  (`df_t` -1.57), 0.957 for a bond yield, 0.95 for VIX in
  [data_ch_dataset_test](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset_test.md),
  and 0.89-0.94 for the PMI diffusion indices. Any rule that caught an
  undifferenced level would flag all of those.

- **The statistic is `df_t`, not `ac1`, because no `ac1` cut-off
  works.** The largest `ac1` among the 79 flows in the three shipped
  datasets is 0.841 (`electricity_in` in
  [data_ch_dataset_test](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset_test.md)),
  while a 60-observation random walk sits at 0.86-0.89 and the GDP
  *level* over 50 quarters at 0.92 – the two groups overlap, because
  `ac1` is biased down by roughly `1/n` and so confounds persistence
  with sample length. The Dickey-Fuller t-ratio does not: every one of
  those 79 flows reaches -3.72 or lower, against -2.27 for the 60-step
  random walk, -1.32 for a 500-step one and -0.89 for the GDP level.
  `ac1` is reported anyway, since it is the obvious thing to want to
  look at.

- **The cut-off is the textbook one**, the asymptotic 5% critical value
  for the constant-only case, `-2.86` (Fuller 1976; MacKinnon 1991), not
  a value fitted to this data. It is used without lag augmentation and
  without a trend term – see the notes on `unit_root_t()` in the source
  for what that costs. Series with fewer than 24 observations, or no
  variation, get `NA` for both statistics and are not screened.

What this is not: a stationarity *test* per series (one unaugmented
regression, no multiplicity correction, no joint statement about the
panel), and not a check of the model's other assumptions. Treat a
flagged series as a question to answer, and an unflagged panel as
nothing more than the absence of this one signal.

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md),
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)

Other data preparation functions:
[`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md),
[`mfbdfm_example_inputs()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_example_inputs.md),
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)

## Examples

``` r
# from a long data frame
long <- data.frame(
  series = rep(c("a_flow", "b_stock"), each = 24),
  date = rep(seq(as.Date("2020-01-01"), by = "month", length.out = 24), 2),
  value = rnorm(48))
meta <- data.frame(series = c("a_flow", "b_stock"),
                   type = c("flow", "stock"))
d <- mfbdfm_data(long, meta)
d
#> <mfbdfm_data>  2 series  (1 flow, 1 stock)
#> 
#>   by frequency:
#>        12   1 flow   1 stock   <- highest; flow/stock has no effect here
#> 
#>   series (first 10):
#>     a_flow                       flow   freq   12  n    24
#>     b_stock                      stock  freq   12  n    24
#> 
#> Pass to ind_dfm() or fcast_dfm() as the first argument.

# a true weekly series is aggregated onto the 48-week grid the models use,
# and the original frequency is reported
wk <- seq(as.Date("2020-01-06"), by = "week", length.out = 157)
d <- mfbdfm_data(
  rbind(data.frame(series = "weekly", date = wk, value = rnorm(length(wk))),
        data.frame(series = "monthly",
                   date = seq(as.Date("2020-01-01"), by = "month",
                              length.out = 36),
                   value = rnorm(36))),
  data.frame(series = c("weekly", "monthly"), type = c("flow", "stock")))
#> Aggregated to the 48-week grid the models use (by mean): ‘weekly’ (52 -> 48).
d$meta
#>    series  type frequency n_obs        ac1      df_t frequency_in
#> 1 monthly stock        12    36 -0.1072168 -6.292181           NA
#> 2  weekly  flow        48   146  0.2238059 -9.311767           52

# a flow handed over in levels is named by print(), not silently accepted
set.seed(1)
d <- mfbdfm_data(
  data.frame(series = rep(c("growth_rate", "a_level"), each = 60),
             date = rep(seq(as.Date("2015-01-01"), by = "month",
                            length.out = 60), 2),
             value = c(rnorm(60), cumsum(rnorm(60)) + 100)),
  data.frame(series = c("growth_rate", "a_level"), type = "flow"))
d
#> <mfbdfm_data>  2 series  (2 flow, 0 stock)
#> 
#>   by frequency:
#>        12   2 flow   0 stock   <- highest; flow/stock has no effect here
#> 
#>   possible levels rather than growth rates (flow, Dickey-Fuller t > -2.86):
#>     a_level                      DF t  -1.51  ac1 0.894
#>     -> these models assume stationary inputs; consider a growth rate
#>        or a difference. Stocks are not screened; see ?mfbdfm_data.
#> 
#>   series (first 10):
#>     a_level                      flow   freq   12  n    60
#>     growth_rate                  flow   freq   12  n    60
#> 
#> Pass to ind_dfm() or fcast_dfm() as the first argument.
d$meta[, c("series", "ac1", "df_t")]
#>        series        ac1      df_t
#> 1     a_level 0.89409104 -1.509395
#> 2 growth_rate 0.01042752 -7.514619

# from the shipped dataset, which is already a list of `ts`
data(data_ch_dataset_test)
series <- c(data_ch_dataset_test$flows, data_ch_dataset_test$stocks)
meta <- data.frame(
  series = names(series),
  type = rep(c("flow", "stock"), lengths(data_ch_dataset_test)))
mfbdfm_data(series, meta, target = "ch.seco.gdp.real.gdp.ssa")
#> <mfbdfm_data>  46 series  (28 flow, 18 stock)
#> target: ch.seco.gdp.real.gdp.ssa
#> 
#>   by frequency:
#>         4   1 flow   0 stock
#>        12   3 flow  15 stock
#>        48  24 flow   3 stock   <- highest; flow/stock has no effect here
#> 
#>   series (first 10):
#>     ch.fso.rtt.ind.r.noga0801.sa flow   freq   12  n   312
#>     FINANSW                      flow   freq   48  n  1738
#>     INDUSSW                      flow   freq   48  n  1738
#>     SWISSMI                      flow   freq   48  n  1738
#>     oev_freq_hardbruecke         flow   freq   48  n   290
#>     oev_freq_hb                  flow   freq   48  n    97
#>     tages_distanz_median         flow   freq   48  n    72
#>     debiteinsatz_ausland         flow   freq   48  n   180
#>     bezug_bargeld                flow   freq   48  n   144
#>     stat_einkauf                 flow   freq   48  n   331
#>     ... and 36 more
#> 
#> Pass to ind_dfm() or fcast_dfm() as the first argument.
```
