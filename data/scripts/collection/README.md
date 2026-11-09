Acquisition scripts (download raw data into `data/raw/`). Hand-downloaded files are documented in data/raw/README.md.

| Script | Dataset | Run by |
|---|---|---|
| `acquire_acled.py` | ACLED political-violence events via the ACLED API, one CSV per year → `data/raw/acled/` | the user (needs a myACLED login in the git-ignored `.env`; see the script header). Not part of `master.py`: raw data are downloaded once and then frozen. |
