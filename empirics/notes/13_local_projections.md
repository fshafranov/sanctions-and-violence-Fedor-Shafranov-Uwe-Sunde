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
Asia 1997–2023 with either data source. Located in section 5 below.

## Where does the UCDP US effect come from? (section 5, added 2026-11-09)

Table `lp_us_effect_location.md` / `.csv`, figure `fig24_lp_us_effect_location.png`. Same specification as above
(US without ICC, levels, shock second, FE only); full sample h = 2 −0.105*** (0.039), cumulative h = 0..3
−0.222*** (0.079).

- **Not one region.** Leaving out any GW region: h = 2 between −0.095 and −0.119 (all p < 0.1), cumulative −0.20 to
  −0.24 (all p < 0.05). Each region alone: negative everywhere (Africa −0.14**, Americas −0.06**, Europe, Middle
  East, Asia imprecise).
- **A 1990s–2000s pattern.** Separate coefficients by shock year: 1991–99 −0.21** (cum. −0.42**), 2000–09 −0.11**
  (cum. −0.28**), **2010–19 +0.02** (cum. +0.18, n.s.). This fits section G: the ACLED sample is mostly 2000s–2010s
  (many states covered only from the 2010s) and has no 1991–96.
- **No single country drives it,** but a handful of wars carry much of it. Leave one country out (98 states with a
  US shock): every estimate p < 0.05, cumulative −0.24 to −0.18. Dropping the five most influential together
  (Yugoslavia, Iraq, Nepal, Angola, Liberia): h = 2 −0.049* (0.028), cumulative −0.101* (0.057) — about half the
  full-sample size. (Ranking by influence and then dropping is adversarial by construction.)
- **The influential events sit at war ends.** Yugoslavia 1998–99 (Kosovo; deaths fall to zero from 2000), Nepal 2005
  (peace deal 2006), Liberia 2004 (after the 2003 peace agreement), Angola 1993 (falling after the peak).

**Reading.** The negative effect is real in the sense of being statistically robust to dropping any one region or
country, but it is a 1990s–2000s phenomenon carried disproportionately by a few wars that ended shortly after US
measures. This is exactly the pattern the anticipation concern predicts (senders act when a war's end is expected,
or as part of a settlement package), so it cannot yet be read as sanctions reducing violence. Next: GSDB objective
split (conflict-ending objectives vs others), and check whether the 2010s null is about the type of US sanctions
(more targeted / non-conflict objectives) or about the conflicts.

## US effect by sanction objective (section 6, added 2026-11-09)

Table `lp_us_objective_split.md` / `.csv`. US cases without ICC split by GSDB objective (conflict objective = end_war,
prevent_war or territorial_conflict mentioned, as in 14); both parts and their lags in one regression; shock second.

| | All state-years, h = 2 | cum. h = 0..3 | In conflict in t−1, h = 2 | cum. h = 0..3 |
|---|---|---|---|---|
| Conflict objective | −0.145* [42] | −0.374** | −0.277** [23] | −0.706** |
| Other objectives | −0.090** [142] | −0.157 | −0.236*** [62] | −0.552*** |
| p(equal) | 0.51 | 0.35 | 0.75 | 0.66 |

(End war mentioned vs not: same picture, −0.22** vs −0.08** in all state-years, p(equal) 0.18.)

- The decline is **larger after conflict-objective cases**, but **not only there**: US cases with other objectives
  (human rights, democracy, terrorism, …) are also followed by fewer deaths, clearly so among states at war. The
  difference between the groups is never significant (small groups: 15–42 shock years).
- The influential events are not mostly conflict-objective cases: Kosovo 1998–99 are coded human_rights, Nepal 2005
  democracy/human_rights, Liberia 2004 prevent_war, Angola 1993 and Iraq 1990/97 include end_war.

**Reading.** A pure "settlement package" story (sanctions imposed as part of ending the war) is less likely, because
non-conflict cases show the decline too. But the objective split cannot rule out the general anticipation problem:
senders of any kind may act when they see a war turning, and annual data with the violence history as controls
cannot see that information. The leave-out cases are equally consistent with "the sanctions worked there" and "the
wars were ending anyway"; the counterfactual is not identified by these checks. What could help: (i) whether peace
talks / ceasefires were already under way before the sanction (UCDP Peace Agreement and Conflict Termination data,
download by the user); (ii) within-year timing with ACLED months and announcement dates; (iii) case-level reading of
the five most influential episodes.

## Full paths h = 1..8 by sample (section 7, added 2026-11-09)

Figure `fig25_lp_us_paths_by_sample.png`, estimates `lp_us_paths_by_sample.csv` (US without ICC, shock second).
Sections 5–6 summarise samples by h = 2 and cumulative h = 0..3; this shows the whole path.

- **Full sample:** per year −0.04, −0.11***, −0.06, −0.04, then +0.02 to +0.11 at h = 5–8 (n.s.); cumulative
  −0.27** at h = 4, back to ≈ 0 by h = 7. Temporary dip, later slightly positive (imprecise).
- **By shock period:** 1991–99 and 2000–09 dip (cumulative −0.55** / −0.33* at h = 4) and drift back; 2010–19 never
  dips and is **positive** at h = 5–7 (per year +0.22 to +0.27*, cumulative +1.33* at h = 6; wide bands, few shocks
  observed that far out).
- **Without the 5 most influential states:** small dip at h = 2 (−0.05*), then ≈ 0 / slightly positive.
- **In conflict in t−1:** clearest pattern: −0.14*** (h = 1), −0.25*** (h = 2), −0.18** (h = 3), ≈ 0 from h = 5;
  cumulative stays negative (−0.65*** at h = 4, −0.5 to −0.7 n.s. at h = 6–8) → among wars, no visible catch-up.

**Reading.** In wars the decline after US sanctions is not reversed later (cumulative stays negative, imprecise);
in the full sample the later positive per-year estimates come with the 2010s shocks and the non-war state-years.
Still not identified causally (anticipated war ends, section 6).
