"""
clean_imf_trade.py — IMF bilateral goods trade (IMTS) to Gleditsch-Ward origin x destination x year.
ADDED 2026-11-09 (data/README.md, section 4c, T2 and I1-I6).

Input : data/raw/imf_imts/imts_<REPORTER>.csv   (acquire_imf_trade.py; reporter x indicator x partner x year)
        data/clean/base/base.csv                 (GW state-years; iso3c per state-year)
Output: data/clean/imf/imts_dyadic.csv.gz        one row per directed flow origin -> destination and year:
            exports_reported_by_origin       XG_FOB_USD reported by the origin with the destination as partner (FOB)
            imports_reported_by_destination  MG_CIF_USD reported by the destination with the origin as partner (CIF)
            flow_avg                         BASE (user decision 9 Nov): mean of the two where both exist,
                                             otherwise the one available (I3)
            sides                            number of reporting sides (1 or 2)
        data/clean/imf/imts_world_totals.csv     reporter x year: own reported exports to / imports from the world (G001)
        data/clean/imf/imts_unmatched.csv        IMF codes without a GW state (territories, aggregates), for the record

Units (I1): OBS_VALUE is in US dollars (current), although the series carry SCALE = 6 (checked: US imports from
China 2019 = 449,110,676,707). Goods only, no services.
Codes (I2): IMF ISO3 -> base iso3c, with SUN -> RUS (Soviet Union, base RUS covers 1946-), SCG -> YUG (Serbia and
Montenegro 1993-2004 = base YUG to 2005), KOS -> KSV, VNM -> VDR. YUG (SFRY 1980-92) -> YUG. Then GW via base
(iso3c, year); codes or years outside the base (territories, groups G***/T***, 2024-25) are dropped from the dyadic
file and listed in imts_unmatched.csv.
No CIF/FOB adjustment in flow_avg (I4): imports are valued CIF (incl. freight and insurance, typically 5-10 % above
FOB); BACI (Gaulier & Zignago 2010) adjusts and weights sides by reliability — possible later variant.
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "imf_imts"
OUT = ROOT / "data" / "clean" / "imf"
OUT.mkdir(parents=True, exist_ok=True)

IMF_TO_BASE_ISO3 = {"SUN": "RUS", "SCG": "YUG", "KOS": "KSV", "VNM": "VDR"}

# --- 1. Read -----------------------------------------------------------------------------------
files = [f for f in sorted(RAW.glob("imts_*.csv")) if f.name != "imts_country_codes.csv"]
raw = pd.concat([pd.read_csv(f, dtype={"reporter": str, "partner": str}) for f in files], ignore_index=True)
raw = raw[raw["indicator"].isin(["XG_FOB_USD", "MG_CIF_USD"]) & raw["value"].notna()]
raw["year"] = raw["year"].astype(int)
print("raw observations (exports + imports):", len(raw), "| reporters:", raw.reporter.nunique())
assert not raw.duplicated(["reporter", "indicator", "partner", "year"]).any()

# world totals as reported (before any code mapping)
world = (raw[raw.partner == "G001"].pivot_table(index=["reporter", "year"], columns="indicator", values="value")
         .rename(columns={"XG_FOB_USD": "exports_to_world", "MG_CIF_USD": "imports_from_world"}).reset_index())

# --- 2. IMF codes -> GW --------------------------------------------------------------------------
base = pd.read_csv(ROOT / "data" / "clean" / "base" / "base.csv", usecols=["gwcode", "year", "iso3c"])
base["year"] = base["year"].astype(str).str[:4].astype(int)
base = base.dropna(subset=["iso3c"])
gw_of = {(iso, year): gw for gw, year, iso in base.itertuples(index=False)}

for side in ["reporter", "partner"]:
    iso = raw[side].replace(IMF_TO_BASE_ISO3)
    raw[f"{side}_gwcode"] = [gw_of.get((code, year)) for code, year in zip(iso, raw["year"])]
world["gwcode"] = [gw_of.get((IMF_TO_BASE_ISO3.get(c, c), y)) for c, y in zip(world.reporter, world.year)]

unmatched = raw[raw.reporter_gwcode.isna() | raw.partner_gwcode.isna()]
(pd.concat([unmatched[unmatched.reporter_gwcode.isna()].assign(role="reporter", code=lambda d: d.reporter),
            unmatched[unmatched.partner_gwcode.isna()].assign(role="partner", code=lambda d: d.partner)])
   .groupby(["role", "code"]).agg(rows=("value", "size"), usd=("value", "sum"), first_year=("year", "min"),
                                  last_year=("year", "max"))
   .reset_index().sort_values(["role", "usd"], ascending=[True, False])
   .to_csv(OUT / "imts_unmatched.csv", index=False))
matched = raw.dropna(subset=["reporter_gwcode", "partner_gwcode"]).copy()
matched = matched[matched.reporter_gwcode != matched.partner_gwcode]        # e.g. SCG and SRB/MNE overlaps
print("observations with GW codes on both sides:", len(matched), f"({len(matched) / len(raw):.1%})")
for side in ["reporter_gwcode", "partner_gwcode"]:
    matched[side] = matched[side].astype(int)
# Two IMF codes can map to the same GW state-year (I5): after 1992 many partners still report "YUG" next to "SCG"
# for Serbia and Montenegro (base YUG 1993-2005). Keep SCG where both exist (it is the IMF code for that state);
# "YUG" after 1992 is used only where no SCG figure exists. Same rule for SUN vs RUS (prefer RUS).
CODE_PRIORITY = {"SCG": 0, "RUS": 0, "YUG": 1, "SUN": 1}
matched["priority"] = (matched.reporter.map(CODE_PRIORITY).fillna(0) + matched.partner.map(CODE_PRIORITY).fillna(0))
key = ["reporter_gwcode", "indicator", "partner_gwcode", "year"]
dupes = matched.duplicated(key, keep=False)
print("observations where two IMF codes map to one GW state-year:", int(dupes.sum()),
      "| codes involved:", sorted((set(matched.loc[dupes, "reporter"]) | set(matched.loc[dupes, "partner"])) &
                                   {"YUG", "SCG", "SUN", "RUS", "SRB", "MNE"}))
matched = matched.sort_values("priority").drop_duplicates(key, keep="first").drop(columns="priority")

# --- 3. Directed flows origin -> destination, both reporting sides ------------------------------------
exports = (matched[matched.indicator == "XG_FOB_USD"]
           .rename(columns={"reporter_gwcode": "origin_gwcode", "partner_gwcode": "destination_gwcode",
                            "value": "exports_reported_by_origin"})
           [["origin_gwcode", "destination_gwcode", "year", "exports_reported_by_origin"]])
imports = (matched[matched.indicator == "MG_CIF_USD"]
           .rename(columns={"partner_gwcode": "origin_gwcode", "reporter_gwcode": "destination_gwcode",
                            "value": "imports_reported_by_destination"})
           [["origin_gwcode", "destination_gwcode", "year", "imports_reported_by_destination"]])
flows = exports.merge(imports, on=["origin_gwcode", "destination_gwcode", "year"], how="outer")
flows["sides"] = flows[["exports_reported_by_origin", "imports_reported_by_destination"]].notna().sum(axis=1)
flows["flow_avg"] = flows[["exports_reported_by_origin", "imports_reported_by_destination"]].mean(axis=1)
flows = flows.sort_values(["origin_gwcode", "destination_gwcode", "year"])
flows.to_csv(OUT / "imts_dyadic.csv.gz", index=False)
world.to_csv(OUT / "imts_world_totals.csv", index=False)

both = flows[flows.sides == 2]
ratio = (both.imports_reported_by_destination / both.exports_reported_by_origin).replace([float("inf")], pd.NA).dropna()
print(f"directed flows: {len(flows)} ({flows.year.min()}-{flows.year.max()}); reported by both sides: "
      f"{(flows.sides == 2).mean():.1%}; median CIF/FOB ratio where both: {ratio.median():.3f}")
print("value share reported by only one side:",
      f"{flows.loc[flows.sides == 1, 'flow_avg'].sum() / flows.flow_avg.sum():.1%}")
