"""
clean_sipri.py — SIPRI Arms Transfers Database to Gleditsch-Ward supplier x recipient x year (and deal level).
ADDED 2026-11-09 (data/README.md, section 4c, T3 and S1-S6).

Input : data/raw/sipri/tiv/sipri_tiv_<CODE>_<id>.csv        (acquire_sipri.py; per supplier: recipient x year, TIV delivered)
        data/raw/sipri/register/sipri_register_<CODE>_<id>.csv (per supplier: deal-level transfer register)
        data/raw/sipri/sipri_entities.json                   (SIPRI entity names and codes)
        data/clean/base/base.csv                              (GW state-years; iso3c per state-year)
Output: data/clean/sipri/sipri_country_crosswalk.csv  every SIPRI entity: type, ISO3, host country (non-state)
        data/clean/sipri/sipri_tiv_dyadic.csv          supplier x recipient x year, TIV delivered > 0 (millions of TIV),
                                                       with GW codes where the entity is a state in the GW base
        data/clean/sipri/sipri_register.csv            deals with GW codes, numeric order year, delivery years
        data/clean/sipri/sipri_unmatched.csv           TIV by entity that has no GW code (non-state, organisations,
                                                       unknown, unrecognised), for the record

Entity types (S1): "state" (matched to ISO3 below), "non_state" (SIPRI name ends in "*", e.g. "FARC (Colombia)*";
host country in brackets kept as text), "organisation" (name ends in "**": NATO, UN, AU, ...), "unknown"
("unknown supplier(s)", "(multiple sellers)", "Unknown country Africa", ...), "other" (unrecognised or historical
units without a GW state: see OTHER_UNITS). Only "state" rows get a GW code; everything else stays in the files with
gwcode missing (S2), so totals can still be reproduced.

State -> ISO3 (S3): by NAME with pycountry (SIPRI's own codes are not ISO: CHI = China, BOS = Bosnia, ...), plus the
manual NAME_TO_ISO3 list for names pycountry does not resolve. ISO3 -> GW via the base (iso3c, year), as in
clean_acled.py. Base conventions used: RUS = Soviet Union/Russia, YUG = Yugoslavia/FRY to 2005, SRB/MNE from 2006,
YEM = North Yemen and unified Yemen, YMD = South Yemen to 1990, DDR = GDR, VDR = Vietnam, KSV = Kosovo.
Units in OTHER_UNITS get no GW code (S6; user 9 Nov: Palestine left out, O1): Palestine, Abkhazia, South Ossetia,
Northern Cyprus, Somaliland, Trans-Dniester, Artsakh and others.
Non-state recipients (S7; user 9 Nov, O2): host country taken from the name ("FARC (Colombia)*" -> Colombia,
"Syria rebels*" -> Syria) and mapped to GW as `recipient_host_gwcode`, for a SEPARATE "arms to rebels" variable;
never added to the host government's imports. Libya GNC (rival government, 2014-) is treated as a non-state recipient
in Libya. Hosts "Palestine" and "Israel/Palestine" are left unassigned (consistent with O1); groups without a
country (Al-Qaeda, Jemaah Islam, unknown rebel group) have no host. Colonial-era hosts (e.g. "FRELIMO (Portugal)*")
are mapped literally; they predate the estimation sample.

TIV (S4): SIPRI cells '0' = 0 < TIV < 0.5 million (kept as 0, with flag tiv_below_half = 1);
empty = no deliveries identified (row not written). "Total ..." summary rows are dropped.
"""
import io
import json
import re
from pathlib import Path

import pandas as pd
import pycountry

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "sipri"
OUT = ROOT / "data" / "clean" / "sipri"
OUT.mkdir(parents=True, exist_ok=True)

