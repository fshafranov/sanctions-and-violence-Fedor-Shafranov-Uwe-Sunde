# Doubly robust local projections (Jordà & Taylor approach)

Separate analysis project (started 9 Nov 2026), built on the same data pipeline as the main project (`data/`,
`empirics/results/data/analysis_panel.csv`). Main project: `empirics/`; sister project: `exposure/`.

**Question.** The main LP result, fewer UCDP deaths two years after a new US sanction (`empirics/notes/13`),
assumes that given the state's recent violence and sanction history, the timing of a sanction is as good as random
(selection on observables). This project makes that assumption explicit, following Jordà & Taylor (2016, *EJ*) and
Angrist, Jordà & Kuersteiner (2018, *JBES*):

1. model the decision to sanction (a logit reaction function, i.e. the propensity score);
2. check **overlap** (are there unsanctioned state-years that looked equally likely to be sanctioned?) and
   **balance** (after weighting, do sanctioned and unsanctioned state-years have the same history?);
3. re-estimate the LP with inverse propensity weights, with and without the regression controls (IPW vs IPWRA).
   IPWRA is **doubly robust**: consistent if either the propensity model or the outcome regression is right.

It does **not** address unobserved confounders such as anticipated war ends (`empirics/notes/13`, section 6).
Literature: `papers/reading_list_causal_lp.md`.

**Layout**

```
doubly_robust/
  README.md          this file (design choices DR1-DR7 below)
  scripts/           00_setup.R (main setup + output paths + design constants), 01_dr_lp.R
  results/           tables/, figures/, logs/ (logs git-ignored)
  notes/             interpretation of the results
```

**Run:** `uv run python master.py --stage doubly_robust`, or `Rscript doubly_robust/scripts/01_dr_lp.R` (~10 s).

## Design choices (defaults set by Claude, 9 Nov; to confirm by the user)

| ID | Choice | Default | Alternatives |
|---|---|---|---|
| DR1 | Treatment | any new US case without ICC case 685, **0/1** (propensity methods need a binary treatment; main LP uses the count) | count capped at 1 is the same thing; all cases without ICC |
| DR2 | Outcome | UCDP `viol_lev` = log(1 + deaths per 100k), per year and cumulative, h = 1..6 | incidence; ACLED |
| DR3 | Propensity covariates | y(t−1), y(t−2), D(t−1), D(t−2), [y(t) if shock second], region (5 GW regions), 5-year period; logit | more lags (y(t−3), y(t−4)), controls (stock, GDP growth, democracy), Mundlak country means, ML (DML) |
| DR4 | Trimming | drop p outside [0.01, 0.99] | 0.05; none |
| DR5 | Estimand | ATE (as Jordà & Taylor) and ATT (effect on the sanctioned) | |
| DR6 | Outcome model in IPWRA | the script-13 LP: history + state FE + year FE, weighted | |
| DR7 | Inference | SEs clustered by state, propensity treated as known | cluster bootstrap over both steps |

Samples: all state-years in the window (1989–2019); state-years in conflict in t−1 (as in script 14).
Timing: shock second (main) and shock first.

## Results so far

| Script | Result | Notes |
|---|---|---|
| 01_dr_lp | The US result survives propensity weighting: IPWRA h = 2 −0.127*** (OLS −0.103**), in wars −0.284*** (OLS −0.274***). New US sanctions are hard to predict from the violence history (AUC 0.68–0.72), so overlap is good and trimming drops almost nothing. One placebo (violence at t−4, all state-years) is not balanced. | [notes/01](notes/01_dr_lp.md) |
