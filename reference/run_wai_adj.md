# Fit the WAI dynamic factor model at a given evaluation date

Runs
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
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
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  (currently without effect there).

- output_dir:

  Directory to save the fit to, or `NULL` (default) to skip saving. When
  given, the fit is saved as
  `file.path(output_dir, dataset_used, "fit_<date>.Rda")`.

## Value

Invisibly, the windowed `ind_dfm` fit object.

## Examples

``` r
# \dontrun rather than \donttest because the chain length is fixed at 5000
# draws inside this function, so it runs for minutes to tens of minutes - too
# long for a checked example. It is self-contained, though: paste it and it
# runs on the shipped data, writing into a temporary directory.
if (FALSE) { # \dontrun{
data(data_ch_dataset_test)
target <- "ch.seco.gdp.real.gdp.ssa"
out <- tempfile(); dir.create(out)

fit <- run_wai_adj(flows = data_ch_dataset_test$flows,
                   stocks = data_ch_dataset_test$stocks,
                   target = target,
                   date = 2024.5, dataset_used = "example",
                   output_dir = out)
fit$nowcast
list.files(out, recursive = TRUE)
unlink(out, recursive = TRUE)
} # }
```
