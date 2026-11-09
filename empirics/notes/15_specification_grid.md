# 15–16 — Specification grid and specification curves

Scripts: `empirics/specifications.R` (dimensions + one data builder for all sources),
`empirics/scripts/15_specification_grid.R` (all combinations), `empirics/scripts/16_specification_curve.R` (curves).
Run 2026-11-09 14:36 (grid, 277 s, commit 5a5c5bd + uncommitted changes) and 14:40 (curves).
Outputs: `results/tables/spec_grid_estimates.csv.gz` (43,680 estimates), `results/spec_runs/` (every run + `index.csv`; per-run files are git-ignored and kept locally, the index and the latest estimates are committed),
`results/tables/spec_curves.md`, figures `fig23_spec_curve_*.png`.

## How it works

- **Base definitions stay fixed**; every variant is an option in one of the dimensions of `specifications.R`
  (base option listed first, with who asked and when). A new "play around" combination = one new option.
- **One builder for all violence sources** (`build_source_panel`): UCDP, ACLED and GDELT get the same variable
  names, so every sanction measure, sample and window applies to all three automatically.
- Dimensions: direction (sanctions → violence, violence → sanctions) × source (UCDP, ACLED, GDELT) × sanction measure
  (all, without ICC 685, US, US without 685, arms embargo, conflict objective, sender units, breadth) × type
  (levels, incidence) × sample (all states, in conflict in t−1 defined by UCDP for every source = option c, without
  Israel) × years (own coverage, common window 1997–2021 where all three are observed) × FE (state, region) ×
  timing (shock second, first) × controls (none, lagged). Not estimated: incidence for sender units/breadth (equals
  "all"), the in-conflict sample for violence → sanctions. 3,360 specifications, h = 0..6, per year and cumulative.
- **Check:** the grid reproduces script 13 exactly (416 overlapping estimates, max difference 7e−16, same N).
- **Specification curves** (Simonsohn, Simmons & Nelson 2020): for one question, all specifications sorted by
  estimate, with a facet panel per dimension showing the choices (one ggplot, facets). Timing fixed to shock second.
  Levels estimates in **SD units of each source's outcome** (UCDP 0.78–0.92, ACLED 0.95–0.96, GDELT 4.4–4.8 in raw
  units), because GDELT levels (% of reports) and log deaths are not comparable otherwise.

## What the curves show (run 14:40)

| Question | Specs | Median | Share < 0 | Sig. negative | Sig. positive | Base |
|---|---|---|---|---|---|---|
| Violence (levels, SD) at h = 2 after a sanction | 576 | −0.015 | 0.60 | 6 % | 1 % | −0.034 (p = 0.18) |
| Conflict (0/1) at h = 2 after a sanction | 432 | −0.006 | 0.62 | 0 % | 0 % | −0.007 (p = 0.57) |
| Cumulative violence t..t+3 (levels, SD) | 576 | −0.038 | 0.59 | 13 % | 2 % | −0.062 (p = 0.28) |
| Cumulative new-sanction prob. t..t+2 after conflict | 288 | +0.074 | 0.08 | 0 % | 67 % | +0.112 (p < 0.001) |

**Reading.**
- *Senders react to violence:* robust — positive in 92 % of specifications, significant in two thirds; 100 % of the
  UCDP specifications, 69 % ACLED, 33 % GDELT (GDELT's weaker link with violence, known from script 11).
- *Sanctions → conflict incidence:* nothing anywhere (0 of 432 significant). Sanctions do not end or start wars.
- *Sanctions → deaths:* mostly near zero; a minority of specifications is significantly negative. Which choices put a
  specification on the negative side (cumulative t..t+3): **UCDP** (32 % significant negative, median −0.11 SD) rather
  than ACLED (0 %) or GDELT; **arms embargo** (median −0.30 SD) and **conflict objective** (−0.14) rather than all/US
  cases; **in-conflict sample** (−0.15, 21 % significant) rather than all states (≈ 0); state FE more than region FE.
  US measures have positive medians here. Controls and the Israel exclusion change nothing.
- So the picture of scripts 13–14 holds up across all combinations: the only systematic sanction → violence pattern
  is *fewer deaths after arms embargoes / conflict-aimed sanctions in ongoing wars*, mainly in UCDP; the general
  "sanctions reduce violence" claim is not supported, and the earlier US dip is not robust.
- Caveat: shares of significant results must be compared with the ~5 % expected by chance in each direction; 6 %
  significant negative at h = 2 is close to chance overall, the concentration in specific options is what matters.
