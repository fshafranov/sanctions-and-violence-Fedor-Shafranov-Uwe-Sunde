# Raw data — as downloaded, never modified

| Folder | File(s) | Source | Used by |
|---|---|---|---|
| `gsdb/` | `GSDB_V4_dyadic.dta`, `GSDB_V4.csv`, `gsdb_v4.zip`, `Var_Description.xlsx` | Global Sanctions Data Base, v4 | `clean_gsdb.py` (dyadic .dta) |
| `ucdp_ov/` | `OrganizedViolenceCYDataSet26_1.csv`, codebook PDF | UCDP Organized Violence Country-Year, v26.1 | `clean_ucdp_ov.py` |
| `gdelt/` | `gdelt_conflict_1_0.csv` | GDELT 1.0 conflict events (country-year-CAMEO root) | `clean_gdelt.py` |
| `population/` | `population_owid_WPP2024_processed.csv` (+ `.metadata.json`, `.readme.md` as downloaded) | UN World Population Prospects 2024 – processed by Our World in Data (“Population – UN WPP”, total population on 1 July, persons, 1950–2023); downloaded 20 Oct 2026 from ourworldindata.org | `clean_population.py` |
| `gdp-per-capita-worldbank/` | `gdp-per-capita-worldbank.csv` (+ `.metadata.json`, `readme.md`) | World Bank WDI GDP per capita, PPP (constant 2021 int. $), via Our World in Data, 1990–2025; downloaded 20 Oct 2026 | `clean_gdp.py` |
| `acled/` | `acled_political_violence_<year>.csv`, `acled_download_manifest.json` | ACLED events, disorder type "Political violence", via the ACLED API (`data/scripts/collection/acquire_acled.py`; download date per year in the manifest). Terms restrict redistribution — never commit | `clean_acled.py` |
| `ucdp_prio/` | `UcdpPrioConflict_v26_1.csv` | UCDP/PRIO Armed Conflict Dataset v26.1 | not used (clean_base.R uses peacesciencer's copy of the ACD) |
| `states/` | `gwstates.csv`, `cowstates.csv`, `codelist_panel.csv` | exported from the R packages `states` and `countrycode` | not used |
| `owid/` | deaths and death rates in armed conflicts | Our World in Data (UCDP-based) | not used |

The state-year base (`clean_base.R`) has no raw file: it comes from the R package peacesciencer at run time.
TODO: record download dates and URLs for each dataset.

**Git and DVC (2026-11-09):** the raw folders are git-ignored **by name** in the root `.gitignore` — add every new
raw folder there (e.g. `data/raw/ties/` is already listed). `acled/` is versioned with DVC (`data/raw/acled.dvc`).
