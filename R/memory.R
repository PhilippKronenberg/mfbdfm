#' Estimate the peak memory of a model fit, and size a parallel run from it
#'
#' `dfm_memory()` predicts the peak heap one [fcast_dfm()] fit will occupy, from
#' the dimensions of the data and the length of the chain. `dfm_workers()` turns
#' that into the number of parallel workers a machine can actually carry.
#'
#' @details
#' Vintage sweeps are parallelised over dates, and the binding constraint is
#' memory rather than cores: a machine with 16 cores runs out of RAM long before
#' it runs out of cores, and the failure mode is an opaque
#' `CHOLMOD error 'out of memory'` from deep inside the sparse solver, hours
#' into a run. This exists so the worker count can be derived rather than
#' guessed.
#'
#' # The model
#'
#' Peak memory is fitted as
#'
#' \deqn{a + b \cdot G + c \cdot D}
#'
#' where \eqn{G} is the footprint of the observation matrix `Gmat`
#' (`q(t-1)n(s+2)` nonzeros at 12 bytes each) and \eqn{D} is the footprint of
#' the retained draws (`length_sample` rows of `nq + pq^2 + 2n + nt + t + s`
#' doubles). The fitted coefficients say the fit holds about **6.2 live copies
#' of `Gmat`** and **1.9 copies of the draw matrix**, over a fixed **267 MB** of
#' R and package overhead.
#'
#' **Memory is linear in `q`, not quadratic.** The natural guess is that the
#' sparse Cholesky of the `q(t+s)` square factor precision matrix dominates,
#' which would scale with `q^2`. Measured, it does not: adding that term to the
#' regression does not improve it, because the `Gmat` working set is an order of
#' magnitude larger. Doubling the factor count costs roughly one extra `Gmat`
#' worth of working set, not four.
#'
#' # Calibration
#'
#' Fitted to six fits measured one per fresh R process (the GC high-water mark
#' is per process, so several in one session would report only their maximum) at
#' `n = 53`, `t = 1559`, `s = 22`: `q = 1..4` at `length_sample = 30`, and
#' `q = 2` at `length_sample = 30, 120, 240`. Adjusted R-squared 0.98, largest
#' residual 34 MB.
#'
#' Validated out of sample against a fit on a **different** dataset and a
#' different version of the code (`n = 43`, `t = 1464`, `q = 2`,
#' `length_sample = 200`): 690 MB predicted against 744 MB measured, a 7% error.
#'
#' Treat it as accurate to roughly 10%, which is why `dfm_workers()` applies a
#' safety factor rather than dividing exactly. The constants are specific to
#' this package's samplers; they were measured on x86_64 Windows and will drift
#' if the samplers' allocation pattern changes. `dev/calibrate-memory.R`
#' regenerates them.
#'
#' Calibrated on [fcast_dfm()]. [ind_dfm()] is a different sampler with no
#' post-hoc rotation and no packed draw matrix, and has **not** been measured
#' here.
#'
#' @param flows,stocks Named lists of `ts` objects, or an [mfbdfm_data()] object
#'   as `flows`. Supply these to have the dimensions derived from the data. If
#'   `NULL`, give `n`, `t` and `s` directly.
#' @param n Integer, number of series. Derived from the data when supplied.
#' @param t Integer, number of high-frequency periods **before** `extend`.
#'   Derived from the data when supplied.
#' @param s Integer, `2 * (k - 1)` where `k` is the ratio of highest to lowest
#'   frequency. Derived from the data when supplied.
#' @param q Integer, number of factors.
#' @param p Integer, number of lags in the factor VAR.
#' @param length_sample Integer, number of posterior draws **kept** (`thinning`
#'   does not enter: it changes how long the chain runs, not how much is
#'   stored).
#' @param extend Numeric, the `extend` argument the fit will be given, in years.
#'   Lengthens the sample the sampler sees and so the memory it needs.
#' @param frequency Integer, observations per year of the highest-frequency
#'   series, used with `extend`. Derived from the data when supplied.
#'
#' @return `dfm_memory()`: estimated peak memory for one fit, in MB (numeric,
#'   length 1). `dfm_workers()`: the number of workers (integer, length 1, at
#'   least 1), with the estimate and the budget it used attached as attributes.
#'
#' @examples
#' # from dimensions
#' dfm_memory(n = 53, t = 1535, s = 22, q = 2, length_sample = 500)
#'
#' # the whole point: how many workers fit in 24 GB
#' dfm_workers(n = 53, t = 1535, s = 22, q = 4, length_sample = 500,
#'             available_mb = 24 * 1024)
#'
#' # from the data itself
#' data(data_ch_dataset_test)
#' dfm_memory(flows = data_ch_dataset_test$flows,
#'            stocks = data_ch_dataset_test$stocks,
#'            q = 2, length_sample = 1000)
#'
#' @seealso [fcast_dfm()]
#' @family model fitting functions
#' @importFrom stats frequency
#' @export
dfm_memory <- function(flows = NULL, stocks = NULL,
                       n = NULL, t = NULL, s = NULL,
                       q = 2, p = 1, length_sample = 1000,
                       extend = 0.5, frequency = NULL){

  dims <- resolve_dims(flows, stocks, n, t, s, frequency)

  if(!is_count(q) || q < 1) stop("`q` must be a single positive whole number.", call. = FALSE)
  if(!is_count(p) || p < 1) stop("`p` must be a single positive whole number.", call. = FALSE)
  if(!is_count(length_sample) || length_sample < 1){
    stop("`length_sample` must be a single positive whole number.", call. = FALSE)
  }
  if(!is.numeric(extend) || length(extend) != 1 || !is.finite(extend) || extend < 0){
    stop("`extend` must be a single non-negative number.", call. = FALSE)
  }

  n <- dims$n; s <- dims$s
  t_eff <- dims$t + round(extend * dims$frequency)

  gmat_mb  <- q * (t_eff - 1) * n * (s + 2) * 12 / 1e6
  draws_mb <- length_sample * (n * q + p * q^2 + 2 * n + n * t_eff + (t_eff + s)) * 8 / 1e6

  unname(MEM_FIXED_MB + MEM_GMAT_COPIES * gmat_mb + MEM_DRAW_COPIES * draws_mb)

}


