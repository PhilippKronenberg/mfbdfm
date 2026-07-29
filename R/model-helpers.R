#' Build an inventory of the model input series
#'
#' Combines the flow and stock series lists into a data frame describing
#' each series: its name, type, frequency, and the mean and standard
#' deviation used for standardization in [prepare_data()].
#'
#' @param flows Named list of `ts` objects treated as flow variables, or
#'   `NULL` for a model with no flow variables.
#' @param stocks Named list of `ts` objects treated as stock variables, or
#'   `NULL` for a model with no stock variables.
#'
#' @return A data frame with one row per series and columns `key` (series
#'   name), `type` (factor, `"flow"` or `"stock"`), `freq` (observations
#'   per year), `mean` and `sd` (moments of the raw series, NA-removed).
#'
#' @examples
#' data(data_ch_dataset_test)
#' inv <- create_inventory(flows = data_ch_dataset_test$flows,
#'                         stocks = data_ch_dataset_test$stocks)
#' head(inv)
#'
#' @importFrom stats frequency sd
#' @export
create_inventory <- function(flows, stocks){

  # construct inventory of time series. Each block is skipped entirely when
  # that side is NULL, so a model can be specified with flows only or stocks
  # only; rbind() drops NULL arguments, so the non-NULL block is returned
  # unchanged and the both-supplied case is byte-for-byte as before.
  if(is.null(flows)){
    df_flows <- NULL
  } else {
    df_flows <- data.frame("key" = as.character(names(flows)),
                           "type" = factor("flow", levels = c("stock","flow")),
                           "freq" = sapply(flows, frequency),
                           "mean" = sapply(flows, mean, na.rm=TRUE),
                           "sd" = sapply(flows, sd, na.rm=TRUE),
                           stringsAsFactors = FALSE,
                           row.names = NULL)
  }

  if(is.null(stocks)){
    df_stocks <- NULL
  } else {
    df_stocks <- data.frame("key" = names(stocks),
                            "type" = factor("stock", levels = c("stock","flow")),
                            "freq" = sapply(stocks, frequency),
                            "mean" = sapply(stocks, mean, na.rm=TRUE),
                            "sd" = sapply(stocks, sd, na.rm=TRUE),
                            stringsAsFactors = FALSE,
                            row.names = NULL)
  }

  inventory <- rbind(df_flows, df_stocks)

  # remove NULL entires
  if(length(which(inventory$key == "") > 0)) inventory <- inventory[-which(inventory$key == ""),]

  return(inventory)

}


#' Standardize and align mixed-frequency series into one matrix
#'
#' Standardizes each series using the moments from the inventory, aligns
#' all series on the highest-frequency time grid, and returns a single
#' multivariate `ts` matrix in which missing observations are encoded as
#' zero (as expected by the [ind_dfm()] sampler).
#'
#' @param flows Named list of `ts` objects treated as flow variables.
#' @param stocks Named list of `ts` objects treated as stock variables.
#' @param inventory Data frame from [create_inventory()].
#' @param target Character, name of the target series (currently unused
#'   here; kept for interface stability).
#'
#' @return A multivariate `ts` at the highest input frequency with one
#'   column per series; missing values are encoded as `0`.
#'
#' @examples
#' data(data_ch_dataset_test)
#' inv <- create_inventory(flows = data_ch_dataset_test$flows,
#'                         stocks = data_ch_dataset_test$stocks)
#' Ymat <- prepare_data(flows = data_ch_dataset_test$flows,
#'                      stocks = data_ch_dataset_test$stocks,
#'                      inventory = inv,
#'                      target = "ch.seco.gdp.real.gdp.ssa")
#' dim(Ymat)
#'
#' @importFrom dplyr left_join
#' @importFrom zoo na.trim
#' @importFrom stats ts time frequency
#' @export
prepare_data <- function(flows, stocks, inventory, target){

  data <- c(flows, stocks)

  # standardize data
  data_std <- lapply(inventory$key, function(ix){

    (data[[ix]] - inventory[which(inventory$key == ix),"mean"])/
      inventory[which(inventory$key == ix),"sd"]

  }); names(data_std) <- inventory$key

  # adjust time periods
  freq_max <- max(sapply(data, frequency))

  data_adj <- lapply(inventory$key, function(ix){

    tim <- time(data_std[[ix]]) + (freq_max/frequency(data_std[[ix]]) - 1)/freq_max
    out <- as.data.frame(cbind(round(tim,5), data_std[[ix]]))
    colnames(out) <- c("time",ix)

    return(out)

  }); names(data_adj) <- inventory$key

  # coerce to sparse matrix
  idx = data.frame("time" = round(seq(1900, 2100, 1/freq_max),5))

  dfs <- lapply(data_adj, function(fx){

    tab <- left_join(idx, fx, by = "time")
    tab[,-1]

  })

  dfs <- do.call(cbind,dfs)
  colnames(dfs) <- inventory$key
  dfts <- ts(dfs, start = 1900, frequency = max(sapply(data, function(x) frequency(x))))
  dfts <- na.trim(dfts, is.na = "all")

  dfts[which(is.na(dfts))] <- 0

  return(dfts)

}


