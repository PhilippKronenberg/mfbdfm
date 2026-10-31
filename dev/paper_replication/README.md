# Replicating results that carry the paper's `get_zmat()`

Kronenberg (2026) and Eckert et al. (2025) were estimated with a loading regressor that has two distributed-lag indices swapped. Issue #166 fixed this in the package, so the current code no longer gives those results. This folder keeps the old code.

## To get the old behaviour back

```r
library(mfbdfm)      # or devtools::load_all()
source("dev/paper_replication/use_paper_zmat.R")
use_paper_zmat()     # from the package root; lasts for this R session
```

Then run the fit or the analysis script as usual. To check that it worked:

```r
source("dev/baseline.R")
baseline_check("dev/paper_replication/baseline_before_fix.rds")   # BASELINE MATCHES
```

## The files

| File | What it is |
| --- | --- |
| `model-helpers.R` | `R/model-helpers.R` as of commit `ac9c2a6`, the last one before the fix. It holds the old `get_zmat()`. |
| `samplers_fcast.R` | `R/samplers_fcast.R` as of `ac9c2a6`. It holds the old `get_zmat_fcast()`. |
| `use_paper_zmat.R` | Puts those two functions into the loaded package. |
| `baseline_before_fix.rds` | `dev/baseline.rds` as of `ac9c2a6`, the proof that the restoration is exact. |

Only those two functions are restored from the archived files. Everything else comes from the package you loaded.

## What this does not restore

This undoes only #166. A later package version also differs from the paper in other ways, all listed in `CLAUDE.md` under "Where we knowingly differ from the published Eckert et al. (2025) results". The `phi` orientation fix (#66) matters most: the published multi-factor factors carry that bug too. For an exact replication of everything, check out the commit that matches the paper's code state, or the stored `fits/`.

The restoration is exact only on the platform the snapshot came from, as with every comparison through `dev/baseline.R`.
