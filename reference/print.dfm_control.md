# Print a dfm_control object

Print a dfm_control object

## Usage

``` r
# S3 method for class 'dfm_control'
print(x, ...)
```

## Arguments

- x:

  An object of class `"dfm_control"` from
  [`dfm_control()`](https://philippkronenberg.github.io/mfbdfm/reference/dfm_control.md).

- ...:

  Ignored, present for compatibility with the
  [`print()`](https://rdrr.io/r/base/print.html) generic.

## Value

`x`, invisibly.

## Examples

``` r
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
```
