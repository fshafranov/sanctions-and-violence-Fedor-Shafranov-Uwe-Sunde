"""
clean_acled.py — ACLED political-violence events to Gleditsch-Ward country-years (and country-months).
ADDED 2026-11-09 (data/README.md, section "ACLED", A1-A8).

Input : data/raw/acled/acled_political_violence_<year>.csv   (acquire_acled.py; one row per event, dyadic)
        data/clean/base/base.csv                              (GW state-years)
Output: data/clean/acled/acled_cy.csv          GW state x year: events and fatalities by violence type
        data/clean/acled/acled_cm.csv          GW state x month: the same (for within-year timing later)
        data/clean/acled/acled_coverage.csv    per GW state: ACLED region, coverage start year, first event year
        data/clean/acled/acled_dropped.csv     events not assigned to a GW state (territories, seas), by country

Zero-filling (no events = 0 deaths) happens in process_sanctions_violence.py, and ONLY inside each state's
coverage window (coverage start .. LAST_YEAR); outside it the ACLED variables are missing.

Violence types (UCDP organized-violence analogue, A4). Codes inter1/inter2 (numeric, inter_num=1):
1 state forces, 2 rebel group, 3 political militia, 4 identity militia, 5 rioters, 6 protesters, 7 civilians,
8 external/other forces, 0 no second actor.
  one_sided   : civilian_targeting == "Civilian targeting", event types other than Riots
                (all "Violence against civilians" + explosions/remote violence against civilians)
  state_based : Battles / Explosions-Remote violence, not civilian-targeted, state forces (1) on either side
  non_state   : Battles / Explosions-Remote violence, not civilian-targeted, no state forces
  orgvio      : state_based + non_state + one_sided          (main ACLED violence measure; no death threshold)
  riots       : event type Riots (mob violence), kept separately, NOT part of orgvio
"""
from pathlib import Path

import pandas as pd
import pycountry

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "acled"
OUT = ROOT / "data" / "clean" / "acled"
OUT.mkdir(parents=True, exist_ok=True)

# ACLED shows only events at least 12 months old (account restriction, see the download manifest): the download of
# 9 Nov 2026 ends on 9 Nov 2025, so 2025 is incomplete. The GW base ends in 2023, so ACLED is used to 2023 (A2).
LAST_YEAR = 2023

# --- 1. Read -----------------------------------------------------------------------------------
files = sorted(RAW.glob("acled_political_violence_*.csv"))
events = pd.concat([pd.read_csv(f, low_memory=False) for f in files], ignore_index=True)
print("raw events:", len(events), "| files:", len(files), "| years", events["year"].min(), "-", events["year"].max())
assert not events["event_id_cnty"].duplicated().any(), "event ids must be unique (dyadic file = one row per event)"
events = events[events["year"] <= LAST_YEAR].copy()
print(f"events up to {LAST_YEAR}:", len(events))

# --- 2. Country -> GW state (A3) --------------------------------------------------------------------
# ACLED codes the country where the event happened (ISO 3166 numeric). ISO3 via pycountry, then the GW state
# with that ISO3 in the base in that year. Exceptions:
ISO3_EXCEPTIONS = {
    0:   "KSV",    # Kosovo: ACLED iso 0; base code KSV (GW 347, from 2008)
    704: "VDR",    # Vietnam: base code VDR (GW 816)
    275: "ISR",    # Palestine: no GW state; assigned to Israel (GW 666), as UCDP does for the West Bank and Gaza
}
def to_iso3(numeric):
    if numeric in ISO3_EXCEPTIONS:
        return ISO3_EXCEPTIONS[numeric]
    record = pycountry.countries.get(numeric=f"{int(numeric):03d}")
    return record.alpha_3 if record else None

events["iso3c"] = events["iso"].map(to_iso3)
base = pd.read_csv(ROOT / "data" / "clean" / "base" / "base.csv", usecols=["gwcode", "gw_name", "year", "iso3c"])
base["year"] = base["year"].astype(str).str[:4].astype(int)
# rows without ISO3 on either side must not match each other (pandas joins NaN keys): seas vs Abkhazia/S. Ossetia
events = events.merge(base.dropna(subset=["iso3c"]), on=["iso3c", "year"], how="left")
events.loc[events["iso3c"].isna(), "gwcode"] = None

