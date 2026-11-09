# AI context: sanctions & violence project (handoff for the next session)

Last updated **9 Nov 2026, end of the second session**: script 13 sections 5–7 (where the US effect comes from),
trade/FDI/arms data (WDI, IMF, SIPRI) with exposure variables in the panel, the separate `exposure/` project,
ACLED vs UCDP comparison (17), Africa subanalysis (18). **Start with section 12 ("Start here next session").**
Per-session change record: `SESSION_LOG.md` (git-ignored, project root). Read this first, then:
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
exposure/                    SEPARATE project (user, 9 Nov): trade/arms exposure analysis; own README, ANALYSIS_PLAN (E1–E3),
                             scripts/ (00_setup.R reuses empirics setup, writes to exposure/results/), notes/; stage `--stage exposure`.
                             Exposure variables stay in the main panel (option B).
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
| 13_local_projections | **new focus (advisor, 9 Nov)**: plain panel LP (no DiD), both directions, shock first/second, cumulative; all / US sanctions, with/without ICC case 685; UCDP, ACLED, UCDP on the ACLED sample | done |
| 14_conflict_sample_lp | arms embargoes / conflict-objective sanctions among state-years in conflict in t−1 (104 states, ~90 events): deaths −0.20 to −0.25 at h = 2, no effect on war continuation | done |
| 15_specification_grid / 16_specification_curve | all combinations of `empirics/specifications.R` (source × measure × type × sample × years × FE × timing × controls) for UCDP/ACLED/GDELT; specification curves fig23 | done |
| 13 sections 5–7 (9 Nov, 2nd session) | US effect by region / shock period / leave-one-country-out (fig24), by GSDB objective, full paths h = 1..8 by sample (fig25) | done |
| 17_acled_ucdp_comparison | descriptive: coverage, agreement, countries, US events per sample (fig26–29) | done |
| 18_africa | African states: UCDP vs ACLED on the same state-years, GDELT, in conflict, both directions (fig30–33) | done |
| `exposure/` (separate project) | 01_exposure_lp (shock × pre-sanction trade/arms exposure, UCDP/ACLED/GDELT), 02_exposure_robustness; own README, ANALYSIS_PLAN E1–E8, notes; `--stage exposure` | done (first round) |

master.py empirics order: prepare_sample, descriptives, data_diagnostics, reaction_functions, robustness,
pvar_gmm, model_diagnostics, empirical_response, irf, gdelt, lpdid, local_projections, conflict_sample_lp,
specification_grid, specification_curve, acled_ucdp_comparison, africa, writing_tables; then stage `exposure`
(exposure_lp, exposure_robustness). Data stage now also clean_wdi, clean_imf_trade, clean_sipri, process_exposure.
**R runs locally in the session now** (Rscript + renv on the Mac work from Claude's shell; renv reports
"out-of-sync", harmless so far).

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

- **Data versioning (user, 9 Nov):** data files are git-ignored (public repo) but versioned with DVC; storage folder
  `RA_Work_Sunde/sanctions and violence - dvc storage` (in `.dvc/config.local`). After data changes run
  `uv run python master.py --dvc`, then commit the `*.dvc` pointer files. New raw folders must be added BY NAME to
  `.gitignore` (wildcard breaks DVC). README "Data versions (DVC)".

- **Specifications (user, 9 Nov):** base definitions stay fixed; variants are options in `empirics/specifications.R`
  (dimension tables, base first) and apply to UCDP, ACLED and GDELT through one data builder. Run the grid (15) and
  curves (16) after adding an option; every run is logged in `empirics/results/spec_runs/index.csv`.

- Every data change logged in `data/README.md`; analysis decisions and changes logged in `empirics/ANALYSIS_PLAN.md`
  (change log at the end); result interpretation in `empirics/notes/`.
- **Figures (user, 9 Nov 2026): follow Kieran Healy, *Data Visualization: A Practical Introduction* (socviz.co)** —
  rules in README.md "Figures: visualisation guidelines"; combine panels with ggplot2 facets, not by stitching plots.
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

## 10. Next steps

### Advisor meeting 9 Nov 2026 (user's notes) — now the priority

Focus on **local projections** (the panel VAR seems to do worse in the panel setting); target spec:
**LP, without the ICC case, with ACLED, US sanctions only**. Status after the 9 Nov session:
- LP without DiD — **done** (13_local_projections.R, UCDP). Result: US cases without ICC → log deaths −0.105 at h = 2
  (shock second), cumulative −0.15/−0.22 at h = 2/3, transitory; all cases: no significant effect; violence → sanctions robust.
