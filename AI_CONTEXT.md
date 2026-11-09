# AI context: sanctions & violence project (handoff for the next session)

Last updated **9 Nov 2026** (meeting preparation: variable coding review, no code or results changed; see
section 9). Read this first, then:
`empirics/notes/README.md` (headline findings + index of result notes),
`empirics/notes/variable_coding_and_functions.md` (onset vs presence coding, the four functions, reading fig10), `empirics/ANALYSIS_PLAN.md` (design,
decisions D1–D8, robustness list R1–R12, change log), `data/README.md` (all data decisions + change log),
`papers/README.md` (literature notes), `Writing/README.md` (advisor brief).

## 1. Project in one paragraph

RA project (LMU, Prof. Uwe Sunde). Do sanctions break or feed a "cycle of violence"? A **panel version of
Jaeger & Paserman (2008, AER)**: two reaction functions (new sanctions on past violence; violence on past new
sanctions) = bivariate panel VAR(2) with state and year FE, 197 Gleditsch–Ward states, 1989–2019 (estimation
years 1991–2019). Sanctions = **new** GSDB cases (flows), violence = UCDP organized violence. Data panel:
`data/processed/sanctions_violence/sanctions_violence_panel.csv` (country-years 1950–2023).
**Base case (user, 22 Oct): follow Jaeger & Paserman** — reaction functions/Granger (04), response functions
(07), IRFs (08). Everything else is robustness or extension.

## 2. Folders — important

| Path | Status |
|---|---|
| `~/Documents/LMU_Life/RA_Work_Sunde/sanctions and violence` | **ORIGINAL — never modify.** |
| `~/Documents/LMU_Life/RA_Work_Sunde/sanctions and violence - working copy` | **All work happens here.** |

## 3. Layout of the working copy

```
data/raw|clean|processed/    data pipeline (Python cleaning, see data/README.md); data/logs/ = master logs
data/scripts/                cleaning/, processing/, checks/check_replication.py
empirics/ANALYSIS_PLAN.md    design, decisions D1–D8, robustness R1–R12, script structure (section 8), change log
empirics/scripts/            numbered R scripts (table below), 00_setup.R (paths, VAR_LAGS=2, MAX_LAGS=3, CONTROLS), functions.R
empirics/results/            data/ (analysis_panel.csv, gdelt_analysis_panel.csv), tables/ (md + csv), figures/, models/, logs/
empirics/notes/              hand-written interpretation per script + tests_explained.md + README (headline findings) — update when results change
Writing/                     advisor brief / paper skeleton (see section 7)
papers/                      PDFs + README.md (16 entries, priority A/B/C)
archive/                     old notebooks, legacy outputs, baseline/ — move files here instead of deleting
master.py                    runs everything; logs per step
```

| Script | Content | Status |
|---|---|---|
| 01_prepare_sample | variables, sample rule (≥10 complete years; 197 states, 5,932 state-years; GDR, CS, South Sudan, South Yemen excluded), lagged controls | done |
| 02_descriptives | figures 1–9 (`figures/descriptives/`), flow summary | done |
| 03_data_diagnostics | series classes, own ADF→Maddala–Wu/Choi, CIPS, persistence (Nickell-corrected), balance (167 balanced), VAR lag criteria | done |
| 04_reaction_functions | JP Table 1 (OLS + half-panel jackknife, with/without controls), lag grid (JP Table 2) | done |
| 05_granger_heterogeneous | Juodis–Karavias–Sarafidis bias-corrected test on balanced panel; Dumitrescu–Hurlin | **planned** |
| 06_model_diagnostics | residual AR vs −1/(T−1), Pesaran CD (all / outcome varies), stability incl. GMM (runs after 10) | done |
| 07_empirical_response | JP Fig. 2 response functions (raw + two-way FE) — LP-DiD moved to 12 | done |
| 08_irf | IRFs: simple (JP fn. 12) + 2 Cholesky orderings, cumulative, country bootstrap (IRF_BOOT_DRAWS, default 199), jackknife IRF | done |
| 09_robustness | Part 1 R3 logit/PPML (base `glm` with dummies); Part 2 R10 raw deaths (uncapped, p99, p95) in linear levels VAR; Part 3 IRFs + response function with deaths capped at p99 (fig17) | parts 1–3 done; more parts planned |
| 10_pvar_gmm | panelvar GMM (FOD, collapsed instruments lags 2–5, year-demeaned), Hansen, Andrews–Lu | done |
| 11_gdelt | R12: everything with GDELT violence (1991–2019 and 1981–2021, thin-coverage check), JP response functions, IRFs (GDELT_BOOT_DRAWS default 99) | done |
| 12_lpdid | **EXTENSION, not base case**: LP-DiD (Dube et al.), UCDP + GDELT | done |

