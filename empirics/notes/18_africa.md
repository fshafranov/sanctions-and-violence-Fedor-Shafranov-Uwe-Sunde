# 18 — Sanctions and violence in Africa

Script `empirics/scripts/18_africa.R`, run 2026-11-09 (user request: ACLED mostly covers Africa). Table
`empirics/results/tables/africa_lp.md` / `.csv`; figures fig30 (UCDP vs ACLED, same state-years), fig31 (UCDP
1989–2019, all vs in conflict), fig32 (GDELT), fig33 (violence → sanctions).

Same LP as script 13 (shock second, state + year FE, 2 lags), African states (GW 400–626), ≥ 10 years per state.

| Sample | States | State-years | Years |
|---|---|---|---|
| UCDP, main window | 52 | 1,607 | 1989–2019 |
| UCDP and ACLED, same state-years | 48 | 1,282 | 1997–2023 |
| GDELT | 53 | 2,150 | 1979–2021 |

## Sanctions → violence

| Shock (shock years, same state-years) | UCDP same, h = 1 | ACLED same, h = 1 | UCDP same, cum. h = 0..3 | ACLED same, cum. h = 0..3 | UCDP 1989–2019, h = 2 |
|---|---|---|---|---|---|
| UN (28) | −0.29*** | −0.22*** | −0.73*** | −0.30 | −0.06 |
| Arms embargo (40) | −0.19*** | −0.15** | −0.44** | −0.27 | −0.14 |
| EU (43) | 0.00 | −0.19* | −0.19 | −0.34 | −0.21* |
| US w/o ICC (99) | ≈ 0 | ≈ 0 | +0.01 | +0.12 | −0.14** |
| All w/o ICC (166) | ≈ 0 | ≈ 0 | −0.08 | −0.01 | −0.05 |
| Conflict objective (62) | ≈ 0 | ≈ 0 | −0.11 | −0.11 | 0.00 |

- **On the same African state-years, UCDP and ACLED agree** (fig30), but the evidence is thin: the 95% interval
  excludes zero **only at h = 1** and only for **UN sanctions** (UCDP −0.29 [−0.50, −0.09]; ACLED −0.22 [−0.36, −0.09])
  and **arms embargoes** (UCDP −0.19 [−0.32, −0.05]; ACLED −0.15 [−0.29, −0.02]). From h = 2 on, and for all cases,
  US, EU and conflict-objective sanctions at every horizon, the intervals include zero. Cumulative to h = 3 only UCDP
  is significant (UN −0.73***, arms −0.44**), ACLED not (−0.30, −0.27). With 6 shocks × 8 horizons × 2 sources,
  a few single-year rejections are expected by chance; what speaks for it is that both sources pick the same shocks
  and year. **Suggestive, not a finding.** (Corrected 2026-11-09 after the user pointed out that the bands overlap
  zero; the first summary said "short-lived decline".)
- **US cases:** the decline appears only in the 1989–2019 UCDP window (h = 2 −0.14**; in wars −0.39***) and not in
  1997–2023 with either source — the same period pattern as in notes/13 section 5.
- **GDELT:** no decline; point estimates positive (media-reported violence), as in notes/11.

## Violence → sanctions (fig33)

A conflict year raises the probability of new sanctions in Africa in both sources: cumulative to h = 3, all cases
+0.15** (UCDP main) / +0.25*** (UCDP same) / +0.17** (ACLED); UN +0.10–0.11; EU +0.08–0.12. Robust, as everywhere.

## Reading and caveats

Africa gives the cleanest source comparison; the two fatality sources agree in pattern, but the only significant
estimates are single-year (h = 1) declines after UN sanctions and arms embargoes. UN sanctions in Africa often come together with peace agreements,
ceasefires or peacekeeping missions (Liberia, Sierra Leone, Côte d'Ivoire, …), so the decline may reflect the
package, not the sanction — not separable here (anticipation, notes/13). Few events (UN 28, arms 40); many cells.
Next options: UN sanctions with vs without a peacekeeping mission (would need peacekeeping data, e.g. the IPI
Peacekeeping Database or Geo-PKO, download by the user); leave-one-country-out for the UN/arms result.
