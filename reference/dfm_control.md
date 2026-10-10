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

## Retaining draws

Both samplers hold every retained draw in memory for the whole fit
anyway; until \#110 they were averaged and discarded when the sampler
returned, so a fit carried posterior means and no chain. These settings
decide what survives into the fit object, not what is computed – nothing
here consumes RNG, and the numbers a fit reports are identical with them
on or off.

- `keep_draws`:

  Default `TRUE`. Stores the parameter and nowcast draws in `fit$draws`
  (see
  [mfbdfm_draws](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)),
  which is what
  [`mfbdfm_diagnostics()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_diagnostics.md)
  and the trace plots read. Small: one row per retained draw and one
  column per scalar parameter, plus one column per nowcast period – a
  few hundred kilobytes for a typical chain.

- `keep_factor_draws`:

  Default `FALSE`, because this is the one large component:
  `length_sample x (t+s) x q` doubles, which at 1000 draws of a weekly
  30-year sample is of the order of 10 MB per factor. On for the
  posterior of any functional of the factor path.

- `keep_burn_in`:

  Default `FALSE`,
  **[`ind_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm.md)
  only**. Retains the burn-in *parameter* draws as well, so a trace plot
  can show the chain settling rather than starting at the first kept
  draw.

`keep_burn_in` is absent from
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
deliberately, rather than accepted and ignored. That model identifies
post hoc: a draw is comparable with other draws only after the rotation
step has mapped it onto a reference computed from the *retained* draws,
and a burn-in draw has no such reference. Rotating the burn-in too would
either move that reference – and so change the results – or cost an
extra optimisation per burn-in draw, while storing it unrotated would
put a non-comparable series on a trace plot. Naming a setting the chosen
model does not have is an error, as with `phi_sum_max` and `omega_max`;
the parity rule is about the same *concept* in both models, and this
concept does not exist there.

## Verbosity

`verbose = FALSE` silences both the progress
[`message()`](https://rdrr.io/r/base/message.html)s and the
[`utils::txtProgressBar`](https://rdrr.io/r/utils/txtProgressBar.html).
The progress bar writes with [`cat()`](https://rdrr.io/r/base/cat.html),
so [`suppressMessages()`](https://rdrr.io/r/base/message.html) alone
does not quieten a fit – which is why this is a setting rather than
something a caller can arrange from outside. Use it for scripted sweeps
and for the worker processes planned by
[`dfm_workers()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_memory.md).

## Muffling one warning but not the others

The warnings a fit can raise repeatedly over a sweep carry their own
condition classes, so a single kind can be suppressed without hiding the
rest:

- `mfbdfm_warning_rho_fallback`:

  the measurement-error autocorrelation hit `rho_max_tries` redraws for
  at least one series and `rho_fallback` was substituted. Raised once
  per fit, with the number of substitutions.

- `mfbdfm_warning_rotation_cap`:

  the
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
  rotation (or its initialisation) stopped on its iteration cap rather
  than on convergence.

- `mfbdfm_warning_fit_failed`:

  a fit failed and
  [`run_fcast()`](https://philippkronenberg.github.io/mfbdfm/reference/run_fcast.md)`(on_error = "warn")`
  turned the error into a warning.

- `mfbdfm_warning_collinear`:

  two or more input series are near-perfectly correlated on their
  overlapping observed span. Raised once per fit, naming the pairs.
  Muffle it once you have decided the duplication is intended – see the
  "Near-collinear input series" section of
  [`mfbdfm_data()`](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_data.md)
  for what it costs you if it is not.

All of them also inherit from `mfbdfm_warning`. To muffle one:

    withCallingHandlers(
      fcast_dfm(flows = flows, stocks = stocks, target = target),
      mfbdfm_warning_rho_fallback = function(w) invokeRestart("muffleWarning")
    )

Substituting `mfbdfm_warning` for the class name muffles all of them.

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
[`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md),
[mfbdfm_draws](https://philippkronenberg.github.io/mfbdfm/reference/mfbdfm_draws.md)

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
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
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
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
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
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
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
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
#>   phi_sum_max              0.9       
#>   sigma_max                10          (default 5)
#>   keep_burn_in             FALSE     

# silence the messages and the progress bar
dfm_control("ind_dfm", verbose = FALSE)
#> Control settings for ind_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   verbose                  FALSE       (default TRUE)
#>   keep_draws               TRUE      
#>   keep_factor_draws        FALSE     
#>   phi_sum_max              0.9       
#>   sigma_max                5         
#>   keep_burn_in             FALSE     

# keep the factor-path draws too, and the burn-in, for trace plots
dfm_control("ind_dfm", keep_factor_draws = TRUE, keep_burn_in = TRUE)
#> Control settings for ind_dfm()
#> 
#>   rho_max                  0.99      
#>   rho_max_tries            10        
#>   rho_fallback             0.98      
#>   jitter                   1e-09     
#>   sv_offset                0.001     
#>   verbose                  TRUE      
#>   keep_draws               TRUE      
#>   keep_factor_draws        TRUE        (default FALSE)
#>   phi_sum_max              0.9       
#>   sigma_max                5         
#>   keep_burn_in             TRUE        (default FALSE)
```
