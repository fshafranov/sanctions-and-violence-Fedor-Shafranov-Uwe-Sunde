Acquisition scripts (download raw data into `data/raw/`). Hand-downloaded files are documented in data/raw/README.md.

| Script | Dataset | Run by |
|---|---|---|
| `acquire_acled.py` | ACLED political-violence events via the ACLED API, one CSV per year → `data/raw/acled/` | the user (needs a myACLED login in the git-ignored `.env`; see the script header). Not part of `master.py`: raw data are downloaded once and then frozen. |
| `acquire_wdi.py` | World Bank WDI: trade/exports/imports % GDP, FDI % GDP, SIPRI arms imports/exports (TIV), GDP current US$ → `data/raw/wdi/` | anyone (public API, no login); not in `master.py` |
| `acquire_imf_trade.py` | IMF IMTS bilateral goods trade, all reporters × partners → `data/raw/imf_imts/` (`--test` = USA only) | anyone (public API); ~272 requests, resumable (skips reporters on disk); not in `master.py` |
