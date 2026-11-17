# 25 — LP-DiD for new US sanctions, following the authors' reference code

Script `empirics/scripts/25_lpdid_dgjt.R` (< 1 min). Table `results/tables/lpdid_dgjt.md` / `.csv`; figure
`fig47_lpdid_dgjt.png`. User request (17 Nov): a new LP-DiD script based on the R code at
github.com/danielegirardi/lpdid (GPL-3.0), replacing our own implementation in 12 for the US question.

## What was taken from where

- **R example files** (`LP_DiD_R_example_VW.R`, `_EW.R`, 23 Feb 2026): long difference y(t+h) − y(t−1) on the
  treatment indicator with year FE only, SE clustered by unit with reghdfe's small-sample correction; pre-periods
  y(t−k) − y(t−1); pooled post / pre averages; reweighting by the inverse of the OLS variance weights (equally
  weighted ATT). These files cover **absorbing** treatment only.
- **Stata example** `LPDiD_nonabsorbing_example.do`, variant 5b: the clean-control windows for **non-absorbing**
  treatment (our case: repeated US cases). Translated with "switch" = a new US case:
  CCS_0 = no case in t−L..t−1; CCS_h = CCS_{h−1} and no case in t+h; CCS_mk = CCS_m(k−1) in t and t−1. The sample
  at h is every state-year with CCS_h (treated and controls), so **treated events must also have no further US case
  through t+h**. L = 3 (main), 5 (check; the do-file's value).
- Not used: the Stata command itself (its .ado/help could not be fetched; its `oneoff` sub-option may differ from
  this translation — check with `ssc type lpdid` if Stata is available); tsibble/slider/marginaleffects (not in renv;
  replaced by `lag_by_year()` and fixest, same computations).

## Differences from 12 (our earlier LP-DiD) and from D11

| | 12 (Oct) | 25 (this) | D11 base LP |
|---|---|---|---|
| shock | any new sanction | new US case (binary) | new US cases (count) |
| controls clean | t−3..t | t−3..**t+h** | — (all state-years, regression) |
| treated clean after t | no | yes (no new US case through t+h) | — |
| base year | t−1 | t−1 | t (shock second) |
| lagged outcomes | 2 lags (post only) | none (package baseline) | 2 lags + y_t |
| FE | year | year | state + year |

## Results (L = 3, variance-weighted; reweighting gives the same to two decimals)

| | h −5 | h −4 | h 0 | h 2 | h 3 | h 4 | pooled 0..3 |
|---|---|---|---|---|---|---|---|
| In conflict in t−1 | −0.50*** | −0.25* | −0.05 | −0.23 | −0.31 | −0.37 | −0.18 (0.24) |
| All state-years | −0.18** | −0.11* | +0.10 | −0.07 | −0.04 | −0.05 | +0.04 (0.11) |

Treated events in wars: 75 at h = 0, 46 at h = 2, 20 at h = 8 (the clean-through-t+h rule drops events followed by
another US case).

## Reading

- **One clear pre-period difference (corrected 17 Nov; stars are 10/5/1 %, the figure's bands are 95 %).** In wars,
  deaths in t−5 were 0.50 log points below t−1 relative to controls (p < 0.01; 95 % band ≈ −0.85..−0.15). h = −4
  (−0.25*) is significant only at 10 %; h = −3 and −2 are ≈ 0. So: an escalation 3–5 years before the sanction, then
  parallel paths in the last two years. One significant pre-period out of four plus a monotone shape is a warning
  sign, not a proven trend. The package's baseline does not condition on past outcomes; D11 controls y(t), y(t−1),
  y(t−2) (covering the plateau, not the earlier escalation); Dube et al. add lagged outcomes for this reason.
- **Post-sanction dip of the same shape as D11, without significance:** in wars −0.23 to −0.37 at h = 2..4 (L = 5:
  −0.37 to −0.41), back to 0 by h = 6. h = 0 is ≈ 0 in wars but +0.10 in all state-years (sanctions coincide with
  violence spikes in countries not yet at war).
- **Equal vs variance weights do not matter** (one binary event per state-year, similar treated shares per year).
- Next step if wanted: the package variant with lagged outcomes as controls (ylags / dylags), which is the
  comparison closest to D11 within the LP-DiD design.

## Conflict incidence as the outcome (added 17 Nov, user request)

Same design, y = conflict incidence (0/1, ≥ 25 UCDP deaths), so coefficients are changes in the probability of
conflict. In the in-conflict sample y(t−1) = 1, so a negative value means the conflict ended more often.

| L = 3, variance-weighted | h −3 | h −2 | h 0 | h 1 | h 2 | h 3 | h 6 | h 7 | pooled 0..3 |
|---|---|---|---|---|---|---|---|---|---|
| In conflict in t−1 | +0.03 | +0.09* | +0.05 | **+0.13**** | +0.12* | +0.01 | +0.13 | 0.00 | +0.04 (0.07) |

Significant at 5 % (95 % band excludes 0): only h = 1 in wars, and h = −3 and h = 7 in all state-years.
| All state-years | −0.07** | −0.02 | +0.01 | −0.01 | −0.04 | −0.04 | −0.07* | −0.11*** | −0.01 (0.03) |

- **Wars do not end sooner after a US sanction; if anything they continue more often:** +13 pp at h = 1 (p < 0.05),
  +12 pp at h = 2 (10 % only), then not significant, while deaths are lower (the dip above). Consistent with the
  termination result of 20 ("no effect on war termination"). The pre-period +0.09 at h = −2 is significant only at
  10 % (95 % band includes 0) — not evidence that the sanctioned wars were more persistent (an earlier version of
  this note said so; corrected 17 Nov).
- All state-years: nothing at h = 0..5; lower incidence at h = 6..8 (−7 to −11 pp), with a pre-period dip at h = −3
  (−0.07**) — not a pattern to build on.
- Reweighting again changes nothing; L = 5 gives the same picture.
