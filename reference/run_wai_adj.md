# Fit the WAI dynamic factor model at a given evaluation date

Runs
[`hfdfm()`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
with the settings used in the WAI out-of-sample evaluation and windows
the factor and nowcast output to the evaluation date.

## Usage

``` r
run_wai_adj(
  flows,
  stocks,
  target,
  date,
  dataset_used,
  stochastic_volatility = TRUE,
  output_dir = NULL
)
```

## Arguments

- flows:

  Named list of `ts` objects containing `target`.

- stocks:

  Named list of `ts` objects.

- target:

  Character, name of the target series in `flows`.

- date:

  Numeric (decimal time), evaluation date; the factor is cut at this
  date.

- dataset_used:

  Character, dataset label used as sub-directory when saving.

- stochastic_volatility:

  Logical, passed to
  [`hfdfm()`](https://philippkronenberg.github.io/mfbdfm/reference/hfdfm.md)
  (currently without effect there).

- output_dir:

  Directory to save the fit to, or `NULL` (default) to skip saving. When
  given, the fit is saved as
  `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.

## Value

Invisibly, the windowed `hfdfm` fit object.

## Examples

``` r
if (FALSE) { # \dontrun{
# Full MCMC estimation at one evaluation date, saving the fit:
fit <- run_wai_adj(flows = dat$flows, stocks = dat$stocks,
                   target = "ch.seco.gdp.real.gdp.ssa",
                   date = 2024.5, dataset_used = "full_RT",
                   output_dir = "fits/updated")
} # }
```
