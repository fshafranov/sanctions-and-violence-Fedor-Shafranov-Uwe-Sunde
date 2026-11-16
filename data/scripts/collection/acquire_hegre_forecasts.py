"""
acquire_hegre_forecasts.py — download the replication packages of Hegre et al. (2013, ISQ) and Hegre et al. (2016,
ERL), the country-year conflict forecasting model behind https://havardhegre.net/forecasting/.

ISQ 2013 package (https://havardhegre.net/replication-data/, 3.7 MB) -> data/raw/hegre_isq/replicationdataisq2013.zip
  CountryYearResults.dta          169 GW states x 2010-2050: predicted risk of minor / major / any conflict
                                  (share of simulations; sh_cnt_t1, sh_cnt_t2, sh_cnt_c) + p10/p50/p90 across model
                                  draws; model estimated on data through 2009 -> genuine forecasts for 2010-2019
  estimationdata_withlags.dta     1970-2009 observed (+ projections to 2050), all model variables (IMR, youth,
                                  education, polity, PKO, neighbours, ...)
  aggregatedglobalpredictions.dta global / regional shares in conflict, 9 models
  estimationreplication.do        Stata code for tables A-1, A-2
  The 2001-2009 out-of-sample test (trained 1970-2000) is NOT in the package; only summary figures on the website.

    uv run python data/scripts/collection/acquire_hegre_forecasts.py            # skips the file if on disk
    uv run python data/scripts/collection/acquire_hegre_forecasts.py --force    # re-download

Added 2026-11-16 (advisor: use conflict forecasts as an analogue to a propensity score; does the reaction to
predictable and unpredictable conflict differ?).

Source: Hegre, Buhaug, Calvin, Nordkvelle, Waldhoff & Gilmore (2016), "Forecasting civil conflict along the shared
socioeconomic pathways", Environmental Research Letters 11(5) 054002. Replication zip linked from
https://havardhegre.net/forecasting-civil-conflict-ssps/ (about 66 MB). Saved unchanged to data/raw/hegre_ssp/;
data/scripts/cleaning/clean_hegre_forecasts.py reads it straight from the zip (no extraction, nothing in it is run).

What is inside (checked 2026-11-16):
  SSPForecasts/Sim/Program/estimationdata.dta  country-year (GW codes), 1960-2013 observed: conflict 0/1/2
                                               (none / minor 25-999 BD / major 1000+ BD, UCDP/PRIO intrastate),
                                               time in status, neighbour conflict, population, GDP pc, education
                                               (YMHEP), region; 2014-2099 = SSP projections of the covariates
  PredictionTemp/SSP_sim/Res_sim_1_1_1_1.txt   ONE simulation file of the 2016 forecast (scenario 1 = SSP1,
                                               random-effect draw 1, coefficient draw 1, 19 runs, last run cut
                                               off); cutoff0/cutoff1 = cumulative predicted probabilities
  SSPForecasts/Parameters/parameters_baseline_ssp.txt  model specification (multinomial logit terms)
The full forecast ensemble (8 scenarios x 15 x 15 draws) is NOT in the package.
"""

import argparse
import hashlib
import json
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PACKAGES = {  # folder: (url, reference)
    "hegre_ssp": ("https://havardhegre.net/wp-content/uploads/2016/04/replicationssp_hh.zip",
                  "Hegre et al. (2016), Environmental Research Letters 11(5) 054002"),
    "hegre_isq": ("https://havardhegre.net/wp-content/uploads/2013/09/replicationdataisq2013.zip",
                  "Hegre et al. (2013), International Studies Quarterly 57(2) 250-270"),
}
HEADERS = {"User-Agent": "sanctions-violence-research/0.1 (python)"}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-download if the file exists")
    args = parser.parse_args()
    for folder, (url, reference) in PACKAGES.items():
        out = ROOT / "data" / "raw" / folder
        out.mkdir(parents=True, exist_ok=True)
        target = out / url.rsplit("/", 1)[1]
        if target.exists() and not args.force:
            print(f"on disk, skipped: {target.relative_to(ROOT)}")
            continue
        for attempt in range(5):  # the site drops connections (16 Nov 2026); retry the whole file
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=600) as response:
                    expected, body = int(response.headers.get("Content-Length", 0)), response.read()
                if expected and len(body) != expected:
                    raise IOError(f"got {len(body)} of {expected} bytes")
                break
            except Exception as error:
                if attempt == 4:
                    raise
                print(f"    retry after error: {error}")
        target.write_bytes(body)
        sha = hashlib.sha256(body).hexdigest()
        manifest = {"file": target.name, "url": url, "downloaded": datetime.now().isoformat(timespec="seconds"),
                    "bytes": len(body), "sha256": sha, "reference": reference}
        (out / "hegre_download_manifest.json").write_text(json.dumps(manifest, indent=2))
        print(f"{len(body) / 1e6:.1f} MB, sha256 {sha[:12]}... -> {target.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
