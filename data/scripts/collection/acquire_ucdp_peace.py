"""
acquire_ucdp_peace.py — download the UCDP Peace Agreement Dataset and the UCDP Conflict Termination Dataset
from the UCDP download centre (https://ucdp.uu.se/downloads/, public, no login) into data/raw/ucdp_peace/.

    uv run python data/scripts/collection/acquire_ucdp_peace.py          # skip files already on disk
    uv run python data/scripts/collection/acquire_ucdp_peace.py --force  # re-download

Added 2026-11-16 (anticipation check of the US sanction effect: were peace processes already under way when the US
sanctioned? empirics/notes/13, section 8). Files are saved unchanged; the manifest records URL, time, size, sha256.

  ucdp-peace-agreements-222.xlsx                        UCDP Peace Agreement Dataset v22.2, one row per agreement
                                                        (1975-2021), conflict id, date, type (full / partial / process)
  ucdp-codebook-peace-agreements-221.pdf                its codebook (v22.1 is the latest codebook published)
  UCDPConflictTerminationDataset_v4_2024_Conflict.csv   conflict episodes with start/end dates and outcome
                                                        (peace agreement, ceasefire, victory, low activity, ...)
  UCDPConflictTerminationDataset_v4_2024_Dyad.csv       the same per dyad
  UCDPConflictTerminationDataset_v4_2024_Codebook.pdf   codebook
"""

import argparse
import hashlib
import json
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "data" / "raw" / "ucdp_peace"
BASE = "https://ucdp.uu.se/downloads/"
FILES = [
    "peace/ucdp-peace-agreements-222.xlsx",
    "peace/ucdp-codebook-peace-agreements-221.pdf",
    "monadterm/UCDPConflictTerminationDataset_v4_2024_Conflict.csv",
    "monadterm/UCDPConflictTerminationDataset_v4_2024_Dyad.csv",
    "monadterm/UCDPConflictTerminationDataset_v4_2024_Codebook.pdf",
]
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python; UCDP download)"}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-download files that exist")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_file = OUT / "ucdp_peace_download_manifest.json"
    manifest = json.loads(manifest_file.read_text()) if manifest_file.exists() else {}
    for rel in FILES:
        target = OUT / Path(rel).name
        if target.exists() and not args.force:
            print(f"{target.name:56s} on disk, skipped")
            continue
        with urllib.request.urlopen(urllib.request.Request(BASE + rel, headers=HEADERS), timeout=120) as response:
            data = response.read()
        target.write_bytes(data)
        manifest[target.name] = {"url": BASE + rel, "downloaded": datetime.now().isoformat(timespec="seconds"),
                                 "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        print(f"{target.name:56s} {len(data) / 1024:8.0f} KB")
    manifest_file.write_text(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
