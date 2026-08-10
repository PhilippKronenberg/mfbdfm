# Numerical and algorithmic settings for the samplers

Bundles the numerical and algorithmic knobs that were previously
hard-coded inside the samplers: the rotation stopping rule, the
stability bounds that reject or cap a draw, and two numerical guards.
Passing a control object is **optional** – omit it and the defaults
reproduce the published behaviour exactly.

## Usage

``` r
dfm_control(model = c("ind_dfm", "fcast_dfm"), strict = FALSE, ...)
```

## Arguments

- model:

  Character, which model the settings are for: `"ind_dfm"` or
  `"fcast_dfm"`. Determines which knobs are present, since the two
  samplers do not share all of them.

- strict:

  Logical. If `TRUE`, sets the rotation to the published algorithm –
  `rotation_criterion = "sum"`, `rotation_max_iter` raised, and failure
  to converge becomes an **error** rather than a warning. A single
  switch for "run it the way the paper specifies". Ignored by
  [`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).

- ...:

  Named overrides for individual settings, e.g.
  `rotation_criterion = "sum"` or `sigma_max = 10`. Naming a setting the
  chosen model does not have is an error, so a typo surfaces
  immediately.

## Value

An object of class `"dfm_control"`: a named list of settings plus
`model` and `strict`.

## What is and is not here

This holds settings that affect *how* the sampler searches, not *what
model* it fits. Priors live in
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md);
model structure is in the arguments of
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
and
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

Deliberately absent: initial values, and the numerical conditioning
constants that are not choices (the `1e-9` ridge that encodes
"effectively zero" autocorrelation when `serial_correlation = FALSE`,
and the `pi - 1e-16` domain guard on the Givens angles).

## The rotation stopping rule

Only
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
rotates, so `rotation_*` is ignored by
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md).

Appendix E of the online appendix to Eckert et al. (2025), following
Assmann, Boysen-Hogrefe & Pape (2016), specifies convergence when the
**sum** of squared deviations between successive `theta*` falls below
`1e-9`. The implementation has always tested the **mean**, which over a
packed vector of several thousand elements is a much weaker requirement,
and additionally capped the loop at five iterations.
`rotation_criterion = "sum"` restores the published rule.

Measured on a small two-factor fit, convergence is geometric at roughly
an order of magnitude per iteration: the mean criterion converged at
iteration 5 and the sum criterion at iteration 6. Matching the paper
therefore costs about one extra iteration, not the blow-up the
difference in thresholds suggests. Note also that the default cap of 5
sits *exactly* on that convergence point, so on other data it can bind
and truncate the loop – which is why a binding cap warns.

`rotation_max_iter` and `rotation_init_max_iter` are safety valves, not
targets. They default high enough not to bind in practice (100 against
5-7 observed) while still guaranteeing the loop terminates. `Inf` is not
accepted: an unbounded loop has no termination guarantee, and a
non-converging rotation should stop and complain rather than run
forever.

## Stability bounds

`rho_max` bounds the measurement-error autocorrelation. A draw outside
it is redrawn up to `rho_max_tries` times, after which `rho_fallback` is
used. The others cap or reject a draw for numerical stability:
`phi_sum_max` and `sigma_max` in
[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
`omega_max` in
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

## References

Assmann, C., Boysen-Hogrefe, J., & Pape, M. (2016). Bayesian analysis of
static and dynamic factor models with an unknown number of factors, and
structural instability. *Journal of Applied Econometrics*, 31(8),
1518-1533.

Eckert, F., Kronenberg, P., Mikosch, H., & Neuwirth, S. (2025). Tracking
economic activity with alternative high-frequency data. *Journal of
Applied Econometrics*, 40(3), 270-290.
[doi:10.1002/jae.3104](https://doi.org/10.1002/jae.3104)

## See also

[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md),
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)

Other model specification:
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md)

## Examples

``` r
dfm_control("fcast_dfm")
#> Control settings for fcast_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   omega_max                1         
#>   rotation_criterion       "mean"    
#>   rotation_tol             1e-09     
#>   rotation_max_iter        5         
#>   rotation_init_tol        1e-09     
#>   rotation_init_max_iter   100       
#>   rotation_on_failure      "warning" 
#> 
#>   Note: rotation_criterion "mean" is weaker than the published rule.
#>   dfm_control("fcast_dfm", strict = TRUE) matches Eckert et al. (2025).

# the published rotation rule
dfm_control("fcast_dfm", strict = TRUE)
#> Control settings for fcast_dfm()  [strict: published rotation rule]
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   omega_max                1         
#>   rotation_criterion       "sum"       (default "mean")
#>   rotation_tol             1e-09     
#>   rotation_max_iter        100         (default 5)
#>   rotation_init_tol        1e-09     
#>   rotation_init_max_iter   100       
#>   rotation_on_failure      "error"     (default "warning")

# or one setting at a time
dfm_control("fcast_dfm", rotation_criterion = "sum", rotation_tol = 1e-10)
#> Control settings for fcast_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   omega_max                1         
#>   rotation_criterion       "sum"       (default "mean")
#>   rotation_tol             1e-10       (default 1e-09)
#>   rotation_max_iter        5         
#>   rotation_init_tol        1e-09     
#>   rotation_init_max_iter   100       
#>   rotation_on_failure      "warning" 
dfm_control("ind_dfm", sigma_max = 10)
#> Control settings for ind_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   phi_sum_max              0.9       
#>   sigma_max                10          (default 5)
```