master.py empirics order: prepare_sample, descriptives, data_diagnostics, reaction_functions, robustness,
pvar_gmm, model_diagnostics, empirical_response, irf, gdelt, lpdid, writing_tables. Full empirics run on the
Mac ≈ 6–7 min (irf ~110 s, gdelt ~145 s, robustness ~60 s).

## 4. How to run (user, on the Mac)

```bash
uv run python master.py --stage empirics        # all R empirics + LaTeX tables
uv run python master.py --only <step>           # one step (names: --list), e.g. robustness, writing_tables
uv run python master.py                         # data pipeline;  --check / --set-baseline for the data replication check
cd Writing && latexmk -pdf main.tex             # compile the brief (needs MacTeX/TinyTeX; the AI can compile instead)
```

## 5. Working environment notes for the AI (learned the hard way)

- **Three machines:** (a) the user's Mac (R 4.5 + renv incl. fixest, panelvar, plm, sandwich, urca) — only the
  user runs R there; (b) the device VM via `device_bash` (connected folder mounted at
  `$HOME/mnt/sanctions and violence - working copy`): **no R**, but python3 + pandas, `pdflatex`/`latexmk`/`pdftotext`;
  (c) the cloud container: R 4.3.3 with tidyverse, here, plm, sandwich, lmtest, urca (apt) — **no CRAN access**,
  so no fixest/panelvar; mirror of the project in the scratchpad (`.../scratchpad/proj`, has `.here`).
- Workflow that worked: write/test R scripts in the container on a staged copy of the panel (check md5 of
  `sanctions_violence_panel.csv` / `analysis_panel.csv` against the Mac first), then commit to the Mac; the
  user runs master.py; read results/logs via `device_bash`. Results of the container runs matched the Mac exactly.
- **Commit with a NEW staged name every time** (e.g. `rb_v3/r3_<file>`) and verify `md5sum` on both sides —
  re-using a staged name can deliver a stale cached copy.
- Small edits to text files (main.tex, notes, plan, AI_CONTEXT) can be done directly on the device with a python
  read-modify-write; **the container copies of `Writing/main.tex` and `empirics/notes/*` are stale** — always edit
  the device version (or re-stage it first).
- Compile LaTeX in the VM: `latexmk -pdf -interaction=nonstopmode -outdir=$HOME/texbuild main.tex`, then copy
  `main.pdf` into `Writing/` (keeps aux files out of the project). Check `Overfull` in the log; stage the PDF to
  look at pages.
- Deleting files in the user's folders is not allowed → move to `archive/`. Never modify the original folder.
- VM/container network: CRAN, World Bank, UN, OWID blocked; new raw data must be downloaded by the user.

## 6. Conventions and user preferences

- Every data change logged in `data/README.md`; analysis decisions and changes logged in `empirics/ANALYSIS_PLAN.md`
  (change log at the end); result interpretation in `empirics/notes/`.
- Code: commented, readable variable names (user request); R for empirics, Python for cleaning; uv, not bash scripts.
- User wants concise answers, asks "why"; be precise about what results show — **do not overstate** (see the
  corrections in section 8).
- Tables in the brief are generated (`Writing/scripts/make_tables.py`), text numbers are marked `% NUMBERS`.

## 7. Writing/ (advisor brief, paper skeleton)

