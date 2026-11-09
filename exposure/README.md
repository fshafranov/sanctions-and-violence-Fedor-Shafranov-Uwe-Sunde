# Exposure extension: do sanctions bite harder where the target depends on the sender?

Separate analysis project (user decision 9 Nov 2026), built on the same data pipeline as the main project
(`data/`, one panel, one DVC history, one replication check). Main project: `empirics/`.

**Question.** Is the response of violence to new sanctions larger when the target trades more with, or
buys more of its arms from, the sanctioning states? (Advisor meeting 9 Nov: "weight by trade and capital
flows", "symbolic vs effective sanctions", "SIPRI arms data".)

**Data.** The exposure variables are columns of the main panel
(`data/processed/sanctions_violence/sanctions_violence_panel.csv`, user decision 9 Nov: option B), built by
`data/scripts/processing/process_exposure.py`. Definitions, sources and every coding decision:
`data/README.md`, section 4c (T1–T5 downloads and user choices, W/I/S cleaning, X1–X7 exposure).

| Group | Variables (base = mean t−3..t−1; `_l1` = t−1; `_t` = t) |
|---|---|
| US | `trade_us_gdp`, `trade_us_share`, `arms_us_tiv`, `arms_us_share` |
| EU members of the year | `trade_eu_*`, `arms_eu_*` |
| UN (= all states = total) | `trade_un_*`, `arms_un_*` |
| Senders of the year's new cases | `trade_senders_*`, `arms_senders_*`, `n_sender_states` (only in years with a new case) |
| General | `trade_gdp`, `exports_gdp`, `imports_gdp`, `fdi_in_gdp`, `goods_trade_gdp`, `arms_imports_tiv`, `arms_supplier_hhi`, `arms_to_rebels_tiv` |
| Flags | `trade_<us|eu|senders>_zero_imputed` (NA robustness), `arms_no_sipri_record`, `trade_years` |

**Layout**

```
exposure/
  README.md          this file
  ANALYSIS_PLAN.md   design, decisions (E1, E2, ...), change log
  scripts/           00_setup.R (main setup + exposure/ paths), functions_exposure.R (data for UCDP/ACLED/GDELT,
                     estimation), 01_exposure_lp.R, 02_exposure_robustness.R
  results/           tables/, figures/, logs/ (written by the scripts; logs git-ignored)
  notes/             interpretation of the results
```

**Run:** `uv run python master.py --stage exposure` (all steps of this project) or `--only <step>`.
Figures follow Healy, *Data Visualization* (as the main project).

## Results so far

| Script | Result | Notes |
|---|---|---|
| 01_exposure_lp | Violence response to new sanctions does not vary with the target's trade or arms exposure to the sender in UCDP or ACLED; GDELT: more reported violence after EU/all-case sanctions on trade-exposed targets. | [notes/01](notes/01_exposure_lp.md) |
| 02_exposure_robustness | Trade null holds (no-record = missing, in wars, terciles; UCDP, ACLED). Arms: only EU sanctions on targets buying many EU arms show larger declines (UCDP −0.31**, ACLED −0.45*; 8–17 events). | [notes/02](notes/02_exposure_robustness.md) |
