# Replicating results that carry the paper's `get_zmat()`

Kronenberg (2026) and Eckert et al. (2025) were estimated with a loading regressor that has two distributed-lag indices swapped. Issue #166 fixed this in the package, and later issues changed the sampler as well, so the current code no longer gives those results.

## To get the old results back

Use the code as it was at commit `ac9c2a6`, the last one before the fix. Restoring the old function in the current code is **not** enough: #168, #169 and #170 changed the sampler too.

```sh
git archive ac9c2a6 R DESCRIPTION NAMESPACE dev data inst | tar -x -C <empty folder>
R CMD INSTALL --no-docs --library=<separate library> <that folder>
```

Then run the fit or the analysis script with `library(mfbdfm, lib.loc = "<separate library>")`. To check it, run this from that folder:

```r
source("dev/baseline.R")
baseline_check()     # BASELINE MATCHES
```

Measured on 2026-10-31 on the platform that wrote the snapshot: `BASELINE MATCHES`. Keep the separate library, so that your normal installation stays current.

## The files

| File | What it is |
| --- | --- |
| `model-helpers.R` | `R/model-helpers.R` as of `ac9c2a6`. It holds the old `get_zmat()`. |
| `samplers_fcast.R` | `R/samplers_fcast.R` as of `ac9c2a6`. It holds the old `get_zmat_fcast()`. |
| `use_paper_zmat.R` | Puts those two functions into the loaded package. |
| `baseline_before_fix.rds` | `dev/baseline.rds` as of `ac9c2a6`. |

## What `use_paper_zmat()` is still for

It puts the old regressor into the current sampler, which gives results that match **neither** the paper nor the current package. On the current code, `baseline_check("dev/paper_replication/baseline_before_fix.rds")` reports `BASELINE DIFFERS`. It has two remaining uses:

- `dev/geweke.R` uses the old regressor as its negative control, to show that the test can detect a wrong sampler.
- At commit `17bdd8e` only `get_zmat()` had changed, so there it does restore the old results exactly.

## What this does not restore

`ac9c2a6` still contains the earlier fixes listed in `CLAUDE.md` under "Where we knowingly differ from the published results". The `phi` orientation fix (#66) matters most: the published multi-factor factors carry that bug too. For those, use the stored `fits/`.

The comparison is exact only on the platform the snapshot came from, as with every comparison through `dev/baseline.R`.
