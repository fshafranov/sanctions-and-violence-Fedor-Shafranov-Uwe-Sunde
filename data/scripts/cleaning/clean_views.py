"""
clean_views.py — country-year conflict forecasts from the archived VIEWS country-month runs.

    uv run python data/scripts/cleaning/clean_views.py

Input : data/raw/views/views_cm_<run>.csv (acquire_views.py)
Output: data/clean/forecasts/
  views_forecasts_cy_vintages.csv  every forecast run x GW state x target year (only target years the run covers
                                   in full, 12 months): vintage = first forecast month, horizon, the yearly
                                   aggregates below
  views_forecast_cy_yearahead.csv  ONE forecast per GW state x target year Y: the run whose window starts closest
                                   to (but not after) January of Y and covers all of Y = "what VIEWS expected for Y
                                   at the turn of the year" -> comparable to an annual propensity using t-1 data
  views_actuals_cy.csv             UCDP GED state-based fatalities per GW state-year from the predictors run
                                   (VIEWS's own actuals; to compare forecast and outcome)

Yearly aggregates of the 12 monthly forecasts (decision V2, data/README section V):
  views_p_month_mean   mean of the monthly P(>= 25 BRD)  = expected share of months with >= 25 BRD
  views_p_any_indep    1 - prod(1 - p_m): P(at least one such month) if months were independent (upper bound-ish)
  views_p_month_max    max of the monthly probabilities
  views_fat_sum        sum of predicted fatalities (main_mean; for fatalities001 exp(ln)-1 of sc_cm_sb_main)
  views_fat_ln         ln(1 + views_fat_sum)
Decisions:
  V1 Probability column by model family: fatalities002/003 main_dich; fatalities001 sc_cm_sb_dich_main;
     r_2021 sc_cm_sb_main (0-1, Africa + Middle East only). r_2021 runs have no fatality forecast.
  V3 Year-ahead choice: among runs covering all 12 months of Y, the latest first forecast month <= January of Y;
     ties -> newer model family. Horizon (months from last input month to the end of Y) is kept.
"""

import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "views"
OUT = ROOT / "data" / "clean" / "forecasts"
FAMILY_RANK = {"r": 0, "fatalities001": 1, "fatalities002": 2, "fatalities003": 3}


def month_id_to_ym(m):
    m = np.asarray(m) - 1
    return 1980 + m // 12, m % 12 + 1


def read_run(path):
    run = path.stem.removeprefix("views_cm_")
    family = "r" if run.startswith("r_2021") else run.split("_")[0]
    d = pd.read_csv(path)
    if family in ("fatalities002", "fatalities003"):
        p, fat = d["main_dich"], d["main_mean"]
    elif family == "fatalities001":
        p, fat = d["sc_cm_sb_dich_main"], np.expm1(d["sc_cm_sb_main"])
    else:
        p, fat = d["sc_cm_sb_main"], np.nan  # r_2021: probability (0-1), Africa + Middle East only
    out = pd.DataFrame({"run": run, "family": family, "gwcode": d["gwcode"], "month_id": d["month_id"],
                        "p": p, "fat": fat})
    out["year"], out["month"] = month_id_to_ym(out["month_id"])
    out["vintage_month_id"] = out["month_id"].min()
    return out


def yearly(m):
    g = m.groupby(["run", "family", "vintage_month_id", "gwcode", "year"])
    y = g.agg(n_months=("month", "nunique"), views_p_month_mean=("p", "mean"), views_p_month_max=("p", "max"),
              views_fat_sum=("fat", lambda s: s.sum(min_count=1)),
              views_p_any_indep=("p", lambda s: 1 - np.prod(1 - s.clip(0, 1)))).reset_index()
    y = y[y["n_months"] == 12].drop(columns="n_months")
    y["views_fat_ln"] = np.log1p(y["views_fat_sum"])
    vy, vm = month_id_to_ym(y["vintage_month_id"])
    y["vintage"] = [f"{a}-{b:02d}" for a, b in zip(vy, vm)]
    # horizon: months from the last input month (vintage - 1) to December of the target year
    y["horizon_months"] = (y["year"] - 1980) * 12 + 12 - (y["vintage_month_id"] - 1)
    return y


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    files = sorted(p for p in RAW.glob("views_cm_*.csv") if "predictors" not in p.name)
    months = pd.concat([read_run(p) for p in files], ignore_index=True)
    assert months["p"].between(0, 1).all(), "probability outside [0, 1]"
    vint = yearly(months)
    vint.to_csv(OUT / "views_forecasts_cy_vintages.csv", index=False)

    vint["jan_id"] = (vint["year"] - 1980) * 12 + 1
    cand = vint[vint["vintage_month_id"] <= vint["jan_id"]].copy()
    cand["rank"] = cand["family"].map(FAMILY_RANK)
    ahead = (cand.sort_values(["gwcode", "year", "vintage_month_id", "rank"])
                 .groupby(["gwcode", "year"]).tail(1).drop(columns=["jan_id", "rank"]))
    ahead.to_csv(OUT / "views_forecast_cy_yearahead.csv", index=False)

    pred = sorted(RAW.glob("views_cm_predictors_fatalities003_*.csv"))
    if pred:
        a = pd.read_csv(pred[-1])
        act = (a.groupby(["gwcode", "year"])
                 .agg(ged_sb_deaths=("ucdp_ged_sb_best_sum", "sum"), n_months=("month", "nunique"),
                      months_sb25=("ucdp_ged_sb_best_sum", lambda s: int((s >= 25).sum())))
                 .reset_index())
        act.to_csv(OUT / "views_actuals_cy.csv", index=False)
        print(f"views_actuals_cy.csv            {len(act):,} state-years {act.year.min()}-{act.year.max()}")

    print(f"runs read: {len(files)}; vintages file {len(vint):,} rows")
    print("year-ahead forecast per target year (run used, states):")
    print(ahead.groupby("year").agg(run=("run", "first"), vintage=("vintage", "first"),
                                    states=("gwcode", "nunique")).to_string())
    return 0


if __name__ == "__main__":
    sys.exit(main())