dropped = events[events["gwcode"].isna()]
(dropped.groupby(["country", "region"]).agg(events=("event_id_cnty", "size"), fatalities=("fatalities", "sum"),
                                            first_year=("year", "min"), last_year=("year", "max"))
        .reset_index().sort_values("events", ascending=False)
        .to_csv(OUT / "acled_dropped.csv", index=False))
print("events without a GW state (territories, international waters; dropped):", len(dropped),
      "| fatalities:", int(dropped["fatalities"].sum()))
print(dropped.groupby("country").size().sort_values(ascending=False).to_string())
events = events[events["gwcode"].notna()].copy()
events["gwcode"] = events["gwcode"].astype(int)

# --- 3. Violence types (A4) --------------------------------------------------------------------------
civilian = events["civilian_targeting"].eq("Civilian targeting")
armed = events["event_type"].isin(["Battles", "Explosions/Remote violence"])
state = events["inter1"].eq(1) | events["inter2"].eq(1)
events["type"] = None
events.loc[events["event_type"].eq("Riots"), "type"] = "riots"
events.loc[civilian & ~events["event_type"].eq("Riots"), "type"] = "one_sided"
events.loc[armed & ~civilian & state, "type"] = "state_based"
events.loc[armed & ~civilian & ~state, "type"] = "non_state"
assert events["type"].notna().all(), events.loc[events["type"].isna(), "event_type"].value_counts()
print("\nevents and fatalities by type:")
print(events.groupby("type").agg(events=("event_id_cnty", "size"), fatalities=("fatalities", "sum")).to_string())

def aggregate(data, keys):
    wide = (data.groupby(keys + ["type"])
                .agg(events=("event_id_cnty", "size"), deaths=("fatalities", "sum"))
                .unstack("type", fill_value=0))
    wide.columns = [f"acled_{measure}_{kind}" for measure, kind in wide.columns]
    for measure in ["events", "deaths"]:
        for kind in ["state_based", "non_state", "one_sided", "riots"]:
            wide[f"acled_{measure}_{kind}"] = wide.get(f"acled_{measure}_{kind}", 0)
        wide[f"acled_{measure}_orgvio"] = (wide[f"acled_{measure}_state_based"] + wide[f"acled_{measure}_non_state"]
                                           + wide[f"acled_{measure}_one_sided"])
    columns = [f"acled_{m}_{k}" for m in ["deaths", "events"]
               for k in ["orgvio", "state_based", "non_state", "one_sided", "riots"]]
    return wide[columns].reset_index()

country_year = aggregate(events, ["gwcode", "year"])
events["month"] = pd.to_datetime(events["event_date"]).dt.month
country_month = aggregate(events, ["gwcode", "year", "month"])

# --- 4. Coverage start per GW state (A5) ----------------------------------------------------------------
# ACLED extended its coverage region by region. Before a state is covered, "no event" means "not observed",
# not zero. Start years: region defaults below, with country exceptions, set from (i) ACLED's coverage history
# (Africa 1997; South and Southeast Asia from 2010; Middle East 2015-17; Eastern Europe, the Balkans, Central Asia,
# the Caucasus, East Asia and Latin America 2018; rest of Europe, US 2020; Canada and Oceania 2021) and (ii) the
# first event year of each country in this download. TO VERIFY against ACLED's published coverage list.
REGION_START = {"Western Africa": 1997, "Middle Africa": 1997, "Eastern Africa": 1997, "Southern Africa": 1997,
                "Northern Africa": 1997, "South Asia": 2010, "Southeast Asia": 2010, "Middle East": 2016,
                "Caucasus and Central Asia": 2018, "Europe": 2020, "East Asia": 2018, "South America": 2018,
                "Central America": 2018, "Caribbean": 2018, "North America": 2018, "Oceania": 2021}
