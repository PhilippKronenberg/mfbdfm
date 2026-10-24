# Build the full path for a figure output file

Purely a path: this creates nothing on disk. `figures_dir` is expected
to exist already — the analytics preludes (`analysis/5_plots/_setup.R`,
`analysis/fcast/_setup.R`) create the whole output tree up front, and so
does any caller that has written a table or result through
[`write_table_output()`](https://philippkronenberg.github.io/mfbdfm/reference/write_table_output.md)/[`save_result_output()`](https://philippkronenberg.github.io/mfbdfm/reference/save_result_output.md).

## Usage

``` r
output_figure_path(filename, figures_dir)
```

## Arguments

- filename:

  File name (without directory). The extension selects the graphics
  device the caller will write with, so it must be one a device exists
  for (`.pdf`, `.png`, `.jpg`, `.jpeg`, `.svg`, `.eps`, `.ps`, `.tiff`,
  `.tif`, `.bmp`, `.wmf`); `.pdf` is appended when none is given, since
  an extensionless path makes
  [`ggplot2::ggsave()`](https://ggplot2.tidyverse.org/reference/ggsave.html)
  error on a device it cannot guess (G4.0).

- figures_dir:

  Directory the figure belongs in (e.g.
  `wai_sample_config()$figures_dir`). Must already exist; not created
  here.

## Value

The full file path.

## Details

It did briefly create the directory, on the reasoning that the returned
path is written to immediately afterwards. That was a mistake worth
recording: a path builder with a side effect surprised a test that
passed it the relative path `"outputs/figures"`, which had been harmless
for as long as the function was a plain
[`file.path()`](https://rdrr.io/r/base/file.path.html) call, and the
suite started leaving `tests/testthat/outputs/figures` behind in the
source tree.
