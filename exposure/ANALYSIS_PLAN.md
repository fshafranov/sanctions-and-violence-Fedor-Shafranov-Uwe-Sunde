# Analysis plan — exposure extension

Started 9 Nov 2026. Main project plan: `empirics/ANALYSIS_PLAN.md` (its decisions D1–D10 apply here unless
stated otherwise). Data decisions: `data/README.md`, section 4c.

## 1. Question and design (draft, to be agreed with the user)

Main idea: interact the sanction shock with the target's pre-sanction exposure to the sender, in the panel local
projections of `empirics/scripts/13_local_projections.R`:

    y_i,t+h = b_h x_it + c_h (x_it × E_i,t) + d_h E_i,t + history (2 lags of x and y, y_t) + state FE + year FE

x = new-sanction shock (US, EU, all cases), E = matching exposure (US → `trade_us_*`, EU → `trade_eu_*`,
all cases → `trade_senders_*`), measured over t−3..t−1. c_h > 0 / < 0: larger / smaller response where the
target depends more on the sender.

## 2. Decisions

| ID | Decision | Status |
|---|---|---|
| E1 | Exposure variables stay in the main panel (option B); this project only adds analysis code. | user 2026-11-09 |
| E2 | Exposure measures, timing (t−3..t−1 base; t−1, t), sender groups, zeros vs NA: as in data/README 4c (T5, X2–X5). | user 2026-11-09 |
| E3 | First specification (script 01): LP as script 13 (levels, shock second, FE only), shock × standardised exposure (mean t−3..t−1, standardised over shock years); shocks US w/o ICC, EU, all w/o ICC; exposure trade/GDP (log), trade share, arms share. Proposed by Claude, started on the user's go-ahead. | user 2026-11-09 |
| E4 | Trade/GDP also winsorised at p99 (in-window state-years), as the capped deaths in R10. | user 2026-11-09 |
| E5 | Robustness (script 02): no-recorded-trade = missing (X5 flags), ACLED outcome, in-conflict sample (UCDP ≥ 25 deaths in t−1), exposure terciles; measures trade/GDP (log) and arms share. | user 2026-11-09 |
| E6 | Focused test of arms dependence (arms embargoes × sender share of arms, in wars, as empirics/14; pool senders for power). | open (proposal) |
| E7 | Arms-share groups: none (0 %) / some (below median of positive shares) / high, instead of terciles (most sanctioned targets buy no arms from the sender: US cases, ACLED sample 123 of 228 at 0 %); trade keeps terciles. | proposed by Claude 2026-11-09 (user asked about the zeros), to confirm |
| E8 | All exposure scripts and figures for UCDP, ACLED and GDELT (each in its own window, via `build_source_panel()` of empirics/specifications.R); shared code in `scripts/functions_exposure.R`. | user 2026-11-09 |

## 3. Change log

| Date | Change | Reason |
|---|---|---|
| 2026-11-09 | Folder `exposure/` set up; README, this plan, `scripts/00_setup.R`; master.py stage `exposure` | user: separate project for the trade/arms analysis |
| 2026-11-09 | Script `01_exposure_lp.R` (E3, E4), step `exposure_lp` in master.py; notes `notes/01_exposure_lp.md`. Result: no interaction with exposure; EU arms share borderline. | first analysis |
| 2026-11-09 | Script `02_exposure_robustness.R` (E5), step `exposure_robustness`; notes `notes/02_exposure_robustness.md`. Trade null robust; arms-dependence hint (high tercile, EU/US/all). | user: robustness checks |
| 2026-11-09 17:24 | Scripts 01 and 02 rewritten on `functions_exposure.R`: UCDP, ACLED, GDELT (E8), arms groups (E7), robust to dropped terms; UCDP results of 01 unchanged; superseded UCDP-only figures moved to `archive/exposure_superseded/`. | user: ACLED and GDELT figures |
