"""
acquire_imf_trade.py — download IMF bilateral goods trade (IMTS, formerly DOTS) for every reporter and partner.

    uv run python data/scripts/collection/acquire_imf_trade.py               # all reporters (skips files on disk)
    uv run python data/scripts/collection/acquire_imf_trade.py --reporters USA NGA   # selected reporters
    uv run python data/scripts/collection/acquire_imf_trade.py --test        # one reporter, print a summary

Added 2026-11-09 (advisor: weight sanctions by trade exposure). Goal: exposure of a target to the sender
(e.g. trade with the US / the EU as a share of the target's GDP or total trade). The FULL bilateral matrix is
downloaded (every reporter x every partner), so that the sender definition (US, EU members, any GSDB sender)
can be chosen later in cleaning without a new download.

Source: IMF SDMX 2.1 API, dataflow IMF.STA:IMTS ("International Trade in Goods (by partner country)"):
  https://api.imf.org/external/sdmx/2.1/data/IMF.STA,IMTS/<COUNTRY>.<INDICATOR>.<COUNTERPART_COUNTRY>.A
  INDICATOR: XG_FOB_USD (goods exports, FOB, US$), MG_CIF_USD (goods imports, CIF, US$), TBG_USD (trade balance).
  Partner codes: ISO3 for countries; groups such as G001 World, G998 European Union (EU), G163 Euro Area.
  Goods only (no services). Values as reported (OBS_VALUE; the series' SCALE attribute is stored alongside).
  Mirror data: a partner's own report (e.g. US imports from Liberia) is downloaded too, because many conflict
  states report little; the choice between own and mirror flows is a cleaning decision.

Output: data/raw/imf_imts/imts_<REPORTER>.csv (long: reporter, indicator, partner, year, value, scale,
derivation_type) + imts_download_manifest.json (download time, rows, years per reporter) + imts_country_codes.csv
(code -> name, from the IMF codelist). Reporters already on disk are skipped. Raw files are never edited.
"""

import argparse
import csv
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree

import certifi

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "raw" / "imf_imts"
BASE = "https://api.imf.org/external/sdmx/2.1"
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python; IMF SDMX client)"}
START_YEAR = 1980
PAUSE = 0.5   # seconds between requests
# uv's Python does not use the macOS keychain; without certifi's CA bundle the IMF certificate chain fails to verify
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())


def fetch(url, retries=4):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=300, context=SSL_CONTEXT) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404:          # no data for this reporter
                return None
            if attempt == retries - 1:
                raise
        except Exception:
            if attempt == retries - 1:
                raise
        print(f"    retry {attempt + 1} for {url}")
        time.sleep(10 * (attempt + 1))


def country_codes():
    """IMF country codelist: code -> English name (countries and groups)."""
    root = ElementTree.fromstring(fetch(f"{BASE}/codelist/all/CL_COUNTRY/latest"))
    codes = {}
    for code in root.iter():
        if code.tag.endswith("}Code") and "id" in code.attrib:
            names = [n.text for n in code if n.tag.endswith("}Name")
                     and n.attrib.get("{http://www.w3.org/XML/1998/namespace}lang") == "en"]
            codes[code.attrib["id"]] = names[0] if names else ""
    return codes


def parse_series(xml_bytes):
    """Rows from an SDMX 2.1 structure-specific data message."""
    rows = []
    root = ElementTree.fromstring(xml_bytes)
    for series in root.iter():
        if not series.tag.endswith("Series"):
            continue
        attributes = series.attrib
        for obs in series:
            rows.append({"reporter": attributes.get("COUNTRY"), "indicator": attributes.get("INDICATOR"),
                         "partner": attributes.get("COUNTERPART_COUNTRY"), "year": obs.attrib.get("TIME_PERIOD"),
                         "value": obs.attrib.get("OBS_VALUE"), "scale": attributes.get("SCALE", ""),
                         "derivation_type": obs.attrib.get("DERIVATION_TYPE", "")})
    return rows


def download_reporter(code):
    xml = fetch(f"{BASE}/data/IMF.STA,IMTS/{code}...A?startPeriod={START_YEAR}")
    return parse_series(xml) if xml else []


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--reporters", nargs="+", help="reporter codes (default: every ISO3 code in the IMF codelist)")
    parser.add_argument("--test", action="store_true", help="download USA only and print a summary")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    codes = country_codes()
    with (OUT / "imts_country_codes.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["code", "name"])
        writer.writerows(sorted(codes.items()))
    reporters = ["USA"] if args.test else (args.reporters or sorted(c for c in codes if re.fullmatch(r"[A-Z]{3}", c)))
    print(f"{len(codes)} codes in the IMF codelist; {len(reporters)} reporters to fetch")

    manifest_file = OUT / "imts_download_manifest.json"
    manifest = json.loads(manifest_file.read_text()) if manifest_file.exists() else {}
    for i, code in enumerate(reporters, 1):
        target = OUT / f"imts_{code}.csv"
        if target.exists() and not args.test:
            continue
        rows = download_reporter(code)
        entry = {"downloaded": datetime.now().isoformat(timespec="seconds"), "rows": len(rows)}
        if rows:
            with target.open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
            years = sorted({r["year"] for r in rows})
            entry.update(file=target.name, first_year=years[0], last_year=years[-1],
                         partners=len({r["partner"] for r in rows}))
        manifest[code] = entry
        print(f"[{i}/{len(reporters)}] {code}: {len(rows)} rows" + (f", {entry['first_year']}-{entry['last_year']}" if rows else ""))
        manifest_file.write_text(json.dumps(manifest, indent=2))
        time.sleep(PAUSE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
