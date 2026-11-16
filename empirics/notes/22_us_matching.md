# 22 — Matched difference-in-differences for new US sanctions

Script `empirics/scripts/22_us_matching.R` (4 s). Table `results/tables/us_matching.md` / `.csv`, event-level effects
`us_matching_events.csv`; figures `fig40_us_matching_path.png` (path), `fig41_us_matching_over_time.png` (by shock year).
User request (16 Nov): a matching design instead of regression adjustment, and the change of the effect over the years.

## Design

- **Treated:** state-years 1991–2019 with a new US case (without ICC 685).
- **Controls:** state-years of the **same year** with no new US case in t−2..t+3 (clean), the same conflict status in
  t−1 and the same "US case in t−1..t−2"; 3 nearest by Mahalanobis distance (sample-specific covariance) on deaths in
  t, t−1, t−2, sanction stock and US sanction in force in t−1, and democracy; with replacement; caliper 0.5 SD on
  deaths in t. First attempt (overall covariance, caliper on the Mahalanobis distance) matched only 21 of 104 war
  events → replaced.
- **Outcome:** change since the sanction year, y(t+h) − y(t) (cumulative: Σ_{j=0..h}). Same-year matching ≈ year FE,
  differencing ≈ state FE. Effect = mean over events of treated minus mean of its controls; SE clustered by treated
  country, controls treated as fixed (no Abadie–Imbens matching-variance correction). Bias-adjusted version: intercept
  of the event-level difference on the treated-minus-control covariate gaps.
- **Matched:** in conflict 72 of 104 US events (206 controls); all state-years 149 of 216 (421). **Correction (found
  in 23):** most unmatched events are US sanctions that follow another new US case in t−1..t−2 — no clean control can
  have one, so the exact match drops them. The estimand is therefore the ATT of a new US sanction **after at least two
  years without one** (clean events, as in LP-DiD), not of every US sanction. The rest are high-intensity wars with
  no control within the deaths caliper.
- **Balance:** deaths t, t−1, t−2 SMD 0.12–0.20; **deaths t−3, t−4 (not matched on) 0.05 / 0.00**; residual imbalance on
  sanction stock (0.51 in conflict), US sanction in force (0.31), democracy (−0.38) → bias adjustment.

## Results

| | h = −5..−3 (placebo) | h = 1 | h = 2 | h = 3 | h = 4 | h = 6..8 | cum. 0..3 | bias-adj. h = 2 |
|---|---|---|---|---|---|---|---|---|
| In conflict | −0.04, −0.10, −0.07 | +0.01 | **−0.29**** | **−0.30**** | −0.06 | +0.22, +0.30, +0.21 (n.s.) | −0.60* | **−0.43**** |
| All state-years | −0.08, −0.01, −0.00 | +0.01 | **−0.14**** | −0.12* | −0.01 | +0.10, +0.14, +0.07 (n.s.) | −0.27* | **−0.16**** |

- **The design replicates the LP result:** no pre-trend, a dip at h = 2–3 of the same size (in conflict −0.29 vs LP
  −0.25; all −0.14 vs −0.105), larger after bias adjustment (−0.43**).
- **Different from the LP:** the dip starts a year later (h = 1 ≈ 0 vs LP −0.14) and is followed by a **rebound** at
  h = 6–8 (+0.2 to +0.3 in conflict, not significant), which brings the cumulative effect back to ≈ 0 by h = 7. The LP
  shows no rebound among wars. "Not reversed later" (notes 21) is therefore **not robust to the design**; long horizons
  rest on few events (39–45) and are imprecise in both.

## The effect over the years (fig41)

| Shocks in | In conflict, h = 2 | cum. 0..3 | All state-years, h = 2 |
|---|---|---|---|
| 1991–99 | −0.51* [23] | −0.98 [23] | −0.26* [43] |
| 2000–09 | −0.33* [15] | −0.73 [15] | −0.10 [44] |
| 2010–19 | −0.06 [24] | +0.16 [14] | −0.06 [41] |

Rolling 9-year windows (in conflict, h = 2): −0.4 to −0.5 for windows centred 1995–97, −0.2 to −0.35 for 1999–2007,
then ≈ 0 from windows centred ~2009 (shocks from ~2005). [n] = events.

- **Within wars the matched effect declines over time**, from about −0.5 (1990s shocks) to ≈ 0 (2010s). The LP
  within wars (notes 21, 13 section 8) showed no decline (−0.25 / −0.25). With 14–25 events per window none of the
  period differences is significant, but the two designs disagree on whether the effect changed among wars.
- In all state-years both designs agree: strongest for 1990s shocks, small afterwards.

## Reading

The matching design confirms the core finding (deaths fall 2–3 years after a new US sanction, no pre-trend, similar
size) with a different identification (same-year clean controls, no regression extrapolation). It weakens two
secondary claims: that the decline is not reversed later, and that it is stable across decades within wars. The
honest summary: a robust short-run decline, concentrated in sanctions of the 1990s–2000s; for 2010s shocks neither
design finds a clear effect in matched comparisons. Caveats: SEs ignore matching uncertainty; 30 % of war events are
unmatched (the most intense); still selection on observables.
