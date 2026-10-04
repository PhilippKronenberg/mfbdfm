# Choose the number of factors with the Bai-Ng information criteria

Computes the Bai & Ng (2002) information criteria IC1, IC2 and IC3 for
factor counts `1:max_q`, together with the principal-component
eigenvalues and the share of panel variance each component explains. It
answers the question
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)'s
`q` argument poses and that the model itself gives no guidance on.

## Usage

``` r
select_factors(
  flows = NULL,
  stocks = NULL,
  target = NULL,
  max_q = 10,
  na_action = c("omit", "interpolate")
)
```

## Arguments

- flows:

  Either an
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  object carrying all series and their flow/stock classification, or a
  named list of `ts` objects treated as flow variables, or `NULL`. Must
  contain `target` if `stocks` does not.

- stocks:

  Named list of `ts` objects treated as stock variables, or `NULL`.

- target:

  Character, name of the series of interest, or `NULL` (the default).
  Accepted so that the same data specification works here and in
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
  and validated if supplied, but it does **not** enter the criteria – no
  series is treated specially by a principal-component decomposition.

- max_q:

  Integer, the largest factor count to evaluate. Must be smaller than
  both the number of series and the number of periods in the panel
  actually used.

- na_action:

  How to handle missing values in the retained highest-frequency block.
  `"omit"` (default) drops every period that is not fully observed;
  `"interpolate"` fills gaps within each series linearly and carries the
  nearest observed value outward at the ends.

## Value

An object of class `"select_factors"`: a list with components

- ic:

  Data frame with one row per evaluated factor count: `q`, `IC1`, `IC2`,
  `IC3`.

- q_hat:

  Named integer vector of length 3, the minimizer of each criterion.

- at_boundary:

  Character, the criteria whose minimum is `max_q` and which therefore
  did not settle. Empty when all three did.

- eigenvalues:

  Numeric, the eigenvalues of the panel's second-moment matrix, in
  decreasing order.

- var_explained, cum_var_explained:

  Numeric, the share of panel variance explained by each component and
  its cumulative sum.

- max_q:

  The `max_q` used.

- series:

  Character, the series the criteria were computed on.

- excluded:

  Character, the series dropped for being observed below the highest
  frequency.

- frequency:

  Numeric, the frequency of the retained block.

- n_series, n_obs:

  Panel dimensions after the reduction.

- n_dropped:

  Number of periods removed by `na_action = "omit"`.

- na_action:

  The `na_action` used.

- call:

  The matched call.

## What is actually computed, and on which data

