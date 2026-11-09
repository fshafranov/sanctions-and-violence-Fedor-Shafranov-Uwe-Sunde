# 13 — Panel local projections (no DiD)

Script `empirics/scripts/13_local_projections.R`, run 2026-11-09 (UCDP 12:22; ACLED added 13:40, ~30 s). Tables
`empirics/results/tables/local_projections.md` / `.csv`; figures `fig18_lp_sanctions_to_violence.png`,
`fig19_lp_violence_to_sanctions.png` (UCDP), `fig20_lp_acled_sanctions_to_violence.png`, `fig21_lp_acled_violence_to_sanctions.png` (ACLED). Added after the advisor meeting of 9 Nov ("focus on local projections;
LP without the DiD; US sanctions only, without the ICC case; with ACLED").

## Specification

    y_i,t+h = beta_h x_it + Σ_{k=1,2} (a y_i,t-k + b x_i,t-k) [+ c y_it] + state FE + year FE + e

h = 0..8, SE clustered by state, shock years 1991–2019 (outcomes only to 2019, so the sample shrinks with h).
Two timings: **shock first** (x may move y in the same year) and **shock second** (y_t controlled, the timing of the
VAR's base IRF). Cumulative version: outcome Σ y(t..t+h). Main: FE only; with controls in section E of the table.

Sanction measures (state-years with a new case, 1991–2019): all 642; all without ICC case 685: 540;
US 350; **US without ICC: 244**. Case 685 (US military-aid cut to ICC signatories) puts 108 of the 113
new-sanction state-years of 2002 into the data.

## What the results show (FE only)

**Sanctions → violence**
- *Shock first*: violence is **higher** in the sanction year and the year after (incidence +5 pp at h = 0,
  levels +0.12 per case, all measures). This is the same-year co-movement seen in the response functions
  (sanctions arrive at the peak of escalations) and cannot be read as escalation caused by the sanction.
- *Shock second* (VAR timing): for all cases, levels dip at h = 2–3 (−0.026, −0.020) but are not significant.
  For **US cases without ICC**, log deaths are lower two years after a new case: **−0.105 (SE 0.039)** per year at
  h = 2, cumulative **−0.149*** (h = 2) and −0.222*** (h = 3)**, back to zero by h = 8. US with ICC: −0.092** / −0.124**.
  Incidence: nothing significant in any measure.
- So the LP reproduces the VAR's "lower deaths two years later" pattern, and it is **concentrated in US sanctions**;
  removing the ICC case strengthens it a little. The effect is transitory (cumulative response ≈ 0 by h = 8).

**Violence → sanctions**
- A conflict year raises the probability of a new sanction for 2–3 years: cumulative +0.21 (all) / +0.09–0.10 (US)
  by h = 2–3, significant at every horizon in incidence. Robust to timing and to dropping case 685.
- Levels, US: small (cumulative +0.03–0.05), significant only with shock first.

**ICC case 685** hardly matters for "all cases" (year FE absorb 2002, when it applies to 108 states at once) but
matters somewhat for US cases (US measure loses 30 % of its events).

## Caveats

- Many specifications (4 measures × 2 specs × 2 timings × 2 control sets × 9 horizons): single significant cells
  should not be over-read; the US-levels-shock-second pattern is significant at h = 2 and 3 in per-year and cumulative
  form, which is more convincing than one cell.
- Levels shock = number of new cases (for US mostly 0/1); the response is in log(1 + deaths per 100k), not a percentage.
- With controls, the stock control still contains case 685 in the *without ICC* variants.

## ACLED (sections F and G of the table)

Sample: ACLED-covered state-years, 1997–2023, states with ≥ 10 covered years → **58 states** (Africa, South and
Southeast Asia, Middle East; Europe and the Americas are covered only from 2018–21 and drop out), 1,435 state-years.
New-case state-years: all 271, US without ICC 142. Violence: ACLED organized-violence fatalities (state-based +
non-state + one-sided; `data/README.md` A4), incidence ≥ 25 fatalities, levels log(1 + fatalities per 100k).

**Sanctions → violence:** no reduction. Shock second (VAR timing), US without ICC: per year +0.025, +0.022, +0.115*
at h = 1–3; cumulative +0.83** by h = 8 (39 shock years left at h = 8 — fragile). All cases: ≈ 0 throughout.
Incidence: nothing significant in any measure. Shock first: deaths higher at h = 0–1 as with UCDP.

**Violence → sanctions:** robust, as with UCDP. Cumulative new-sanction probability after a conflict year +0.15 to
+0.25 (all) / +0.09 to +0.17 (US without ICC) by h = 2–5, both timings.

**Source or sample? (section G).** UCDP estimated on exactly the ACLED state-years gives the same answer as ACLED:
US without ICC, shock second, cumulative h = 2: UCDP −0.028 (0.094) vs ACLED +0.032 (0.078); per year at h = 2
UCDP +0.001 vs ACLED +0.022. So the two sources agree, and the difference from the full-sample UCDP result
(−0.105 at h = 2) is a **sample** difference. The samples differ in both directions: the main sample has 1991–96
and the states ACLED covers only late or for < 10 years (Europe incl. ex-Yugoslavia, Latin America, Central Asia,
East Asia; Middle East before 2016); the ACLED sample adds 2020–23. Which of these matters is not yet known. Recall
the VAR effect was already weaker without the ex-Yugoslav states (09 part 5).

**Reading.** The "fewer deaths two years after a US sanction" result is not general: it is absent in Africa and
Asia 1997–2023 with either data source. Next: locate where it comes from (UCDP LP by region / period, leave-one-
country-out), before interpreting it.
