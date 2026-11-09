# 02 — Exposure interaction: robustness (UCDP, ACLED, GDELT)

Script `exposure/scripts/02_exposure_robustness.R`, run 2026-11-09 17:24. Table
`exposure/results/tables/exposure_robustness.md` / `.csv`; figures `fig_e2_interaction_h2.png`,
`fig_e2_interaction_cum3.png` (interaction by check × source), `fig_e3_groups_trade.png`, `fig_e3_groups_arms.png`.
(The first UCDP-only version of 17:17 is superseded; its figures are in `archive/exposure_superseded/`.)

Same LP as 01; measures trade with sender / GDP (log) and sender share of arms imports; shocks US w/o ICC 685, EU,
all w/o 685; each source in its own window.

## A. Linear interaction (fig_e2)

- **Trade:** the null holds in every check for UCDP and ACLED: "no recorded trade = missing" changes nothing (US 2,
  all 10 shock years drop), in-conflict sample nothing robust (UCDP all cases +0.08**, positive). GDELT: positive
  interactions for EU and all cases in base and NA versions (+0.69***, +0.18***) — more reported violence after
  sanctions on trade-exposed targets.
- **Arms share:** UCDP EU −0.15* (h = 2), in wars −0.47* (cumulative); ACLED and GDELT ≈ 0.

## B. Exposure groups (fig_e3)

Trade: terciles over the sanctioned state-years. Arms share: **none** (0 % of the target's arms from the sender in
t−3..t−1), **some** (below the median of the positive shares), **high** (above it) — terciles do not work for arms,
because most sanctioned targets buy no arms from the sender (US cases in the ACLED sample: 123 of 228) (E7).

- **Trade terciles:** no monotone pattern in any source (UCDP US: low −0.18**, middle −0.02, high −0.11***).
- **Arms groups, h = 2:** EU "high": UCDP −0.31** (17 shock years), ACLED −0.45* (8), GDELT +0.17 (23); EU "none"
  ≈ 0 to −0.23 n.s.; US and all cases: no consistent pattern across sources (GDELT US "none" +0.60**).
  The EU high-arms-dependence decline appears in UCDP and ACLED but rests on 8–17 events.

## Reading

Trade exposure to the sender does not make sanctions reduce violence — robust across checks and the two
fatality sources; GDELT, if anything, shows more reported violence after sanctions on trade-exposed targets.
The arms hint is now narrower: only EU sanctions on targets that buy many arms from EU states, in UCDP and ACLED,
with very few events. A focused test (E6) would need to pool senders (e.g. arms embargoes by any sender × arms
dependence on that sender) to have power.