COUNTRY_START = {
    # Africa: island states first covered in 2020 (no events before in any of them)
    "Cape Verde": 2020, "Comoros": 2020, "Mauritius": 2020, "Seychelles": 2020, "Sao Tome and Principe": 2020,
    # South / Southeast Asia
    "India": 2016, "Bhutan": 2020, "Maldives": 2020, "Indonesia": 2015, "Philippines": 2016, "Malaysia": 2018,
    "East Timor": 2020, "Brunei": 2020, "Singapore": 2020,
    # Middle East
    "Yemen": 2015, "Saudi Arabia": 2015, "Syria": 2017,
    # Caucasus and Central Asia
    "Afghanistan": 2017,
    # Europe: Eastern Europe and the Balkans from 2018 (first events 2018), the rest of Europe from 2020
    **{c: 2018 for c in ["Albania", "Belarus", "Bosnia and Herzegovina", "Bulgaria", "Croatia", "Cyprus", "Greece",
                         "Kosovo", "Moldova", "Montenegro", "North Macedonia", "Romania", "Russia", "Serbia",
                         "Ukraine"]},
    # North America
    "United States": 2020, "Canada": 2021,
}
# GW states with no ACLED event at all get their ACLED region by hand
REGION_OF_UNOBSERVED = {"Qatar": "Middle East", "Brunei": "Southeast Asia", "Singapore": "Southeast Asia", "Grenada": "Caribbean",
                        "Seychelles": "Eastern Africa", "Liechtenstein": "Europe", "Luxembourg": "Europe",
                        "Monaco": "Europe", "San Marino": "Europe", "Kiribati": "Oceania", "Nauru": "Oceania",
                        "Tonga": "Oceania", "Tuvalu": "Oceania", "Palau": "Oceania", "Marshall Islands": "Oceania",
                        "Federated States of Micronesia": "Oceania"}

acled_names = events.groupby("gwcode").agg(acled_country=("country", lambda s: s.mode()[0]),
                                           acled_region=("region", lambda s: s.mode()[0]),
                                           first_event_year=("year", "min")).reset_index()
states = (base[base["year"].between(1997, LAST_YEAR)].groupby("gwcode")
              .agg(gw_name=("gw_name", "first"), first_gw_year=("year", "min"), last_gw_year=("year", "max"))
              .reset_index().merge(acled_names, on="gwcode", how="left"))
unobserved = states["acled_country"].isna()
states.loc[unobserved, "acled_country"] = states.loc[unobserved, "gw_name"].replace(
    {"Vietnam, Democratic Republic of": "Vietnam"})
states.loc[unobserved, "acled_region"] = states.loc[unobserved, "acled_country"].map(REGION_OF_UNOBSERVED)
states["coverage_start"] = states["acled_country"].map(COUNTRY_START).fillna(states["acled_region"].map(REGION_START))

no_start = states[states["coverage_start"].isna()]
# states that ceased to exist before ACLED covered their region (Yugoslavia 1997-2005) are never covered
# Abkhazia and South Ossetia: ACLED codes their events under Georgia, so they cannot be separated (as GDELT, G11)
NOT_SEPARABLE = ["Yugoslavia", "Abkhazia", "South Ossetia"]
never_covered = no_start["gw_name"].isin(NOT_SEPARABLE)
assert no_start[~never_covered].empty, f"no coverage start for: {no_start[~never_covered][['gw_name', 'acled_region']]}"
early = states[states["first_event_year"] < states["coverage_start"]]
assert early.empty, f"events before the assumed coverage start:\n{early}"
late = states[states["first_event_year"] > states["coverage_start"]]
print("\nstates whose first event comes after their coverage start (years in between are zeros):")
print(late[["gw_name", "acled_region", "coverage_start", "first_event_year"]].to_string(index=False))
print("states with no ACLED event at all (zeros throughout their coverage):",
      sorted(states.loc[unobserved & ~states["gw_name"].isin(NOT_SEPARABLE), "gw_name"]))

states.to_csv(OUT / "acled_coverage.csv", index=False)
country_year.to_csv(OUT / "acled_cy.csv", index=False)
country_month.to_csv(OUT / "acled_cm.csv", index=False)
print("\ncoverage start years:", states["coverage_start"].value_counts().sort_index().to_dict())
print("Wrote", OUT / "acled_cy.csv", country_year.shape, "|", OUT / "acled_cm.csv", country_month.shape)
