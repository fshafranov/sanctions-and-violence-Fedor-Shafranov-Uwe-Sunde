"""
acquire_views.py — download archived VIEWS country-month forecast runs (Hegre's current early-warning system,
Uppsala/PRIO) from the public API https://api.viewsforecasting.org (no login).

    uv run python data/scripts/collection/acquire_views.py            # year-ahead runs only, main columns (default)
    uv run python data/scripts/collection/acquire_views.py --all      # every run below, all model columns
    uv run python data/scripts/collection/acquire_views.py --force    # re-download files on disk

Default (YEAR_AHEAD): for each target year the run made at the turn of the year (window starting in
January, or December for the 2021 release), only the main forecast columns, GED actuals with --actuals. The API was
very slow on 2026-11-16 (2.4 MB in > 3 min, timeouts), so the default keeps requests few and small; the script
resumes (files on disk are skipped) and pages are small so a timeout costs little.

Added 2026-11-16 (advisor: conflict forecasts as an analogue to a propensity score).

Runs downloaded (country-month 'cm' level, all models of the run, one CSV per run in data/raw/views/):
  r_2021_MM_01                ViEWS2020 model, monthly releases 2021 (name = release month; per the API wiki
                              r_2021_12_01 used data through 2021-10)
  fatalities001_YYYY_MM_t01   2021-12 .. 2023-03   (name = last month of input data, from 2022 on)
  fatalities002_YYYY_MM_t0x   2023-04 .. 2025-10
  fatalities003_YYYY_MM_t01   2025-10 .. today
  predictors_fatalities003_*  UCDP GED monthly fatality counts the models use (state-based, non-state,
                              one-sided; 1995-) = VIEWS's own actuals
Each forecast run covers the 36 months after its last input month. month_id 1 = January 1980 (checked: 562 =
October 2026). Column meanings (API codebooks, https://api.viewsforecasting.org/<run>/codebook):
  main_dich / sc_cm_sb_dich_main   P(at least 25 battle-related deaths, state-based, in the country-month)
  main_mean                        point prediction of state-based fatalities (UCDP GED)
  main_mean_ln / sc_cm_sb_main     the same as ln(1 + fatalities)
  cm_sb_main (r_2021 runs)         probably P(>= 25 BRD) (ViEWS2020 main outcome) — not stated in the codebook
Raw API responses are saved unchanged as CSV (column order as returned); a manifest records time, rows, columns.
"""

import argparse
import csv
import json
import re
import sys
import time
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "raw" / "views"
API = "https://api.viewsforecasting.org"
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python; VIEWS API client)", "Accept": "application/json"}
KEEP = re.compile(r"^(r_2021_\d\d_01|fatalities00\d_\d{4}_\d\d_t\d\d|predictors_fatalities003_.*)$")
PAGESIZE = 100  # 16 Nov 2026: responses > ~100 KB stall on the VIEWS server; 100-row pages (~12 KB) get through
# target year -> (run, columns). Run names: from 2022 YYYY_MM = last input month, so the 2022_12 run forecasts
# Jan 2023 on. Leaf columns only: asking for a parent node (e.g. sc_cm_sb_main, main_mean_ln) returns its whole
# sub-model tree. fatalities001 runs: None = full run (its main column is the root node).
# No 2021 entry: r_2021_01_01 (checked 16 Nov 2026) starts in Feb 2021 (month_id 494), covers only 111 countries
# (ViEWS2020 = Africa + Middle East), and its probability column is called sc_cm_sb_main (values 0-1).
YEAR_AHEAD = {
    2022: ("fatalities001_2021_12_t01", None),
    2023: ("fatalities001_2022_12_t01", None),
    2024: ("fatalities002_2023_12_t01", ["main_dich", "main_mean"]),
    2025: ("fatalities002_2024_12_t01", ["main_dich", "main_mean"]),
    2026: ("fatalities003_2025_12_t01", ["main_dich", "main_mean"]),
}
ACTUALS = ("predictors_fatalities003_0000_00", ["ucdp_ged_sb_best_sum"])  # --actuals (70k rows = 700 pages)
ID_COLS = ["country_id", "month_id", "name", "gwcode", "isoab", "year", "month"]


def get_json(url, retries=8):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=90) as response:
                return json.load(response)
        except Exception as error:  # network hiccup: wait and retry
            if attempt == retries - 1:
                raise
            print(f"    retry after error: {error}")
            time.sleep(5 * (attempt + 1))


def download_column(run, column):
    """One model column of a run (endpoint /<run>/cm/<sb|px>/<column>), all pages."""
    level = "px" if run.startswith("predictors") else "sb"
    return download_run(run, f"{API}/{run}/cm/{level}/{column}?pagesize={PAGESIZE}")


def download_run(run, url=None):
    rows, url = [], url or f"{API}/{run}/cm?pagesize={PAGESIZE}"
    meta = None
    while url:
        page = get_json(url)
        meta = meta or {k: page.get(k) for k in ("models", "row_count", "start_date", "end_date")}
        rows.extend(page["data"])
        url = page.get("next_page") or ""
    return rows, meta


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-download files that exist")
    parser.add_argument("--all", action="store_true", help="every forecast run, all model columns")
    parser.add_argument("--actuals", action="store_true", help="also the UCDP GED monthly actuals (slow)")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_file = OUT / "views_download_manifest.json"
    manifest = json.loads(manifest_file.read_text()) if manifest_file.exists() else {}

    if args.all:
        jobs = [(r, None) for r in get_json(f"{API}/")["runs"] if KEEP.match(r)]
    else:
        jobs = list(YEAR_AHEAD.values()) + ([ACTUALS] if args.actuals else [])
    print(f"{len(jobs)} runs to fetch")
    for run, columns in jobs:
        target = OUT / f"views_cm_{run}.csv"
        if target.exists() and not args.force:
            print(f"{run:34s} on disk, skipped")
            continue
        if columns is None:
            rows, meta = download_run(run)
        else:  # merge the single-column downloads on country x month
            merged, meta = {}, None
            for column in columns:
                part, part_meta = download_column(run, column)
                meta = meta or part_meta
                for row in part:
                    merged.setdefault((row["country_id"], row["month_id"]), {k: row[k] for k in ID_COLS})[column] = row.get(column)
            missing = sum(r.get(c) is None for r in merged.values() for c in columns)
            print(f"    {run}: {missing} empty cells in {columns}")
            rows, meta["models"] = list(merged.values()), columns
        columns = list(dict.fromkeys(k for row in rows for k in row))
        with target.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=columns)
            writer.writeheader()
            writer.writerows(rows)
        assert len(rows) == meta["row_count"], f"{run}: {len(rows)} rows, API says {meta['row_count']}"
        manifest[run] = {"file": target.name, "downloaded": datetime.now().isoformat(timespec="seconds"),
                         "rows": len(rows), "first_month_id": meta["start_date"], "last_month_id": meta["end_date"],
                         "models": meta["models"]}
        print(f"{run:34s} {len(rows):7d} rows, month_id {meta['start_date']}-{meta['end_date']}")
        manifest_file.write_text(json.dumps(manifest, indent=2))
    manifest_file.write_text(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
