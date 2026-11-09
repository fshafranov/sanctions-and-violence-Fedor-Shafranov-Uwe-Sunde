"""
acquire_wdi.py — download selected World Bank WDI indicators (trade, capital flows, arms transfers, GDP in US$).

    uv run python data/scripts/collection/acquire_wdi.py            # all indicators below (skips files on disk)
    uv run python data/scripts/collection/acquire_wdi.py --force    # re-download everything

Added 2026-11-09 (advisor meeting 9 Nov: "weight by trade and capital flows, (X+M)/GDP"; "SIPRI arms data").
Public World Bank API v2, no login: https://api.worldbank.org/v2/country/all/indicator/<code>?format=json

Indicators (one CSV per indicator in data/raw/wdi/, long format: iso3c, country, year, value):
  NE.TRD.GNFS.ZS        Trade (% of GDP) = exports + imports of goods and services / GDP
  NE.EXP.GNFS.ZS        Exports of goods and services (% of GDP)
  NE.IMP.GNFS.ZS        Imports of goods and services (% of GDP)
  BX.KLT.DINV.WD.GD.ZS  Foreign direct investment, net inflows (% of GDP)
  BM.KLT.DINV.WD.GD.ZS  Foreign direct investment, net outflows (% of GDP)
  MS.MIL.MPRT.KD        Arms imports (SIPRI trend indicator values, TIV) — total from all suppliers, no bilateral detail
  MS.MIL.XPRT.KD        Arms exports (SIPRI TIV)
  NY.GDP.MKTP.CD        GDP (current US$) — denominator for the IMF bilateral goods trade (acquire_imf_trade.py)

The API returns all economies AND aggregates (regions, income groups); aggregates are kept in the raw file and
dropped in cleaning. Indicator metadata (source, definition, last update) go to wdi_indicators.json; the download
time and row counts to wdi_download_manifest.json. Raw files are never edited.
"""

import argparse
import csv
import json
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "raw" / "wdi"
API = "https://api.worldbank.org/v2"
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python; World Bank API client)", "Accept": "application/json"}
FIRST_YEAR, LAST_YEAR = 1960, datetime.now().year

INDICATORS = {
    "NE.TRD.GNFS.ZS": "trade_pct_gdp",
    "NE.EXP.GNFS.ZS": "exports_pct_gdp",
    "NE.IMP.GNFS.ZS": "imports_pct_gdp",
    "BX.KLT.DINV.WD.GD.ZS": "fdi_inflows_pct_gdp",
    "BM.KLT.DINV.WD.GD.ZS": "fdi_outflows_pct_gdp",
    "MS.MIL.MPRT.KD": "arms_imports_tiv",
    "MS.MIL.XPRT.KD": "arms_exports_tiv",
    "NY.GDP.MKTP.CD": "gdp_current_usd",
}


def get_json(url, retries=4):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as response:
                return json.load(response)
        except Exception as error:  # network hiccup: wait and retry
            if attempt == retries - 1:
                raise
            print(f"    retry after error: {error}")
            time.sleep(5 * (attempt + 1))


def download_indicator(code):
    """All pages of one indicator for all economies and aggregates."""
    rows, page, pages = [], 1, 1
    while page <= pages:
        meta, data = get_json(f"{API}/country/all/indicator/{code}?format=json&per_page=20000"
                              f"&date={FIRST_YEAR}:{LAST_YEAR}&page={page}")
        pages = meta["pages"]
        for obs in data or []:
            rows.append({"iso3c": obs["countryiso3code"], "wb_id": obs["country"]["id"],
                         "country": obs["country"]["value"], "year": obs["date"], "value": obs["value"],
                         "obs_status": obs.get("obs_status", ""), "decimal": obs.get("decimal", "")})
        page += 1
    return rows, meta.get("lastupdated", "")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-download files that exist")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    manifest_file = OUT / "wdi_download_manifest.json"
    manifest = json.loads(manifest_file.read_text()) if manifest_file.exists() else {}
    metadata = {}
    for code, short in INDICATORS.items():
        target = OUT / f"wdi_{short}.csv"
        info = get_json(f"{API}/indicator/{code}?format=json")[1][0]
        metadata[code] = {"file": target.name, "name": info["name"], "source_organization": info["sourceOrganization"],
                          "definition": info["sourceNote"], "source": info["source"]["value"]}
        if target.exists() and not args.force:
            print(f"{code:22s} on disk, skipped ({target.name})")
            continue
        rows, last_updated = download_indicator(code)
        with target.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
        non_missing = sum(r["value"] is not None for r in rows)
        manifest[code] = {"file": target.name, "downloaded": datetime.now().isoformat(timespec="seconds"),
                          "wb_last_updated": last_updated, "rows": len(rows), "non_missing": non_missing,
                          "years": f"{FIRST_YEAR}-{LAST_YEAR}"}
        print(f"{code:22s} {len(rows):6d} rows, {non_missing:6d} non-missing, WB last updated {last_updated} -> {target.name}")
    (OUT / "wdi_indicators.json").write_text(json.dumps(metadata, indent=2))
    manifest_file.write_text(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
