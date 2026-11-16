"""Build the aggregated CSVs behind the conflict-dynamics dashboard.

Inputs (all already in the repo):
  data/clean/ucdp_ov/ucdp_ov_cy.csv                  UCDP organized violence, country-year, 1989-2025
  data/raw/ucdp_prio/UcdpPrioConflict_v26_1.csv      UCDP/PRIO armed conflict, conflict-year, 1946-2025
  data/clean/gsdb/gsdb_new_cases.csv                 GSDB V4 new sanction cases (target iso3, start year)
  data/processed/sanctions_violence/sanctions_violence_panel.csv  only for the iso3c -> gwcode map

Outputs in dashboard/data/:
  year_violence.csv     year: deaths by violence type, countries in conflict, new US sanction cases
  conflicts_year.csv    year: active state-based conflicts, wars, conflicts with the US as a party
  us_conflicts.csv      one row per UCDP conflict with the US as a primary or secondary party
  country_period.csv    country x period: deaths, US sanction cases, US conflict years
  country_year.csv      top-40 countries by deaths x year: deaths, US cases, US sanction in force, US party
  us_cases.csv          US sanction cases 1989-2023 (w/o ICC case 685) with target deaths before/after

US involvement in UCDP/PRIO = gwcode 2 in gwno_a / gwno_b (primary) or gwno_a_2nd / gwno_b_2nd (secondary).
US sanction cases follow script 13 (us == 1, case != 685). Deaths = UCDP best estimate, all organized violence.
Run: uv run python dashboard/build_dashboard_data.py
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "dashboard" / "data"
OUT.mkdir(parents=True, exist_ok=True)

US = "2"
ICC_CASE = 685
CONFLICT_MIN_DEATHS = 25
TOP_N = 40


def period(y: int) -> str:
    if y <= 1999:
        return "1989-99"
    if y <= 2009:
        return "2000-09"
    if y <= 2019:
        return "2010-19"
    return "2020-25"


def gw_list(s: pd.Series) -> pd.Series:
    return s.fillna("").astype(str).str.split(",").apply(lambda l: [x.strip() for x in l if x.strip()])


# --- 1. UCDP organized violence, country-year ---------------------------------------------
ov = pd.read_csv(ROOT / "data/clean/ucdp_ov/ucdp_ov_cy.csv")
ov["year"] = ov["year"].str[:4].astype(int)
ov = ov.rename(columns={"country_id": "gwcode"})
ov["deaths"] = ov["cumulative_total_deaths_in_orgvio_best"].fillna(0)
for c in ["sb_total_deaths_best", "ns_total_deaths_best", "os_total_deaths_best"]:
    ov[c] = ov[c].fillna(0)
assert not ov.duplicated(["gwcode", "year"]).any()
assert (ov["deaths"] - ov[["sb_total_deaths_best", "ns_total_deaths_best", "os_total_deaths_best"]].sum(axis=1)).abs().max() < 1

# --- 2. GSDB US cases -> gwcode --------------------------------------------------------------
panel = pd.read_csv(ROOT / "data/processed/sanctions_violence/sanctions_violence_panel.csv",
                    usecols=["gwcode", "iso3c", "year", "us_sanction"], low_memory=False)
panel["year"] = panel["year"].str[:4].astype(int)
iso_map = panel.dropna(subset=["iso3c"]).drop_duplicates(["iso3c", "year"])[["iso3c", "year", "gwcode"]]

cases = pd.read_csv(ROOT / "data/clean/gsdb/gsdb_new_cases.csv")
us_cases = cases[(cases["us"] == 1) & (cases["case"] != ICC_CASE)].copy()
us_cases = us_cases.merge(iso_map, left_on=["country_iso3", "year"], right_on=["iso3c", "year"], how="left")
unmatched = us_cases["gwcode"].isna().sum()
print(f"US cases: {len(us_cases)}; without gwcode match: {unmatched}")
us_cases = us_cases.dropna(subset=["gwcode"])
us_cases["gwcode"] = us_cases["gwcode"].astype(int)

us_new_cy = us_cases.groupby(["gwcode", "year"]).size().rename("us_new_cases").reset_index()
us_force = panel[["gwcode", "year", "us_sanction"]].fillna({"us_sanction": 0})

# --- 3. UCDP/PRIO conflicts ------------------------------------------------------------------
prio = pd.read_csv(ROOT / "data/raw/ucdp_prio/UcdpPrioConflict_v26_1.csv")
prim = gw_list(prio["gwno_a"]) + gw_list(prio["gwno_b"])
sec = gw_list(prio["gwno_a_2nd"]) + gw_list(prio["gwno_b_2nd"])
prio["us_primary"] = prim.apply(lambda l: US in l)
prio["us_secondary"] = sec.apply(lambda l: US in l) & ~prio["us_primary"]
prio["us_any"] = prio["us_primary"] | prio["us_secondary"]
prio["war"] = prio["intensity_level"] == 2
TYPE = {1: "Extrasystemic", 2: "Interstate", 3: "Intrastate", 4: "Internationalized intrastate"}
prio["type"] = prio["type_of_conflict"].map(TYPE)

conf_year = prio.groupby("year").agg(
    conflicts=("conflict_id", "nunique"),
    wars=("war", "sum"),
    internationalized=("type_of_conflict", lambda s: (s == 4).sum()),
    us_conflicts=("us_any", "sum"),
    us_primary=("us_primary", "sum"),
    us_secondary=("us_secondary", "sum"),
    us_wars=("us_any", lambda s: (s & prio.loc[s.index, "war"]).sum()),
).reset_index()
conf_year.to_csv(OUT / "conflicts_year.csv", index=False)

us_conf = prio[prio["us_any"]].groupby("conflict_id").agg(
    location=("location", "first"),
    opponent=("side_b", lambda s: s.iloc[-1]),
    first_year=("year", "min"),
    last_year=("year", "max"),
    us_years=("year", "size"),
    war_years=("war", "sum"),
    role=("us_primary", lambda s: "Primary" if s.any() else "Secondary"),
    type=("type", lambda s: s.iloc[-1]),
).reset_index().sort_values("first_year")
us_conf["era"] = us_conf["first_year"].apply(lambda y: "Cold War" if y < 1989 else period(y))
us_conf.to_csv(OUT / "us_conflicts.csv", index=False)

# US as a party in a conflict located in country g in year t
loc = prio[prio["us_any"]][["year", "gwno_loc"]].copy()
loc["gwcode"] = gw_list(loc["gwno_loc"])
loc = loc.explode("gwcode").dropna()
loc = loc[loc["gwcode"] != US]
loc["gwcode"] = loc["gwcode"].astype(int)
us_party_cy = loc.drop_duplicates(["gwcode", "year"])[["gwcode", "year"]].assign(us_party=1)

# --- 4. Country-year frame -------------------------------------------------------------------
cy = (ov[["gwcode", "country", "region", "year", "deaths", "sb_total_deaths_best",
          "ns_total_deaths_best", "os_total_deaths_best"]]
      .merge(us_new_cy, on=["gwcode", "year"], how="left")
      .merge(us_force, on=["gwcode", "year"], how="left")
      .merge(us_party_cy, on=["gwcode", "year"], how="left"))
cy[["us_new_cases", "us_party"]] = cy[["us_new_cases", "us_party"]].fillna(0).astype(int)
cy.loc[cy["year"] > 2023, "us_sanction"] = pd.NA      # GSDB V4 ends 2023
cy["in_conflict"] = (cy["deaths"] >= CONFLICT_MIN_DEATHS).astype(int)
cy["period"] = cy["year"].apply(period)

year_viol = cy.groupby("year").agg(
    state_based=("sb_total_deaths_best", "sum"),
    non_state=("ns_total_deaths_best", "sum"),
    one_sided=("os_total_deaths_best", "sum"),
    total=("deaths", "sum"),
    countries_in_conflict=("in_conflict", "sum"),
    us_new_cases=("us_new_cases", "sum"),
    us_targets_in_conflict=("us_new_cases", lambda s: ((s > 0) & (cy.loc[s.index, "in_conflict"] == 1)).sum()),
).reset_index()
year_viol.loc[year_viol["year"] > 2023, ["us_new_cases", "us_targets_in_conflict"]] = pd.NA
year_viol.round(0).to_csv(OUT / "year_violence.csv", index=False)

cp = cy.groupby(["gwcode", "country", "region", "period"]).agg(
    deaths=("deaths", "sum"),
    state_based=("sb_total_deaths_best", "sum"),
    conflict_years=("in_conflict", "sum"),
    peak_year=("deaths", lambda s: int(cy.loc[s.idxmax(), "year"]) if s.max() > 0 else None),
    us_new_cases=("us_new_cases", "sum"),
    us_party_years=("us_party", "sum"),
).reset_index()
cp = cp[cp["deaths"] > 0]
cp["rank"] = cp.groupby("period")["deaths"].rank(ascending=False, method="first").astype(int)
cp.sort_values(["period", "rank"]).round(0).to_csv(OUT / "country_period.csv", index=False)

all_cy = cy[(cy["deaths"] > 0) | (cy["us_sanction"] == 1) | (cy["us_new_cases"] > 0)][["gwcode", "country", "region", "year", "deaths", "sb_total_deaths_best",
                                "ns_total_deaths_best", "os_total_deaths_best", "us_new_cases",
                                "us_sanction", "us_party"]].rename(columns={
    "sb_total_deaths_best": "state_based", "ns_total_deaths_best": "non_state", "os_total_deaths_best": "one_sided"})
all_cy[["deaths", "state_based", "non_state", "one_sided"]] = all_cy[["deaths", "state_based", "non_state", "one_sided"]].round(0).astype(int)
all_cy["us_sanction"] = all_cy["us_sanction"].astype("Int64")
all_cy.to_csv(OUT / "country_year_all.csv", index=False)

top = cy.groupby("country")["deaths"].sum().nlargest(TOP_N).index
cyt = cy[cy["country"].isin(top)][["country", "region", "year", "deaths", "us_new_cases",
                                     "us_sanction", "us_party"]].copy()
cyt["deaths"] = cyt["deaths"].round(0).astype(int)
cyt.to_csv(OUT / "country_year.csv", index=False)

# --- 5. US cases with target deaths around the start year ------------------------------------
d = cy.set_index(["gwcode", "year"])["deaths"]
def deaths_at(g, y):
    return d.get((g, y), pd.NA)
uc = us_cases[(us_cases["year"] >= 1989) & (us_cases["year"] <= 2023)].copy()
uc = uc.merge(ov[["gwcode", "country", "region"]].drop_duplicates("gwcode"), on="gwcode", how="left")
uc["deaths_before"] = [deaths_at(g, y - 1) for g, y in zip(uc["gwcode"], uc["year"])]
uc["deaths_start"] = [deaths_at(g, y) for g, y in zip(uc["gwcode"], uc["year"])]
uc["deaths_after2"] = [deaths_at(g, y + 2) for g, y in zip(uc["gwcode"], uc["year"])]
uc["period"] = uc["year"].apply(period)
uc["conflict_obj"] = uc["conflict_obj"].astype(int)
uc = uc[["case", "country", "region", "year", "period", "objective", "conflict_obj", "success",
         "deaths_before", "deaths_start", "deaths_after2"]].sort_values(["year", "country"])
uc.to_csv(OUT / "us_cases.csv", index=False)

for f in sorted(OUT.glob("*.csv")):
    print(f.name, len(pd.read_csv(f)), "rows")