`main.tex` (~27 pages): summary box for the meeting, intro, short literature review, data, strategy, results
(Granger, lag grid, response functions, IRFs), diagnostics, robustness (GMM, logit/PPML, raw/capped deaths incl.
"Reading Figure 5" discussion, GDELT, planned checks), LP-DiD extension (full discussion incl. reconciliation with
the VAR), discussion/next steps, appendix. `references.bib` (52 entries; field `comment` = source: `[folder]`,
`[web]` checked, `[check]` verify before submission). Author line is a placeholder `[Name]`; red `[To do]` / grey
`[Paper:]` notes hidden with `\showtodosfalse`. Tables: `make_tables.py` → `tables/*.tex` (14 tables); figures read
from `../empirics/results/figures/`.

## 8. Key results (Mac runs of 22 Oct; numbers in `empirics/notes/` and the brief)

- **Data OK:** all series stationary (Maddala–Wu/Choi/CIPS p<0.01); persistence well below 1 (conflict 0.49,
  new sanction 0.18); all VARs stable (roots 0.56–0.80); violence equation no residual AR; sender equation tiny AR
  at lag 2; weak cross-state residual correlation (0.01–0.03) → Driscoll–Kraay planned.
- **Violence → sanctions (robust in UCDP):** Granger p=0.007 (incidence) / 0.026 (levels) without controls;
  weakens with controls mainly via GDP growth (likely bad control, D8); 11/12 IRF versions significant;
  logit/PPML same. **Not found with GDELT** (but GDELT median-split incidence tracks UCDP poorly: 64% vs 46%).
- **Sanctions → violence (revised 23 Oct after 09 part 4, master run 16:50):** negative effect at t−2 on **log
  deaths** in every control version (sum −0.035 FE only p=0.028, −0.050 with controls p=0.018), jackknife, GMM,
  PPML winsorised (−11 to −16%, p=0.002); weaker without ex-Yugoslav states (FE only −0.024, p=0.08). Cumulative
  levels IRF negative but insignificant. The **incidence** effect (−3.5 pp, p=0.026) exists only with the sanction
  stock in t−1 as control, which mechanically contains the tested lags → **not a finding**; same for logit APE −0.046
  and the incidence IRF −0.077. With a same-year effect (Cholesky, sanctions first) the IRF is positive.
- **Timing:** violence rises before and peaks in the sanction year, normal after ~2 years (response functions).
  Annual data cannot order within-year events → main identification limit.
- **GDELT:** incidence estimate same sign/size (−0.032) but insignificant; reported low-level violence *rises* after sanctions.
- **LP-DiD (extension):** violence higher after sanctions vs clean controls (+8.6 pp at h=0), sanctions follow
  conflict onsets (+12.8 pp); not a contradiction of the VAR (different baseline: t−1 vs conditioning on the
  sanction-year level; gap shrinks 0.086→0.063 by h=2). As specified it cannot confirm the VAR effect; proposed
  variant conditioning on sanction-year violence not implemented.
- **Capped vs log deaths:** capped (p99) results ~15–25% less precise (signal/noise) than log — same sign and timing;
  log stays the base case.

## 9. Open decisions

- **D9 (new, 9 Nov)** incidence specification is asymmetric: sanction *onset* (`new_sanction`) vs conflict
  *presence* (`viol_inc`, every war year = 1). Options: conflict onset/termination, sanctions in force, or rename.
  Possibly why incidence results are weak and levels hold. To discuss with the advisor.
- **D10 (new, 9 Nov)** which sanctions count (all new cases vs conflict objective; extensions; group cases).
- **D1 caveat:** 25 deaths is the UCDP threshold, but applied to the country-year sum of all organized violence,
  not per conflict.
- Response functions (07): code compares with non-event years and does not scale; JP and the plan use the overall
  mean and scale per fatality; JP show no leads. Align plan and code. Suggested variant: conflict onset as event.
