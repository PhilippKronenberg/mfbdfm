# Small self-contained example dataset, GDP target included

A ready
[`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
object holding eight series: the quarterly GDP target and seven
indicators, enough for
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
or
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
to be fitted meaningfully in a few seconds on a short chain. Unlike
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
it **carries the target**, and unlike both shipped datasets it is an
`mfbdfm_data` object rather than a bare `flows`/`stocks` list – so the
whole of a runnable example is

## Usage

``` r
mfbdfm_example_data
```

## Format

An
[`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
object – a list with four components:

- flows:

  Named list of 6 `ts` objects: GDP (frequency 4), two monthly (12) and
  three weekly (48) series.

- stocks:

  Named list of 2 `ts` objects, one monthly and one weekly.

- meta:

  Data frame, one row per series, with `series`, `type`, `frequency`,
  `n_obs`, the level screen's `ac1` and `df_t` (see
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md))
  and the carried-through `label`, `source`, `category`, `unit` and
  `transformation`.

- target:

  `"ch.seco.gdp.real.gdp.ssa"`, used as the default `target` by both
  model entry points.

## Source

Built by `data-raw/example_data.R` from
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
(series) and the real-time GDP vintage database shipped at
`system.file("extdata", "realtime_gdp.csv", package = "mfbdfm")`
(target). Original sources are per-series in `$meta$source`; see the
data dictionary in `README.md`.

## Details

    data(mfbdfm_example_data)
    fit <- ind_dfm(mfbdfm_example_data, length_sample = 50, burn_in = 10)

