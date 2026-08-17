# Build the full path for a figure output file

Creates `figures_dir` if it does not exist, since the returned path
exists to be written to immediately afterwards by the caller's plotting
code — there is no other point at which a figure directory could be
created on demand. This is the one path-building function in the package
that touches disk, and it is deliberate; see
[`wai_sample_config()`](https://philippkronenberg.github.io/mfbdfm/reference/wai_sample_config.md),
which no longer does.

## Usage

``` r
output_figure_path(filename, figures_dir)
```

## Arguments

- filename:

  File name (without directory).

- figures_dir:

  Directory the figure belongs in (e.g.
  `wai_sample_config()$figures_dir`). Created if missing.

## Value

The full file path.

## Examples

``` r
figs <- file.path(tempdir(), "figures")
output_figure_path("history.pdf", figures_dir = figs)
#> [1] "/tmp/Rtmp2FJjCC/figures/history.pdf"
```