- Without ICC case 685, US only — **done** (measures built from `data/clean/gsdb/gsdb_new_cases.csv`).
- **ACLED** — **done 9 Nov**: downloaded by the user (`acquire_acled.py`, login in git-ignored `.env`, account sees data
  ≥ 12 months old), `clean_acled.py`, merged into the panel (`acled_*`, data/README 4b A1–A7), in script 13 (58 states,
  1997–2023). Result: no sanction → violence reduction with ACLED; **UCDP on the same state-years agrees** → the
  negative UCDP US effect comes from state-years outside Africa/Asia 1997–2023. Next: locate it (region/period splits,
  leave-one-country-out). Panel changed (new columns only) → user to run `--set-baseline`.
  **Located (13 section 5, 9 Nov):** not regional; shocks 1991–99 −0.21, 2000–09 −0.11, 2010–19 +0.02 (n.s.);
  leave-one-country-out always p < 0.05, but dropping Yugoslavia, Iraq, Nepal, Angola, Liberia halves it (−0.049, p 0.08);
  influential events sit at war ends → anticipation concern. **Objective split (13 section 6):** decline after conflict-
  objective US cases (−0.15*, in wars −0.28**) and also after other-objective cases (−0.09**, in wars −0.24***), difference
  n.s. → not just settlement packages, but anticipation in general not ruled out (user: leave-outs may be the cases where
  sanctions worked; counterfactual not identified). Ideas: UCDP peace agreement / termination data, monthly timing, case reading.
- **Arms embargoes / conflict-aimed sanctions** — **done 9 Nov** (script 14, design agreed with the user): among wars
  with the same violence history, arms embargoes are followed by lower deaths at h = 2–3 (−0.20 to −0.25 log points,
  both FE versions), no effect on whether the war continues. Arms-only too few (28). Next checks: ACLED, UN vs non-UN,
  leave-one-war-out.
