# 26 — US sanctions as staggered adoption (exploratory, 17 Nov 2026)

Script: `empirics/scripts/26_us_staggered.R` (not in master.py). Output: `tables/us_staggered.csv`,
`figures/fig48_us_staggered.png`, `figures/fig49_us_staggered_trade.png`.

**Design.** Absorbing treatment = a state's first-ever new US case (GSDB, w/o ICC 685); cohort = that year.
Sun–Abraham (fixest `sunab`) vs. naive TWFE event study, never-sanctioned states as controls, state + year FE,
1989–2019, ref. h = −1, end bins ≤ −6 / ≥ 8, SE by state.

**Sample problem.** 75 states got their first US case before 1991 (already treated → dropped); this removes most
of the conflicts that drive the LP result (Iraq, Yugoslavia's later cases, Angola, …). Only 48 of 245 US cases in
1991–2019 are first-ever cases; 47 cohort states, 26 with any conflict year within ±5 years of the cohort year.
Several cohorts are non-conflict targets (Canada, Ireland, Austria, Costa Rica, Belize — trade/regulatory cases).

**Results.**
- Pooled: no effect. ATT (mean h = 0..5) on log deaths +0.03 (SE 0.06); ever-in-conflict states +0.04 (0.08);
  incidence +0.01 (0.04). Path flat; small dip h = 3–4 (≈ −0.1, 5 %) with similar-sized pre-period wiggles.
  TWFE and Sun–Abraham nearly identical → staggered-timing bias is not the issue here.
- US trade exposure (median split in the cohort year, each half vs. never-treated):
  - US share of trade: low-exposure targets dip h = 2–4 (≈ −0.2, ever-in-conflict −0.25), high-exposure ≈ 0.
    Averaged over h = 0..5 neither differs from zero (−0.07 / +0.04). Low-share pre-period h = −3 also ≈ −0.2.
  - Trade with US in % of GDP: "high" −0.23*** (−0.37*** in conflict states), "low" +0.18***. **Not an effect**:
    the high group sits at −0.2..−0.4 *before* treatment as well (level shift relative to h = −1), and the tiny SEs
    come from many near-zero-death small open economies. Measures disagree in sign → no robust trade gradient.

**Reading.** The LP finding (−0.25 at h = 2 in wars) is about new US cases, mostly increments on existing regimes
in conflict states. The first-ever-sanction estimand throws those away and finds nothing. Consistent with the
exposure project (no trade gradient). Not pursued further unless the advisor wants an absorbing-treatment design;
a cleaner version would define adoption per conflict episode (first US case during a given conflict).

## 27 — other control groups (17 Nov 2026, user: never-sanctioned states should not be the control)

Script `27_us_staggered_controls.R`; Callaway–Sant'Anna (`did` 2.5.1, installed into renv, not yet in renv.lock),
doubly robust, base period g−1, bootstrap SE by state. Output `tables/us_staggered_controls.csv`, fig50, fig51.
Trade split now matches controls on exposure too (non-treated classified by mean US share 1989–2019, same cut 4.9 %).

| Control group | ATT, mean e = 0..5 (SE) | High US share | Low US share |
|---|---|---|---|
| A Never sanctioned (78) | +0.01 (0.17) | +0.02 (0.14) | −0.06 (0.33) |
| B Not yet treated only (later first-sanctioned states) | +0.07 (0.18) | +0.17 (0.22) | −0.01 (0.35) |
| C Not yet treated + never (`did` default) | +0.02 (0.16) | +0.04 (0.14) | −0.04 (0.33) |
| D Last-treated cohorts 2014–19 (7 states), years ≤ 2013 | +0.04 (0.21) | too few controls | too few controls |
| E Already sanctioned before 1991, TWFE (forbidden comparison) | +0.06 (0.14) | +0.14 (0.13) | −0.08 (0.25) |

Nothing is significant under any control group. B shows a rising pre-trend (−0.2 at e = −6 → 0 at −1): states
about to be sanctioned are getting more violent relative to later-sanctioned ones — anticipation/selection, the bias
of not-yet-treated controls. Low-exposure dip at e = 2–4 (≈ −0.2) appears in A, C, E but never near significance.
The first-ever-US-sanction design gives a null regardless of the control group.

## 28 — the pre-specified trade test (D12, written before estimation, run once)

D11 in wars (in conflict in t−1) + US share of trade (mean t−3..t−1, standardised; SD 15 pp), terms x, x × E, E.
1,026 state-years, 104 states, 85 shock years (cumulative: 976 / 72).

| | Per year, h = 2 | Cumulative, h = 0..3 |
|---|---|---|
| x at mean exposure | −0.26*** (0.06) | −0.63*** (0.14) |
| **x × E (per SD)** — primary | **+0.03 (0.05), p 0.51** | +0.06 (0.12), p 0.62 |
| x at p25 (US share ≈ 4 %) | −0.28*** (0.07) | −0.67*** (0.17) |
| x at p75 (US share ≈ 17 %) | −0.25*** (0.06) | −0.62*** (0.14) |

**Result: no trade gradient.** The US effect in wars is the same for targets that trade little and a lot with the
US; the point estimate leans (insignificantly) toward a *smaller* decline with more US trade. The main effect is
unchanged from D11 (−0.25). This closes the exposure question for the US in this project; consistent with
exposure/ (01, 02). Whatever drives the decline, it is not visibly economic leverage through trade.

**Post-hoc variant (user, after D12): trade with the US in % of GDP** (SD 8 pp; 1,012 state-years, 82 shock years).
x × E per SD at h = 2: +0.04 (0.08), p 0.64; cumulative +0.05 (0.18), p 0.77; effect at p25 (1.5 % of GDP) −0.29***,
at p75 (8.4 %) −0.26***. Paths h = 1..6 (fig52): interaction never significant under either measure (trade/GDP leans
−0.09..−0.10 at h = 3–4, SE ≈ 0.1). fig53: effect of one US case at h = 2 across exposure — negative and
significant up to ≈ 40 % US share / ≈ 15 % of GDP (where most shocks are), then the band widens over a handful of
high-exposure shocks. Same answer as D12: no trade gradient.
