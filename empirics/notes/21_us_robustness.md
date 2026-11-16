# 21 — The US effect: base specification and one robustness table

Script `empirics/scripts/21_us_robustness.R` (7 s). Table `results/tables/us_robustness.md` / `.csv`; figure
`fig37_us_robustness.png`. Added 2026-11-16 after the user asked to stop adding controls and consolidate.

## Base (decision D11, frozen 2026-11-16)

Local projection; shock = number of new US cases without ICC case 685; response = log(1 + UCDP deaths per 100k);
shock second (y_t controlled); 2 lags of shock and response; state + year FE; no controls; SE clustered by state;
shock years 1991–2019; outcomes y(t+2) and cumulative y(t..t+3); two samples: all state-years and in conflict in t−1.
Every row of the table changes exactly one thing. New checks go into this table, not into new scripts.

## Results (h = 2; cumulative 0..3 in brackets)

| Check | All state-years | In conflict in t−1 |
|---|---|---|
| **Base** | **−0.105*** [−0.222***]** | **−0.251*** [−0.617***]** |
| Lagged controls | −0.107*** [−0.228***] | −0.243*** [−0.581***] |
| Shock first | **−0.056 [+0.116]** | −0.256*** [−0.586**] |
| Nonlinear history (deciles) | −0.101*** [−0.201***] | −0.285*** [−0.687***] |
| Peace-agreement dummies t−2..t | −0.109*** [−0.229***] | −0.269*** [−0.683***] |
| Without the 5 most influential states | **−0.049* [−0.101*]** | −0.188*** [−0.437***] |
| Leave one country out (range) | −0.115 to −0.081, max p 0.018 | −0.274 to −0.225, max p 0.001 |
| Shocks 1991–99 / 2000–19 | −0.213** / **−0.046** | −0.252** / −0.250*** |
| Panel VAR(2) (19) | −0.113** [−0.213***] | not estimated |
| IPWRA doubly robust, 0/1 shock | −0.127*** [−0.334***] | −0.284*** [−0.679***] |

## Reading

- **In conflict in t−1, every row is negative and significant** (−0.19 to −0.29 at h = 2), including the two that are
  designed to hurt (dropping the five most influential states; shock first). This is the robust result.
- **All state-years, three rows weaken it:** without the five most influential states (about half, p < 0.1),
  shocks from 2000 (≈ 0), and shock first (≈ 0; cumulative +0.12). Shock first lets the sanction move violence in the
  same year, and the cumulative outcome includes y_t; violence also raises sanctions in the same year (08: the
  violence → sanctions response is robust), so in the full sample this row mixes in reverse causality. Among wars it
  makes no difference.
- Headline for the write-up (to decide with the advisor): the within-war estimate, with the all-state-years result
  and its 1990s concentration reported next to it.
- Separate analyses (objective split, shock characteristics, peace-process split, termination, reaction function,
  exposure) stay in notes 13, 20 and exposure/ — they answer other questions and are not robustness rows.

## Part B: the whole path, placebos, and is it noise? (added 2026-11-16)

Figure `fig38_us_paths.png`, estimates and noise bands `us_paths.csv`, table appended to `us_robustness.md`.
Base specification at every horizon h = 1..8 (per year and cumulative) plus placebo horizons h = −5..−3 (deaths
before the shock, beyond the controlled lags). **Permutation test:** the US shocks are reshuffled across the sample's
states within each year (300 draws; in the in-conflict sample only among state-years in conflict, so each year keeps
its number of shocks), lags rebuilt, the whole path re-estimated. The grey band is what pure noise produces with
this data and specification. Family-wise p: largest |t| over h = 1..6 against the same statistic under reshuffling,
i.e. corrected for having looked at six horizons.

| | h = −5..−3 (placebo) | h = 1 | h = 2 | h = 3 | h = 4 | h = 5..8 | cum. 0..3 | family-wise p |
|---|---|---|---|---|---|---|---|---|
| All state-years | −0.03, −0.05, 0.00 (perm. p ≥ 0.15) | −0.04 | **−0.105 (p 0.007)** | −0.06 | −0.04 | +0.02 → **+0.11 (p 0.05, 0.02, 0.01 at h = 6..8)** | −0.22 (p 0.017) | 0.033 (per year), 0.017 (cum.) |
| In conflict in t−1 | −0.01, −0.07, +0.03 (p ≥ 0.53) | −0.14 (p 0.08) | **−0.251 (p 0.003)** | −0.18 (p 0.07) | −0.08 | ≈ 0 to +0.06 (p ≥ 0.6) | −0.62 (p < 0.004) | < 0.004 |

