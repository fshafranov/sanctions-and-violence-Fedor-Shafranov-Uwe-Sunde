# Analysis plan: sanctions and violence as a "cycle"? A panel-VAR replication of Jaeger & Paserman (2008)

**Status:** draft, 2026-10-21. To be fixed (and committed to git) **before** any estimation.
Decisions still open are marked **[D#]** (section 9). Changes after the plan is fixed are logged in section 11
with date and reason, so that what was pre-specified and what was added later stays visible.

Template: Jaeger, D. A. & Paserman, M. D. (2008), "The Cycle of Violence? An Empirical Analysis of Fatalities in
the Palestinian-Israeli Conflict", *AER* 98(4): 1591–1604 (henceforth JP; `papers/Jaeger-CycleViolenceEmpirical-2008.pdf`).

---

## 1. Question and mapping to JP

JP ask whether Israeli and Palestinian fatalities form a cycle: does violence by side A predict violence by
side B, and vice versa? They estimate two **reaction functions** in a VAR and test Granger causality in each.

We ask the same question for **sanctions and organized violence** in a country-year panel:

| JP | This project |
|---|---|
| Palestinian fatalities | Organized violence in the target country (UCDP) |
| Israeli fatalities | New sanctions imposed on the country (GSDB) |
| "Israeli reaction function": Palestinian fatalities on lagged Israeli fatalities | **Violence reaction function**: violence on lagged new sanctions → do sanctions deter / incapacitate (−) or escalate (+)? |
| "Palestinian reaction function": Israeli fatalities on lagged Palestinian fatalities | **Sender reaction function**: new sanctions on lagged violence → do senders react to violence? |
| one conflict, daily, Sep 2000–Jan 2005 | ~170 states, annual, 1989–2019 (main) |
| day-of-week + 7 phase dummies + barrier length | country FE + year FE + lagged controls |

Four possible outcomes, as in JP: a cycle (both directions), one-way in either direction, or neither.

**Expected priors (stated now, not tested):** strong sender reaction (sanctions are often imposed *because* of
violence; GSDB objectives `end_war`, `prevent_war`, `territorial_conflict`); sign of the violence response a priori
ambiguous (deterrence / incapacitation vs. escalation / resource substitution, Urtuzuastigui & Koren 2024).

## 2. Data and variables

Panel: `data/processed/sanctions_violence/sanctions_violence_panel.csv` (Gleditsch–Ward states; construction in
`data/README.md`). Unit `gwcode` × `year`.

**Sanctions (the "Israeli" side).** Event (flow) variables, `data/README.md` S11:

| Spec | Variable | Note |
|---|---|---|
| Incidence | `new_sanction` | 1 if ≥ 1 GSDB case begins against the state in t |
| Levels | `n_new_cases` | number of cases beginning in t (89% zeros, 8% ones in 1989–2019) |

Stocks (`n_cases_received`, `any_sanction`) are **not** modelled as VAR variables (near-unit-root, "a shock to the
stock" is not a meaningful experiment); the lagged stock enters as a control (section 3). `n_joined_cases` is not used.

**Violence (the "Palestinian" side)** — UCDP Organized Violence country-year, available from 1989:

| Spec | Variable | Note |
|---|---|---|
| Incidence | `viol_inc` = 1 if `cumulative_total_deaths_in_orgvio_best` ≥ 25 | UCDP activity threshold **[D1]** |
| Levels | `viol_lev` = log(1 + `cumulative_total_deaths_in_orgvio_best_pc`) | deaths per 100,000, log(1 + x) because of extreme years (see note) **[D1, D2]** |

*Why a log for deaths and nothing else.* In 1989–2019, 72% of state-years have zero deaths, the 99th percentile is
45 per 100,000, and Rwanda 1994 has 12,577 (next highest: Eritrea 1999, 754). The top 1% of state-years account
for 99.9% of the variance of raw deaths per capita, so a linear VAR in raw deaths would in effect be a regression
on a handful of genocides and wars. log(1 + x) keeps the zeros and compresses the tail. Caveat (Chen & Roth 2024,
*QJE*): with zeros, the size of log-type coefficients depends on the units, so they are not percentage effects;
signs and Granger tests are what we interpret, and magnitudes come from the incidence specification and the PPML
check (R3). Raw deaths per 100,000 (JP's choice of raw counts) are a robustness check, winsorised at the
99th percentile (R10). `n_new_cases` (max 10) and the GDELT measure (bounded shares, 2% zeros) stay untransformed.

**Violence, alternative source: GDELT 1.0** (media-reported conflict events, 1979–2021; `data/README.md` G1–G13).
Used as a **separate robustness measure** (R12), with the whole analysis repeated:

| Spec | Variable | Note |
|---|---|---|
| Levels | `gdelt_viol` = `assault_norm1000` + `fight_norm1000` + `mass_violence_norm1000` (untransformed) | violent events per 1,000 GDELT events in the country-year (normalised for media volume, G13; median 50, max 667, 2% zeros). CAMEO root COERCE (threats, repression) is left out of the measure because it is used as the anticipation proxy (R6) |
| Incidence | `gdelt_inc` = 1 if `gdelt_viol` is above the state's own 1979–2021 median **[D6]** | GDELT has no natural event threshold |

Why it is useful: (i) independent source (news reports instead of UCDP's fatality coding), so agreement with the
UCDP results is not an artefact of one dataset; (ii) measures violence **below the UCDP 25-death threshold**
(clashes, assaults), closer to JP's "intended violence" (Appendix II); (iii) starts in **1979**, so the analysis
can include the late Cold War (1979–1988). Caveats: counts of reports, not of deaths; coverage differs by country
and is thin before 2013 (historical backfile); missing for the GDR, South Yemen, Abkhazia and South Ossetia (G11)
and after 2021 (G7).

**Controls X_it** (lagged one year so they are predetermined): `n_cases_received` (stock in force), log `gdp_ext`
growth, `v2x_polyarchy` (`ex_yugo_1991_2016` removed 2026-10-23, see change log; Yugoslavia handled in R9).

## 3. Main specification (JP eq. 1–2, Table 1)

For state i, year t, lag length p:

    V_it = Σ_{k=1..p} α_k V_i,t−k + Σ_{k=1..p} β_k S_i,t−k + γ'X_i,t−1 + μ_i + τ_t + ε_it     (violence reaction function)
    S_it = Σ_{k=1..p} δ_k S_i,t−k + Σ_{k=1..p} θ_k V_i,t−k + γ'X_i,t−1 + μ_i + τ_t + u_it     (sender reaction function)

- Estimated **equation by equation with OLS** (as JP; identical to system estimation because the regressors are the
  same in both equations), country fixed effects μ_i and year fixed effects τ_t (the analogue of JP's phase dummies:
  they absorb common shocks such as the 2002 ICC aid cut or the 2014 Russia counter-sanctions).
- Incidence equations are linear probability models (JP's choice).
- Standard errors **clustered by country** (JP: heteroskedasticity-robust; clustering is the panel analogue and
  also covers serial correlation).
- **Lag length p = 2 [D3]** (annual data; JP's 14 daily lags are not feasible). Lag-length grid in section 6.
- Sample **1989–2019** (UCDP from 1989; GDP and population without extension to 2019) **[D4]**.
- Estimation sample rule: keep every state with ≥ `MIN_OBS` = 10 complete years; **no variance filter** (states
  that never had violence are informative zeros, dropping them selects on the outcome; section 6a). Every
  exclusion is logged.
- Software: R, `fixest::feols` (fixed effects, clustering, Wald tests). Nickell bias: with T ≈ 31 the FE bias in
  the own-lag coefficients is of order 1/T and small for the cross-lag (Granger) coefficients; GMM is a
  robustness check, not the main estimator (section 6).

## 4. Tests and quantities reported

1. **Granger causality** (JP Table 1, penultimate row): Wald test that all p cross-lag coefficients are zero,
   with the clustered covariance: H0: β_1 = … = β_p = 0 (sanctions do not Granger-cause violence) and
   H0: θ_1 = … = θ_p = 0 (violence does not Granger-cause sanctions). χ²(p) statistic and p-value.
2. **Signs of the cross-lag coefficients**: negative significant β → net deterrence / incapacitation;
   positive → escalation (JP's reading of the boxed coefficients).
3. **Long-run cumulative effects** (JP Section V): impulse responses implied by the levels VAR, iterated forward
   10 years; report the cumulative response of violence to one new sanction case and of new sanctions to a
   one-unit violence shock, with confidence bands from a **country-cluster bootstrap** (resample states with
   replacement, 999 draws, re-estimate, recompute; percentile bands).
   - Main IRF: JP's "simple" IRF (footnote 12): no contemporaneous effect (Θ_0 = I).
   - Check: orthogonalised IRFs with both Cholesky orderings (sanctions first / violence first). With annual
     data within-year feedback is likely, so ordering sensitivity is reported, not assumed away.
4. **Stability**: eigenvalues of the companion matrix inside the unit circle (report the largest modulus).

## 5. Empirical (nonparametric) response functions (JP Section III.A, Figures 2A/2B)

Before the regressions, model-free response functions, panel version of JP's formula:

    SanctionRF_k = [ mean(V_i,t+k | S_it = 1) − mean(V) ] / mean(n_new_cases | S_it = 1),   k = 0..10
    ViolenceRF_k = [ mean(S_i,t+k | V-event_it = 1) − mean(S) ] / mean(V | V-event_it = 1)

- Version (a) as in JP, raw means; version (b) on two-way FE residuals (country and year means removed), because
  in a panel the raw version mixes "after a sanction" with "in a sanctioned country".
- 95% bands from standard errors clustered by country.
- Naming follows the trigger, as in JP: "SanctionRF" = how violence moves after a new sanction.

## 6. Robustness (each mirrors a JP check; all pre-specified)

| # | JP | Here |
|---|---|---|
| R1 | Table 2: lag structures (own, opposite) 4/7/14/21 days | (own, opposite) lags ∈ {(1,1), (2,1), (2,2), (3,1), (3,2), (3,3)}; selection by BIC reported |
| R2 | Table 3: time aggregation (weekly, biweekly, monthly) | 2-year and 3-year aggregation of the panel; finer frequency see section 8 |
| R3 | Footnote 3: probit / zero-inflated Poisson | incidence: FE logit; levels: Poisson PPML on deaths per 100,000 (raw and winsorised at p99) and `n_new_cases`; FE as dummies in `glm` (same estimates as `fixest::feglm` / `fepois`). **Done** (09, 2026-10-22) |
| R4 | Footnote 4: no control variables | FE only (no X); no year FE (cf. JP footnote 5: barrier result depends on phase dummies) |
| R5 | Footnote 7: disaggregation (civilians, location, time) | by violence type: state-based, non-state, one-sided (`sb_`, `ns_`, `os_`), parties vs civilians; by period: 1989–2001 / 2002–2019; by region |
| R6 | Section IV: Israeli preventive measures (omitted anticipation) | add a proxy for anticipated violence: GDELT `coerce_norm1000` (threats, coercion), lagged, in both reaction functions |
| R7 | — (panel-specific) | sanction heterogeneity: UN / EU / US new sanctions; arms embargoes; conflict-objective vs other objectives (`new_conflict_obj_sanction`) — the latter separates mechanical reaction from other sanctions |
| R8 | — (panel-specific) | Nickell bias: panel-VAR GMM (`panelvar::pvargmm`, forward orthogonal deviations, collapsed instruments, ≤ 2 instrument lags) with Hansen test; heterogeneous-panel Granger test (Dumitrescu–Hurlin 2012) |
| R9 | — | without group cases (cases against groups expanded to all members, e.g. 685 ICC, 995, 559; `data/README.md` S10); without ex-Yugoslavia 1991–2016 |
| R10 | — | sample to 2023 (`gdp_ext`, `pop_ext`); levels untransformed: raw deaths per 100,000 (as JP's raw counts), winsorised at the 99th percentile, and unwinsorised |
| R11 | — | lifting: replace `new_sanction` by `lifted_sanction` (does falling violence predict lifting; does lifting predict violence?) |
| R12 | Appendix II: alternative measures of (intended) violence | **GDELT as a separate violence measure** (section 2): the full analysis — Table 1 and Granger tests, Table 2 lag grid, empirical response functions, cumulative IRFs — re-estimated with `gdelt_viol` / `gdelt_inc` in place of the UCDP measures, on (a) 1991–2019, the estimation years of Table 1, and (b) 1981–2021, the full GDELT period (1979–80 serve as lags). Script `11_gdelt.R`; levels measure expressed as % of all events (`gdelt_lev` = `gdelt_viol`/10), IRF violence shock = one within-state SD; extra check without state-years with < 100 GDELT events. Reported side by side with the UCDP results; in (b) controls without GDP extension end in 2019 → use `gdp_ext` |

### 6a. Stationarity and persistence protocol (before Table 1)

**Principle: unit-root tests are a diagnostic of the series, not a sample filter.** A state whose violence series
is zero in every year (or whose `new_sanction` never changes) has no unit root — a constant is trivially
stationary. Panel unit-root tests fail on such units only *numerically* (the unit-level ADF regression is
singular), which is why the old notebooks dropped them. They are not dropped from the VAR, for two reasons:
(i) in the FE regression a never-violent state still carries information — its rows say "sanctions came and
violence stayed at zero", which pulls β towards zero; dropping these states **selects on the outcome** and biases
β away from zero; (ii) the estimand would silently change from "all states" to "states that turned out violent".

Scale of the issue, 1989–2019 (201 states, 5,949 state-years):

| Series | States with a constant series | Note |
|---|---|---|
| violence levels (deaths per 100,000) | 81 (2,294 state-years) | all zero |
| violence incidence (≥ 25 deaths) | 104 | 93 never, 11 always (e.g. long wars) |
| `new_sanction` | 34 | mostly never a new sanction |
| both violence and sanctions constant | 25 | contribute only to the controls |

Protocol:
1. **Classify** every state × series as *constant*, *too short* (< `MIN_OBS` years), or *testable*; report counts
   per series (table U0). No state leaves the VAR sample because of this.
2. **Unit-level ADF** for testable units (intercept; with trend for GDP), lag order by AIC, max 2.
   Combine with **Fisher-type tests** — Maddala–Wu (χ²) and Choi (inverse normal) — which allow an unbalanced
   panel and different lag lengths (`plm::purtest(test = "madwu" / "invnormal")`). Also report the share of
   units rejecting at 5%. IPS as a check where the panel is balanced.
3. **Cross-sectional dependence:** sanction waves and global conflict trends are common shocks, which first-
   generation tests ignore. Pesaran (2007) CIPS (`plm::cipstest`) on the balanced sub-panel; and all tests
   repeated on year-demeaned series (the year FE of the main model).
4. **Binary series** (`new_sanction`, `viol_inc`): a 0/1 variable is bounded and cannot have a unit root in the
   usual sense; report persistence instead — the pooled within-AR(1) coefficient (with the Nickell correction
   ≈ (1 + ρ)/(T − 1)) and the transition probabilities P(1→1), P(0→1).
5. **The decisive check is VAR stability** (section 4.4): all eigenvalues of the estimated companion matrix
   inside the unit circle, for every specification. If a specification is unstable, its IRFs are not reported.
6. Small-sample caveat: with T ≈ 31 and many zeros, unit-level ADF tests have low power and size distortions;
   results are read together with steps 4–5, not alone.

### 6b. Which population? (estimand)

The main estimand is the **average over all states**. Because 40% of states never have organized violence in
1989–2019, a second estimand — the response **among conflict-prone states** — is reported as a robustness
check. "Conflict-prone" must be defined **without using the 1989–2019 outcomes**, otherwise it reintroduces the
selection above **[D7]**:

- (a) any armed conflict 1946–1988 (UCDP/PRIO via `n_conflicts_all`): 76 states — but misses most states born
  after 1988 (56 states without pre-1989 conflicts have violence later);
- (b) split-sample: classify on 1989–2003, estimate on 2004–2019;
- (c) interaction instead of a split: cross-lag × pre-sample conflict history, keeping one sample.

## 7. Identification and interpretation (JP Section II)

Granger causality is **predictive precedence, not causation**. JP argue (i) fatalities have a large random
component and (ii) plausible forward-looking behaviour would bias against their result. Our version:

- **Sender side.** Senders are forward-looking: sanctions are often imposed *in anticipation* of violence
  (arms embargoes, `prevent_war`). This biases the violence reaction function **towards a positive β**
  (sanctions "predict" violence that would have come anyway). Hence: a **negative** (deterrence) finding is
  robust to this bias; a positive (escalation) finding needs R6 (anticipation proxy) and R7 (objectives) to be credible.
- **Violence side.** Violence → sanctions is expected partly by construction (objectives). The interesting
  quantity is the size, lag and asymmetry (JP's ~10:1 asymmetry), plus heterogeneity by sender.
- **Common shocks** (coups, elections, regime change) handled by year FE, country FE, lagged controls;
  remaining confounding acknowledged.
- **Timing.** Annual data blur within-year sequence (JP's Table 3 shows aggregation matters). Contemporaneous
  correlations are reported and the ordering checks in section 4 make the timing assumption explicit.

## 8. Output and code (structure agreed 2026-10-21)

All scripts start with `source(here::here("empirics", "scripts", "00_setup.R"))`, estimation scripts also source
`functions.R`; scripts exchange results only via files in `empirics/results/` and are run in order by `master.py`.

| # | Script | Content | JP analogue / plan section | Status |
|---|---|---|---|---|
| 00 | `00_setup.R`, `functions.R` | packages, paths, main choices; shared helpers (lags, OLS with FE, half-panel jackknife, Wald tests, VAR stability) | — | done |
| 01 | `01_prepare_sample.R` | variables of section 2, sample rule, exclusion log | — | done |
| 02 | `02_descriptives.R` | figures 1–9, summary of the sanction flows | Figure 1 | done |
| 03 | `03_data_diagnostics.R` | unit roots and persistence, constant series, panel balance, lag-length criteria (6a) | — (appendix) | done |
| 04 | `04_reaction_functions.R` | both equations, OLS and half-panel jackknife, Granger tests (Table 1); lag grid (Table 2) | Tables 1–2 | done |
| 05 | `05_granger_heterogeneous.R` | Juodis–Karavias–Sarafidis bias-corrected Granger test (balanced panel); Dumitrescu–Hurlin | — | planned |
| 06 | `06_model_diagnostics.R` | residual autocorrelation, cross-sectional dependence of residuals (Pesaran CD), stability across specifications | — (appendix) | done |
| 07 | `07_empirical_response.R` | model-free response functions (raw and two-way FE) | Figures 2A/2B | done |
| 08 | `08_irf.R` | impulse responses (simple, both Cholesky orderings), cumulative effects, country-cluster bootstrap | Section V | done |
| 09 | `09_robustness.R` | **done (2026-10-22): R3 logit / PPML; R10 raw deaths (uncapped, p99, p95); R10 dynamics (IRFs + response function, deaths capped at p99, fig17); 2026-10-23: part 4 same-sample control check (D8), part 5 Yugoslavia (R9)**; planned: leave-one-country-out, anticipation (objective split, GDELT coerce, R6), time aggregation, splits (sender, type, objective), Driscoll–Kraay, to 2023, lifting | Tables 3–4, R1–R12 | partly done |
| 10 | `10_pvar_gmm.R` | GMM panel VAR (FOD, collapsed instruments lags 2–5, year-demeaned), Hansen, Andrews–Lu | R8 | done |
| 11 | `11_gdelt.R` | GDELT robustness: sample + validation against UCDP, stationarity, Table 1 (OLS + jackknife, incl. thin-coverage check), lag grid, LP-DiD, cumulative IRFs with bootstrap; on 1991–2019 and 1981–2021 | R12 | done |
| 12 | `12_lpdid.R` | **extension, not base case:** LP-DiD event study with clean controls (Dube et al.), UCDP and GDELT | — | done |

Methodological additions since the first draft (see `papers/README.md`): the half-panel jackknife is reported next to
FE-OLS for all reaction functions (Nickell bias with N ≈ 170, T ≈ 30); the Juodis–Karavias–Sarafidis test is the main
heterogeneous panel Granger test; an LP-DiD event study (non-absorbing treatment, clean controls) is kept as a separate
**extension** (`12_lpdid.R`), not part of the Jaeger & Paserman base case; GMM Wald tests are approximate because `panelvar` does not store the full
coefficient covariance (only standard errors). The old notebooks are in `archive/rmd/legacy_empirics/`.

**Open (D8):** main specification with or without controls. Same-sample check (09 part 4, container test run of
2026-10-23, to be confirmed by the Mac run): the sample difference (174 vs 197 states) does not matter. **Sanctions →
violence, incidence:** the negative sum (−0.035) appears only when the sanction stock in t−1 is controlled for; FE only,
GDP growth, democracy or the stock in t−3 give sums of −0.009 to 0.000. The stock in t−1 contains the tested lags
(it is a function of new cases in t−1 and t−2), so the incidence result is largely mechanical. **Levels:** −0.035 to
−0.050 and significant in every version. **Violence → sanctions:** incidence significant in every version; levels lost
with GDP growth (as before). Proposal unchanged: FE only as the main specification; stock in t−3 if a stock control is
wanted.

**Extension (not part of this plan):** monthly frequency with UCDP GED events and dated sanction impositions
(UN Security Council resolution dates, EU Official Journal), to match JP's daily design more closely.

## 9. Decisions to confirm before fixing the plan

| # | Decision | Proposal | Alternative |
|---|---|---|---|
| D1 | Violence measure | all organized violence, best estimate (`cumulative_total_deaths_in_orgvio_best`); incidence threshold 25 deaths | battle deaths among parties only (`…_parties_…`, used in the old notebooks); state-based conflict only |
| D2 | Levels transformation of deaths | log(1 + deaths per 100,000) | raw deaths per 100,000, winsorised (closest to JP; R10); PPML on counts (R3) |
| D3 | Main lag length | p = 2 | p = 1; chosen by BIC |
| D4 | Main sample | 1989–2019 | 1989–2023 with extended GDP/population |
| D5 | Lifted sanctions | robustness only (R11) | third variable in the main VAR |
| D6 | GDELT incidence definition | above the state's own median of `gdelt_viol` | any `mass_violence` event; top quartile of the pooled distribution; levels only |
| D7 | Conflict-prone subsample (6b) | (b) split-sample classification | (a) pre-1989 conflict history; (c) interaction |
| D8 | Main specification with or without controls (section 8) | FE only; controls one at a time as robustness | lagged controls in the main specification |
| D9 | Symmetry of the incidence specification: now sanction **onset** (`new_sanction`) vs conflict **presence** (`viol_inc`) | open — to discuss with the advisor | conflict onset (and termination) on the violence side; sanctions in force on the sanction side; keep and rename |
| D10 | Which sanction events count | all new GSDB cases, any sender and objective, group cases once per member | conflict-objective cases only (`new_conflict_obj_sanction`); include extensions / joined cases |

## 10. Closest prior work and how this project differs (checked 2026-10-21)

Cross-country panel VARs with sanctions or violence are few. The two closest, read in full (PDFs in `papers/`):

**Dizaji & Murshed (2024), "External arms embargoes and their implications for government expenditure,
democracy and internal conflict", *World Development* 173, 106410** — the closest paper.

| Check | What they do | Consequence for us |
|---|---|---|
| Country selection | 48 developing countries, 1990–2017, list in the appendix; no selection rule stated in this paper. The same authors' 2023 paper (below) uses the same list minus Syria and says the countries were chosen "according to data availability". The list includes many states never under an arms embargo (e.g. Brazil, Chile, Mexico, Uruguay, Poland, Malaysia) and leaves out most embargoed ones (e.g. Iraq, Libya, Liberia, Sierra Leone, DRC, Somalia, Rwanda, Afghanistan, ex-Yugoslavia, North Korea) | not a sample of sanctioned or conflict states; our all-states panel with logged exclusions avoids this |
| Sanctions measure | **No embargo data.** The "embargo" is a one-s.d. negative shock to arms imports / GDP (SIPRI), plus an asymmetric version, min(0, Δ arms imports) | any fall in arms imports (procurement cycles, budgets) is read as an embargo; we use dated sanction impositions from GSDB |
| Violence measure | ICRG *internal conflict risk* index (0–12, higher = less risk), plus ethnic/religious tensions. Footnote 6: they do **not use UCDP/PRIO "as there is insufficient variation in that data set for our purposes"** | they avoid the zeros problem by switching to an expert risk rating, not fatalities; we keep fatality data and deal with zeros explicitly (incidence spec, 6a, 6b, R3) |
| Estimator | "Unrestricted PVAR in levels" with country effects; they state that OLS is consistent because only lags are on the right-hand side. No GMM / forward orthogonal deviations, **no discussion of Nickell bias**, **no year effects** (common shocks only in the CIPS unit-root test) | our main spec has year FE; Nickell bias addressed (T ≈ 31 argument + GMM check R8) |
| Lags / stability | 2 lags by SIC/HQ (EViews-style criteria table); roots inside the unit circle | same checks in our plan (4.4, R1) |
| Inference | IRFs with **68% bands (±1 s.d.)**, significance judged on these | we report 95% bands from a country-cluster bootstrap |
| Identification | Cholesky, arms imports ordered first ("most exogenous"); generalized IRFs as an ordering check | similar ordering checks (4.3) |
| Granger tests | **None**; only impulse responses | Granger tests in both directions are our main tool (JP) |
| Unit roots | LLC, IPS, Fisher-ADF/PP, CIPS; some CIPS cells "NA" | our protocol 6a |
| Finding | negative arms-import shocks → lower military spending, better democracy scores, **more internal conflict** (ICRG) | prior for R7 (arms embargoes) |

**Dizaji & Farzanegan (2023), "Democracy and Militarization in Developing Countries: A Panel Vector Autoregressive
Analysis", *Defence and Peace Economics* 34(3): 272–292** — same design and same 47 countries ("according to data
availability"; they argue selection bias is small because the sample covers 69% of world population), 1990–2017,
2 lags (2 and 3 as robustness), OLS PVAR, 68% bands, Cholesky + generalized IRFs, cross-sectional dependence
(Pesaran CD) rejected; no conflict variable. Relevant only as the methodological template of the closest paper.

**Positioning.** Neither paper (i) measures sanctions directly, (ii) uses fatality-based violence data, (iii) covers
all states, (iv) tests Granger causality in both directions, (v) includes year effects or addresses Nickell bias.
These five points are what this project adds.

Other related work (abstracts only, not yet read in full): Bove & Elia (2011/2013, opium prices ↔ violence, panel
VAR over Afghan provinces with CCE / mean-group); Meierrieks & Gries (2013, *JPR*, panel Granger tests terrorism ↔
growth, 160 countries); Drakos & Konstantinou (2014, *DPE*, panel VAR terrorism, crime, public spending, Europe);
Paliouras et al. (2025, *J. Econ. Finance*, panel VAR terrorism, tourism, growth, 28 countries); Hultman & Peksen
(2017, *JCR*, sanctions and conflict intensity in Africa); Asali, Abu-Qarn & Beenstock (2017, *JAE*, nonlinear VAR
re-analysis of JP).

## 11. Change log of the plan

| Date | Change | Reason |
|---|---|---|
| 2026-10-21 | First draft | — |
| 2026-10-21 | GDELT added as a separate violence measure (section 2, R12, D6); COERCE kept only as anticipation proxy (R6) | user request: independent source, sub-threshold violence, longer period |
| 2026-10-21 | Levels: log(1 + x) instead of asinh for deaths; GDELT measure untransformed; reason for transforming deaths documented (section 2) | user question; data: top 1% of state-years = 99.9% of the variance of raw deaths |
| 2026-10-21 | Unit-root protocol (6a) and estimand / conflict-prone subsample (6b, D7) | user concern: many zeros, constant series would exclude many states |
| 2026-10-21 | Section 10: closest prior work checked in full (Dizaji & Murshed 2024; Dizaji & Farzanegan 2023) | positioning; user request |
| 2026-10-21 | Section 8 rewritten to the agreed script structure (03 data diagnostics … 10 GMM); jackknife, JKS test, LP-DiD added; decision D8 added | after first estimates (Table 1, lag grid, GMM) |
| 2026-10-22 | GDELT robustness moved from 09 into its own script `11_gdelt.R` (R12); window (a) set to the Table 1 estimation years 1991–2019; thin-coverage check added | user request: separate GDELT file |
| 2026-10-22 | LP-DiD moved out of 07 into `12_lpdid.R` and labelled an extension; base case = Jaeger & Paserman (04, 07 response functions, 08); GDELT script 11 now reports JP response functions instead of LP-DiD | user: LP-DiD not yet a confirmed approach |
| 2026-10-22 | R3 implemented in `09_robustness.R` (logit, PPML on deaths per 100k raw and winsorised); results in the brief | user request |
| 2026-10-22 | R10 (raw deaths per 100k in the linear levels VAR, uncapped and capped at p99 / p95) implemented in `09_robustness.R`; sample to 2023 still open | user request |
| 2026-10-22 | R10 dynamics: cumulative IRFs (bootstrap) and response function of the levels VAR with deaths capped at p99 (`09_robustness.R` part 3, fig17) | user request: magnitudes in deaths |
| 2026-10-23 | Script table updated (03/06/08 done; 09 parts listed); next steps agreed: same-sample control check (D8), leave-one-country-out, anticipation via objective split | end-of-session update |
| 2026-10-23 | `ex_yugo_1991_2016` removed from `CONTROLS` (00_setup.R). Reason: with state FE it is identified only from 2017–19 in 7 ex-Yugoslav states (Yugoslavia/FRY itself: always 1, absorbed), all with zero new sanctions and zero conflict; it cannot handle the real issue, the attribution of one GSDB case to several successor states. Replaced by R9 in `09_robustness.R` part 5 (drop the ex-Yugoslav states; ex-Yugoslav states as one cluster). Changes all "with controls" results slightly (test run: S → V incidence 7.27, p = 0.026, unchanged; V → S incidence 6.22 instead of 6.11). | review of the controls |
| 2026-10-23 | `09_robustness.R` part 4 (D8): same-sample control check — FE only, each control alone, sanction stock in t−1 vs t−3, all controls, on one common sample (4,888 obs., 174 states). | decision D8; stock in t−1 contains the tested sanction lags |
| 2026-11-09 | Decisions D9 (onset vs presence in the incidence specification) and D10 (which sanction events count) added; D1 note: the 25-death threshold is applied to the country-year total of all organized violence, not per conflict as in UCDP. No code changed. Details: `empirics/notes/variable_coding_and_functions.md` | meeting preparation, review of the variable coding |
| 2026-11-09 | New script `13_local_projections.R`: plain panel local projections (Jorda; no DiD), both directions, two timings (shock first / shock second), per-year and cumulative, FE only and with controls; sanction measures all / all without ICC case 685 / US / US without case 685 (built from the new case-level file `data/clean/gsdb/gsdb_new_cases.csv`). Notes: `empirics/notes/13_local_projections.md` | advisor meeting 9 Nov: focus on LP instead of the panel VAR; US sanctions only; drop the ICC group case |
| 2026-11-09 | ACLED as a second violence source in `13_local_projections.R`: `acled_inc` (≥ 25 ACLED organized-violence fatalities) and `acled_lev` (log(1 + fatalities per 100k)), state-years inside ACLED coverage 1997–2023, states with ≥ 10 covered years (58 states); plus UCDP re-estimated on the same ACLED state-years to separate source from sample. Data decisions: `data/README.md` A1–A7 | advisor meeting 9 Nov: "LP, without ICC, with ACLED, US sanctions only" |
| 2026-11-09 | New script `14_conflict_sample_lp.R`: LP on state-years in conflict in t−1; shocks arms embargo (any), conflict objective (any mention), arms embargo only; other new sanctions as separate regressor; outcomes still in conflict and log deaths; state FE vs region FE; shock second (main) and first. Design agreed with the user before estimation. Notes `empirics/notes/14_conflict_sample_lp.md` | user: effect of arms embargoes and conflict-aimed sanctions; compare wars with wars (R7) |
| 2026-11-09 | Specification table `empirics/specifications.R` (dimensions with base option first; one data builder for UCDP, ACLED, GDELT), `15_specification_grid.R` (3,360 specifications; every run logged in `results/spec_runs/` with git commit), `16_specification_curve.R` (curves; levels in SD units of each source). New options: sender units, breadth; sample without Israel; common window 1997–2021; in-conflict sample defined by UCDP for all sources (option c). Grid reproduces script 13 exactly. Notes `empirics/notes/15_specification_grid.md` | user: keep base definitions fixed, explore combinations transparently, same permutations for all sources |
| 2026-11-09 | `13_local_projections.R` section 5: breakdown of the UCDP US-without-ICC effect (levels, shock second) by GW region (leave one out / only), shock-year period (1991–99, 2000–09, 2010–19), leave one country out, and dropping the 1–5 most influential states together; table `lp_us_effect_location`, fig24. Result: not regional; present 1991–2009, zero 2010–19; halves without Yugoslavia, Iraq, Nepal, Angola, Liberia | locate the effect after the ACLED sample showed none (section G) |
| 2026-11-09 | `13_local_projections.R` section 6: US effect split by GSDB objective (conflict objective vs other; end_war vs other), all state-years and in conflict in t−1; table `lp_us_objective_split`. Result: decline after both groups, larger after conflict-objective cases, difference not significant | anticipation check (plan item 3b), user request |
| 2026-11-09 | `13_local_projections.R` section 7: full LP paths h = 1..8 (per year and cumulative) for full sample, shock periods, without the 5 most influential states, in conflict in t−1; fig25 | user: show the whole horizon, not only h = 2 |
| 2026-11-09 | Descriptive script `17_acled_ucdp_comparison.R` (fig26–29): coverage, agreement, selected countries, US sanction events in each LP sample. ACLED vs UCDP differ mainly by sample (ACLED: Africa/Asia, 1997–2023), not by measurement (r = 0.85–0.99 except Americas 0.39). Notes 17 | user: visualise how ACLED and UCDP differ |
| 2026-11-09 | Script `18_africa.R` (fig30–33): LPs for African states; UCDP 1989–2019, UCDP and ACLED on the same state-years (1997–2023), GDELT; shocks all w/o ICC, US w/o ICC, UN, EU, arms embargo, conflict objective; in-conflict sample; violence → sanctions. Design chosen by Claude (defaults stated to the user). Notes 18 | user: subanalysis of sanctions on conflicts in Africa |
