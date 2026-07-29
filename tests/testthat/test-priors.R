# dfm_priors() must (a) reproduce the published priors by default, (b) actually
# change the fit when altered, and (c) protect the priors that carry each
# model's identification.

test_that("dfm_priors returns a model-specific, classed specification", {
  p <- dfm_priors("ind_dfm")
  expect_s3_class(p, "dfm_priors")
  expect_equal(p$model, "ind_dfm")
  expect_equal(p$type, "default")
  expect_true(all(c("sigma_target", "rho_target", "sigma_other", "rho_other",
                    "lambda", "phi", "omega", "factor_var") %in% names(p)))

  q <- dfm_priors("fcast_dfm")
  expect_equal(q$model, "fcast_dfm")
  expect_true(all(c("lambda", "sigma", "rho", "omega") %in% names(q)))
  # the two models take different prior sets
  expect_false(setequal(names(p), names(q)))
})

test_that("the published defaults are reproduced exactly", {
  p <- resolve_priors(dfm_priors("ind_dfm"), t = 400, p = 2)
  expect_equal(p$sigma_target$c0, 400)          # c0 = t
  expect_equal(p$sigma_target$d0, 400 * 1e-3)   # d0 = t * 1e-3
  expect_equal(p$sigma_other$c0, 3)
  expect_equal(p$sigma_other$d0, 5e-2)
  expect_equal(p$rho_target$R0, 1e-9)
  expect_equal(p$rho_other$R0, 5)
  expect_equal(p$lambda$B0, 1)
  expect_equal(p$phi$A0, 0.12 / ((1:2)^2))      # decay preserved
  expect_equal(p$omega$k0, 400)
  expect_equal(p$omega$l0, 400 * 1e-2)

  q <- resolve_priors(dfm_priors("fcast_dfm"), t = 400, p = 1)
  expect_equal(q$lambda$B0, 1e9)
  expect_equal(q$sigma$d0, 1e-9)
  expect_equal(q$rho$R0, 1/400)                 # R0 = 1/t
  expect_equal(q$omega$d0, 1)
})

test_that("type moves tunable priors but never the structural ones", {
  d <- dfm_priors("ind_dfm", type = "default")
  u <- dfm_priors("ind_dfm", type = "uninformative")
  i <- dfm_priors("ind_dfm", type = "informative")

  # tunable priors move
  expect_false(identical(d$sigma_other, u$sigma_other))
  expect_false(identical(d$sigma_other, i$sigma_other))

  # structural priors do not
  for (nm in d$structural) {
    expect_identical(d[[nm]], u[[nm]])
    expect_identical(d[[nm]], i[[nm]])
  }

  # same for the multi-factor model's diffuse loading prior
  expect_identical(dfm_priors("fcast_dfm")$lambda,
                   dfm_priors("fcast_dfm", type = "uninformative")$lambda)
})

test_that("overriding a structural prior warns and is flagged", {
  expect_warning(dfm_priors("ind_dfm", sigma_target = list(d0 = 1)),
                 "changes how `ind_dfm` is identified")
  expect_warning(dfm_priors("fcast_dfm", lambda = list(B0 = 1)),
                 "changes how `fcast_dfm` is identified")

  p <- suppressWarnings(dfm_priors("ind_dfm", sigma_target = list(d0 = 1)))
  expect_true(p$structural_modified)
  expect_equal(p$sigma_target$d0, 1)

  # a tunable override is silent and not flagged
  expect_silent(q <- dfm_priors("ind_dfm", sigma_other = list(d0 = 1e-3)))
  expect_false(q$structural_modified)
})

test_that("invalid prior specifications are rejected informatively", {
  expect_error(dfm_priors("ind_dfm", nonsense = list(a = 1)), "Unknown prior")
  expect_error(check_priors(dfm_priors("fcast_dfm"), "ind_dfm"),
               "built for model")
  expect_error(check_priors(list(a = 1), "ind_dfm"), "must be built with")
})

test_that("priors reach the sampler and change the fit", {
  data(data_ch_dataset_test, envir = environment())
  target <- "ch.seco.gdp.real.gdp.ssa"
  flows <- lapply(data_ch_dataset_test$flows[c(target, "SWISSMI")],
                  stats::window, start = 2020)
  stocks <- lapply(data_ch_dataset_test$stocks[1:2], stats::window, start = 2020)

  fit <- function(pr) {
    set.seed(4)
    suppressMessages(ind_dfm(flows = flows, stocks = stocks, target = target,
                             length_sample = 8, burn_in = 4, plots = FALSE,
                             priors = pr))
  }

  base <- fit(dfm_priors("ind_dfm"))
  alt <- fit(dfm_priors("ind_dfm", type = "uninformative"))

  # different priors must give a different answer, or they are not being used
  expect_false(identical(base$factor, alt$factor))

  # and a prior set for the other model is refused
  expect_error(fit(dfm_priors("fcast_dfm")), "built for model")
})

test_that("print.dfm_priors is registered and returns invisibly", {
  p <- dfm_priors("ind_dfm")
  expect_output(print(p), "Priors for ind_dfm")
  expect_output(print(p), "structural")
  expect_output(print(p), "from data")
  expect_false(withVisible(print(p))$visible)
})
