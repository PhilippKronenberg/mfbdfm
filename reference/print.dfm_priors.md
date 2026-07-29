# Print a prior specification

Print a prior specification

## Usage

``` r
# S3 method for class 'dfm_priors'
print(x, ...)
```

## Arguments

- x:

  An object of class `"dfm_priors"` from
  [`dfm_priors()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_priors.md).

- ...:

  Ignored, present for compatibility with the
  [`print()`](https://rdrr.io/r/base/print.html) generic.

## Value

`x`, invisibly.

## Examples

``` r
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
```
