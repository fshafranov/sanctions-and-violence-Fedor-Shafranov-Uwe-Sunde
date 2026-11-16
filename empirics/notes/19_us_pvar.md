# 19 — Panel VAR for the US shock, by period

Script `empirics/scripts/19_us_pvar.R`, run 2026-11-16 (72 s, 199 bootstrap draws). Table
`results/tables/pvar_us_periods.md` / `.csv`; figure `fig35_pvar_us_periods.png`.
User question (16 Nov): can the panel VAR be used for the US result, and is it more precise than the LP (13, section 8)?

## Design

- VAR(2) in log(1 + UCDP deaths per 100k) and the number of new US cases without ICC 685, state and year FE, no
  controls; impulse response to a one-unit US shock with no same-year effect on violence ("simple" timing of 08 =
  the LP's "shock second"). Per year h = 1..6 and cumulative.
- Separate VARs for shock years 1991–2019, 1991–99, 2000–09, 2010–19, 2000–19 (own FE and coefficients).
- State-cluster bootstrap: each draw resamples states once and re-estimates every period, so period differences
  get a proper band. The in-conflict sample is not estimated (selecting on violence in t−1 breaks the VAR's dynamics).
- Differs from 08 only in the shock (08: all new GSDB cases).

## Results

| Sample | VAR h = 2 | LP h = 2 | VAR cum. 0..3 | LP cum. 0..3 |
|---|---|---|---|---|
| 1991–2019 | −0.113** (0.050) | −0.105*** (0.039) | −0.213*** (0.089) | −0.222*** (0.079) |
| 1991–99 | −0.175** (0.086) | −0.181** (0.073) | −0.188 (0.152) | −0.301** (0.127) |
| 2000–09 | −0.121** (0.054) | −0.094** (0.042) | −0.270** (0.103) | −0.224** (0.098) |
| 2010–19 | −0.039 (0.051) | −0.066 (0.057) | −0.061 (0.105) | −0.046 (0.100) |
| 2000–19 | −0.055** (0.033) | −0.054* (0.031) | −0.136** (0.076) | −0.112 (0.074) |

- **Same picture as the LP.** Point estimates at h = 2 agree within 0.03 in every period; 2010–19 is null in both.
- **Not more precise where it matters.** At h ≤ p = 2 the VAR and the LP use essentially the same coefficients;
  the VAR's SEs at h = 2 are as large or larger. The VAR gains precision only at longer horizons, by imposing that
  the effect decays through the estimated dynamics (paths die out by h ≈ 4 everywhere). That is why the pooled
  2000–19 cumulative response becomes significant in the VAR (−0.14** at 0..3, −0.19** at 0..6) but not in the LP.
- **1990s cumulative is weaker in the VAR** (−0.19, n.s.): the 1990s VAR has a positive h = 1 response (+0.05).
- **No significant period difference in the VAR**: 1991–99 minus 2000–19 −0.12 [−0.29, 0.03] at h = 2, cumulative
  −0.05 [−0.40, 0.31]; 1991–99 minus 2010–19 −0.14 [−0.32, 0.05]. The LP's "1990s different" is borderline
  (p = 0.055 / 0.11, 13 section 8); the VAR does not strengthen it.

**Reading.** The VAR confirms the sign and size of the US effect (fewer deaths about two years after a new US case)
and its absence for 2010s shocks, but adds no precision at the horizon of interest; the extra significance at long
horizons comes from the VAR's restriction, not from the data. Report it as a robustness check next to the LP. The
decade contrast is weaker in the VAR than in the LP: the main finding is the negative effect, not its timing.
