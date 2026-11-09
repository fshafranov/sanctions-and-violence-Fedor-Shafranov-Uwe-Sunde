"""
acquire_sipri.py — download the SIPRI Arms Transfers Database (bilateral TIV tables and the transfer register).

    uv run python data/scripts/collection/acquire_sipri.py                 # all suppliers (skips files on disk)
    uv run python data/scripts/collection/acquire_sipri.py --test          # United States only
    uv run python data/scripts/collection/acquire_sipri.py --suppliers USA RUS

Added 2026-11-09 (advisor: "SIPRI arms data"). The WDI copy of SIPRI (acquire_wdi.py) has only each country's
TOTAL arms imports; this script gets the supplier -> recipient detail, so that arms supplied by the sanctioning
state(s) can be measured.

There is no documented SIPRI API. The public website https://armstransfers.sipri.org/ArmsTransfer/ is a JavaScript
app whose "DOWNLOAD AS CSV" buttons POST a JSON filter to a public backend (https://atbackend.sipri.org/api/p, no
login; endpoints and request format read from the site's bundle.js on 2026-11-09). This script sends the same
requests the buttons send, one supplier at a time with a pause in between, and saves SIPRI's CSV output unchanged.
If SIPRI changes its site the requests may stop working; the manual route is the site's Data menu
("Import/Export values" = TIV tables, "Transfer register").

Per supplier (SIPRI entity, incl. non-state actors and organisations), years FIRST_YEAR..last full year:
  tiv/sipri_tiv_<CODE>.csv          "Import/Export values": TIV of major arms DELIVERED by the supplier, one row per
                                    recipient, one column per year (millions of SIPRI TIV; '0' = between 0 and 0.5;
                                    empty = no deliveries identified). Header lines with SIPRI's notes kept.
  register/sipri_register_<CODE>.csv "Transfer register": one row per deal with deliveries or orders in the range
                                    (recipient, weapon designation and category, order year, numbers, delivery years,
                                    TIV per unit / of the order / of deliveries, comments).
Plus sipri_entities.json (SIPRI entity ids, names, codes) and sipri_download_manifest.json.
Suppliers with no transfers return an empty table; recorded in the manifest, no file written.

Terms: SIPRI data are free for research; cite "SIPRI Arms Transfers Database" with the download date. The raw folder
is git-ignored and versioned with DVC.
"""

import argparse
import base64
import json
import ssl
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

import certifi

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "raw" / "sipri"
BACKEND = "https://atbackend.sipri.org/api/p"
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python; SIPRI public CSV export)",
           "Content-Type": "application/json"}
SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
FIRST_YEAR = 1950          # earliest year SIPRI allows
PAUSE = 1.0                # seconds between requests (be polite to SIPRI's server)


def request(path, body=None, retries=4):
    data = None if body is None else json.dumps(body).encode()
    for attempt in range(retries):
        try:
            req = urllib.request.Request(BACKEND + path, data=data, headers=HEADERS,
                                         method="GET" if body is None else "POST")
            with urllib.request.urlopen(req, timeout=300, context=SSL_CONTEXT) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            message = error.read().decode("utf-8", "replace")[:300]
            if attempt == retries - 1:
                raise RuntimeError(f"{path}: HTTP {error.code} {message}") from error
        except Exception:
            if attempt == retries - 1:
                raise
        time.sleep(10 * (attempt + 1))


def csv_text(response):
    """The CSV endpoints return {"bytes": <base64 CSV>}, as the website decodes it."""
    return base64.b64decode(response["bytes"]).decode("utf-8", "replace")


def condition_filter(field, value1="", value2="", ids=None, condition="contains"):
    return {"field": field, "oldField": "", "condition": condition, "value1": value1, "value2": value2,
            "listData": ids or []}


def tiv_table(entity_id, last_year):
    """'Import/Export values' page: deliveries by this supplier, by recipient and year (as the web form sends it)."""
    filters = [condition_filter("Year range 1", FIRST_YEAR, last_year),
               condition_filter("Supplier", ids=[str(entity_id)]),
               condition_filter("summarize-by", "country", condition=""),
               condition_filter("DeliveryType", "delivered", condition=""),
               condition_filter("Status", "0", condition="")]
    return csv_text(request("/trades/import-export-csv/", {"filters": filters, "logic": "AND"}))


def transfer_register(entity_id, last_year):
    """'Transfer register' page: deals of this supplier active in the year range (as the web form sends it)."""
    filters = [condition_filter("activePrograms", FIRST_YEAR, last_year),
               condition_filter("Supplier", ids=[str(entity_id)]),
               condition_filter("opendeals", condition="")]
    return csv_text(request("/trades/trade-register-csv/?output=csv", {"filters": filters, "logic": "AND"}))


def data_rows(text, header_start):
    """Number of data lines after the table header (0 = supplier without transfers)."""
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if line.startswith(header_start)), None)
    return 0 if start is None else sum(1 for line in lines[start + 1:] if line.strip() and not line.startswith("Total"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--suppliers", nargs="+", help="SIPRI country codes (default: every entity)")
    parser.add_argument("--test", action="store_true", help="United States only, overwrite")
    args = parser.parse_args()
    (OUT / "tiv").mkdir(parents=True, exist_ok=True)
    (OUT / "register").mkdir(parents=True, exist_ok=True)

    last_year = int(request("/trades/getMaxYear"))           # last full year SIPRI publishes
    entities = [e for e in request("/countries/getAllCountriesTrimmed") if not e.get("deleted")]
    (OUT / "sipri_entities.json").write_text(json.dumps(entities, indent=2, ensure_ascii=False))
    wanted = ["USA"] if args.test else args.suppliers
    if wanted:
        entities = [e for e in entities if e.get("CountryCode") in wanted]
    print(f"SIPRI data to {last_year}; {len(entities)} supplier entities to fetch")

    manifest_file = OUT / "sipri_download_manifest.json"
    manifest = json.loads(manifest_file.read_text()) if manifest_file.exists() else {}
    manifest["_query"] = {"years": f"{FIRST_YEAR}-{last_year}", "backend": BACKEND,
                          "tiv": "import-export-csv, supplier, summarize-by country, delivered, status 0",
                          "register": "trade-register-csv, supplier, activePrograms year range, opendeals"}
    for i, entity in enumerate(entities, 1):
        code = entity.get("CountryCode") or str(entity["EntityId"])
        key = f"{code}_{entity['EntityId']}"
        tiv_file, register_file = OUT / "tiv" / f"sipri_tiv_{key}.csv", OUT / "register" / f"sipri_register_{key}.csv"
        if key in manifest and not args.test:
            continue
        tiv = tiv_table(entity["EntityId"], last_year); time.sleep(PAUSE)
        register = transfer_register(entity["EntityId"], last_year); time.sleep(PAUSE)
        recipients, deals = data_rows(tiv, "Recipient,"), data_rows(register, "Recipient,")
        if recipients:
            tiv_file.write_text(tiv)
        if deals:
            register_file.write_text(register)
        manifest[key] = {"name": entity["Name"], "entity_id": entity["EntityId"], "code": code,
                         "downloaded": datetime.now().isoformat(timespec="seconds"),
                         "tiv_recipient_rows": recipients, "register_rows": deals}
        manifest_file.write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
        print(f"[{i}/{len(entities)}] {entity['Name']}: {recipients} recipients, {deals} register rows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