The criteria are defined for a **balanced panel of one frequency**, so
the mixed-frequency input has to be reduced to one before they can be
applied. The reduction is deliberate and is reported by
[`print()`](https://rdrr.io/r/base/print.html):

1.  The series are standardized and aligned by
    [`prepare_data()`](https://philippkronenberg.github.io/mfbdfm/reference/prepare_data.md),
    exactly as they are for a model fit.

2.  **Only the series observed at the highest frequency are kept.** In a
    weekly WAI-style dataset that is the weekly block; the quarterly
    target and any monthly series are excluded. They are excluded rather
    than interpolated because in this model the low-frequency series are
    observed on a small fraction of the periods, so filling them in
    would put imputed values in most of their column and let an
    imputation rule, rather than the data, drive the criteria.

3.  Missing values in that block – the ragged edge, mostly – are removed
    by listwise deletion (`na_action = "omit"`, the default) or filled
    by linear interpolation within each series, carrying the nearest
    observed value outward at the ends (`na_action = "interpolate"`).

4.  The retained block is re-standardized column by column over the
    retained periods, and the criteria are computed from the singular
    values of the result.

With \\V(k)\\ the mean squared residual of the \\k\\-factor principal
component approximation of the \\T \times N\\ panel, the criteria are

\$\$IC_1(k) = \log V(k) + k \frac{N+T}{NT} \log\frac{NT}{N+T}\$\$
\$\$IC_2(k) = \log V(k) + k \frac{N+T}{NT} \log \min(N,T)\$\$
\$\$IC_3(k) = \log V(k) + k \frac{\log \min(N,T)}{\min(N,T)}\$\$

and the chosen `q` is the minimizer over `1:max_q`. The three differ
only in how hard they penalize an extra factor, IC3 most and IC1 least,
so they need not agree; when they do not, the disagreement is itself the
result and [`print()`](https://rdrr.io/r/base/print.html) shows all
three.

A minimum that sits on `max_q` is **not** a chosen factor count – the
criteria simply ran out of range – so it warns and
[`print()`](https://rdrr.io/r/base/print.html) says so. Raising `max_q`
is the first thing to try. If the minimum stays on the boundary however
high `max_q` goes, the panel is too narrow: the penalties are calibrated
for \\N\\ and \\T\\ both large, and with \\N\\ in the dozens the fall in
\\\log V(k)\\ can outrun them all the way to \\\min(N,T)\\. That happens
on the weekly block of the shipped `data_ch_dataset_test`, which is why
its example warns. Read the scree plot and the share of variance
explained instead.

## How much weight to put on the answer

These are **frequentist, principal-component criteria for an approximate
factor model**.
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
is a Bayesian mixed-frequency state-space model whose factors are
identified by a post-hoc rotation, and it is fitted on data the criteria
never see – the lower-frequency series, and the periods dropped at the
ragged edge. So the criteria **inform** `q`; they do not determine it.
Treat a disagreement between IC1 and IC3, or a scree plot with no clear
elbow, as a reason to fit more than one `q` and compare, not as a defect
in the criteria.

## References

Bai, J., & Ng, S. (2002). Determining the number of factors in
approximate factor models. *Econometrica*, 70(1), 191-221.
[doi:10.1111/1468-0262.00273](https://doi.org/10.1111/1468-0262.00273)

## See also

[select_factors_methods](https://philippkronenberg.github.io/mfbdfm/reference/select_factors_methods.md)
for [`print()`](https://rdrr.io/r/base/print.html),
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) and
[`screeplot()`](https://rdrr.io/r/stats/screeplot.html);
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
whose `q` this is for.

Other model fitting functions:
[`dfm_memory()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)

## Examples

``` r
data(data_ch_dataset_test)

# The shipped weekly block is 27 series, which is small for these criteria:
# all three are minimised at max_q, so this warns rather than reporting a
# settled factor count. That is the intended behaviour, not a failure.
sel <- select_factors(flows = data_ch_dataset_test$flows,
                      stocks = data_ch_dataset_test$stocks,
                      max_q = 8, na_action = "interpolate")
#> Warning: IC1/IC2/IC3 are minimised at `max_q` (8), so the minimum may lie beyond the range evaluated. Raise `max_q`; if the minimum stays on the boundary, the panel is too narrow for these criteria to settle - see `?select_factors`.
sel
#> Bai-Ng factor-count selection
#> 
#> Panel: 27 series at frequency 48, 1742 periods
#>        19 lower-frequency series excluded: ch.fso.rtt.ind.r.noga0801.sa, ch.seco.gdp.real.gdp.ssa, ch.ozd.e.wa.index.re.d11, ch.ozd.i.wa.index.re.d11, ...
#>        missing values: interpolate
#> 
#>  q       IC1       IC2       IC3 var % cum %
#>  1 -0.1380   -0.1375   -0.1393    23.0  23.0
#>  2 -0.2397   -0.2386   -0.2424    15.5  38.5
#>  3 -0.2863   -0.2845   -0.2902     9.6  48.1
#>  4 -0.2988   -0.2965   -0.3040     6.6  54.7
#>  5 -0.2976   -0.2947   -0.3041     5.2  59.9
#>  6 -0.3063   -0.3028   -0.3142     5.0  64.9
#>  7 -0.3167   -0.3127   -0.3259     4.4  69.3
#>  8 -0.3332 * -0.3286 * -0.3437 *   4.0  73.3
#> 
#> Chosen q:  IC1 = 8,  IC2 = 8,  IC3 = 8
#> IC1/IC2/IC3 are minimised at max_q = 8, so the minimum may lie beyond
#> the range evaluated. Raise `max_q`.
#> These are frequentist, principal-component criteria. They inform fcast_dfm()'s
#> `q`; they do not determine it.
sel$q_hat
#> IC1 IC2 IC3 
#>   8   8   8 
sel$at_boundary
#> [1] "IC1" "IC2" "IC3"
round(head(sel$cum_var_explained, 5), 3)
#> [1] 0.230 0.385 0.481 0.547 0.599
```