#' @rdname dfm_memory
#'
#' @param available_mb Numeric, memory to plan against, in MB. Defaults to the
#'   machine's currently **free** memory, not its total -- whatever else is
#'   running is not available to the sweep.
#' @param safety Numeric in (0, 1], the fraction of `available_mb` to commit.
#'   The default 0.7 leaves room for the estimate's ~10% error, for the
#'   allocator's inability to reuse freed blocks immediately, and for the
#'   process that launched the workers.
#' @param max_workers Integer, an upper bound (defaults to the core count).
#' @param ... Passed to `dfm_memory()`.
#'
#' @export
dfm_workers <- function(..., available_mb = NULL, safety = 0.7,
                        max_workers = NULL){

  if(!is.numeric(safety) || length(safety) != 1 || safety <= 0 || safety > 1){
    stop("`safety` must be a single number in (0, 1].", call. = FALSE)
  }

  per_fit <- dfm_memory(...)

  if(is.null(available_mb)) available_mb <- free_memory_mb()
  if(is.null(max_workers)) max_workers <- parallel::detectCores(logical = FALSE)
  if(is.na(max_workers) || max_workers < 1) max_workers <- 1L

  n_workers <- floor(available_mb * safety / per_fit)
  # at least one: a machine that cannot hold a single fit will fail either way,
  # and failing inside the fit gives a better error than returning zero workers
  n_workers <- max(1L, min(as.integer(n_workers), as.integer(max_workers)))

  structure(n_workers,
            per_fit_mb = per_fit,
            available_mb = available_mb,
            budget_mb = available_mb * safety)

}


# Fitted constants; see ?dfm_memory and dev/calibrate-memory.R.
MEM_FIXED_MB     <- 267
MEM_GMAT_COPIES  <- 6.22
MEM_DRAW_COPIES  <- 1.92


#' Dimensions for the memory model, from data or from explicit arguments
#'
#' @noRd
resolve_dims <- function(flows, stocks, n, t, s, frequency){

  if(!is.null(flows)){
    d <- resolve_data_arg(flows, stocks, NULL)
    inv <- create_inventory(flows = d$flows, stocks = d$stocks)
    # prepare_data() rather than a shortcut: t is the length of the aligned,
    # trimmed matrix the sampler actually sees, which no simpler expression of
    # the inputs gives
    Ymat <- prepare_data(d$flows, d$stocks, inv,
                         target = c(names(d$flows), names(d$stocks))[1])
    k <- max(inv$freq) / min(inv$freq)
    return(list(n = ncol(Ymat), t = nrow(Ymat), s = 2 * (k - 1),
                frequency = max(inv$freq)))
  }

  missing_dims <- c("n", "t", "s")[c(is.null(n), is.null(t), is.null(s))]
  if(length(missing_dims)){
    stop("Supply either `flows`/`stocks`, or all of `n`, `t` and `s`. Missing: ",
         paste(missing_dims, collapse = ", "), ".", call. = FALSE)
  }
  for(nm in c("n", "t", "s")){
    v <- get(nm)
    if(!is_count(v) || v < 1){
      stop("`", nm, "` must be a single positive whole number.", call. = FALSE)
    }
  }
  if(is.null(frequency)) frequency <- 48

  list(n = n, t = t, s = s, frequency = frequency)

}


#' Free physical memory in MB, or NA when it cannot be determined
#'
#' @noRd
free_memory_mb <- function(){

  out <- NA_real_

  if(.Platform$OS.type == "windows"){
    # PowerShell rather than wmic: wmic is deprecated and absent from current
    # Windows builds, where it fails silently rather than reporting anything.
    # memory.limit() is no help either, having been removed in R 4.2.
    x <- try(suppressWarnings(system2(
      "powershell",
      c("-NoProfile", "-Command",
        "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"),
      stdout = TRUE, stderr = FALSE)), silent = TRUE)
    if(!inherits(x, "try-error") && length(x)){
      kb <- suppressWarnings(as.numeric(trimws(x[nzchar(trimws(x))][1])))
      if(is.finite(kb)) out <- kb / 1024
    }
  } else if(file.exists("/proc/meminfo")){
    mi <- readLines("/proc/meminfo", warn = FALSE)
    hit <- grep("^MemAvailable:", mi, value = TRUE)
    if(length(hit)) out <- as.numeric(gsub("[^0-9]", "", hit[1])) / 1024
  }

  if(!is.finite(out)){
    stop("Could not determine free memory on this platform; pass ",
         "`available_mb` explicitly.", call. = FALSE)
  }

  out

}
