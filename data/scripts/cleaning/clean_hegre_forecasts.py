"""
clean_hegre_forecasts.py — country-year files from the Hegre et al. (2016) replication package.

    uv run python data/scripts/cleaning/clean_hegre_forecasts.py

Input : data/raw/hegre_ssp/replicationssp_hh.zip, data/raw/hegre_isq/replicationdataisq2013.zip
        (acquire_hegre_forecasts.py); read inside the zips.
Output: data/clean/forecasts/
  hegre_isq2013_forecast_gy.csv  GW state x year 2010-2050: the published ISQ 2013 forecast (model estimated on
                           data through 2009): P(minor), P(major), P(any conflict) = share of simulations
                           (sh_cnt_t1, sh_cnt_t2, sh_cnt_c), and the 10th/50th/90th percentile of P(any) across
                           model draws; horizon = year - 2009. 2010-2019 overlaps our sample.
  hegre_history_gy.csv     GW state x year 1960-2013: the model's outcome and inputs as observed —
                           conflict (0 none, 1 minor 25-999 BD, 2 major 1000+ BD), years in current status,
                           neighbour in conflict, log population, log GDP pc, education (YMHEP), region,
                           log time since independence. The basis for re-estimating the Hegre model ourselves
                           (one-year-ahead forecasts for 1991-2019; design choice, see data/README section H).
  hegre_ssp1_sim_gy.csv    GW state x year 2014-2023: predicted P(no / minor / major conflict) from the one
                           simulation file shipped with the package (SSP1, single coefficient and random-effect
                           draw). 2014 = genuine one-year-ahead forecast from 2013 data (same in every run);
                           2015+ = average over the simulated paths (conditional on simulated, not observed,
                           conflict history) — use with care.

Decisions (data/README section H):
  H1 Before 2014 the covariates differ slightly across the SSP columns (data revisions in the 2016 SSP inputs);
     SSP2 ("middle of the road") values are used.
  H2 Population and GDP enter in logs as in the model (lpop, lGDPcap), education as YMHEP (share of men 20-24
     with upper-secondary education), as in the parameter file.
  H3 Simulation file: rows of the last, cut-off run (simno 19) and rows with missing cutoffs are dropped.
"""

import io
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "hegre_ssp" / "replicationssp_hh.zip"
OUT = ROOT / "data" / "clean" / "forecasts"
EST = "ReplicationSSP/SSPForecasts/Sim/Program/estimationdata.dta"
SIM = "ReplicationSSP/PredictionTemp/SSP_sim/Res_sim_1_1_1_1.txt"
RAW_ISQ = ROOT / "data" / "raw" / "hegre_isq" / "replicationdataisq2013.zip"
ISQ = "ReplicationDataISQ2013/CountryYearResults.dta"


def isq_forecast(zf):
    d = pd.read_stata(io.BytesIO(zf.read(ISQ)), convert_categoricals=False)
    out = pd.DataFrame({
        "gwcode": d["gwno"].astype(int), "year": d["year"].astype(int),
        "hegre13_p_minor": d["sh_cnt_t1"], "hegre13_p_major": d["sh_cnt_t2"], "hegre13_p_conflict": d["sh_cnt_c"],
        "hegre13_p_conflict_p10": d["p10_c_c"], "hegre13_p_conflict_p50": d["p50_c_c"],
        "hegre13_p_conflict_p90": d["p90_c_c"],
    })
    out["hegre13_horizon"] = out["year"] - 2009
    # H6: the ISQ file keeps Serbia under 345 (Yugoslavia) after 2006; our panel uses 340 from 2006 (B10)
    out.loc[(out["gwcode"] == 345) & (out["year"] >= 2006), "gwcode"] = 340
    assert not out.duplicated(["gwcode", "year"]).any()
    assert (out["hegre13_p_minor"] + out["hegre13_p_major"] - out["hegre13_p_conflict"]).abs().max() < 1e-6
    return out.sort_values(["gwcode", "year"])


def history(zf):
    d = pd.read_stata(io.BytesIO(zf.read(EST)), convert_categoricals=False)
    d = d[d["year"] <= 2013].copy()
    out = pd.DataFrame({
        "gwcode": d["gwno"].astype(int), "year": d["year"].astype(int),
        "hegre_country": d["countryname"],
        "hegre_conflict": d["conflict"].astype(int),
        "hegre_minor": (d["conflict"] == 1).astype(int), "hegre_major": (d["conflict"] == 2).astype(int),
        "hegre_timeinstatus": d["timeinstatus"], "hegre_nb_conflict": d["nc"],
        "hegre_lpop": np.log(d["PopSSP2"]), "hegre_lgdppc": np.log(d["GDPcapSSP2"]), "hegre_ymhep": d["YMHEPSSP2"],
        "hegre_region": d["region"], "hegre_ltimeindep": d["ltimeindep"],
    })
    assert not out.duplicated(["gwcode", "year"]).any(), "duplicate state-years"
    assert out["hegre_conflict"].isin([0, 1, 2]).all()
    return out.sort_values(["gwcode", "year"])


def simulation(zf):
    raw = zf.read(SIM).decode()
    d = pd.read_csv(io.StringIO(raw), usecols=["simno", "gwno", "year", "cutoff0", "cutoff1"], on_bad_lines="skip")
    n_raw = len(d)
    d = d[(d["simno"] < d["simno"].max()) & d["cutoff0"].notna() & d["year"].between(2014, 2023)]
    d = d.assign(p_none=d["cutoff0"], p_minor=d["cutoff1"] - d["cutoff0"], p_major=1 - d["cutoff1"])
    out = (d.groupby(["gwno", "year"])
             .agg(hegre_p_none=("p_none", "mean"), hegre_p_minor=("p_minor", "mean"),
                  hegre_p_major=("p_major", "mean"), hegre_n_sims=("simno", "nunique"))
             .reset_index().rename(columns={"gwno": "gwcode"}))
    out["hegre_p_conflict"] = 1 - out["hegre_p_none"]
    out["hegre_horizon"] = out["year"] - 2013
    print(f"  simulation rows read {n_raw:,}; kept runs 1-{d['simno'].max()}; {len(out):,} state-years 2014-2023")
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(RAW) as zf:
        hist = history(zf)
        sim = simulation(zf)
    with zipfile.ZipFile(RAW_ISQ) as zf:
        isq = isq_forecast(zf)
    isq.to_csv(OUT / "hegre_isq2013_forecast_gy.csv", index=False)
    print(f"hegre_isq2013_forecast_gy.csv: {len(isq):,} state-years, {isq.gwcode.nunique()} states, "
          f"{isq.year.min()}-{isq.year.max()}")
    hist.to_csv(OUT / "hegre_history_gy.csv", index=False)
    sim.to_csv(OUT / "hegre_ssp1_sim_gy.csv", index=False)
    print(f"hegre_history_gy.csv : {len(hist):,} state-years, {hist.gwcode.nunique()} states, "
          f"{hist.year.min()}-{hist.year.max()}; conflict shares "
          + ", ".join(f"{k}={v:.3f}" for k, v in hist.hegre_conflict.value_counts(normalize=True).sort_index().items()))
    print(f"hegre_ssp1_sim_gy.csv: {len(sim):,} state-years, {sim.gwcode.nunique()} states")
    return 0


if __name__ == "__main__":
    sys.exit(main())
