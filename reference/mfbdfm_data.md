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
used, plus `frequency_in` where a series was converted) and `target`.

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

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md),
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)

Other data preparation functions:
[`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md),
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
#>    series  type frequency n_obs frequency_in
#> 1 monthly stock        12    36           NA
#> 2  weekly  flow        48   146           52

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
