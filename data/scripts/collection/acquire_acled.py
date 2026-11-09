"""
acquire_acled.py — download ACLED political-violence events through the ACLED API.

Run by the USER (the credentials never pass through the AI assistant):

    1. Put your myACLED login into a file `.env` in the project root (git-ignored):
           ACLED_EMAIL=you@example.org
           ACLED_PASSWORD=your-password
    2. uv run python data/scripts/collection/acquire_acled.py              # all years 1997..last year
       uv run python data/scripts/collection/acquire_acled.py --years 2018 2019   # selected years
       uv run python data/scripts/collection/acquire_acled.py --test        # one small call (10 rows) to check access

What it downloads (decision 2026-11-09, see data/README.md):
  - ACLED endpoint https://acleddata.com/api/acled/read, dyadic events (one row per event).
  - disorder_type LIKE "Political violence" (matches "Political violence" and "Political violence; Demonstrations",
    i.e. battles, explosions/remote violence, violence against civilians, and mob violence). Protests and strategic
    developments are not downloaded.
  - Selected columns only (FIELDS below; no `notes`/`source` text, to keep the files small).
  - inter1/inter2/interaction as numeric codes (inter_num=1), so that UCDP's three types can be rebuilt
    (state-based: a State-forces actor; non-state; one-sided: violence against civilians).
  - One CSV per year: data/raw/acled/acled_political_violence_<year>.csv; years already on disk are skipped
    (delete a file to re-download it). A manifest (acled_download_manifest.json) records the download time,
    query, row count and any access restrictions ACLED reports (`data_query_restrictions`).

API details (ACLED API documentation, "Getting started", "Elements of ACLED's API", read 2026-11-09):
  OAuth token: POST https://acleddata.com/oauth/token (username, password, grant_type=password, client_id=acled),
  valid 24 h; header "Authorization: Bearer <token>". Cursor pagination: start with cursor=0, pass next_cursor
  from each response, stop when next_cursor is null. Default/maximum page size used here: 5000 rows.

ACLED terms of use restrict redistribution: data/raw/ is git-ignored; do not commit or share the raw files.
"""

import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "raw" / "acled"
ENV_FILE = ROOT / ".env"

TOKEN_URL = "https://acleddata.com/oauth/token"
READ_URL = "https://acleddata.com/api/acled/read"
PAGE_SIZE = 5000
# ACLED sits behind Cloudflare, which rejects Python's default "Python-urllib" User-Agent with
# "error code: 1010" (HTTP 403) before the login is checked. Send a plain client name instead.
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python; ACLED API client)", "Accept": "application/json"}
FIRST_YEAR = 1997                     # earliest ACLED coverage (Africa)
FIELDS = ["event_id_cnty", "event_date", "year", "time_precision", "disorder_type", "event_type", "sub_event_type",
          "actor1", "assoc_actor_1", "inter1", "actor2", "assoc_actor_2", "inter2", "interaction",
          "civilian_targeting", "iso", "region", "country", "admin1", "fatalities", "timestamp"]


# --- credentials and token ---------------------------------------------------------------
def read_credentials():
    """ACLED_EMAIL / ACLED_PASSWORD from the environment or from .env (simple KEY=VALUE lines)."""
    values = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"').strip("'")
    email = os.environ.get("ACLED_EMAIL") or values.get("ACLED_EMAIL")
    password = os.environ.get("ACLED_PASSWORD") or values.get("ACLED_PASSWORD")
    if not email or not password:
        sys.exit(f"Missing ACLED_EMAIL / ACLED_PASSWORD: put them into {ENV_FILE} (see the header of this script).")
    return email, password


def get_token(email, password):
    body = urllib.parse.urlencode({"username": email, "password": password, "grant_type": "password",
                                   "client_id": "acled", "scope": "authenticated"}).encode()
    request = urllib.request.Request(TOKEN_URL, data=body, method="POST",
                                     headers={**HEADERS, "Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)["access_token"]
    except urllib.error.HTTPError as error:
        detail = error.read()[:300]
        hint = (" (Cloudflare block of the client, not a password problem)" if b"1010" in detail else
                ": check the email/password in .env and that your myACLED account has API access")
        sys.exit(f"Login failed (HTTP {error.code}){hint}. Server says: {detail!r}")


# --- one API call ---------------------------------------------------------------------------
def read_page(token, params, retries=4):
    url = READ_URL + "?" + urllib.parse.urlencode(params, safe="|")
    request = urllib.request.Request(url, headers={**HEADERS, "Authorization": f"Bearer {token}"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                sys.exit(f"Access denied (HTTP {error.code}): {error.read()[:300]!r}")
            if attempt == retries - 1:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == retries - 1:
                raise
        wait = 10 * (attempt + 1)
        print(f"    call failed, retrying in {wait} s ...")
        time.sleep(wait)


def base_params(year):
    return {"_format": "json", "year": year, "disorder_type": "Political violence", "inter_num": 1,
            "fields": "|".join(FIELDS), "limit": PAGE_SIZE}


# --- download one year with cursor pagination ------------------------------------------------
def download_year(token, year):
    rows, cursor, restrictions = [], 0, None
    while cursor is not None:
        result = read_page(token, {**base_params(year), "cursor": cursor})
        if result.get("status") not in (200, None) or "data" not in result:
            sys.exit(f"Unexpected response for {year}: {str(result)[:500]}")
        rows.extend(result["data"])
        restrictions = restrictions or result.get("data_query_restrictions")
        cursor = result.get("next_cursor")
        print(f"    {year}: {len(rows):>7} rows", end="\r")
    print()
    return rows, restrictions


def write_csv(rows, path):
    tmp = path.with_suffix(".tmp")
    with tmp.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    tmp.replace(path)                                  # only complete years appear under the final name


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--years", nargs="+", type=int, help="years to download (default: 1997..last year)")
    parser.add_argument("--test", action="store_true", help="one call of 10 rows to check login and access")
    args = parser.parse_args()

    email, password = read_credentials()
    token = get_token(email, password)
    print("Logged in to ACLED (token received).")

    if args.test:
        result = read_page(token, {**base_params(2019), "limit": 10})
        print("Test call OK:", result.get("count"), "rows;", "restrictions:",
              json.dumps(result.get("data_query_restrictions"), indent=1))
        for row in result.get("data", [])[:3]:
            print({k: row.get(k) for k in ("event_date", "country", "event_type", "inter1", "inter2", "fatalities")})
        return

    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "acled_download_manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    years = args.years or list(range(FIRST_YEAR, datetime.now().year))

    for year in years:
        path = OUT / f"acled_political_violence_{year}.csv"
        if path.exists():
            print(f"  {year}: already downloaded, skipped")
            continue
        print(f"  {year}: downloading ...")
        rows, restrictions = download_year(token, year)
        write_csv(rows, path)
        manifest[str(year)] = {"downloaded": datetime.now().isoformat(timespec="seconds"), "rows": len(rows),
                               "fatalities": sum(int(r.get("fatalities") or 0) for r in rows),
                               "query": {k: v for k, v in base_params(year).items() if k != "fields"},
                               "fields": FIELDS, "data_query_restrictions": restrictions}
        manifest_path.write_text(json.dumps(manifest, indent=1))
        print(f"  {year}: {len(rows)} events, {manifest[str(year)]['fatalities']} fatalities -> {path.name}")
        if restrictions:
            print(f"  NOTE: ACLED reports access restrictions for this query: {restrictions}")

    print("Done. Files in", OUT)


if __name__ == "__main__":
    main()
