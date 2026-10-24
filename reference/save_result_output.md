# Save a result object to the results directory

Save a result object to the results directory

## Usage

``` r
save_result_output(object, filename, results_dir)
```

## Arguments

- object:

  Object to save (stored under its own name).

- filename:

  File name (without directory). The object is written by
  [`save()`](https://rdrr.io/r/base/save.html) and read back by
  [`load()`](https://rdrr.io/r/base/load.html), so the extension must be
  `.Rda`, `.rda`, `.RData` or `.rdata`; `.Rda` is appended when none is
  given, and any other extension is an error rather than a binary
  payload under a name promising something else (G4.0).

- results_dir:

  Directory to write into (e.g. `wai_sample_config()$results_dir`).

## Value

Invisibly, the full path written.
