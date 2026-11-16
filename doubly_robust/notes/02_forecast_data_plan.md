# Conflict forecasts as a "propensity score": data options and plan (16 Nov 2026)

**Advisor idea.** Use conflict forecasts from Håvard Hegre's work (https://havardhegre.net/forecasting/) in the way
a propensity score is used, and ask whether reactions differ between conflict that **could be predicted** and conflict
that **could not**. Data decisions: `data/README.md` section 4d. Clean files: `data/clean/forecasts/`.

## 1. Which forecast data exist

Hegre has two forecasting lines, and they are different data:

| | (A) Hegre et al. 2013 / 2016 model (the havardhegre.net page) | (B) VIEWS (Hegre's current system, Uppsala/PRIO) |
|---|---|---|
| Unit | country-year (GW codes) | country-month (GW codes), also PRIO-GRID-month |
| Outcome | intrastate conflict 0 / minor (25–999 BD) / major (1000+) | P(≥ 25 state-based BRD in the month), predicted fatalities (UCDP GED) |
| Model | multinomial logit, conflict history + population, GDP pc, education, neighbours, region | ensembles of ML models (conflict history, V-Dem, WDI, ACLED, ...) |
| Genuine ex-ante forecasts | **ISQ 2013 package: published country-year risk 2010–2050 (data through 2009) → 2010–2019 in our sample**; SSP 2016: one simulation draw from 2014 | monthly vintages from Jan 2021 on (API archive) |
| Covers our sample 1991–2019? | **no forecasts**, but the **data and model spec** to produce them (observed 1960–2013) | **no** (2021–2023 overlap with our sanctions data at most) |
| Downloaded | yes, `hegre_history_gy.csv`, `hegre_ssp1_sim_gy.csv` | year-ahead runs 2021–2026 (`acquire_views.py`; API very slow on 16 Nov) |

**VIEWS "input data / predictor datasets" (1990–2025)** are a different kind of data: the *inputs* the VIEWS models use (UCDP GED deaths, six V-Dem indices, five WDI series, country-month), not forecasts. They could train our own VIEWS-style forecast for the 1990s–2010s, but they hold no prediction made by VIEWS for those years.

**Usable timeframes (updated 16 Nov):** published Hegre forecast 2010–2019 (`hegre_isq2013_forecast_gy.csv`; AUC 0.84–0.91 against our violence measure); VIEWS 2022–2023 (worldwide year-ahead forecasts start with 2022; the 2021 runs cover only Africa and the Middle East and start in February); anything before 2010 only by re-estimating the model ourselves. Hegre's 2001–2009 out-of-sample test exists only as summary figures on his website — the country-year predictions could be requested from him.

So neither source gives a ready-made forecast for 1991–2019. Hegre's published forecasts start where our sample
ends. VIEWS is the better forecaster (more data, monthly, true real-time vintages) but it starts in 2021.

## 2. Recommendation

**Main: re-estimate the Hegre (2013) model ourselves as a real-time forecast**, one year ahead, with an
expanding window: for each year t from 1989 to 2019 (or 2023), fit the model on 1960…t−1 and predict t from data
known at t−1. This gives p̂(t) = P(conflict in t | information at t−1) for every panel state-year. It is the
established model from the literature, it is country-year like our panel, and it uses only past data, so the
forecast is not contaminated by later events.

- Inputs: conflict history from UCDP/PRIO ACD (we have it through peacesciencer; this also fixes the missing
  Yugoslavia, H3), population and GDP (in our panel), neighbour conflict (computable from ACD + a contiguity list,
  peacesciencer), education (YMHEP: Wittgenstein Centre data, a new download) — or drop education as a simpler
  first version.
- Check first: re-estimate their model on `hegre_history_gy.csv` and compare with the coefficients in their
  results files (`re_model_1_*_o.tex` inside the zip). That tells us we have the specification right.
- Outcome choice: forecast their outcome (state-based intrastate conflict) or our outcome (UCDP organized violence
  ≥ 25 deaths, `viol_inc`). They differ in 297 state-years (H4). For the reaction function, forecasting **our**
  violence measure is the consistent choice.

**Check: VIEWS for 2021–2023** — compare our forecast with VIEWS's genuine forecast where they overlap. If they
agree, the re-estimated forecast is credible. A further check: the 2023/24 VIEWS prediction challenge archive has
true-future forecasts for 2018–2021 from many models (Dropbox folder linked in the README of
https://github.com/prio-data/prediction_competition_2023; not downloaded).

## 3. How the forecast would enter the analysis (to discuss with the advisor)

1. **Sanctions on violence (reaction function 1): predicted vs surprise conflict.** Split violence in t into the
   part expected at t−1 (p̂) and the surprise (y − p̂), or interact conflict onset with low / high p̂. Question: do
   senders react to *news* (unexpected outbreaks) or also to conflicts everyone saw coming?
2. **Violence on sanctions (local projections): condition on the forecast.** The open worry in `empirics/notes/13`
   section 6 is that sanctions come when wars were *expected* to end anyway. The Hegre model also predicts
   termination, so P(conflict continues in t+h) is a direct control for that anticipation.
3. **Terminology.** A forecast of the *outcome* (violence) given history is, strictly, a **prognostic score**
   (Hansen 2008, *Biometrika*), not a propensity score: the propensity score is P(sanction | history), which
   `01_dr_lp.R` already estimates. In the violence → sanctions direction, violence is the "treatment", so there the
   conflict forecast *is* the propensity score. Worth stating this precisely in the write-up.

## 4. Decisions needed

- (A) re-estimated Hegre model as main, VIEWS as check — or a different source?
- Forecast target: their outcome (state-based conflict) or ours (organized violence)?
- Education variable: download Wittgenstein Centre data, or start without it?
- Training window: expanding 1960…t−1 (default) or fixed?
