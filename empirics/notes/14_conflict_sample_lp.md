# 14 — Conflict-sample local projections: arms embargoes and conflict-aimed sanctions

Script `empirics/scripts/14_conflict_sample_lp.R`, run 2026-11-09 14:02 (6 s). Table
`empirics/results/tables/conflict_sample_lp.md` / `.csv`; figure `fig22_conflict_sample_lp.png`.
Design agreed with the user on 9 Nov (question: do arms embargoes or sanctions aimed at ending wars calm or
shorten wars?).

## Design

- **Sample:** state-years in conflict in t−1 (≥ 25 UCDP deaths), shock years 1991–2019: 1,130 state-years, 104 states
  (~1,065–1,086 in the regressions). Median deaths 0.79 per 100k; 82 % are still in conflict in t.
- **Shocks (new case in t):** arms embargo, any (91 events); conflict objective (end_war / prevent_war /
  territorial_conflict, any mention; 95); arms embargo only (30, side check). 60 of the 91 embargo state-years also have
  a conflict objective, so the first two shocks are largely the same sanctions.
- **Comparison:** wars with no new sanction; other new sanctions in t enter as a separate regressor.
- **Controls:** conflict (0/1) in t−2 (t−1 is 1 for everyone by the sample rule), log deaths in t−1, t−2, lags of the
  shock and of other sanctions; same-year conflict and deaths (shock second); year FE; state FE or region FE.
- SE clustered by state.

## Results

**Deaths (log(1 + deaths per 100k)), shock second:** arms embargoes are followed by lower deaths 2–3 years later
than in comparable wars without a new sanction: h = 2 −0.25** (region FE) / −0.20* (state FE); h = 3 −0.20** /
−0.14; back to ≈ 0 from h = 4. Cumulative h = 3: −0.57** / −0.45**. Conflict-objective sanctions: same pattern,
slightly weaker (h = 2 −0.16 / −0.18*). Arms embargo only: no clear pattern, wide bands (28 events).

**War continuation (still in conflict), shock second:** no effect. Per year within ±0.05 and insignificant,
except arms embargo h = 4 −0.076** with state FE (one cell). Embargoes do not end wars sooner, at least not
detectably.

**Shock first:** large positive h = 0 (+0.55 to +0.64 in log deaths; +0.07 to +0.12 in conflict) — embargoes are
imposed in the year a war escalates (same pattern as all sanctions in script 13).

State FE and region FE agree closely, so the result does not hinge on that choice.

## Reading

- Among wars with the same recent violence (incl. the sanction year), wars hit by an arms embargo are less deadly
  two to three years later, but they do not end sooner. This is the cleanest sanction → violence pattern so far
  (both FE versions, per-year and cumulative), but it rests on ~90 events.
- Magnitude: −0.2 to −0.25 in log(1 + deaths per 100k) is about a fifth of the sample mean (1.11). With many values
  below 1 per 100k this is not a percentage effect (Chen & Roth caveat).
- **Mean reversion** (embargoes at the peak, wars calm anyway) is the main threat. Shock second holds the sanction-year
  violence fixed, so the comparison is with wars equally violent in t — this addresses it, but not if embargoed wars
  peak *within* t more sharply than annual data show.
- **Selection** into embargoes (visibility, atrocities, UN attention) is not controlled beyond the violence history.
- Arms embargo vs conflict objective cannot be separated (heavy overlap); the honest label is "conflict-related
  sanctions, mostly arms embargoes, often UN".

## Possible next checks

ACLED version (deaths and continuation); UN vs non-UN embargoes; placebo with pre-period outcomes; leave-one-war-out;
conflict onset vs ongoing wars.
