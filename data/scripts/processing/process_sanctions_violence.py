"""
process_sanctions_violence.py
Build the analysis-ready country-year panel: state-year base + GSDB sanctions
(received and sent) + UCDP organized violence + GDELT conflict events.

Inputs : data/clean/base/base.csv
         data/clean/population/wpp_population.csv
         data/clean/gdp/wb_gdppc.csv
         data/clean/gsdb/gsdb_received.csv, data/clean/gsdb/gsdb_sent.csv
         data/clean/ucdp_ov/ucdp_ov_cy.csv
         data/clean/gdelt/gdelt_cy.csv
Outputs: data/processed/sanctions_violence/sanctions_violence_panel.csv
             (formerly data/data_clean/country_year_sanctions_coflict_gdelt.csv)
         data/processed/sanctions_violence/intermediate/country_year_sanctions.csv
         data/processed/sanctions_violence/intermediate/country_year_sanctions_conflict.csv
         data/processed/sanctions_violence/checks/orphans_recieved.csv
         data/processed/sanctions_violence/checks/orphans_outgoing.csv
         data/processed/sanctions_violence/checks/base_cross.csv

Refactored 1:1 from the merge cells of archive/notebooks/
  create_sanction_data.ipynb  (cells 14, 16, 21-24, 26)
  Create_violence_data.ipynb  (cells 9, 10, 13)
  create_gdelt_data.ipynb     (cells 8-10)

Note on exact replication: the old notebooks passed the data from one notebook
to the next through CSV files, and pandas' default CSV parser can change the
last digit (~1e-16) of a float. To reproduce the old numbers bit for bit, the
two intermediate stages are still written to CSV and read back with the same
default parser, exactly as before. The clean datasets are read with
float_precision="round_trip", because in the old notebooks they never left memory.
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
CLEAN = ROOT / "data" / "clean"
OUT = ROOT / "data" / "processed" / "sanctions_violence"
CHECKS = OUT / "checks"
INTER = OUT / "intermediate"
CHECKS.mkdir(parents=True, exist_ok=True)
INTER.mkdir(parents=True, exist_ok=True)
EXACT = dict(float_precision="round_trip")   # exact float reading for the clean files

# ---------------------------------------------------------------------------
# Load
# ---------------------------------------------------------------------------
base = pd.read_csv(CLEAN / "base" / "base.csv")
base["year"] = pd.to_datetime(base["year"].astype(str), format="%Y")

# ADDED 2026-10-20 (data/README.md, P6): panel starts in 1950, the first GSDB year
# (before, 1946-49 were in the panel with all sanction counts zero-filled).
base = base[base["year"] >= pd.Timestamp("1950-01-01")].reset_index(drop=True)

# ADDED 2026-10-20 (data/README.md, P7; data/README_yugoslavia.md): ex-Yugoslavia controls
EX_YUGO = {345, 340, 341, 343, 344, 346, 347, 349}   # Yugoslavia/FRY, Serbia, Montenegro, Macedonia, Croatia, Bosnia, Kosovo, Slovenia
base["ex_yugo"] = base["gwcode"].isin(EX_YUGO).astype(int)
base["ex_yugo_1991_2016"] = (base["ex_yugo"].eq(1) & base["year"].dt.year.between(1991, 2016)).astype(int)

received_sanctions = pd.read_csv(CLEAN / "gsdb" / "gsdb_received.csv", **EXACT)
received_sanctions["year"] = pd.to_datetime(received_sanctions["year"], format="%Y-%m-%d")
outgoing_sanctions = pd.read_csv(CLEAN / "gsdb" / "gsdb_sent.csv", **EXACT)
outgoing_sanctions["year"] = pd.to_datetime(outgoing_sanctions["year"], format="%Y-%m-%d")

conflict_to_merge = pd.read_csv(CLEAN / "ucdp_ov" / "ucdp_ov_cy.csv", **EXACT)
conflict_to_merge["year"] = pd.to_datetime(conflict_to_merge["year"], format="%Y-%m-%d")
conflict_vars = list(conflict_to_merge.columns)

gdelt = pd.read_csv(CLEAN / "gdelt" / "gdelt_cy.csv", **EXACT)
gdelt["Year"] = pd.to_datetime(gdelt["Year"], format="%Y-%m-%d")

# ===========================================================================
# 1. Sanctions (GSDB)
# ===========================================================================
# orphan checks: sanction country-years with no match in the base
merged = pd.merge(
    received_sanctions, base,
    how='left',
    left_on=['year', 'country_iso3'], right_on=['year', 'iso3c'],
    indicator=True
)
orphans = merged[merged['_merge'] == 'left_only']
orphans_check_recieved = orphans[['year', 'country_iso3', 'num_sanctioners']].drop_duplicates()

merged = pd.merge(
    outgoing_sanctions, base,
    how='left',
    left_on=['year', 'country_iso3'], right_on=['year', 'iso3c'],
    indicator=True
)
orphans = merged[merged['_merge'] == 'left_only']
orphans_check_outgoing = orphans[['year', 'country_iso3', 'num_targets_sanctioned']].drop_duplicates()

orphans_check_outgoing.to_csv(CHECKS / 'orphans_outgoing.csv', index=False)
orphans_check_recieved.to_csv(CHECKS / 'orphans_recieved.csv', index=False)
print("orphans received:", len(orphans_check_recieved), "| orphans outgoing:", len(orphans_check_outgoing))

base_recieved = pd.merge(base, received_sanctions, how='left', left_on=['year', 'iso3c'], right_on=['year', 'country_iso3'])

cols_to_fill = [c for c in list(outgoing_sanctions.columns) + list(received_sanctions.columns)
                if c not in ['country', 'country_iso3', 'year']]

base_recieved_outgoing = pd.merge(base_recieved, outgoing_sanctions, how='left', left_on=['year', 'iso3c'], right_on=['year', 'country_iso3'])
base_recieved_outgoing = base_recieved_outgoing.drop(columns=['country_iso3_x', 'country_iso3_y'])
base_recieved_outgoing[cols_to_fill] = base_recieved_outgoing[cols_to_fill].fillna(0)

crosswalk = base_recieved_outgoing[['gwcode', 'gw_name', 'iso3c']].groupby(['gwcode', 'gw_name', 'iso3c']).agg('first').reset_index()
crosswalk.to_csv(CHECKS / 'base_cross.csv')

base_recieved_outgoing.to_csv(INTER / 'country_year_sanctions.csv', index=False)

# ===========================================================================
# 2. Organized violence (UCDP OV-CY)
# ===========================================================================
base = pd.read_csv(INTER / 'country_year_sanctions.csv')
base["year"] = pd.to_datetime(base["year"].astype(str).str[:4], format="%Y")

base_conflict = pd.merge(base, conflict_to_merge, how='left',
    left_on=['year', 'gwcode'], right_on=['year', 'country_id'])

# columns you don't want to fillna with 0 (they're strings/labels, not counts)
non_numeric_cols = ['country', 'region', 'govt_name', 'year', 'country_id']

# numeric columns to zero-fill
numeric_conflict_vars = [c for c in conflict_vars if c not in non_numeric_cols]

mask = base_conflict['year'] > pd.Timestamp('1988-01-01')
base_conflict.loc[mask, numeric_conflict_vars] = base_conflict.loc[mask, numeric_conflict_vars].fillna(0)

print(base_conflict['pwtpop'].describe())

# columns that should NOT be divided by population (binary existence/involvement flags)
binary_flags = [
    'sb_exist', 'sb_intrastate_exist', 'sb_interstate_exist',
    'ns_exist', 'os_exist',
    'sb_intrastate_govt_inv_incomp', 'sb_interstate_govt_inv_incomp',
    'os_govt_inv', 'os_any_govt_inv',
]

# columns to actually convert to per-capita (counts and death totals)
vars_to_percap = [c for c in numeric_conflict_vars if c not in binary_flags]

# pwtpop is in millions, so:
# deaths / pwtpop           -> deaths per million
# deaths / pwtpop / 10      -> deaths per 100,000  (equivalent to (deaths / (pwtpop * 1_000_000)) * 100_000)
# ADDED 2026-10-20 (data/README.md, P4): population divisor extended to 2023.
# pop_ext = pwtpop up to 2019 (unchanged); 2020-2023 = pwtpop(2019) x WPP growth since 2019
# (UN WPP 2024 as processed by Our World in Data, population on 1 July). Chain-linking keeps every value up to 2019 and
# avoids a level jump: WPP and pwtpop levels differ by up to ~25% for some countries.
WPP_ISO = {"KSV": "XKX",   # Kosovo: panel code KSV, WPP code XKX
           "VDR": "VNM"}   # Vietnam (GW 816): panel code VDR, WPP code VNM
wpp = pd.read_csv(CLEAN / "population" / "wpp_population.csv")
wpp_idx = wpp.set_index(["iso3c", "year"])["wpp_pop"]
yr_int = base_conflict["year"].dt.year
iso_wpp = base_conflict["iso3c"].replace(WPP_ISO)
pwt2019 = (base_conflict.loc[yr_int == 2019].set_index("gwcode")["pwtpop"])
growth = (pd.Series([wpp_idx.get((i, y)) for i, y in zip(iso_wpp, yr_int)], index=base_conflict.index, dtype=float)
          / pd.Series([wpp_idx.get((i, 2019)) for i in iso_wpp], index=base_conflict.index, dtype=float))
ext = yr_int.between(2020, 2023)
base_conflict["pop_ext"] = base_conflict["pwtpop"]
base_conflict.loc[ext, "pop_ext"] = base_conflict.loc[ext, "gwcode"].map(pwt2019) * growth[ext]
base_conflict["pop_ext_source"] = None
base_conflict.loc[base_conflict["pwtpop"].notna(), "pop_ext_source"] = "pwtpop"
base_conflict.loc[ext & base_conflict["pop_ext"].notna(), "pop_ext_source"] = "pwtpop2019 x WPP growth (OWID)"
print("pop_ext 2020-2023: filled", int((ext & base_conflict["pop_ext"].notna()).sum()), "of", int(ext.sum()),
      "| missing:", sorted(base_conflict.loc[ext & base_conflict["pop_ext"].isna(), "gw_name"].unique()))

# ADDED 2026-10-20 (data/README.md, P5): GDP per capita extended to 2023, same method as pop_ext.
# gdp_ext = mrgdppc up to 2019 (unchanged); 2020-2023 = mrgdppc(2019) x World Bank GDP pc growth
# since 2019 (WDI, PPP constant 2021 $, via Our World in Data).
wb = pd.read_csv(CLEAN / "gdp" / "wb_gdppc.csv")
wb_idx = wb.set_index(["iso3c", "year"])["wb_gdppc"]
gdp2019 = base_conflict.loc[yr_int == 2019].set_index("gwcode")["mrgdppc"]
g_wb = (pd.Series([wb_idx.get((i, y)) for i, y in zip(iso_wpp, yr_int)], index=base_conflict.index, dtype=float)
        / pd.Series([wb_idx.get((i, 2019)) for i in iso_wpp], index=base_conflict.index, dtype=float))
base_conflict["gdp_ext"] = base_conflict["mrgdppc"]
base_conflict.loc[ext, "gdp_ext"] = base_conflict.loc[ext, "gwcode"].map(gdp2019) * g_wb[ext]
base_conflict["gdp_ext_source"] = None
base_conflict.loc[base_conflict["mrgdppc"].notna(), "gdp_ext_source"] = "mrgdppc"
base_conflict.loc[ext & base_conflict["gdp_ext"].notna(), "gdp_ext_source"] = "mrgdppc2019 x WB growth (OWID)"
print("gdp_ext 2020-2023: filled", int((ext & base_conflict["gdp_ext"].notna()).sum()), "of", int(ext.sum()),
      "| missing:", sorted(base_conflict.loc[ext & base_conflict["gdp_ext"].isna(), "gw_name"].unique()))

# CHANGED 2026-10-20: no .fillna(0) before dividing. Counts are already 0-filled from
# 1989 (above); before 1989 UCDP has no data, so the per-capita values are now missing
# like the counts themselves (they were 0 before). See data/README.md, U6.
for col in vars_to_percap:
    base_conflict[f'{col}_pc'] = (
        base_conflict[col] / base_conflict['pop_ext'] / 10   # CHANGED 2026-10-20: was pwtpop (identical up to 2019)
    )

base_conflict.to_csv(INTER / 'country_year_sanctions_conflict.csv', index=False)

# ===========================================================================
# 3. GDELT conflict events
# ===========================================================================
base = pd.read_csv(INTER / 'country_year_sanctions_conflict.csv')
base["year"] = pd.to_datetime(base["year"].astype(str).str[:4], format="%Y")

base_gdelt = pd.merge(base, gdelt, how='left',
    left_on=['year', 'gwcode'], right_on=['Year', 'gwcode'])

numeric_cols = [
 'assault_norm1000',
 'coerce_norm1000',
 'fight_norm1000',
 'mass_violence_norm1000',
 'total_violence_norm1000',
 'assault_goldstein',
 'coerce_goldstein',
 'fight_goldstein',
 'mass_violence_goldstein',
 'total_violence_goldstein']

# CHANGED 2026-10-20 (data/README.md, G10-G11): zero-fill only inside GDELT's coverage
# (1979 to the last GDELT year, 2021) and not for states GDELT cannot separate from
# another country (their events are inside that country's GDELT data) -> missing.
GDELT_NOT_SEPARABLE = {
    265: "German Democratic Republic (in GDELT 'Germany', assigned to 260)",
    680: "South Yemen (in GDELT 'Yemen', assigned to 678)",
    396: "Abkhazia (in GDELT 'Georgia')",
    397: "South Ossetia (in GDELT 'Georgia')",
}
gdelt_last = gdelt['Year'].max()
numeric_cols = numeric_cols + ['gdelt_total_events']
mask = ((base_gdelt['year'] > pd.Timestamp('1978-01-01'))
        & (base_gdelt['year'] <= gdelt_last)
        & ~base_gdelt['gwcode'].isin(list(GDELT_NOT_SEPARABLE)))
base_gdelt.loc[mask, numeric_cols] = base_gdelt.loc[mask, numeric_cols].fillna(0)
base_gdelt.loc[mask, 'gdelt_n_units'] = base_gdelt.loc[mask, 'gdelt_n_units'].fillna(0)
print("GDELT zero-filled up to", gdelt_last.year, "| missing for", sorted(GDELT_NOT_SEPARABLE))

# ===========================================================================
# 4. ACLED political violence — ADDED 2026-11-09 (data/README.md, A1-A8)
# ===========================================================================
# Merge by gwcode x year. Zero-fill only inside each state's ACLED coverage window
# (coverage start .. last ACLED year); outside it the ACLED variables stay missing.
# Deaths also per 100,000 inhabitants (pop_ext), like the UCDP variables.
acled = pd.read_csv(CLEAN / "acled" / "acled_cy.csv")
acled["year"] = pd.to_datetime(acled["year"].astype(str), format="%Y")
acled_coverage = pd.read_csv(CLEAN / "acled" / "acled_coverage.csv").set_index("gwcode")["coverage_start"]
acled_cols = [c for c in acled.columns if c.startswith("acled_")]
base_gdelt = base_gdelt.merge(acled, on=["gwcode", "year"], how="left")
start = base_gdelt["gwcode"].map(acled_coverage)
covered = start.notna() & (base_gdelt["year"].dt.year >= start) & (base_gdelt["year"] <= acled["year"].max())
base_gdelt.loc[covered, acled_cols] = base_gdelt.loc[covered, acled_cols].fillna(0)
base_gdelt.loc[~covered, acled_cols] = None
assert acled.merge(base_gdelt[covered][["gwcode", "year"]], on=["gwcode", "year"]).shape[0] == len(acled), \
    "ACLED country-years outside the coverage window or without a base row"
base_gdelt["acled_covered"] = covered.astype(int)
for col in [c for c in acled_cols if c.startswith("acled_deaths_")]:
    base_gdelt[f"{col}_pc"] = base_gdelt[col] / base_gdelt["pop_ext"] / 10    # per 100,000 (pop_ext in millions)
print("ACLED: covered state-years", int(covered.sum()), "| by year:",
      base_gdelt[covered].groupby(base_gdelt["year"].dt.year).size().to_dict())

# duplicate check (printed to the log; should be 0)
tab = base_gdelt.groupby(["gw_name", "year"]).size()
print("duplicate gw_name-year rows:", int((tab > 1).sum()))

# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------
# ADDED 2026-10-20 (data/README.md, P8): drop merge leftovers, one ISO3 column
LEFTOVERS = ['country', 'country_id', 'region', 'govt_name',          # UCDP identifiers
             'Year', 'CountryCode', 'CountryName', 'iso3c_y']          # GDELT identifiers
base_gdelt = base_gdelt.drop(columns=LEFTOVERS).rename(columns={'iso3c_x': 'iso3c'})

base_gdelt.to_csv(OUT / 'sanctions_violence_panel.csv', index=False)
print("Wrote", OUT / 'sanctions_violence_panel.csv', base_gdelt.shape)
