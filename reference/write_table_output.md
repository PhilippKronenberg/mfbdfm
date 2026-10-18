# Write a table output file

Write a table output file

## Usage

``` r
write_table_output(filename, contents, tables_dir)
```

## Arguments

- filename:

  File name (without directory).

- contents:

  Character vector written via
  [`writeLines()`](https://rdrr.io/r/base/writeLines.html).

- tables_dir:

  Directory to write into (e.g. `wai_sample_config()$tables_dir`).

## Value

Invisibly, the full path written.