- **D8** main specification with or without controls (proposal: FE only main, controls as robustness) — needs the same-sample check below.
- **D6** GDELT incidence definition (median split is weak; alternatives top quartile / any mass-violence event).
- **D7** conflict-prone subsample. Whether LP-DiD (12) enters the paper (appendix / robustness / drop).
- Whether to pursue monthly data (needs sanction announcement dates; GSDB has years only) — raise with the advisor.

## 10. Next steps (agreed priority, 23 Oct)

1. **DONE 23 Oct (master run 16:50):** `ex_yugo_1991_2016` removed from CONTROLS; 09 part 4 (same-sample control
   check, D8) and part 5 (Yugoslavia R9); notes, ANALYSIS_PLAN, main.tex (new section 7.5, Tables 12–13 via
   make_tables.py `controls_check()`, `yugoslavia()`) updated. **Open: user/advisor decision D8** — proposal FE only
   as main specification (would require switching Table 1 / IRF / brief ordering), stock dated t−3 if a stock
   control is used. Summary box in main.tex now spills onto page 2.
2. **Leave-one-country-out** Granger tests/coefficients + most influential sanction events.
3. **Anticipation (JP Table 4 analogue)** — no direct proxy exists; plan agreed in the last exchange:
   (a) text argument on bias direction (expected escalation → biases S→V upward, our negative estimate conservative;
   expected war end → could create the negative t−2 effect mechanically); (b) **main check: split new sanctions by
   GSDB objective** (prevent war / end war vs non-conflict objectives such as democracy, human rights, policy change)
   — the raw GSDB case data have an `objective` field (see `data/raw/gsdb/`, `data/clean/gsdb/gsdb_self_dyads_dropped.csv`
   header; panel has only `new_conflict_obj_sanction`); **first count new sanctions per objective group** to see
   whether the split has power; (c) GDELT `coerce_norm1000` (threats/coercion), lagged, as proxy (R6).
4. Heterogeneity: sender (UN/EU/US; UN thin), arms embargoes, conflict objective.
5. Script 05 (JKS test, balanced 167 states), Driscoll–Kraay SEs, D7 subsample.
6. Lower priority: stricter GDELT incidence, sample to 2023, lifting, year-by-year capped-IRF figure / p95 dynamics,
   999 bootstrap draws for the final version, LP-DiD variant conditioning on sanction-year violence, bias-corrected FE logit.
7. Housekeeping: `renv::snapshot()` after any package change (urca now used by 03 and 11); commit to git regularly
   (check `git status` — a lot of work from 21–23 Oct may be uncommitted).

**User's own plan:** read the papers to understand and trust the results. Suggested order: Jaeger & Paserman
(esp. Section IV identification argument), Abrigo & Love 2016 (panel VAR practice), Juodis et al. 2021 §1–3
(Nickell bias, jackknife), Plagborg-Møller & Wolf 2021 intro, Dube et al. (only if LP-DiD stays), Hultman & Peksen
2017 and Escribà-Folch 2010 (substantive positioning). Suggested self-check: re-estimate one Table 1 equation by
hand with `fixest::feols` and compare.

## 11. Data side (unchanged since 20 Oct; details in `data/README.md`)

- Sources: GSDB R4 (sanctions; flows S11 validated vs GSDB-R4 Fig. 6b, Russia 2022 = 25 new / 38 active), UCDP
  OV-CY v26.1 (deaths, per 100,000; missing before 1989), GDELT 1.0 (1979–2021, own crosswalk/assignments),
  peacesciencer/isard democracy (isard 0.2.0, B11), GDP/population extended to 2023 (`gdp_ext`, `pop_ext`).
- Yugoslavia: cases attributed per republic (`data/README_yugoslavia.md`), dummies `ex_yugo`, `ex_yugo_1991_2016`.
  `ex_yugo_1991_2016` is **no longer a control** (removed 23 Oct, see ANALYSIS_PLAN change log); R9 in 09 part 5.
- Known gaps: GDP 2020–23 missing for 12 states; GDELT ends 2021; UCDP starts 1989; GSDB group cases kept as coded.
- Data replication check: `master.py --check` against `archive/baseline`; after intentional changes the user runs `--set-baseline`.