(perm. p = share of reshuffles with an estimate at least as large in absolute value.)

- **Not noise.** Under reshuffled shocks, estimates as large as the observed h = 2 occur in 0.7 % (all) and 0.3 %
  (in conflict) of draws, and the family-wise p over six horizons stays below 0.05 in both samples. The noise band is
  wider than the clustered 95 % interval (in conflict ± 0.18 vs ± 0.12 at h = 2), so clustered SEs are somewhat
  optimistic; the permutation p is the one to quote.
- **No pre-trend.** Deaths 3–5 years before a US sanction do not differ (all placebos inside the noise band).
- **Shape: a temporary dip.** Among wars: −0.14 (h = 1), −0.25 (h = 2), −0.18 (h = 3), back to ≈ 0 by h = 5, no
  significant rebound; the cumulative effect stays at −0.5 to −0.67 (imprecise beyond h = 4) → deaths avoided are
  not made up later. All state-years: the dip at h = 2 is followed by a **positive** per-year response at h = 6..8
  (+0.07 to +0.11, outside the noise band) that brings the cumulative effect back to 0 by h = 7 — consistent with
  the 2010s / non-war shocks (13 section 7). Long horizons lose late shocks (outcomes end 2019).

**Size.** −0.25 log points of (1 + deaths per 100k) at h = 2 among wars: for the median war state-year (1.18 deaths
per 100k) deaths fall to ≈ 0.70 per 100k in that year (≈ −40 %; for a country of 20 million, ≈ 236 → 140 deaths).
Cumulative −0.62 over t..t+3 ≈ −0.15 log points per year on average.

**What it supports for policy (and what not).** Supported: in countries already at war, a new US sanction is
followed by a short-lived fall in deaths of about a third to two fifths, starting in year 1–2 and fading by year 4–5,
not reversed afterwards, not explained by peace processes (20), pre-trends or noise. Not supported: that sanctions
end wars (no effect on termination, 20), that the effect is permanent, or a causal claim beyond selection on the
violence/sanction history (anticipation without a trace in agreements remains possible). Outside wars the average
effect is small and partly reversed later. Based on ~85 US shock-years in ~46 states at war.

## Part C: specification curve around the base (added 2026-11-16)

Figures `fig39_us_spec_curve_h2.png`, `fig39_us_spec_curve_cum3.png`; estimates `us_spec_curve.csv`; summary by
dimension appended to `us_robustness.md`. All combinations of sample (all / in conflict) × timing (second / first)
× lags (1 / 2 / 3) × FE (state + year / region + year) × lagged controls × history (linear / deciles) × peace
dummies × top-5 states (kept / dropped) × shock coding (count / 0-1) = 768 specifications per outcome.

**The curve is less flattering than the one-row-at-a-time table, and it says exactly where the result lives.**

| h = 2 | Specs | Median | Significant negative | Significant positive |
|---|---|---|---|---|
| In conflict, state + year FE | 192 | −0.23 | **100 %** | 0 % |
| In conflict, region + year FE | 192 | −0.09 | 16 % | 0 % |
| All state-years, state FE, shock second, all states | 48 | −0.11 | **100 %** | 0 % |
| All state-years, state FE, any other timing / top-5 choice | 144 | −0.02 to −0.06 | 0–8 % | — |
| All state-years, region + year FE | 192 | +0.01 | 1 % | 3 % (h = 2), 20 % (cum.) |

- **Among wars with country fixed effects the result is completely robust**: every one of 192 specifications is
  negative and significant (−0.20 to −0.26), whatever the timing, lags, controls, history, peace dummies, coding or
  the top-5 states.
- **The decisive choice is country vs region fixed effects.** With region FE, sanctioned countries are compared with
  other countries of the region, i.e. mostly *between* countries; the countries the US sanctions are persistently
  different (more violent, more often at war), so this comparison is confounded by stable country differences —
  which is why the design uses state FE (within-country: the same country before and after). Region FE is a
  weaker design, not an equally valid alternative; it is in the curve to show the dependence, not as a vote.
- **In all state-years the result is fragile**: significant only in the exact base combination (state FE, shock
  second, all states); dropping the top-5 states or allowing a same-year effect removes it. Consistent with notes
  13 sections 5–8: outside wars the average US effect is small and carried by a few wars.
- Significant positive estimates appear only with region FE in all state-years (cumulative 20 %), i.e. the
  between-country comparison: sanctioned countries are more violent.

**Reading.** Report the within-war, within-country estimate as the result, and the curve as evidence that it does
not depend on timing, lag length, controls, functional form of the history, peace processes, coding or the
influential wars — but does depend on comparing a country with itself (state FE) and on restricting to wars.