- **Within-year ordering of sanctions and violence (sub-year direction)** — open, recorded 9 Nov at the user's request.
  Annual data cannot tell whether a sanction preceded or followed same-year violence ("shock first" vs "shock
  second" in script 13 bracket the answer). Check later with monthly data: ACLED country-months
  (`data/clean/acled/acled_cm.csv`, already built) + sanction announcement dates (not in GSDB; e.g. OFAC / Federal
  Register for US cases, UN SC resolution dates, EU Official Journal). Compare violence in the months before vs
  after the announcement.
- **Counter-sanctions / "noise" sanctions** — idea noted 9 Nov (user), to look at later. (i) Neighbouring developing
  countries in disputes may sanction and counter-sanction each other; (ii) Russia's 2014 counter-sanctions on EU members
  (case 995). Such cases are unrelated to violence in the target and may make results less stable. Methodological issues
  discussed: GSDB has no retaliation flag; same-year moves (EU<->Russia 2014) cannot be ordered with annual dates, so a
  mechanical "reverse sanction exists" rule also flags the original; group cases need membership matching; long mutual
  disputes (US-Cuba, US-Iran, India-Pakistan, Arab League-Israel) are not clear retaliation. Options: (A) mechanical
  rule, (B) mechanical candidates + hand check (preferred), (C) objective filter (drop policy_change/other),
  (D) counter-sanctions as a separate shock ("is retaliation having an effect"). US-only measure already excludes most.
  Checked 9 Nov: the impression that Afghanistan/North Korea "sanction many countries" comes from GSDB listing every UN
  member as a sender of UN cases (Afghanistan: 83 of 85 sender cases are UN; one own case, vs Pakistan 1961; North Korea
  never a sender). Our case-based measures count a UN case once per target, so this does not enter them; it does
  inflate `num_sanctioners` (S5).
- **GSDB coverage gap / TIES cross-check** — open, noted 9 Nov: GSDB has few sanctions between developing countries
  (78 of 1,547 cases) → "sanctions" = sanctions by Western states and international organisations. Possible
  cross-check with TIES (1945–2005, incl. threats, more non-Western senders): compare South–South counts, re-run main
  LPs 1989–2005. Needs download by the user. Details: data/README.md, "Notes on GSDB coverage".
- **Retaliation** — open, meaning to clarify (target counter-sanctions vs violent retaliation).
- **"Net out symmetric vs asymmetric"** — open, meaning to clarify (imposition vs lifting? multilateral vs unilateral?).
- **Weight by trade and capital flows**: raw data **downloaded 9 Nov** (`acquire_wdi.py` → `data/raw/wdi/`: trade/exports/
  imports % GDP, FDI % GDP, SIPRI arms imports/exports TIV, GDP current US$; `acquire_imf_trade.py` → `data/raw/imf_imts/`:
  IMF IMTS bilateral goods trade, all 272 reporter codes × all partners, 217 with data, 1980–2025, 129 MB; DVC-tracked).
  **Cleaned 9 Nov** (clean_wdi / clean_imf_trade / clean_sipri → data/clean/wdi, imf, sipri; SIPRI bilateral TIV + register too).
  User decisions: data/README 4c T5, O1–O4 (decided). **Exposure in the panel (9 Nov):** `process_exposure.py` → 71 columns (incl. `trade_<g>_zero_imputed` flags for the NA robustness)
  (`trade_<us|eu|un|senders>_gdp/_share`, `arms_<g>_tiv/_share`, `trade_gdp`, `fdi_in_gdp`, `arms_supplier_hhi`, `arms_to_rebels_tiv`;
  base t−3..t−1 mean, `_l1`, `_t`); data/README 4c X1–X7. Not yet used in the empirics (next: option in specifications.R).
  **Analysed (exposure/ project, 9 Nov):** no evidence that trade exposure to the sender changes the violence response
  (UCDP, ACLED; GDELT positive); arms: only EU sanctions × high EU arms dependence, few events.
- **Symbolic vs effective sanctions** — open; GSDB type flags/`descr_trade` and `success` are in `gsdb_new_cases.csv`.
- **Arms data (SIPRI)** — **done 9 Nov**: `acquire_sipri.py` (no documented API; replays the site's CSV export per
  supplier), bilateral TIV 1950–2025 + transfer register, cleaned (`clean_sipri.py`), totals = WDI's SIPRI exports.

### Earlier list (agreed priority, 23 Oct)

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

## 12. Start here next session (written 9 Nov 2026, end of session 2)

**State:** all work committed on `main` (last commits: exposure project, ACLED/UCDP comparison, Africa); `main` is
ahead of GitHub (not pushed — push also refreshes the stale "Claude" entry in GitHub's contributor sidebar; the
history itself has no Claude author or co-author). Replication baseline set after the exposure columns (user,
`--set-baseline`); DVC up to date (`master.py --dvc`). Working tree clean.

**What we learned this session (honest version, details in the notes):**
1. UCDP "fewer deaths after US sanctions" (h = 2) is a 1991–2009 phenomenon, not regional, robust to dropping any one
   country but halves without Yugoslavia, Iraq, Nepal, Angola, Liberia; influential cases sit at war ends →
   anticipation not ruled out (notes/13 sections 5–7). Objective split: decline after conflict and non-conflict
   cases alike. Among wars, no later catch-up.
2. ACLED differs from UCDP by **sample** (Africa/Asia 1997–2023), not measurement (r 0.85–0.99; Americas 0.39)
   (notes/17).
3. Africa, same state-years: UCDP and ACLED agree; only h = 1 after UN sanctions and arms embargoes excludes zero —
   suggestive, not a finding (user caught an overstatement; notes/18 corrected).
4. Trade exposure to the sender does not change the response (exposure/notes/01–02).

**Open, in suggested order:**
1. Leave-one-country-out for the Africa UN/arms h = 1 result (offered, not run).
2. Peace processes: do sanctions come with ceasefires / peace agreements / peacekeeping? Data the user would
   download: UCDP Peace Agreement and Conflict Termination datasets; IPI Peacekeeping Database or Geo-PKO.
3. Counter-sanctions draft table (`data/scripts/cleaning/gsdb_counter_sanctions_draft.csv`, `confirmed` column) —
   still unchecked by the user.
4. Exposure project E6 (arms embargoes × arms dependence, pooled senders, in wars) and E7 (arms groups none/some/high,
   proposed, to confirm).
5. ACLED coverage start years (A5) still to check against ACLED's published list; TIES download; monthly timing
   (ACLED months + announcement dates); "retaliation", "symmetric vs asymmetric" meanings with the advisor.
6. Writing/main.tex has not been updated with any of the 9 Nov results.

**Working rules learned (also in memory):** ask before non-mechanical data choices; document every download and
cleaning decision in data/README (section 4c pattern); no Claude co-author in commits; Healy-style faceted figures;
do not overstate — check what the intervals actually show before summarising.

## 11. Data side (unchanged since 20 Oct; details in `data/README.md`)

- Sources: GSDB R4 (sanctions; flows S11 validated vs GSDB-R4 Fig. 6b, Russia 2022 = 25 new / 38 active), UCDP
  OV-CY v26.1 (deaths, per 100,000; missing before 1989), GDELT 1.0 (1979–2021, own crosswalk/assignments),
  peacesciencer/isard democracy (isard 0.2.0, B11), GDP/population extended to 2023 (`gdp_ext`, `pop_ext`).
- Yugoslavia: cases attributed per republic (`data/README_yugoslavia.md`), dummies `ex_yugo`, `ex_yugo_1991_2016`.
  `ex_yugo_1991_2016` is **no longer a control** (removed 23 Oct, see ANALYSIS_PLAN change log); R9 in 09 part 5.
- Known gaps: GDP 2020–23 missing for 12 states; GDELT ends 2021; UCDP starts 1989; GSDB group cases kept as coded.
- Data replication check: `master.py --check` against `archive/baseline`; after intentional changes the user runs `--set-baseline`.
