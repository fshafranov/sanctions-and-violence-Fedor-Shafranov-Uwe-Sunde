# 20 — Peace agreements and the US effect

Script `empirics/scripts/20_peace_process_lp.R`, run 2026-11-16 (3 s). Table `results/tables/peace_process_lp.md` /
`.csv`; figure `fig36_peace_process_lp.png`. Data: UCDP Peace Agreement Dataset v22.2 and Conflict Termination
v4-2024 → `data/clean/ucdp_peace/peace_cy.csv` (`clean_ucdp_peace.R`, data/README section 4e).
Question (user, 16 Nov, after 13 sections 5–8 and 19): is the deaths decline after new US sanctions just the US
sanctioning wars that were already ending through peace processes?

## Design

Same LP as 13 (US cases without ICC, levels, shock second, 2 lags, state + year FE), all state-years and in conflict in t−1.
(A) dummies for a peace agreement in the target state in t−2..t−1, t−2..t, t−2..t+1 (t+1 partly a bad control → upper
bound for anticipation), also with the before/from-2000 split; (B) shock split by an agreement in t−2..t;
(C) war termination as outcome (episode's last active year in t..t+2, linear probability, in conflict); (D) do
agreements predict a new US case?

## Results

- **Peace processes are rare around US sanctions:** an agreement in t−2..t for 19 % (1990s), 12 %, 9 % of US shock-years;
  in t+1..t+2 for 14 %, 3 %, 11 %. Agreements peak in the 1990s overall, but most 1990s US sanctions were not at a
  settlement.
- **(A) The effect does not move with peace-agreement controls:** all state-years −0.105*** → −0.108 to −0.110***
  (cum. −0.22 → −0.23***); in conflict −0.25*** → −0.26 to −0.27*** (cum. −0.62 → −0.68***), even with the t+1
  agreement included. The 1990s coefficient is unchanged too (−0.21 → −0.22***).
- **(B) The decline comes from US sanctions WITHOUT a peace process:** in conflict, no agreement in t−2..t
  −0.342*** (cum. −0.92***, 67 shock-years) vs agreement under way −0.05 (cum. −0.05, 18), p(equal) 0.10 / 0.06.
  All state-years −0.112*** vs −0.09 (24 shock-years, p = 0.89). The opposite of the settlement story, which predicts
  the decline after sanctions that accompany agreements.
- **(C) US sanctions do not make wars end** (as UCDP codes endings): P(an episode in the state ends in t..t+2)
  +0.02 (mean 0.34), by agreement/ceasefire +0.01, victory +0.04 (p ≈ 0.12), low activity −0.01; all n.s.
  So the effect is fewer deaths within ongoing wars, not more terminated wars.
- **(D) Agreements do not trigger US sanctions;** among wars a same-year agreement makes a new US case **less**
  likely (−0.079***, mean 0.097) — the US holds off when a deal is signed, rather than sanctioning into a settlement.
- **Among wars the 1990s and 2000–19 coefficients are the same** (−0.25 / −0.25, p = 0.99; with controls p = 0.88),
  as in 13 section 8: the decade contrast exists only in the all-state-years comparison.

## Reading

The anticipation concern in its "peace-process" form is not supported: the decline survives agreement controls,
is concentrated in sanctions imposed with no agreement under way, and agreements make US sanctions less likely, not
more. Within wars the US effect is stable across decades (≈ −0.25 at h = 2). What remains open: anticipation that
leaves no trace in signed agreements (military turning points, secret talks — 13 notes, section 6); and (C) shows
the deaths decline is not a faster formal end, so mechanism = lower intensity of continuing wars. Agreement coding
is by conflict location and year (annual timing; same-year ordering unknown).
