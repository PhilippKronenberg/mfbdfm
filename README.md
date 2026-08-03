# mfbdfm — Mixed-Frequency Bayesian Dynamic Factor Model

<!-- badges: start -->
[![R-CMD-check](https://github.com/PhilippKronenberg/mfbdfm/actions/workflows/r.yml/badge.svg)](https://github.com/PhilippKronenberg/mfbdfm/actions/workflows/r.yml)
[![test-coverage](https://github.com/PhilippKronenberg/mfbdfm/actions/workflows/test-coverage.yaml/badge.svg)](https://github.com/PhilippKronenberg/mfbdfm/actions/workflows/test-coverage.yaml)
[![Codecov test coverage](https://codecov.io/gh/PhilippKronenberg/mfbdfm/branch/main/graph/badge.svg)](https://app.codecov.io/gh/PhilippKronenberg/mfbdfm)
<!-- badges: end -->

`mfbdfm` estimates a Bayesian **mixed-frequency dynamic factor model**
by Markov chain Monte Carlo (Gibbs) sampling, combining weekly, monthly
and quarterly indicator series into a single dynamic factor that can be
anchored to a chosen target series.

The package ships a flagship application: the **weekly activity index
(WAI) for Switzerland**, which produces weekly GDP nowcasts and
backcasts by anchoring the factor to quarterly real GDP. Around it, the
package also provides:

- **real-time GDP vintage handling** — the Swiss real-time GDP vintage
  database ships with the package,
- **out-of-sample forecast evaluation** (expanding-window backcasts, an
  AR(1) benchmark, modified Diebold–Mariano tests),
- the **table and plot generators** used in the accompanying analysis.

## Installation

``` r
# install.packages("remotes")
remotes::install_github("PhilippKronenberg/mfbdfm")
```

The package requires R >= 4.1.

## Getting started

For a fuller walkthrough of the model (data augmentation, stochastic
volatility, the identification restriction) with a runnable example,
see `vignette("mfbdfm")` — also browsable on the
[package website](https://philippkronenberg.github.io/mfbdfm/articles/mfbdfm.html).

The curated indicator datasets ship with the package. A small (fast,
demonstration-sized) nowcast:

``` r
library(mfbdfm)

data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"   # quarterly real Swiss GDP

# small subset and short chain so this runs in seconds;
# real runs use the full dataset and length_sample = 10000
flows  <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                 stats::window, start = 2018)
stocks <- lapply(data_ch_dataset_test$stocks[1:2],
                 stats::window, start = 2018)

set.seed(1)
fit <- ind_dfm(flows = flows, stocks = stocks, target = target,
             length_sample = 500, burn_in = 100)

fit$factor    # weekly activity factor (annualized growth)
fit$nowcast   # quarterly GDP nowcast
```

Real-time GDP vintages work out of the box:

``` r
vintages <- get_real_time_gdp_vintages("quarterly")
dat <- cut_data_real_time(data_ch_dataset_test, current_date = 2024.5,
                          GDP_gr_vintages = vintages)
```

## How to apply the package

The sequence below is the whole user-facing workflow, using only exported
functions. `demo/run_package_demo.R` runs exactly this end to end — install,
fit, inspect, save — in about five minutes on the shipped data, and is the
quickest way to confirm an installation is sound:

``` sh
Rscript demo/run_package_demo.R
```

### 1. Assemble and check the input

Series go in as `ts` objects split into flows and stocks. `mfbdfm_data()` builds
that from a long or wide data frame, an `mts`, or a list of `ts`, and — more
usefully — makes the classification inspectable *before* a run that can take
hours:

``` r
library(mfbdfm)
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"

series <- lapply(c(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                   data_ch_dataset_test$stocks[1:2]),
                 window, start = 2018)
meta <- data.frame(series = names(series), type = rep(c("flow", "stock"), each = 2))

d <- mfbdfm_data(series, meta, target = target)
d   # prints the flow/stock split and the frequency of every series
```

Flow versus stock selects the temporal aggregation weights, so getting it wrong
changes results silently. `mfbdfm_data()` requires `type` only where it can
matter — below the highest frequency — and puts weekly or daily series onto the
48-periods-per-year grid the models are built on.

### 2. Choose priors and numerical settings (optional)

Both are optional; the defaults reproduce the published behaviour.

``` r
priors  <- dfm_priors("ind_dfm")                       # or type = "tight"/"loose"
control <- dfm_control("ind_dfm")                      # stability bounds, tolerances
strict  <- dfm_control("fcast_dfm", strict = TRUE)     # the paper's rotation rule
```

### 3. Fit

Two models, two entry points — **not one model with a `q` argument**. They
differ in identification, priors and how the dynamics are drawn:

``` r
fit  <- ind_dfm(d, length_sample = 5000, burn_in = 1000)   # single factor, GDP-anchored
mfit <- fcast_dfm(d, q = 2, length_sample = 1000)          # multi-factor, rotation-identified
```

### 4. Inspect

Both fit classes support the usual generics:

``` r
print(fit); summary(fit); plot(fit)
coef(fit); fitted(fit); residuals(fit); as.data.frame(fit)

fit$factor     # weekly activity factor
fit$nowcast    # aggregated to the target's own frequency
```

### 5. Real-time evaluation

`get_real_time_gdp_vintages()` ships with the package, so a real-time exercise
needs no external data. `cut_data()` trims every series to what was available at
a given date, and the `run_*()` wrappers fit one model at one evaluation date
and write the fit:

``` r
vintages <- get_real_time_gdp_vintages("quarterly")
rt <- cut_data(d, current_date = 2024.5)

run_ar     (rt$flows, rt$stocks, target, date = 2024.5, dataset_used = "demo")
run_wai_adj(rt$flows, rt$stocks, target, date = 2024.5, dataset_used = "demo")
run_fcast  (rt$flows, rt$stocks, target, date = 2024.5, dataset_used = "demo", q = 2)
```

Add `output_dir =` to write them; without it nothing touches the disk.

### 6. Outputs and evaluation

`wai_sample_config()` fixes the output layout, and the evaluation helpers work
off it:

``` r
cfg <- wai_sample_config(sample_id = "my_run")
dm_test_modified(errors_model, errors_benchmark, alternative = "less")
write_table_output("table.csv", contents, cfg$tables_dir)
save_result_output(fit, "fit.Rda", cfg$results_dir)
```

Frequency and date helpers used throughout: `week2mon()`, `daily2weekly()`,
`dec2week()`, `decimal_date_local()`, `drop_weekly()`, `drop_financial()`,
`drop_retail()`, `is_crisis_period()` and `is_crisis_period_fcast()`.

## The analysis pipeline

The `analysis/` directory contains the scripts of the full research
workflow (run from the repository root; model fits are written to a
git-ignored `fits/` directory). `data_ch_dataset` / `data_ch_dataset_test`
already ship as curated package datasets — see the data dictionary
below, sourced from `data-raw/data_meta.csv` — so the pipeline starts
from there:

1. **`analysis/2_backcast.R`**, **`analysis/real_time_backcast.R`** —
   estimate the model across evaluation dates (pseudo and true real-time)
   via `run_wai_adj()` / `run_ar()`.
2. **`analysis/4_tables.R`** — parameter and metadata tables.
3. **`analysis/5_plots/`** — in-sample and out-of-sample evaluation:
   `plots_analytics.R` orchestrates `analytics_data.R`,
   `analytics_in_sample.R` and `analytics_out-of-sample.R`; the sample
   is configured via `wai_sample_config()` (see `_setup.R`).

## Data

| Object / file | What it is |
| --- | --- |
| `data_ch_dataset` | Harmonized Swiss indicator dataset (flows/stocks lists of `ts`) |
| `data_ch_dataset_test` | Test variant, includes the GDP target series |
| `inst/extdata/realtime_gdp.csv`, `realtime_gdp_cssa.csv` | Real-time GDP vintage database (read by `get_real_time_gdp_vintages()`) |

The full `data_ch_dataset` deliberately ships *without* the GDP target
series — the workflow injects it at runtime from the real-time vintages.

### Data dictionary

The 46 variables in `data_ch_dataset`/`data_ch_dataset_test`, generated from
`data-raw/data_meta.csv` (the source-of-truth variable metadata: name,
provider, category, unit, frequency, flow/stock role):

| Key | Name | Source | Category | Unit | Frequency | Type |
| --- | --- | --- | --- | --- | --- | --- |
| `anz_kktrans_ch` | Credit Card Transactions, Swiss-Wide Frequency | SPA | Alternative | Actual, in Thousands | Weekly | Flow |
| `Arbeitsmarkt` | Google Search Index, Perceived Labour Market Situation | KOF | Alternative | Index | Weekly | Stock |
| `aufkommen_miv` | Private Transport Frequency, Important Counting Stations, Zurich | StatistikZH | Alternative | Actual | Weekly | Flow |
| `bezug_bargeld` | Cash Withdrawals, Swiss-Wide Volume in CHF | SIX Group | Alternative | CHF, in Millions | Weekly | Flow |
| `debiteinsatz_ausland` | Swiss Debit Card Transactions Abroad, Volume in CHF | SIX Group | Alternative | CHF, in Millions | Weekly | Flow |
| `electricity_in` | Energy Production in Switzerland | Swissgrid | Alternative | kWh | Weekly | Flow |
| `electricity_out` | Energy Consumed by Swiss End Users | Swissgrid | Alternative | kWh | Weekly | Flow |
| `Lkw-Maut-Fahrleistungsindex_DE` | Truck-Toll Mileage Index, Germany | Destatis | Alternative | Actual | Weekly | Flow |
| `mobility_grocery_and_pharmacy` | Google COVID-19 Community Mobility Reports, Grocery and Pharmacy | Google | Alternative | Percentage | Weekly | Flow |
| `mobility_parks` | Google COVID-19 Community Mobility Reports, Parks | Google | Alternative | Percentage | Weekly | Flow |
| `mobility_residential` | Google COVID-19 Community Mobility Reports, Residential | Google | Alternative | Percentage | Weekly | Flow |
| `mobility_retail_and_recreation` | Google COVID-19 Community Mobility Reports, Retail and Recreation | Google | Alternative | Percentage | Weekly | Flow |
| `mobility_transit_stations` | Google COVID-19 Community Mobility Reports, Transit Stations | Google | Alternative | Percentage | Weekly | Flow |
| `mobility_workplaces` | Google COVID-19 Community Mobility Reports, Workplaces | Google | Alternative | Percentage | Weekly | Flow |
| `oev_freq_hardbruecke` | Public Transport Passenger Frequency, Zurich Hardbruecke | SBB | Alternative | Actual | Weekly | Flow |
| `oev_freq_hb` | Public Transport Passenger Frequency, Zurich Main Station | SBB | Alternative | Actual | Weekly | Flow |
| `stat_einkauf` | Non-Online Retail Sales, Swiss-Wide Volume in CHF | SIX Group | Alternative | CHF, in Millions | Weekly | Flow |
| `tages_distanz_median` | Median Day Distance of Representative Swiss Population Sample | intervista | Alternative | km | Weekly | Flow |
| `traffic_LW` | Truck Frequency, Counting Stations on Major Swiss Motorways | ASTRA | Alternative | Actual | Weekly | Flow |
| `traffic_PW` | Passenger Car Frequency, Counting Stations on Major Swiss Motorways | ASTRA | Alternative | Actual | Weekly | Flow |
| `trendecon` | Google Search Index, Perceived Economic Situation | trendEcon | Alternative | Index | Weekly | Stock |
| `zrh_airport_arrivals` | Total Flight Arrivals, Zurich Airport | Zurich Airport | Alternative | Actual | Weekly | Flow |
| `zrh_airport_departure` | Total Flight Departures, Zurich Airport | Zurich Airport | Alternative | Actual | Weekly | Flow |
| `FINANSW` | Swiss Stock Market Index, Financials | Datastream | Financial | CHF | Weekly | Flow |
| `INDUSSW` | Swiss Stock Market Index, Industrials | Datastream | Financial | CHF | Weekly | Flow |
| `SWISSMI` | Swiss Market Index (SMI) | SIX Group | Financial | CHF | Weekly | Flow |
| `VIX` | Volatility Index (VIX) | CBOE | Financial | Index | Weekly | Stock |
| `SWCONPRCE` | Consumer Price Index, Total | FSO | Prices | Index, 2015M12=100 | Monthly | Stock |
| `SWCPCOREF` | Consumer Price Index, Excl. Energy, Fresh & Seasonal Products | FSO | Prices | Index, 2015M12=100 | Monthly | Stock |
| `SWPROPRCE` | Producer Prices Index | FSO | Prices | Index, 2015M12=100 | Monthly | Stock |
| `ch.seco.gdp.real.gdp.ssa` | Gross Domestic Product, Adjusted for International Sport Events | SECO | Production | CHF, Real Prices | Quarterly | Flow |
| `ch.fso.rtt.ind.r.noga0801.sa` | Retail Sales, Total | FSO | Retail | Index, 2015=100 | Monthly | Flow |
| `ch.kof.aiu.ng08.fx.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Project Engineering | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.bau.ng08.fx.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Construction | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.bts_total.ng08.fx.q_ql_ass_bs.balance.d11` | Business Situation Assessment, All Industries | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.fvu.ng08.fx.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Finance & Insurance | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.inu.ng08.fx.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Manufacturing | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.inu.ng08.fx.sector_mig.cap_gd.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Manufacturing Investment Goods | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.inu.ng08.fx.sector_mig.cons_dr.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Manufacturing Durable Goods | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.inu.ng08.fx.sector_mig.cons_gd.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Manufacturing Consumption Goods | KOF | Survey | Net Balance | Monthly | Stock |
| `ch.kof.inu.ng08.fx.sector_mig.imd_gd.q_ql_ass_bs.balance.d11` | Business Situation Assessment, Manufacturing Intermediate Goods | KOF | Survey | Net Balance | Monthly | Stock |
| `SWPMIORDQ` | Purchasing Managers Index, Manufacturing Sector, Backlog of Orders | procure.ch & UBS | Survey | Index (Diffusion) | Monthly | Stock |
| `SWPMIPROQ` | Purchasing Managers Index, Manufacturing Sector, Output | procure.ch & UBS | Survey | Index (Diffusion) | Monthly | Stock |
| `SWPURCHSQ` | Purchasing Managers Index, Manufacturing Sector | procure.ch & UBS | Survey | Index (Diffusion) | Monthly | Stock |
| `ch.ozd.e.wa.index.re.d11` | Switzerland, Export: Total, Real, SA, Index (1997=100) | FOCBS | Trade | Index | Monthly | Flow |
| `ch.ozd.i.wa.index.re.d11` | Switzerland, Import: Total, Real, SA, Index (1997=100) | FOCBS | Trade | Index | Monthly | Flow |

## Documentation

Full function reference, the vignette, and the change log are published
at **<https://philippkronenberg.github.io/mfbdfm/>**.

## Development

``` r
devtools::document()   # regenerate NAMESPACE and man/ from roxygen
devtools::test()       # run the testthat suite (149 assertions, ~20 s)
devtools::check()      # R CMD check (CI runs this on push/PR to main)
devtools::load_all()   # interactive development
pkgdown::build_site()  # preview the documentation website locally
```

## References

The methodology and full empirical results are described in:

> Kronenberg, P. (2026). A high-frequency GDP indicator for
> Switzerland. *Swiss Journal of Economics and Statistics*, 162, 10.
> <https://doi.org/10.1186/s41937-026-00157-w>

which extends the mixed-frequency dynamic factor model of:

> Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025).
> Tracking economic activity with alternative high-frequency data.
> *Journal of Applied Econometrics*, 40(3), 270-290.

A reference list of the related business-cycle-indicator literature is
in the "References" section of `vignette("mfbdfm")`.

## License

MIT — see `LICENSE`.
