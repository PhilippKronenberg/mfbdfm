# Synthetic input bundle for the analytics table builders

Builds a small, self-contained `inputs` bundle of the shape
[`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md),
[`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md)
and
[`get_insample_error_details()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_error_details.md)
expect, filled with synthetic numbers.

## Usage

``` r
mfbdfm_example_inputs(seed = 99)
```

## Arguments

- seed:

  Integer, the random seed, so a bundle is reproducible. Pass `NULL` to
  draw from the current state of the RNG instead.

## Value

A named list of 11 elements: nine weekly `data.frame`s with `time` and
`value` columns (three of them also carrying `name`), and two quarterly
`ts` objects (`x_hist_gr_yoy`, `x_hist_gr_ann`) standing in for realised
GDP growth.

## Details

The real bundle is assembled by the scripts under `analysis/5_plots/`
from fitted models and the private real-time GDP vintages, so none of
the analytics functions could previously be demonstrated in a runnable
example – their examples were unevaluated sketches referring to objects
that did not exist, which meant `R CMD check` never executed them. That
is exactly how two analysis scripts came to read files nothing produced
(#59, \#63). This exists so those examples run and are checked.

It is **not** a model of Swiss data. The series are random walks and
white noise of the right shape and frequency; use it to exercise the
code paths and to see the argument shapes, not to interpret numbers.

The same bundle backs the analytics tests, so the examples and the tests
exercise identical input.

## See also

[`get_insample_fit_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_fit_table.md),
[`get_combined_cor_table()`](https://philippkronenberg.github.io/mfbdfm/reference/get_combined_cor_table.md),
[`get_insample_error_details()`](https://philippkronenberg.github.io/mfbdfm/reference/get_insample_error_details.md)

Other data preparation functions:
[`create_inventory()`](https://philippkronenberg.github.io/mfbdfm/reference/create_inventory.md),
[`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md),
[`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md)

## Examples

``` r
inputs <- mfbdfm_example_inputs()
names(inputs)
#>  [1] "tab_wai_yoy"   "wwa_gr_df"     "wwa_gr_df_qoq" "fcurve_gr_df" 
#>  [5] "tab_kss"       "tab_snb"       "tab_baro"      "tab_gr"       
#>  [9] "tab_gr_lv"     "x_hist_gr_yoy" "x_hist_gr_ann"
head(inputs$tab_gr)
#>         time name      value
#> 1 2010-01-07 mean -0.1411423
#> 2 2010-01-14 mean  1.1461937
#> 3 2010-01-21 mean  1.0491018
#> 4 2010-01-28 mean -1.3788422
#> 5 2010-02-04 mean -0.3073320
#> 6 2010-02-11 mean -1.2176606

# what it is for
fit_tabs <- get_insample_fit_table("mean", "indicators", inputs = inputs)
fit_tabs$RMSE
#> # A tibble: 12 × 7
#> # Groups:   Series [6]
#>    Frequency Series   `RMSE_Lag_-4` `RMSE_Lag_-3` `RMSE_Lag_-2` `RMSE_Lag_-1`
#>    <fct>     <fct>            <dbl>         <dbl>         <dbl>         <dbl>
#>  1 QoQ       WAI              0.499         0.515         0.484         0.489
#>  2 QoQ       SECO-WWA         0.508         0.494         0.493         0.531
#>  3 QoQ       F-CURVE          0.512         0.503         0.496         0.524
#>  4 QoQ       SECO-SEC         0.504         0.498         0.495         0.524
#>  5 QoQ       SNB-BCI          0.515         0.491         0.490         0.523
#>  6 QoQ       KOF-BARO         0.511         0.504         0.487         0.532
#>  7 YoY       WAI              1.11          1.16          1.15          1.14 
#>  8 YoY       SECO-WWA         1.16          1.17          1.15          1.15 
#>  9 YoY       F-CURVE          1.16          1.13          1.12          1.09 
#> 10 YoY       SECO-SEC         1.18          1.18          1.16          1.16 
#> 11 YoY       SNB-BCI          1.18          1.18          1.15          1.14 
#> 12 YoY       KOF-BARO         1.12          1.15          1.16          1.14 
#> # ℹ 1 more variable: RMSE_Lag_0 <dbl>
```