with no `target =` argument and no windowing prelude. It exists for
exactly that: examples, the vignette and quick experiments. For the real
application use
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md)
with a GDP vintage injected at runtime (see
[`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)).

The seven indicators are taken **as they already appear** in
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md),
i.e. already transformed per `data-raw/data_meta.csv` (`transformation`
in `$meta` records which), and windowed to `start = 2015`. They were
chosen to cover all three frequencies the model handles and both
aggregation types, and to have an unbroken history over the window – so
the only missingness in the dataset is the ragged edge at the end, which
is kept deliberately, that being the thing the model exists to handle.

|  |  |  |  |
|----|----|----|----|
| series | freq | type | what it is |
| `ch.seco.gdp.real.gdp.ssa` | 4 | flow | **target** – GDP, q/q log difference (SECO) |
| `ch.fso.rtt.ind.r.noga0801.sa` | 12 | flow | retail sales, total (FSO) |
| `ch.ozd.e.wa.index.re.d11` | 12 | flow | goods exports, total, real (FOCBS) |
| `SWPMIPROQ` | 12 | stock | PMI manufacturing, output (procure.ch & UBS) |
| `SWISSMI` | 48 | flow | Swiss Market Index (SIX Group) |
| `traffic_PW` | 48 | flow | passenger-car counts on motorways (ASTRA) |
| `electricity_out` | 48 | flow | electricity consumed by end users (Swissgrid) |
| `Arbeitsmarkt` | 48 | stock | Google search index, labour market (KOF) |

The target is the **2026.167 vintage** (published 2026-02-27, the newest
in the shipped real-time database), transformed with
`get_real_time_gdp_vintages("quarterly")`. It is pinned to that vintage
so the dataset does not change when a newer one is appended to
`inst/extdata/realtime_gdp.csv`; to move it on, change `GDP_VINTAGE` in
`data-raw/example_data.R` and rerun it.

## See also

[`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md),
[data_ch_dataset](https://philippkronenberg.github.io/mfbdfm/reference/data_ch_dataset.md),
[`get_real_time_gdp_vintages()`](https://philippkronenberg.github.io/mfbdfm/reference/get_real_time_gdp_vintages.md)

## Examples

``` r
data(mfbdfm_example_data)
mfbdfm_example_data
#> <mfbdfm_data>  8 series  (6 flow, 2 stock)
#> target: ch.seco.gdp.real.gdp.ssa
#> 
#>   by frequency:
#>         4   1 flow   0 stock
#>        12   2 flow   1 stock
#>        48   3 flow   1 stock   <- highest; flow/stock has no effect here
#> 
#>   series (first 10):
#>     ch.fso.rtt.ind.r.noga0801.sa flow   freq   12  n   133
#>     ch.ozd.e.wa.index.re.d11     flow   freq   12  n   131
#>     SWPMIPROQ                    stock  freq   12  n   134
#>     SWISSMI                      flow   freq   48  n   538
#>     traffic_PW                   flow   freq   48  n   532
#>     electricity_out              flow   freq   48  n   529
#>     Arbeitsmarkt                 stock  freq   48  n   541
#>     ch.seco.gdp.real.gdp.ssa     flow   freq    4  n    44
#> 
#> Pass to ind_dfm() or fcast_dfm() as the first argument.
mfbdfm_example_data$target
#> [1] "ch.seco.gdp.real.gdp.ssa"

# \donttest{
set.seed(1)
fit <- ind_dfm(mfbdfm_example_data, length_sample = 50, burn_in = 10)
#> preallocating..
#> simulating posterior distribution..
#>   |                                                                              |                                                                      |   0%  |                                                                              |=                                                                     |   2%  |                                                                              |==                                                                    |   3%  |                                                                              |====                                                                  |   5%  |                                                                              |=====                                                                 |   7%  |                                                                              |======                                                                |   8%  |                                                                              |=======                                                               |  10%  |                                                                              |========                                                              |  12%  |                                                                              |=========                                                             |  13%  |                                                                              |==========                                                            |  15%  |                                                                              |============                                                          |  17%  |                                                                              |=============                                                         |  18%  |                                                                              |==============                                                        |  20%  |                                                                              |===============                                                       |  22%  |                                                                              |================                                                      |  23%  |                                                                              |==================                                                    |  25%  |                                                                              |===================                                                   |  27%  |                                                                              |====================                                                  |  28%  |                                                                              |=====================                                                 |  30%  |                                                                              |======================                                                |  32%  |                                                                              |=======================                                               |  33%  |                                                                              |========================                                              |  35%  |                                                                              |==========================                                            |  37%  |                                                                              |===========================                                           |  38%  |                                                                              |============================                                          |  40%  |                                                                              |=============================                                         |  42%  |                                                                              |==============================                                        |  43%  |                                                                              |================================                                      |  45%  |                                                                              |=================================                                     |  47%  |                                                                              |==================================                                    |  48%  |                                                                              |===================================                                   |  50%  |                                                                              |====================================                                  |  52%  |                                                                              |=====================================                                 |  53%  |                                                                              |======================================                                |  55%  |                                                                              |========================================                              |  57%  |                                                                              |=========================================                             |  58%  |                                                                              |==========================================                            |  60%  |                                                                              |===========================================                           |  62%  |                                                                              |============================================                          |  63%  |                                                                              |==============================================                        |  65%  |                                                                              |===============================================                       |  67%  |                                                                              |================================================                      |  68%  |                                                                              |=================================================                     |  70%  |                                                                              |==================================================                    |  72%  |                                                                              |===================================================                   |  73%  |                                                                              |====================================================                  |  75%  |                                                                              |======================================================                |  77%  |                                                                              |=======================================================               |  78%  |                                                                              |========================================================              |  80%  |                                                                              |=========================================================             |  82%  |                                                                              |==========================================================            |  83%  |                                                                              |============================================================          |  85%  |                                                                              |=============================================================         |  87%  |                                                                              |==============================================================        |  88%  |                                                                              |===============================================================       |  90%  |                                                                              |================================================================      |  92%  |                                                                              |=================================================================     |  93%  |                                                                              |==================================================================    |  95%  |                                                                              |====================================================================  |  97%  |                                                                              |===================================================================== |  98%  |                                                                              |======================================================================| 100%
#> processing output..
utils::tail(fit$nowcast)
#>              Qtr1         Qtr2         Qtr3         Qtr4
#> 2024                                         0.005175396
#> 2025  0.007858665  0.001230667 -0.004400748  0.001506323
#> 2026  0.014249460                                       
# }
```
