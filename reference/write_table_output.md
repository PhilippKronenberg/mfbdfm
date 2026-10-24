# Write a table output file

Write a table output file

## Usage

``` r
write_table_output(filename, contents, tables_dir)
```

## Arguments

- filename:

  File name (without directory). The contents are written as plain text
  by [`writeLines()`](https://rdrr.io/r/base/writeLines.html), so the
  extension must be one of `.tex`, `.csv`, `.txt`, `.tsv` or `.md`;
  `.tex` is appended when none is given, that being what the table
  builders produce. Anything else is an error rather than a text file
  under a misleading name (G4.0).

- contents:

  Character vector written via
  [`writeLines()`](https://rdrr.io/r/base/writeLines.html).

- tables_dir:

  Directory to write into (e.g. `wai_sample_config()$tables_dir`).

## Value

Invisibly, the full path written.
