"""
clean_wdi.py — World Bank WDI trade, FDI, arms (SIPRI totals) and GDP (current US$) to GW state-years.
ADDED 2026-11-09 (data/README.md, section 4c, T1 and W1-W3).

Input : data/raw/wdi/wdi_<name>.csv      (acquire_wdi.py; long: iso3c, wb_id, country, year, value)
        data/clean/base/base.csv          (GW state-years; iso3c per state-year)
Output: data/clean/wdi/wdi_cy.csv         GW state x year: trade_pct_gdp, exports_pct_gdp, imports_pct_gdp,
                                          fdi_inflows_pct_gdp, fdi_outflows_pct_gdp, arms_imports_tiv, arms_exports_tiv
                                          (millions of TIV, = WDI value / 1e6), gdp_current_usd
        data/clean/wdi/wdi_unmatched.csv  WDI economies without a GW state (aggregates, territories), for the record

Codes (W1): WDI ISO3 -> base iso3c with XKX -> KSV (Kosovo), VNM -> VDR (Vietnam); then GW via base (iso3c, year).
Aggregates (regions, income groups) and territories have no GW state and are dropped.
W2 (user 9 Nov, O3): the World Bank has no series for Yugoslavia/Serbia and Montenegro (base YUG, FRY 1992-2005);
its "Serbia" (SRB) values 1992-2005 are used for base YUG as an approximation, flagged `approx_serbia_for_yug = 1`
(Serbia is by far the larger part of FRY; % of GDP measures are close, levels such as GDP slightly understate FRY).
Missing values (W3): kept missing here. Arms imports: SIPRI/WDI leave years without major-arms deliveries empty;
the user decision (0 with a flag "no SIPRI record") is applied in processing, where the bilateral SIPRI data are
also used.
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "wdi"
OUT = ROOT / "data" / "clean" / "wdi"
OUT.mkdir(parents=True, exist_ok=True)

WDI_TO_BASE_ISO3 = {"XKX": "KSV", "VNM": "VDR"}
VARIABLES = ["trade_pct_gdp", "exports_pct_gdp", "imports_pct_gdp", "fdi_inflows_pct_gdp", "fdi_outflows_pct_gdp",
             "arms_imports_tiv", "arms_exports_tiv", "gdp_current_usd"]

frames = []
for name in VARIABLES:
    data = pd.read_csv(RAW / f"wdi_{name}.csv", keep_default_na=False, na_values=[""])
    data = data[data["iso3c"].notna()].assign(variable=name)
    frames.append(data[["iso3c", "country", "year", "variable", "value"]])
wdi = pd.concat(frames).pivot_table(index=["iso3c", "country", "year"], columns="variable", values="value").reset_index()
for column in ["arms_imports_tiv", "arms_exports_tiv"]:
    wdi[column] = wdi[column] / 1e6                     # WDI stores TIV in units; SIPRI reports millions
wdi["base_iso3c"] = wdi["iso3c"].replace(WDI_TO_BASE_ISO3)
serbia_for_yug = wdi["iso3c"].eq("SRB") & wdi["year"].between(1992, 2005)
wdi.loc[serbia_for_yug, "base_iso3c"] = "YUG"
wdi["approx_serbia_for_yug"] = serbia_for_yug.astype(int)

base = pd.read_csv(ROOT / "data" / "clean" / "base" / "base.csv", usecols=["gwcode", "year", "iso3c"])
base["year"] = base["year"].astype(str).str[:4].astype(int)
base = base.dropna(subset=["iso3c"]).rename(columns={"iso3c": "base_iso3c"})
merged = wdi.merge(base, on=["base_iso3c", "year"], how="left")

unmatched = merged[merged.gwcode.isna()]
(unmatched.groupby(["iso3c", "country"]).agg(years=("year", "size"), first_year=("year", "min"),
                                             last_year=("year", "max")).reset_index()
          .to_csv(OUT / "wdi_unmatched.csv", index=False))
out = merged.dropna(subset=["gwcode"]).astype({"gwcode": int})
assert not out.duplicated(["gwcode", "year"]).any()
out = out[["gwcode", "year", "iso3c"] + VARIABLES + ["approx_serbia_for_yug"]].sort_values(["gwcode", "year"])
out.to_csv(OUT / "wdi_cy.csv", index=False)
print(f"WDI: {len(out)} GW state-years ({out.year.min()}-{out.year.max()}), {out.gwcode.nunique()} states; "
      f"unmatched WDI economies: {unmatched.iso3c.nunique()}")
print("non-missing state-years 1989-2023:",
      out[out.year.between(1989, 2023)][VARIABLES].notna().sum().to_dict())