# SIPRI state names pycountry does not resolve (or resolves wrongly) -> ISO3 as used in the GW base
NAME_TO_ISO3 = {
    "Bosnia-Herzegovina": "BIH", "Brunei": "BRN", "Cote d'Ivoire": "CIV", "DR Congo": "COD", "Micronesia": "FSM",
    "Saint Vincent": "VCT", "Soviet Union": "RUS", "Yugoslavia": "YUG", "Kosovo": "KSV", "East Germany (GDR)": "DDR",
    "North Yemen": "YEM", "Yemen Arab Republic (North Yemen)": "YEM", "South Yemen": "YMD", "North Vietnam": "VDR",
    "Viet Nam": "VDR", "Vietnam": "VDR", "Turkiye": "TUR", "Türkiye": "TUR", "Russia": "RUS", "Iran": "IRN",
    "Syria": "SYR", "Laos": "LAO", "Bolivia": "BOL", "Venezuela": "VEN", "Tanzania": "TZA", "Moldova": "MDA",
    "South Korea": "KOR", "North Korea": "PRK", "Taiwan": "TWN", "Congo": "COG", "Czechia": "CZE",
    "Czechoslovakia": "CSK", "UAE": "ARE", "United Arab Emirates": "ARE", "Cape Verde": "CPV", "Swaziland": "SWZ",
    "Eswatini": "SWZ", "Macedonia": "MKD", "North Macedonia": "MKD", "Timor-Leste": "TLS", "Gambia": "GMB",
    "Bahamas": "BHS", "Brunei Darussalam": "BRN", "Vatican": "VAT", "Saint Kitts and Nevis": "KNA",
    "Saint Lucia": "LCA", "Sao Tome and Principe": "STP", "Sao Tomé and Principe": "STP", "Vatican (Holy See)": "VAT", "Serbia": "SRB", "Montenegro": "MNE",
}
# Units without a GW state in our base, or whose assignment is a substantive choice (S6) -> not assigned for now
OTHER_UNITS = {"Palestine", "Abkhazia", "South Ossetia", "Northern Cyprus", "Somaliland",
               "Trans-Dniester", "Artsakh", "Darfur", "Biafra", "Katanga", "Islamic State", "Sikkim", "Zanzibar",
               "South Vietnam", "Europe multi-state", "Test Land"}


# host labels of non-state groups that are not plain country names
HOST_TO_ISO3 = {"Bosnia": "BIH", "CAR": "CAF", "DRC": "COD", "Macedonia": "MKD", "UK": "GBR", "Turkiye": "TUR",
                "Yugoslavia": "YUG", "Russia": "RUS", "Iran": "IRN", "Laos": "LAO", "Libya": "LBY"}
UNASSIGNED_HOSTS = {"Palestine", "Israel/Palestine", "South Vietnam"}


def host_of(name):
    """Host country of a non-state group: text in brackets, or the country before 'rebels'; Libya GNC -> Libya."""
    if name == "Libya GNC":
        return "Libya"
    match = re.search(r"\(([^)]*)\)\s*\*", name) or re.match(r"^(.*?)\s+(?:Palestinian\s+)?[Rr]ebels\*$", name)
    host = match.group(1).strip() if match else None
    return None if host in (None, "TEST", "unknown rebel group") else host


def host_iso3(host):
    if host is None or host in UNASSIGNED_HOSTS:
        return None
    return HOST_TO_ISO3.get(host) or state_iso3(host)


# --- 1. Entity crosswalk ------------------------------------------------------------------------------
def entity_type(name):
    if name == "Libya GNC":
        return "non_state"
    if name.endswith("**"):
        return "organisation"
    if name.rstrip().endswith("*"):
        return "non_state"
    if name.lower().startswith(("unknown", "(multiple")):
        return "unknown"
    if name in OTHER_UNITS:
        return "other"
    return "state"


def state_iso3(name):
    if name in NAME_TO_ISO3:
        return NAME_TO_ISO3[name]
    try:
        return pycountry.countries.lookup(name).alpha_3
    except LookupError:
        return None


entities = pd.DataFrame(json.loads((RAW / "sipri_entities.json").read_text()))
entities = entities.rename(columns={"Name": "sipri_name", "CountryCode": "sipri_code", "EntityId": "sipri_entity_id"})
entities["entity_type"] = entities["sipri_name"].map(entity_type)
entities["iso3c"] = [state_iso3(n) if t == "state" else None for n, t in zip(entities.sipri_name, entities.entity_type)]
entities["host_country"] = [host_of(n) if t == "non_state" else None for n, t in zip(entities.sipri_name, entities.entity_type)]
entities["host_iso3c"] = entities["host_country"].map(host_iso3)
unresolved = entities[(entities.entity_type == "state") & entities.iso3c.isna()]
assert unresolved.empty, f"SIPRI state names without ISO3 (add to NAME_TO_ISO3): {unresolved.sipri_name.tolist()}"
entities[["sipri_entity_id", "sipri_name", "sipri_code", "entity_type", "iso3c", "host_country", "host_iso3c"]] \
    .sort_values(["entity_type", "sipri_name"]).to_csv(OUT / "sipri_country_crosswalk.csv", index=False)
