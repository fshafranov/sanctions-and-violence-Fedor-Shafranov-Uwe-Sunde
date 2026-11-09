# 01 — Sanction response by exposure to the sender

Script `exposure/scripts/01_exposure_lp.R`, run 2026-11-09 (17:24: UCDP, ACLED, GDELT). Table
`exposure/results/tables/exposure_lp.md` / `.csv`, figures `fig_e1_exposure_lp_<ucdp|acled|gdelt>.png`.
Shared code in `scripts/functions_exposure.R` (data via the main project's `build_source_panel()`; UCDP numbers
unchanged from the first run).

## Specification

Local projections as in `empirics/scripts/13_local_projections.R` (levels, shock second, state + year FE, 2 lags,
SE clustered by state), outcome log(1 + UCDP deaths per 100k), h = 1..8, per year and cumulative, with

    y(t+h) = b_h x(t) + c_h x(t) · Z(t) [+ d_h Z(t)] + history + FE

x = number of new cases in t: US without ICC 685 / EU / all without 685. Z = pre-sanction exposure (mean t−3..t−1)
to the matching sender group (US / EU members of the year / actual senders of the year's new cases), standardised
over the sanctioned state-years: **b_h = response at average exposure, c_h = additional response per 1 SD more
exposure**. Exposure measures: trade with sender / GDP as log(1 + %) and winsorised at p99 (user 9 Nov), sender share
of the target's goods trade, sender share of its arms imports. Shock years with missing exposure are dropped.

## What the results show (per year, h = 2 unless stated)

| Shock | Exposure | b (at mean) | c (per SD) | shock years |
|---|---|---|---|---|
| US w/o ICC | trade/GDP (log) | −0.112*** | +0.034 | 186 |
| US w/o ICC | trade/GDP (winsorised) | −0.109*** | +0.015 | 186 |
| US w/o ICC | share of trade | −0.105*** | −0.000 | 200 |
| US w/o ICC | share of arms | −0.081* | −0.002 | 136 |
| EU | trade/GDP (log) | −0.189** | +0.177 | 107 |
| EU | trade/GDP (winsorised) | −0.184** | +0.217 | 107 |
| EU | share of trade | −0.148** | −0.126 | 112 |
| EU | share of arms | −0.176* | −0.146* (h = 1: −0.144*) | 74 |
| All w/o ICC | trade/GDP (log) | −0.059*** | +0.045 | 456 |
| All w/o ICC | share of trade | −0.017 | −0.010 | 476 |
| All w/o ICC | share of arms | +0.005 | −0.036 | 350 |

- **No evidence that exposure to the sender changes the response.** The interaction c_h is insignificant at every
  horizon for US and all cases, for every exposure measure, per year and cumulative. Point estimates for trade/GDP
  are, if anything, positive (more exposed targets: smaller decline), the opposite of "sanctions bite harder".
- EU, sender share of arms: the only borderline negative interaction (h = 1–2, p < 0.1, 74 shock years) — more
  dependence on EU arms, larger decline. Thin and one of many cells: not a finding on its own.
- Log vs winsorised trade/GDP: practically identical (user's winsorising check).
- The b_h column reproduces the familiar dip at h = 2 for US cases (−0.11, as in script 13). The EU dip (−0.15 to
  −0.19) has not been estimated before in the main project and is worth a separate look. The "all cases" b_h differs
  between exposure measures (−0.059 vs −0.017) because the samples differ (shock years with trade data) and b_h is
  evaluated at each measure's mean; do not read it as a new all-cases effect.

## Caveats

- Many cells (3 shocks × 4 measures × 8 horizons × 2 types): single p < 0.1 cells are expected by chance.
- Exposure is goods trade only; arms = major conventional weapons (SIPRI).
- Same identification limits as script 13 (annual timing, anticipation, war ends; empirics/notes/13).

## ACLED and GDELT (added 17:24, user request)

h = 2 per year, interaction per SD (US / EU / all, trade/GDP log): ACLED −0.04 / −0.01 / +0.02, GDELT −0.02 /
**+0.69*** / +0.18***** (winsorised: +0.84***, +0.13***). Response at mean exposure: ACLED and GDELT ≈ 0 or positive
for US cases (no US dip outside UCDP, as in empirics/13 section G).
- ACLED: nothing, apart from EU sender share of trade −0.20*** (one cell).
- GDELT: more trade-exposed targets show MORE media-reported violence after EU and all-case sanctions. GDELT counts
  events in the news (units differ: violent events per 10,000 events); plausible reading: sanctions on closely
  linked targets draw more coverage, or more low-level unrest. Same direction as GDELT's rise in empirics/11.
- So across sources, no sign that trade exposure makes sanctions reduce violence; with GDELT the opposite sign.

## Next

NA robustness (`trade_<g>_zero_imputed`), exposure terciles instead of a linear interaction, ACLED outcome,
in-conflict sample (as script 14), EU dip on its own.
