# How the variables are coded, and what each "function" estimates

Written 2026-11-09 (meeting preparation). No script or result changed; this note collects points found while
reading the code. Equations and line references: [model_equations.md](model_equations.md).

## 1. Coding of the two VAR variables

| Variable | Definition | Type |
|---|---|---|
| `viol_inc` | 1 if UCDP organized-violence deaths (state-based + non-state + one-sided, best estimate) ≥ 25 in the year | **presence** (every year of a war = 1) |
| `viol_lev` | log(1 + deaths per 100,000) | level |
| `new_sanction` | 1 if at least one GSDB case **begins** (GSDB `begin` = t) against the state | **onset** (years a case stays in force = 0) |
| `n_new_cases` | number of cases beginning in t | flow |
| `n_cases_received` | cases in force (stock); used only as the control `ctrl_stock` in t−1 | stock |

Not counted as a new sanction: joining a group already targeted (`n_joined_cases`), cases inherited by successor
states, extension or tightening of an existing case. Group cases count once per member (e.g. Russia's 2014
counter-sanctions are a new case for every EU member). All senders and all objectives are included
(`new_conflict_obj_sanction` exists but is not used in the base case).

Example (10 m inhabitants): a war 1996–99 with deaths 300, 2000, 1500, 40 gives `viol_inc` = 1,1,1,1 (four
events); sanctions beginning 1997 (US, EU) and 1999 (UN), in force 1997–2001, give `new_sanction` = 1,0,1 in
1997–99 (two events).

**Issue 1 — the "incidence" specification is asymmetric:** it pairs sanction *onset* with conflict *presence*. The
label suggests both are presence. Conflict presence is persistent, so the violence equation in incidence has little
within-state variation for a sanction effect; this may be why incidence results are weak while levels hold.
Options: (a) conflict onset (and termination) on the violence side; (b) sanctions in force on the sanction side;
(c) keep, but rename the specification.

**Issue 2 — the 25-death threshold** is the UCDP / UCDP-PRIO convention, but UCDP applies it per conflict or actor
(dyad-year). The code applies it to the country-year **sum of all types of organized violence**, so several small
conflicts can add up to a "conflict year". Alternative: state-based deaths only, or UCDP/PRIO ACD presence.

**Issue 3 — stock control:** stock(t−1) = stock(t−3) + new(t−1) + new(t−2) + joined − lifted, so it contains the
tested sanction lags (already in D8).

## 2. The four functions

| | Reaction functions (04) | Response functions (07) | Impulse responses (08) | LP-DiD (12) |
|---|---|---|---|---|
| JP equivalent | Table 1 | Figure 2A/2B | Section V | none (extension) |
| Question | Do lags of X predict Y given Y's own past? | Mean of Y at t+k after an X event vs non-event years | Total path of Y after a one-unit shock to X, incl. feedback | Change in Y since t−1 after a fresh event vs clean controls |
| Conditions on past violence | yes | no (only FE) | yes (via the VAR) | partly (two lagged outcomes) |
| Event / shock | lags of S, V | any year with E = 1 (both specs use the 0/1 dummy as event) | one unit in year 0 | onset: E = 1 after 3 years without |
| Reported as | tables only | fig10 | fig12, fig13, fig17 | fig11, fig16 |

Reaction functions are not graphed (as in JP); the IRF is their graphical form.

## 3. Reading fig10 (response functions)

- The pre-event rise in violence before a sanction is the sender reaction (violence → sanctions) seen from the
  other side, not noise.
- In the panel "sanctions after a conflict year" the event is any conflict year, so years before an event are often
  in the same war: part of the pre-event elevation is mechanical. Using conflict onset as the event would remove it.
- The figure cannot tell whether the decline after the peak is a sanction effect or the end of the escalation; the
  VAR conditions on past violence for that.
- Differences from JP Fig. 2: JP use daily data, **only post-event horizons** (days 1–60), compare with the
  **overall mean** and divide by mean fatalities on event days. The code compares with non-event years, does not
  scale, removes state and year FE, and adds leads. The plan describes the JP formula; code and plan still differ
  (model_equations.md section 12, point 2).

## 4. Questions for the advisor

1. Symmetric coding: onset on both sides, presence on both sides, or keep and rename (proposed decision D9)?
2. Which sanctions count: all new cases or conflict objectives only; extensions; group cases (D10)?
3. Threshold: country-year total of all organized violence vs state-based only (D1).
4. Stock control: drop, or date at t−3 (D8).
5. Does LP-DiD enter the paper?