print(entities.entity_type.value_counts().to_string())
iso_of = dict(zip(entities.sipri_name, entities.iso3c))
type_of = dict(zip(entities.sipri_name, entities.entity_type))
host_iso_of = dict(zip(entities.sipri_name, entities.host_iso3c))

base = pd.read_csv(ROOT / "data" / "clean" / "base" / "base.csv", usecols=["gwcode", "year", "iso3c"])
base["year"] = base["year"].astype(str).str[:4].astype(int)
base = base.dropna(subset=["iso3c"])


def add_gw(frame, name_column, prefix):
    """GW code of a SIPRI entity in a given year (state entities only; ISO3 + year in the base)."""
    frame[f"{prefix}_type"] = frame[name_column].map(type_of)
    frame[f"{prefix}_iso3c"] = frame[name_column].map(iso_of)
    lookup = base.rename(columns={"iso3c": f"{prefix}_iso3c", "gwcode": f"{prefix}_gwcode"})
    frame = frame.merge(lookup, on=[f"{prefix}_iso3c", "year"], how="left")
    if prefix == "recipient":   # non-state recipients: GW code of the host country (S7)
        frame["recipient_host_iso3c"] = frame[name_column].map(host_iso_of)
        host = base.rename(columns={"iso3c": "recipient_host_iso3c", "gwcode": "recipient_host_gwcode"})
        frame = frame.merge(host, on=["recipient_host_iso3c", "year"], how="left")
    return frame


def read_table(path):
    """SIPRI CSV: notes on top, the table starts at the line beginning with 'Recipient,'."""
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("Recipient,"))
    return pd.read_csv(io.StringIO("\n".join(lines[start:])), dtype=str)


# --- 2. TIV tables -> dyadic supplier x recipient x year ----------------------------------------------
manifest = json.loads((RAW / "sipri_download_manifest.json").read_text())
supplier_of_file = {f"sipri_tiv_{key}.csv": entry["name"] for key, entry in manifest.items() if key != "_query"}
frames = []
for path in sorted((RAW / "tiv").glob("sipri_tiv_*.csv")):
    table = read_table(path)
    table = table[~table["Recipient"].str.startswith("Total")]
    years = [c for c in table.columns if c.isdigit()]
    long = table.melt(id_vars="Recipient", value_vars=years, var_name="year", value_name="tiv_raw")
    long = long[long["tiv_raw"].notna() & (long["tiv_raw"].str.strip() != "")]
    long["supplier"] = supplier_of_file[path.name]
    frames.append(long)
tiv = pd.concat(frames, ignore_index=True).rename(columns={"Recipient": "recipient"})
tiv["year"] = tiv["year"].astype(int)
tiv["tiv"] = pd.to_numeric(tiv["tiv_raw"], errors="raise")
tiv["tiv_below_half"] = (tiv["tiv"] == 0).astype(int)        # SIPRI '0' = between 0 and 0.5 million TIV
assert not tiv.duplicated(["supplier", "recipient", "year"]).any()
unknown_names = set(tiv.recipient) - set(type_of)
assert not unknown_names, f"recipients not in the SIPRI entity list: {sorted(unknown_names)[:10]}"

tiv = add_gw(add_gw(tiv, "supplier", "supplier"), "recipient", "recipient")
tiv = tiv[["supplier", "supplier_type", "supplier_iso3c", "supplier_gwcode", "recipient", "recipient_type",
           "recipient_iso3c", "recipient_gwcode", "recipient_host_gwcode", "year", "tiv", "tiv_below_half"]]
