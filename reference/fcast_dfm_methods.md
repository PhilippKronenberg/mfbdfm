# Methods for multi-factor model fits

The generics supported by a
[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md)
fit. These mirror the single-factor methods exactly – see
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
for what each one does and for why there is no
[`predict()`](https://rdrr.io/r/stats/predict.html) method.

## Usage

``` r
# S3 method for class 'fcast_dfm'
print(x, n_show = 8, ...)

# S3 method for class 'fcast_dfm'
coef(object, ...)

# S3 method for class 'fcast_dfm'
fitted(object, ...)

# S3 method for class 'fcast_dfm'
residuals(object, ...)

# S3 method for class 'fcast_dfm'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S3 method for class 'fcast_dfm'
plot(x, ...)

# S3 method for class 'fcast_dfm'
summary(object, ...)
```

## Arguments

- n_show:

  Integer, how many of the most recent periods
  [`print()`](https://rdrr.io/r/base/print.html) shows.

- ...:

  Ignored, present for compatibility with the generics.

- object, x:

  A fit from
  [`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md).

- row.names, optional:

  Ignored, present for compatibility with the
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html)
  generic.

## Value

As
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md),
except that [`coef()`](https://rdrr.io/r/stats/coef.html) returns a
matrix.

## Details

[`coef()`](https://rdrr.io/r/stats/coef.html) returns an `n x q` loading
matrix here rather than a vector, and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) returns
one mean/lower/upper triple per factor.

## See also

[`fcast_dfm()`](https://philippkronenberg.github.io/mfbdfm/reference/fcast_dfm.md),
[ind_dfm_methods](https://philippkronenberg.github.io/mfbdfm/reference/ind_dfm_methods.md)