#' Distributed lag matrices for the temporal aggregation rule
#'
#' @noRd
get_distributed_lags <- function(inventory){

  # frequencies
  k <- max(inventory$freq)/min(inventory$freq) # Redundant, can be imported from previous function
  s <- 2*(k - 1) #  Redundant, can be imported from previous function

  lmat <- matrix(0, nrow(inventory), s+1)
  freqs <- inventory$freq

  for(ix in 1:nrow(lmat)){

    if(inventory[ix,"type"] == "flow"){

      a <- max(freqs)/freqs[ix]
      b <- c(1:a,a:1)[-a]/a
      lmat[ix,1:length(b)] <- b

    } else {

      a <- max(freqs)/freqs[ix]
      b <- rep(1/a, a)
      lmat[ix,1:length(b)] <- b

    }
  }

  # distributed lag matrices
  out <- lapply(1:ncol(lmat), function(sx) Diagonal(x = lmat[,sx]))
  names(out) <- as.character(0:s)

  return(out)

}


#' Regressor matrix for the factor loading draw
#'
#' @details
#' Every `Llist` entry and `rho` are diagonal (see [get_distributed_lags()]),
#' so each `aux` term below is diagonal too, and therefore every `n x n`
#' block of the result is diagonal: the whole `((t-1)*n) x n` matrix holds
#' only `(t-1)*n` nonzeros, one per row. Rather than forming `s+2` Kronecker
#' products of that full size and summing them (which dominated sampler
#' runtime), the block diagonals are accumulated into a small dense
#' `(t-1) x n` matrix and the sparse result is assembled directly from it.
#'
#' The accumulation deliberately runs in the same `sx` order, with the same
#' per-element multiply-then-add sequence, as the original
#' `Reduce("+", lapply(...))` - floating-point addition is not associative,
#' so preserving that order is what keeps the result bit-identical.
#'
#' @noRd
get_zmat <- function(f, n, t, s, Llist, rho){

  fv <- as.numeric(f)
  rd <- diag(rho)
  tm1 <- t - 1

  # accumulate the block diagonals: cmat[i, j] is the (j, j) entry of block i
  cmat <- NULL
  for(sx in 0:(s+1)){

    if(sx == 0){
      a <- diag(Llist[[as.character(0)]])
    } else if(sx == s+1){
      a <- -rd * diag(Llist[[as.character(s)]])
    } else {
      a <- diag(Llist[[as.character(sx-1)]]) - rd * diag(Llist[[as.character(sx)]])
    }

    term <- outer(fv[seq(from = 2+s-sx, to = t+s-sx)], a)
    cmat <- if(is.null(cmat)) term else cmat + term

  }

  # assemble the sparse matrix in one shot. Column j holds the (j, j) entry of
  # every block, i.e. rows (i-1)*n + j for i = 1..t-1, so the values in
  # column-major order are exactly as.vector(cmat). sparseMatrix() is used in
  # preference to new("dgCMatrix", ...) because ?sparseMatrix recommends it
  # over constructing slots directly; it returns an identical object here and
  # the extra cost is a fraction of a percent of sampler runtime.
  sparseMatrix(i = rep(seq.int(1L, by = n, length.out = tm1), times = n) +
                 rep(seq.int(0L, n - 1L), each = tm1),
               j = rep(seq_len(n), each = tm1),
               x = as.vector(cmat),
               dims = c(tm1 * n, n))

}


#' Observation matrix linking factors to the data
#'
#' @noRd
get_gmat <- function(Gmat_prealloc, Llist, rho, lambda, s, t, n){

  aux <- cbind(-rho %*% Llist[[as.character(s)]] %*% lambda,
               do.call(cbind, lapply((s-1):0, function(sx){
                 (Llist[[as.character(sx+1)]] - rho %*% Llist[[as.character(sx)]]) %*% lambda})),
               Llist[[as.character(0)]] %*% lambda)


  Gmat_prealloc@x <- rep(as.vector(t(aux)),t-1)
  t(Gmat_prealloc)


}


#' Extract the target series nowcast from the augmented dataset
#'
#' @noRd
#' @importFrom stats ts time frequency
get_nowcast <- function(Xmat_full, inventory, target, flows){

  # get the entry where GDP is usually recorded
  idx <- which(round(time(Xmat_full) + 1/max(inventory$freq), 3) %% (1/frequency(flows[[target]])) == 0)
  target_fit <- Xmat_full[idx, which(inventory$key==target)]


  # rescale
  target_rescaled <- (target_fit * inventory[which(inventory$key == target),"sd"]) +
    inventory[which(inventory$key == target),"mean"]

  out <- ts(target_rescaled,
            start = time(flows[[target]])[1],
            frequency = frequency(flows[[target]]))

  return(out)

}
