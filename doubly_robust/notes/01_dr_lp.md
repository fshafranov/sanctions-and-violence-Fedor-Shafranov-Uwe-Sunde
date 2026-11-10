# 01 — Doubly robust LP for the US effect (first run, 9 Nov 2026)

Script `scripts/01_dr_lp.R`; tables `results/tables/dr_propensity.md`, `dr_balance.md`, `dr_lp_estimates.md`
(full `.csv`); figures `dr1_overlap.png`, `dr2_balance.png`, `dr3_lp_paths.png`. Design choices DR1–DR7 in the README
(defaults, not yet confirmed by the user).

## 1. Replication

The OLS LP with the 0/1 treatment reproduces script 13 (count shock): h = 2 −0.103** vs −0.105***, cumulative
h = 0..3 −0.210** vs −0.222***. Switching to a binary treatment changes nothing material.

## 2. Propensity model and overlap

- **New US sanctions are only weakly predictable from the history:** AUC 0.72 (all state-years), 0.68 (in conflict).
  The strongest predictors are earlier US sanctions (D(t−1), D(t−2)) and same-year violence (y(t), shock second).
  Past violence (y(t−1), y(t−2)) adds little once these are in.
- **Overlap is good.** Propensities lie mostly between 0.01 and 0.4 for both groups (dr1); trimming at 0.01 drops
  6 control state-years and no treated ones. Largest ATE weight: 86 (all), 31 (in conflict).
- **Common support (dr4, drawn like Jordà & Taylor 2016, Fig. 2; `dr_common_support.csv`).** Min/max rule:
  0.012–0.407 (all state-years), 0.032–0.318 (in conflict). **No sanctioned state-year lies outside.** Outside are only
  controls: 232 below / 5 above (all), 50 below / 5 above (in conflict), i.e. very peaceful, never-sanctioned
  state-years with no sanctioned counterpart. Contrast with Jordà & Taylor: their treated units pile up near p = 0.8
  (AUC 0.86, with country FE); ours sit at the same low p as the controls, so the densities nearly coincide.
- Reading: given their recent history, sanctioned state-years have comparable unsanctioned counterparts. The plain
  LP is therefore not extrapolating into empty regions of the data.

## 3. Balance (shock second, dr2)

- Unweighted, sanctioned state-years have much more violence and more earlier sanctions (SMD 0.3–0.46, all state-years).
  Among states in conflict, the gap is small except for earlier sanctions (D(t−1): 0.27).
- After ATT weighting, all variables are balanced (|SMD| < 0.08), including the placebo lags y(t−3), y(t−4), which are
  not in the model. After ATE weighting, y(t) and y(t−1) stay just above 0.1 (0.11, 0.13) in all state-years.

## 4. Estimates (`dr_lp_estimates.md`, dr3)

US cases without ICC (0/1) → log(1 + deaths per 100k), shock second:

| | OLS | IPW | IPWRA (DR) | IPWRA, ATT |
|---|---|---|---|---|
| All, h = 2 | −0.103** | −0.110** | −0.127*** | −0.159*** |
| All, cum. h = 0..3 | −0.210** | −0.206 | −0.334*** | −0.431*** |
| In conflict, h = 2 | −0.274*** | −0.282*** | −0.284*** | −0.277*** |
| In conflict, cum. h = 0..3 | −0.667*** | −0.729** | −0.679*** | −0.718*** |

- Weighting does **not** weaken the result. In all state-years the doubly robust estimates are somewhat larger than
  OLS. Among states in conflict, all estimators agree almost exactly.
- **Shock first, all state-years:** as in script 13, weaker. OLS h = 2 −0.057 (n.s.), IPWRA −0.084* (p ≈ 0.05),
  ATT −0.145**. Cumulative h = 0..3 interval includes zero for every estimator. In conflict, the shock-first
  estimates match the shock-second ones (h = 2 −0.27 to −0.31, all p < 0.01).
- Pure IPW (no regression controls) has wide cumulative intervals (cum. h = 0..3, all: −0.206, interval includes zero).
- Paths (dr3): dip at h = 1–4, back to about zero or slightly positive by h = 5–6, as in script 13 section 7.

## 5. Placebo: violence before the sanction

The placebo outcomes are y(t−3) and y(t−4), not used in the propensity model: 32 estimates (2 samples × 2
timings × 4 estimators × 2 lags).

- y(t−3): all near zero, no interval excludes zero.
- y(t−4): negative everywhere (−0.06 to −0.14). Two intervals exclude zero, both IPWRA (ATE) in all state-years:
  −0.101 (p 0.02, shock second) and −0.086 (p 0.045, shock first). ATT and OLS versions include zero.
- Two of 32 is close to what chance alone gives (≈ 1.6 at 5%), so this is at most a weak signal. If real, it means
  that among state-years with the same violence in t−2..t, the sanctioned ones had **less** violence four years
  earlier, i.e. their violence had been **rising**. That is the opposite of the "war already winding down" pattern,
  but it shows the two-lag propensity model does not balance the longer history under ATE weights. A DR3 variant
  with y(t−3), y(t−4) in the propensity model would settle this.

## 6. What this does and does not show

- **Shows:** the US result is not an artefact of comparing sanctioned state-years with very different unsanctioned
  ones, or of the linear functional form of the LP. Selection on the *observed* history is mild (low AUC), and
  correcting for it does not shrink the estimate.
- **Does not show:** that sanctions cause the decline. If senders act on information not in the history (peace
  talks, battlefield turns, an expected war end), the propensity model cannot see it, and every estimator here
  inherits the bias. The low AUC cuts both ways: the decision to sanction is mostly driven by things we do not observe.
- **Not yet done:** standard errors with propensity-estimation uncertainty (cluster bootstrap, DR7); the
  leave-out-top-5 sample under weighting (`empirics/notes/13`, section 5); ACLED; all-case and arms-embargo
  treatments; trimming at 0.05; a richer propensity model (DR3).
