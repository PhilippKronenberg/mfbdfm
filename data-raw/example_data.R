# Build `mfbdfm_example_data`: a small, self-contained example dataset that
# includes the GDP target, so an example or a vignette chunk is one data() call
# and one model call (issue #105).
#
# Run from the package root with:
#   source("data-raw/example_data.R")
#
# Everything it needs ships with the repository: the curated series come from
# `data_ch_dataset` (already transformed per data-raw/data_meta.csv), and the
# quarterly GDP target comes from the real-time vintage database in
# inst/extdata/. No private data is involved.

library(mfbdfm)

# ---- 1. the series -----------------------------------------------------------
#
# Eight series: the GDP target plus seven indicators covering all three
# frequencies the model handles (4, 12, 48) and both aggregation types. Each is
# a flagship WAI series with an unbroken history over the window, so the only
# missingness in the dataset is the ragged edge at the end - which is the thing
# the model exists to handle, and is therefore kept.

TARGET <- "ch.seco.gdp.real.gdp.ssa"
START <- 2015           # a decade of data: long enough to fit, small enough to ship

indicators <- c(
  "ch.fso.rtt.ind.r.noga0801.sa",   # 12, flow  - retail sales, total
  "ch.ozd.e.wa.index.re.d11",       # 12, flow  - goods exports, total, real
  "SWPMIPROQ",                      # 12, stock - PMI manufacturing, output
  "SWISSMI",                        # 48, flow  - Swiss Market Index
  "traffic_PW",                     # 48, flow  - passenger-car counts
  "electricity_out",                # 48, flow  - electricity consumed
  "Arbeitsmarkt"                    # 48, stock - labour-market search index
)

data(data_ch_dataset, package = "mfbdfm")
pool <- c(data_ch_dataset$flows, data_ch_dataset$stocks)

stopifnot(all(indicators %in% names(pool)))

series <- lapply(pool[indicators], stats::window, start = START)

# ---- 2. the GDP target ------------------------------------------------------
#
# `data_ch_dataset` carries no GDP, so the target is taken from a vintage in
# the shipped real-time database - the same route the analysis scripts use, via
# the same transformation ("quarterly" = q/q log difference). The vintage is
# pinned by name below (and documented in R/data.R) so the dataset stays
# reproducible when a newer vintage is appended to the CSV.

vintages <- get_real_time_gdp_vintages("quarterly")
# Pinned by name, not taken as the newest: rerunning this script for any other
# reason (a label fix, say) must not silently move the target to a newer
# vintage while R/data.R still documents this one. To move it on, change this
# line and the vintage named in R/data.R together.
GDP_VINTAGE <- "2026.167"
stopifnot(GDP_VINTAGE %in% names(vintages))
message("GDP vintage used: ", GDP_VINTAGE)

gdp <- zoo::na.trim(stats::ts(vintages[[GDP_VINTAGE]],
                              start = c(1990, 1), frequency = 4))
series[[TARGET]] <- stats::window(gdp, start = START)

# ---- 3. metadata ------------------------------------------------------------
#
# Read off data-raw/data_meta.csv rather than retyped, so the flow/stock split
# and the labels cannot drift from the dataset they describe. `Flow` is 1/0
# there; mfbdfm_data() wants "flow"/"stock".

meta_raw <- utils::read.csv("data-raw/data_meta.csv", check.names = FALSE,
                            stringsAsFactors = FALSE)
rownames(meta_raw) <- meta_raw$keys
meta_raw <- meta_raw[names(series), ]

meta <- data.frame(
  series = names(series),
  type = ifelse(meta_raw$Flow == 1, "flow", "stock"),
  label = meta_raw$Name,
  source = meta_raw$Source,
  category = meta_raw$Category,
  unit = meta_raw$Unit,
  transformation = meta_raw$Transformation,
  stringsAsFactors = FALSE
)

# The CSV carries a LaTeX-escaped ampersand ("procure.ch \\& UBS"); the shipped
# table is plain text, and must stay ASCII for R CMD check's non-ASCII test.
meta[] <- lapply(meta, function(x) if (is.character(x)) trimws(gsub("\\\\&", "&", x)) else x)
stopifnot(!any(grepl("[^\x01-\x7f]", unlist(meta[sapply(meta, is.character)]))))

# ---- 4. assemble and save ---------------------------------------------------
#
# Shipped as a ready mfbdfm_data() object, so `ind_dfm(mfbdfm_example_data)`
# needs no `target =` and no flow/stock bookkeeping at the call site.

mfbdfm_example_data <- mfbdfm_data(series, meta, target = TARGET)
print(mfbdfm_example_data)

usethis::use_data(mfbdfm_example_data, overwrite = TRUE, compress = "xz")

message("installed size: ",
        format(file.size("data/mfbdfm_example_data.rda") / 1024, digits = 3), " KB")
