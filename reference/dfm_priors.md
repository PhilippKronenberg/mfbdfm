# Specify the prior distributions for a dynamic factor model

Builds the prior specification passed to
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
or
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).
The defaults reproduce each model's published prior exactly, so
`dfm_priors(model)` changes nothing; the object exists so that priors
can be inspected and varied deliberately rather than edited in the
sampler source.

## Usage

``` r
dfm_priors(
  model = c("ind_dfm", "fcast_dfm"),
  type = c("default", "uninformative", "informative"),
  ...
)
```

## Arguments

- model:

  Character, which model the priors are for: `"ind_dfm"` or
  `"fcast_dfm"`. The two models take different priors, and passing a set
  built for one to the other is an error.

- type:

  Character, the overall strength of the tunable priors: `"default"`
  (the published values), `"uninformative"` (minimal prior information,
  letting the data dominate) or `"informative"` (more shrinkage). Does
  not affect structural priors – see Details.

- ...:

  Named overrides for individual priors, each a list of the entries
  shown by printing the returned object, e.g.
  `sigma_other = list(c0 = 3, d0 = 1e-3)`. Naming a structural prior is
  allowed but warns.

## Value

An object of class `"dfm_priors"`: a named list with an entry per prior,
plus `model`, `type`, and a `structural_modified` flag recording whether
any identifying prior was overridden.

## Structural versus tunable priors

Some priors are not tuning knobs – they *are* the model's
identification, and changing them changes what the estimates mean:

- `ind_dfm`:

  The target series' measurement-error variance (`sigma_target`, prior
  sample size `t` and scale `t * 1e-3`) and its serial correlation
  (`rho_target`, prior variance `1e-9`) are what force the augmented
  target to reproduce the observed series, which is what makes the
  factor interpretable as the target's growth rate. Loosening them
  dissolves that anchoring.

- `fcast_dfm`:

  The loading prior (`lambda`) must stay diffuse (`B0 = 1e9`);
  restricting it conflicts with the post-hoc rotation that identifies
  the model.

`type` therefore moves **tunable priors only**. Structural priors can
still be set, by naming them explicitly in `...`, but doing so emits a
warning: the resulting fit is a different model from the published one.

## Priors that depend on the data

Several defaults scale with the sample length `t` or the number of lags
`p`, which are not known until the data have been prepared. Those
entries are stored as `NULL`, meaning "use the model's rule", and are
resolved inside the sampler. Supplying a number instead overrides the
rule with a literal value.

## Interpreting the inverse-gamma priors

Variance priors are inverse-gamma, written so that the posterior update
is `c1 = c0 + t` and `d1 = d0 + sum(residuals^2)`. So `c0` is a prior
sample size in pseudo-observations, `d0` is the sum of squares they
carry, and `d0 / c0` is roughly the prior's guess at the variance.

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)

Other model specification:
[`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md)

## Examples

``` r
# the defaults reproduce the published priors
dfm_priors("ind_dfm")
#> Priors for ind_dfm()  [type: default]
#> 
#>   sigma_target  c0 = <from data>, d0 = <from data>  [structural]
#>   rho_target    r0 = 0, R0 = 1e-09  [structural]
#>   sigma_other   c0 = 3, d0 = 0.05
#>   rho_other     r0 = 0, R0 = 5
#>   lambda        b0 = 0, B0 = 1
#>   phi           a0 = 0, A0 = <from data>
#>   omega         k0 = <from data>, l0 = <from data>
#>   factor_var    c0 = 3, d0 = 0.01
#> 
#> <from data> entries follow the model's published rule in terms of t or p.

# let the data speak more
dfm_priors("ind_dfm", type = "uninformative")
#> Priors for ind_dfm()  [type: uninformative]
#> 
#>   sigma_target  c0 = <from data>, d0 = <from data>  [structural]
#>   rho_target    r0 = 0, R0 = 1e-09  [structural]
#>   sigma_other   c0 = 3, d0 = 1e-09
#>   rho_other     r0 = 0, R0 = 1000
#>   lambda        b0 = 0, B0 = 1000
#>   phi           a0 = 0, A0 = 1000
#>   omega         k0 = 3, l0 = 1e-09
#>   factor_var    c0 = 3, d0 = 1e-09
#> 
#> <from data> entries follow the model's published rule in terms of t or p.

# override one tunable prior
dfm_priors("fcast_dfm", sigma = list(c0 = 3, d0 = 1e-6))
#> Priors for fcast_dfm()  [type: default]
#> 
#>   lambda        b0 = 0, B0 = 1e+09  [structural]
#>   sigma         c0 = 3, d0 = 1e-06
#>   rho           r0 = 0, R0 = <from data>
#>   omega         c0 = 3, d0 = 1
#> 
#> <from data> entries follow the model's published rule in terms of t or p.
```
