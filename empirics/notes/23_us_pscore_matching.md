# 23 — Propensity-score matching for new US sanctions, with the lecture's matching estimand

Script `empirics/scripts/23_us_pscore_matching.R` (≈ 80 s, 200 bootstrap draws). Table
`results/tables/us_pscore_matching.md` / `.csv`; figures `fig42_us_pscore_overlap.png`, `fig43_us_pscore_paths.png`.
User request (16 Nov): matching on the propensity score, with the estimand of the lecture slide
β_M = ∫ [E(Y|D=1,X=x) − E(Y|D=0,X=x)] dF_X(x).

## Design

- **Estimand.** The slide's β_M weights the conditional differences by the distribution of x among **all** units =
  the ATE. Also reported: ATT (weights dF_{X|D=1}, the sanctioned; = script 22's estimand) and ATC (dF_{X|D=0}).
  By Rosenbaum–Rubin the comparison conditions on p(x) instead of x.
- **Units.** Clean events (new US case w/o ICC 685, **no new US case in t−1..t−2**) and clean controls (no new US case
  in t−2..t+3), 1991–2019, complete covariates. In conflict: 76 events, 698 controls; all state-years 164 / 3,967.
- **Score.** Logit of D on deaths in t, t−1, t−2, sanction stock and US sanction in force in t−1, democracy, region,
  5-year period. AUC 0.74 in both samples. Common support: 73 of 76 war events, 162 of 164 overall.
- **Estimators.** (NN) nearest-neighbour matching on the logit of the score, 3 matches, same calendar year, in both
  directions (each treated unit's Y(0) from controls, each control's Y(1) from treated units; Abadie–Imbens), then
  ATE = mean over all units, ATT over treated, ATC over controls; without a caliper and with the conventional caliper
  of 0.2 SD of the logit. (SC) subclassification on 5 score blocks, block differences weighted by the block share of
  all units (ATE — the integral written as a sum), of the treated (ATT) or of the controls (ATC); pooled over years.
- **Inference.** State-cluster bootstrap with the score re-estimated in each draw (approximate for NN matching).

**A design point found on the way (also concerns 22).** First run: the score separated perfectly on "new US case in
t−1..t−2" (coefficient 19, SE 690; p = 1 for 28 war events), because by construction no clean control has one. Those
events have no comparable control. Script 22 dropped them through its exact match — that is most of its 32 unmatched
war events. **Both matching designs therefore estimate the effect of a new US sanction after at least two years
without one** (as LP-DiD clean events). Script 23 now restricts treated units explicitly; the estimates did not change
(those units were outside common support anyway).

## Results (h = 2; cumulative 0..3 in brackets; bootstrap SE)

| | ATE (lecture estimand) | ATT | ATC |
|---|---|---|---|
| **In conflict**, NN | −0.12 (0.12) [−0.28] | −0.11 (0.19) [−0.18] | −0.12 (0.12) |
| In conflict, NN, caliper 0.2 SD | −0.25 (0.25) [−0.44] | −0.27 (0.28) [−0.51] | −0.25 (0.25) |
| In conflict, subclassification | −0.02 (0.16) [−0.13] | −0.07 (0.13) [−0.10] | −0.02 (0.16) |
| **All state-years**, NN | −0.21** (0.08) [−0.60***] | −0.10 (0.10) [−0.12] | −0.21** (0.08) |
| All, NN, caliper 0.2 SD | −0.09 (0.06) [−0.25*] | −0.09 (0.10) [−0.13] | −0.09 (0.06) |
| All, subclassification | −0.04 (0.05) [−0.09] | −0.07 (0.08) [−0.12] | −0.04 (0.05) |

Balance after NN matching, ATT side: deaths t, t−1, t−2 within ±0.09 SD, democracy −0.13 / 0.00, sanction stock
0.23 / 0.17. ATC side (imputing Y(1) for unsanctioned units): deaths 0.17–0.23 SD in wars, **0.36–0.48 SD and democracy
−0.45 in all state-years** — the sanctioned events cannot stand in for the many peaceful, democratic state-years.

## Reading

- **Same sign, much less precision.** Every propensity-score estimate among wars is negative (−0.02 to −0.27 at
  h = 2), none is significant. With the standard caliper the ATT (−0.27) equals the covariate-matching ATT of 22
  (−0.29) but rests on 48 events and a bootstrap SE twice as large; without a caliper or by subclassification it is
  close to zero. Matching on one number (the score) leaves pairs that differ in violence levels, which matter for the
  outcome path; 22 matched on violence directly (caliper on deaths in t) and is more precise.
- **The lecture's ATE is not the right target here.** It weights by the distribution of characteristics among all
  units, i.e. mostly unsanctioned state-years. In all state-years the NN ATE (−0.21**) is driven entirely by the ATC
  — imputed effects for peaceful, democratic states the US rarely sanctions, with poor balance (0.47 SD) — i.e.
  extrapolation, and it shrinks to −0.09 with a caliper and −0.04 by subclassification. The policy-relevant estimand
  is the ATT (effect where the US actually sanctions), with weights dF_{X|D=1}; among wars ATE ≈ ATT anyway.
- Placebo (h = −5..−3) in wars: −0.1 to −0.3, not significant but not small — another sign of noise in these
  comparisons.
- Bottom line: propensity-score matching does not contradict the result but cannot confirm it on its own; the
  evidence for the dip rests on the regression designs, doubly robust weighting and covariate matching (22).