tiv.sort_values(["supplier", "recipient", "year"]).to_csv(OUT / "sipri_tiv_dyadic.csv", index=False)
print(f"\nTIV dyadic: {len(tiv)} supplier-recipient-years with deliveries, {tiv.year.min()}-{tiv.year.max()}, "
      f"total {tiv.tiv.sum():,.0f} million TIV")

# Entities without a GW code (by role) — the record of what does not enter state-level measures
state_years = tiv[tiv.recipient_type == "state"]
lost_state = state_years[state_years.recipient_gwcode.isna()]
print(f"state recipients outside the GW base years (e.g. before {base.year.min()} or not a GW state then): "
      f"{len(lost_state)} rows, {lost_state.tiv.sum():,.0f} TIV")
unmatched = pd.concat([
    tiv[tiv.supplier_gwcode.isna()].assign(role="supplier", entity=lambda d: d.supplier, entity_type=lambda d: d.supplier_type),
    tiv[tiv.recipient_gwcode.isna()].assign(role="recipient", entity=lambda d: d.recipient, entity_type=lambda d: d.recipient_type),
])
(unmatched.groupby(["role", "entity_type", "entity"])
          .agg(rows=("tiv", "size"), tiv=("tiv", "sum"), first_year=("year", "min"), last_year=("year", "max"))
          .reset_index().sort_values(["role", "tiv"], ascending=[True, False])
          .to_csv(OUT / "sipri_unmatched.csv", index=False))
for role in ["supplier", "recipient"]:
    part = unmatched[unmatched.role == role]
    print(f"{role} TIV without GW code, by type (all years):",
          part.groupby("entity_type").tiv.sum().round(0).to_dict())

# --- 3. Transfer register (deal level) ---------------------------------------------------------------
frames = []
for path in sorted((RAW / "register").glob("sipri_register_*.csv")):
    table = read_table(path)
    frames.append(table)
register = pd.concat(frames, ignore_index=True)
register.columns = [c.strip() for c in register.columns]
register = register.rename(columns={
    "Recipient": "recipient", "Supplier": "supplier", "Year of order": "order_year", "": "order_year_uncertain",
    "Number ordered": "number_ordered", "Weapon designation": "weapon_designation",
    "Weapon description": "weapon_description", "Deliveries in the Year Range": "number_delivered",
    "Year(s) of delivery": "delivery_years", "status": "status", "Comments": "comments",
    "SIPRI TIV per unit": "tiv_per_unit", "SIPRI TIV for total order": "tiv_order",
    "SIPRI TIV of delivered weapons": "tiv_delivered"})
# the three unnamed '?' columns (uncertainty markers) come after year of order, number ordered, number delivered
unnamed = [c for c in register.columns if c.startswith(".") or c in ("", " ") or c.startswith("Unnamed")]
register = register.rename(columns=dict(zip(unnamed, ["order_year_uncertain", "number_ordered_uncertain",
                                                      "number_delivered_uncertain"])))
register["order_year"] = pd.to_numeric(register["order_year"], errors="coerce").astype("Int64")
for column in ["number_ordered", "number_delivered", "tiv_per_unit", "tiv_order", "tiv_delivered"]:
    register[column] = pd.to_numeric(register[column], errors="coerce")
register["first_delivery_year"] = register["delivery_years"].str.extract(r"(\d{4})", expand=False).astype("Int64")
register["year"] = register["order_year"]                     # GW code as of the order year
register = add_gw(add_gw(register, "supplier", "supplier"), "recipient", "recipient").drop(columns="year")
register.to_csv(OUT / "sipri_register.csv", index=False)
rebels = tiv[tiv.recipient_type == "non_state"]
print(f"non-state recipients: {len(rebels)} rows, {rebels.tiv.sum():,.0f} TIV; with host GW code: "
      f"{rebels.recipient_host_gwcode.notna().sum()} rows, {rebels.loc[rebels.recipient_host_gwcode.notna(), 'tiv'].sum():,.0f} TIV "
      f"(1989-2023: {rebels[rebels.year.between(1989, 2023)].shape[0]} rows)")
print(f"\nregister: {len(register)} deals, order years {register.order_year.min()}-{register.order_year.max()}; "
      f"to non-state recipients: {(register.recipient_type == 'non_state').sum()}")
