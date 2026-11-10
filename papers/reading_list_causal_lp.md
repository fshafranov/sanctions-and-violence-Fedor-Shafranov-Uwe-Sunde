# Reading list: LP, LP-DiD and panel VAR for causal analysis

Search done 2026-11-09 (web search + OpenAlex/arXiv check of each reference). Purpose: which recent methods papers
help turn the sanctions → violence LPs into a more credible causal design. **Not yet read in full**: the
one-line contents come from abstracts and search summaries. Entries move to `papers/README.md` once the PDF is
in `papers/` and read.

Check column: **verified** = title, first author and year match OpenAlex/arXiv; **partial** = title matches,
small difference noted.

## Already in `papers/` (summarised in README.md)

Dube, Girardi, Jordà & Taylor (LP-DiD) · de Chaisemartin & D'Haultfœuille (intertemporal effects) · Mei, Sheng &
Shi (Nickell bias in panel LP) · Plagborg-Møller & Wolf 2021 · Li, Plagborg-Møller & Wolf 2024 · Abrigo & Love
2016 · Juodis, Karavias & Sarafidis 2021.

Updates found: LP-DiD is now published, *Journal of Applied Econometrics* 40(7), 2025, doi:10.1002/jae.70000
(verified). de Chaisemartin & D'Haultfœuille is in press at *Review of Economics and Statistics*,
doi:10.1162/rest_a_01414 (from the HAL listing).

## New: what to read, by question

### 1. Making selection on observables explicit (most relevant for us)

| Paper | Check | Why it matters here |
|---|---|---|
| Angrist, Jordà & Kuersteiner (2018), "Semiparametric Estimates of Monetary Policy Effects: String Theory Revisited", *JBES* 36(3), doi:10.1080/07350015.2016.1204919 | partial (online 2016, print 2018) | LP with inverse propensity weights: model the policy decision, weight the LP. Our robust reaction function (violence → sanctions) would be the propensity model |
| Jordà & Taylor (2016), "The Time for Austerity: Estimating the Average Treatment Effect of Fiscal Policy", *Economic Journal* 126, doi:10.1111/ecoj.12332 | verified (online 2015) | Applied template: doubly robust LP (regression adjustment + IPW) for a policy chosen in response to the economy, with overlap checks |
| Viviano & Bradic, "Dynamic covariate balancing: estimating treatment effects over time with potential local projections", *Biometrika* 2026 (arXiv 2103.01280) | journal details from a third-party tracker, to confirm | Balancing weights for treatment histories in panels; a more modern version of the AJK idea |
| de Abreu Pereira Uhr & Valle Moura (2026), "Doubly robust local projections difference-in-differences", arXiv 2604.27035 | verified (preprint) | LP-DiD + doubly robust (Sant'Anna & Zhao style); consistent if either the outcome or the propensity model is right. Absorbing treatment only, while ours recurs |

### 2. What LP / VAR estimands mean causally

| Paper | Check | Why it matters here |
|---|---|---|
| Jordà (2023), "Local Projections for Applied Economics", *Annual Review of Economics* 15, doi:10.1146/annurev-economics-082222-065846 | verified | Best single overview: LP as a treatment-effect estimator, panels, staggered/heterogeneous treatment. **Read first** |
| Rambachan & Shephard, "When do common time series estimands have nonparametric causal meaning?", arXiv 1903.01637 | title/version history to confirm | Conditions under which IRFs, LP and LP-IV are causal (potential-outcomes time series) |
| Kolesár & Plagborg-Møller, "Dynamic Causal Effects in a Nonlinear World: the Good, the Bad, and the Ugly", arXiv 2411.10415 (v4 2025) | from arXiv listing | Linear LP with an observed shock recovers a positively weighted average of true effects → sign is right even if effects are nonlinear/heterogeneous. Supports reading our signs |
| Stock & Watson (2018), "Identification and Estimation of Dynamic Causal Effects in Macroeconomics Using External Instruments", *Economic Journal* 128, doi:10.1111/ecoj.12593 | verified | LP-IV: what an instrument for sanctions would need (relevance, contemporaneous and lead-lag exogeneity) |

### 3. Estimation and inference problems in panel LP

| Paper | Check | Why it matters here |
|---|---|---|
| Herbst & Johannsen (2024), "Bias in local projections", *Journal of Econometrics*, doi:10.1016/j.jeconom.2024.105655 | verified | Small-sample LP bias, persists with fixed effects; analytic bias correction. Complements Mei et al. |
| Inoue, Jordà & Kuersteiner (2025), "Inference for local projections", *Econometrics Journal*, doi:10.1093/ectj/utaf004 | verified via search | Confidence and simultaneous bands across horizons (we test many h) |
| Montiel Olea, Plagborg-Møller, Qian & Wolf, "Double Robustness of Local Projections and Some Unpleasant VARithmetic", NBER WP 32495 / arXiv 2405.09509 | from arXiv listing | LP intervals keep coverage under VAR misspecification; VAR intervals with short lags undercover. Argument for LP over our VAR |

### 4. Panel VAR with causal identification

| Paper | Check | Why it matters here |
|---|---|---|
| Pala (2025), "Identification, estimation and inference in Panel Vector Autoregressions using external instruments", arXiv 2511.19372 | partial (single-author working paper) | Panel VAR identified with an external instrument recovers a weighted average of unit effects (panel LATE), with two biases. Only route to a causal panel VAR; needs an instrument |

Little else: recent methods work has moved from panel VAR to panel LP for causal questions.

### 5. Applied: sanctions and conflict

| Paper | Check | Why it matters here |
|---|---|---|
| Farzanegan & Albarawi (2026), "Destabilizing the corrupt: Economic sanctions and their conflict-inducing consequences", *European Journal of Political Economy*, doi:10.1016/j.ejpoleco.2026.102885 | verified (title + year) | Recent competitor: 122 countries 1996–2020, trade sanctions → more conflict deaths where corruption is high. Positioning |

No paper found that applies LP or LP-DiD to sanctions and violence. A sanctions–exchange-rate LP paper
(Economic Policy panel) exists; not checked.

## Suggested reading order

1. Jordà (2023) review: what LP buys and what it does not.
2. Jordà & Taylor (2016): the applied doubly robust LP template closest to our problem.
3. Angrist, Jordà & Kuersteiner (2018): the method behind it.
4. Kolesár & Plagborg-Møller: why linear LP signs are still meaningful with heterogeneous effects.
5. Herbst & Johannsen + Mei et al.: bias corrections we may need to apply.
6. Uhr & Moura, Viviano & Bradic: only if we go the DR LP-DiD route.
