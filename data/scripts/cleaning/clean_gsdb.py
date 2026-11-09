"""
clean_gsdb.py
Global Sanctions Data Base (GSDB v4, dyadic): harmonise state codes and
aggregate to country-year counts of sanctions RECEIVED and SENT.

Input : data/raw/gsdb/GSDB_V4_dyadic.dta
        data/clean/base/base.csv   (gwcode-year-iso3c crosswalk, for the *_gw counts)
        data/raw/gsdb/GSDB_V4.csv  (case-level types, for the Yugoslavia attribution)
        data/scripts/cleaning/gsdb_yugoslavia_attribution.csv
Output: data/clean/gsdb/gsdb_received.csv   (country_iso3 x year)
        data/clean/gsdb/gsdb_sent.csv       (country_iso3 x year)
        data/clean/gsdb/gsdb_yugoslavia_attribution_log.csv (every changed dyad, before/after)
        data/clean/gsdb/gsdb_set_aside.csv  (rows kept out of the counts: non-GW entities)
        data/clean/gsdb/gsdb_self_dyads_dropped.csv (sender == target after recoding)

ADDED 2026-10-20 (data/README.md, S11): flow variables on the received side
(n_new_cases, new_sanction, n_joined_cases, n_lifted_cases, lifted_sanction, new_un/eu/us_sanction,
new_arms_sanction, new_conflict_obj_sanction), step 5c.

Refactored 1:1 from archive/notebooks/create_sanction_data.ipynb (cells 3 and 6).

Two ways of counting countries (both kept):
  num_sanctioners, num_targets_sanctioned
      ORIGINAL: number of distinct country NAMES in GSDB. Names are not recoded,
      so e.g. Serbia and Montenegro count as 2 before 2006.
  num_sanctioners_gw, num_targets_sanctioned_gw
      ADDED 2026-10-20: number of distinct Gleditsch-Ward states (gwcode). The recoded
      ISO3 code of each sender/target is matched to the gwcode of the state-year
      base, so counts follow the same country definitions as the panel.
      Countries without a GW state that year are not counted (listed in the log).
The merge onto the state-year base now lives in
data/scripts/processing/process_sanctions_violence.py.
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
RAW = ROOT / "data" / "raw" / "gsdb"
OUT = ROOT / "data" / "clean" / "gsdb"
OUT.mkdir(parents=True, exist_ok=True)

df = pd.read_stata(RAW / "GSDB_V4_dyadic.dta")

# integer year (GSDB stores the year as a date like 1993-01-01)
yr = pd.to_datetime(df["year"]).dt.year

iso_cols  = ["sanctioning_state_iso3", "sanctioned_state_iso3"]
name_cols = ["sanctioning_state", "sanctioned_state"]

# snapshot the ORIGINAL codes — the drop/separate masks must test these,
# not values that a relabel below has already changed
s0 = df["sanctioning_state_iso3"].copy()
t0 = df["sanctioned_state_iso3"].copy()

# =====================================================================
# STEP 1 — mark rows to DROP  (row goes if EITHER side hits a drop rule)
# =====================================================================
def _drop(code):   # small mask helper, not the recoding logic itself
    return (
        (code == "")                                    # terrorist orgs / non-state
        | (code == "BYS")                               # Byelorussian SSR (UN-seat artifact)
        | ((code == "UKR") & (yr <= 1990))              # Ukrainian SSR seat
        | ((code == "SVU") & (yr >= 1990))              # USSR 1990-91 tail (Russia takes over)
        | ((code == "RUS") & (yr <  1990))              # pre-1990 RUS duplicates
        | ((code == "KSV") & (yr <= 2007))              # premature/erroneous Kosovo (case 663)
        | ((code == "ARM") & (yr <  1991))              # pre-independence 'bleed' below
        | ((code == "AZE") & (yr <  1991))
        | ((code == "EST") & (yr <  1991))
        | ((code == "LTU") & (yr <  1991))
        | ((code == "LVA") & (yr <  1991))
        | ((code == "BIH") & (yr <  1992))
        | ((code == "HRV") & (yr <  1992))
        | ((code == "SVN") & (yr <  1992))
        | ((code == "SGP") & (yr <  1965))
        | ((code == "GNB") & (yr <  1974))
        | ((code == "MOZ") & (yr <  1975))
        | ((code == "ERI") & (yr <  1993))              # ADDED 2026-10-20: Eritrea before independence
    )
drop_mask = _drop(s0) | _drop(t0)

# =====================================================================
# STEP 2 — mark rows for a SEPARATE side table (kept, not merged)
# =====================================================================
separate = {"RHO", "PSE", "HKG", "ESH", "VAT", "MSR"}   # RHO kept aside (no Zimbabwe change)
# ADDED 2026-10-20: case 179 (Cyprus vs "Cyprus (Northern)") — GSDB gives Northern Cyprus the
# code CYP, so Cyprus would sanction itself; Northern Cyprus is not a GW state -> set aside.
north_cyprus = df["sanctioned_state"].eq("Cyprus (Northern)") | df["sanctioning_state"].eq("Cyprus (Northern)")
separate_mask = (s0.isin(separate) | t0.isin(separate) | north_cyprus) & ~drop_mask

# =====================================================================
# STEP 3 — relabel codes (and the two clean names), on both columns
# =====================================================================
# 3a. simple same-polity renames (all years)
df[iso_cols]  = df[iso_cols].replace({"DHY": "BEN", "HVO": "BFA"})
df[name_cols] = df[name_cols].replace({"Dahomey": "Benin", "Upper Volta": "Burkina Faso"})
# 3b. folds (all years)
df[iso_cols]  = df[iso_cols].replace({"GIB": "GBR", "COK": "NZL", "NIU": "NZL"})
# 3c. year-conditional relabels (test the original codes s0/t0, write to the live column)
for col, orig in [("sanctioning_state_iso3", s0), ("sanctioned_state_iso3", t0)]:
    df.loc[(orig == "SVU") & (yr <  1990), col] = "RUS"   # Soviet sanctions -> single RUS
    df.loc[(orig == "SRB") & (yr <= 2005), col] = "YUG"   # pre-2006 = Yugoslavia
    df.loc[(orig == "MNE") & (yr <= 2005), col] = "YUG"
    df.loc[(orig == "DDR") & (yr >= 1991), col] = "DEU"   # post-reunification residue
    df.loc[(orig == "CSK") & (yr >= 1993), col] = "CZE"   # post-dissolution residue
    df.loc[(orig == "CZE") & (yr <= 1992), col] = "CSK"   # successor code before the split
    df.loc[(orig == "SVK") & (yr <= 1992), col] = "CSK"
    df.loc[(orig == "VNM") & (yr >= 1976), col] = "VDR"   # unified Vietnam is VDR in base
    #df.loc[(orig == "ERI") & (yr <= 1992), col] = "ETH"   # Eritrea within Ethiopia pre-1993

# =====================================================================
# STEP 4 — split into buckets
# =====================================================================
panel = df[~drop_mask & ~separate_mask].copy()   # merge into the base (dedupe first!)
side  = df[separate_mask].copy()                  # RHO/PSE/HKG/ESH/VAT/MSR
# dropped = df[drop_mask]

print("merge:", len(panel), "| separate:", len(side), "| drop:", int(drop_mask.sum()))

# ADDED 2026-10-20: keep a record of the set-aside rows; drop self-sanctions
side.to_csv(OUT / "gsdb_set_aside.csv", index=False)
print("set aside by entity:", side["sanctioned_state"].where(side["sanctioned_state_iso3"].isin(separate)
      | side["sanctioned_state"].eq("Cyprus (Northern)"), side["sanctioning_state"]).value_counts().to_dict())
# Self-sanctions: after the recoding (e.g. GDR -> DEU from 1991, Serbia/Montenegro -> YUG
# to 2005, North/South Vietnam -> VDR from 1976) some rows have sender == target, i.e. a
# state "sanctioning itself". These are recoding residues -> dropped and listed.
self_mask = panel["sanctioning_state_iso3"] == panel["sanctioned_state_iso3"]
self_rows = panel[self_mask]
self_rows.to_csv(OUT / "gsdb_self_dyads_dropped.csv", index=False)
print("self-dyads dropped (sender == target after recoding):", len(self_rows))
if len(self_rows):
    print(self_rows[["case_id", "sanctioning_state", "sanctioned_state", "year"]].to_string())
panel = panel[~self_mask].copy()

# =====================================================================
# STEP 4a — ADDED 2026-10-20: attribution of the "Yugoslavia" cases
# =====================================================================
# GSDB's case file names "Yugoslavia" as the target of cases 419-422, 469, 470,
# 619-621, 636-638, 660, 676, 732, but the dyadic file copies them to every
# successor republic. gsdb_yugoslavia_attribution.csv says, per case x republic,
# whether the case is kept (arms embargo only, with republic-specific end year)
# or dropped. Rules and sources: data/README_yugoslavia.md.
TYPE_COLS = ["arms", "military", "trade", "financial", "travel", "other"]
rules = pd.read_csv(ROOT / "data" / "scripts" / "cleaning" / "gsdb_yugoslavia_attribution.csv")
rule_of = {(int(r.case_id), r.target_iso3): r for r in rules.itertuples()}
yugo_cases = set(rules["case_id"].astype(int))
case_flags = pd.read_csv(RAW / "GSDB_V4.csv").set_index("case_id")[TYPE_COLS]

panel_yr = pd.to_datetime(panel["year"]).dt.year
in_scope = panel["sanctioned_state_iso3"].isin(set(rules["target_iso3"]))
log_rows, drop_idx = [], []
for i in panel.index[in_scope]:
    cases = [int(c) for c in str(panel.at[i, "case_id"]).split(",") if c.strip()]
    if not yugo_cases.intersection(cases):
        continue
    target, y = panel.at[i, "sanctioned_state_iso3"], panel_yr.at[i]
    kept, flags = [], dict.fromkeys(TYPE_COLS, 0)
    for c in cases:
        if c in yugo_cases:
            r = rule_of.get((c, target))
            if r is None:
                raise ValueError(f"no attribution rule for case {c} and target {target}")
            if r.action == "keep_arms_only" and r.keep_from <= y <= r.keep_to:
                kept.append(c)
                flags["arms"] = 1
        else:                                   # a case that names the republic itself
            kept.append(c)
            for t in TYPE_COLS:
                flags[t] = max(flags[t], int(case_flags.at[c, t]))
    before = {t: int(panel.at[i, t]) for t in TYPE_COLS}
    log_rows.append(dict(target=target, year=y, sender=panel.at[i, "sanctioning_state_iso3"],
                         case_id_before=panel.at[i, "case_id"], case_id_after=",".join(map(str, kept)),
                         **{f"{t}_before": before[t] for t in TYPE_COLS},
                         **{f"{t}_after": (flags[t] if kept else 0) for t in TYPE_COLS}))
    if kept:
        panel.at[i, "case_id"] = ",".join(map(str, kept))
        for t in TYPE_COLS:
            panel.at[i, t] = flags[t]
    else:
        drop_idx.append(i)
panel = panel.drop(index=drop_idx)
attr_log = pd.DataFrame(log_rows)
attr_log.to_csv(OUT / "gsdb_yugoslavia_attribution_log.csv", index=False)
print("Yugoslavia attribution: rows touched", len(attr_log), "| dropped", len(drop_idx),
      "| kept (arms only)", len(attr_log) - len(drop_idx))
print(attr_log.assign(dropped=attr_log["case_id_after"].eq("")).groupby(["target", "dropped"]).size().to_string())

# =====================================================================
# STEP 4b — attach Gleditsch-Ward codes (for the *_gw counts)
# =====================================================================
gw_cw = pd.read_csv(ROOT / "data" / "clean" / "base" / "base.csv", usecols=["gwcode", "year", "iso3c"])
gw_cw = gw_cw.dropna(subset=["iso3c"])
assert not gw_cw.duplicated(["iso3c", "year"]).any(), "iso3c-year must identify one GW state"
gw_cw["year"] = pd.to_datetime(gw_cw["year"].astype(str), format="%Y")
panel = (
    panel
    .merge(gw_cw.rename(columns={"iso3c": "sanctioning_state_iso3", "gwcode": "sanctioning_gwcode"}),
           on=["sanctioning_state_iso3", "year"], how="left")
    .merge(gw_cw.rename(columns={"iso3c": "sanctioned_state_iso3", "gwcode": "sanctioned_gwcode"}),
           on=["sanctioned_state_iso3", "year"], how="left")
)
for side in ["sanctioning", "sanctioned"]:
    miss = panel[panel[f"{side}_gwcode"].isna()]
    print(f"{side} rows without a GW state (not counted in *_gw):", len(miss))
    if len(miss):
        print(miss.groupby(f"{side}_state_iso3")["year"].agg(["min", "max", "size"]).to_string())

# ADDED 2026-11-09 (data/README.md, X1): sender-level file, one row per case x sender x target x year, from the
# cleaned dyadic data (after all drop/recode/Yugoslavia rules). Used by process_exposure.py to measure the target's
# trade and arms exposure to the actual senders of a case (group cases such as EU or UN appear as one row per member
# state here). Does not change any other output.
senders_out = panel[["case_id", "sanctioning_state_iso3", "sanctioning_gwcode", "sanctioned_state_iso3",
                     "sanctioned_gwcode", "year"]].copy()
senders_out["case"] = senders_out["case_id"].astype(str).str.split(",")
senders_out = senders_out.explode("case")
senders_out["case"] = senders_out["case"].str.strip().astype(int)
senders_out["year"] = pd.to_datetime(senders_out["year"]).dt.year
senders_out = (senders_out.drop(columns="case_id").drop_duplicates()
               .sort_values(["sanctioned_state_iso3", "year", "case", "sanctioning_state_iso3"]))
senders_out.to_csv(OUT / "gsdb_case_senders.csv", index=False)
print("Wrote", OUT / "gsdb_case_senders.csv", senders_out.shape)

# =====================================================================
# STEP 5 — aggregate to country-year
# =====================================================================
received_sanctions = (
    panel.groupby(['sanctioned_state_iso3', 'year'])
    .agg(
        num_sanctioners=('sanctioning_state', 'nunique'),
        num_sanctioners_gw=('sanctioning_gwcode', 'nunique'),
        n_arms_received=('arms', 'sum'),
        n_military_received=('military', 'sum'),
        n_trade_received=('trade', 'sum'),
        n_financial_received=('financial', 'sum'),
        n_travel_received=('travel', 'sum'),
        n_other_received=('other', 'sum'),
    )
    .reset_index()
    .rename(columns={'sanctioned_state_iso3': 'country_iso3'})
)

outgoing_sanctions = (
    panel.groupby(['sanctioning_state_iso3', 'year'])
    .agg(
        num_targets_sanctioned=('sanctioned_state', 'nunique'),
        num_targets_sanctioned_gw=('sanctioned_gwcode', 'nunique'),
        n_arms_sent=('arms', 'sum'),
        n_military_sent=('military', 'sum'),
        n_trade_sent=('trade', 'sum'),
        n_financial_sent=('financial', 'sum'),
        n_travel_sent=('travel', 'sum'),
        n_other_sent=('other', 'sum'),
    )
    .reset_index()
    .rename(columns={'sanctioning_state_iso3': 'country_iso3'})
)
# REMOVED 2026-10-20: the original notebook set all received counts of Slovenia
# 1991-1996 to 0. Removed after checking that the UN arms embargo (res. 713) covered
# the whole territory of former Yugoslavia, incl. Slovenia, until 1996 (see data/README.md, S3).

# =====================================================================
# STEP 5b — ADDED 2026-10-20: case-based alternative measures (received side)
# =====================================================================
# num_sanctioners counts senders, and GSDB codes a UN (or EU) case as one row per
# member state, so it jumps to ~190 under any UN regime. These measures count CASES
# (sanction episodes) and mark who imposed them (sender of the case in GSDB_V4.csv).
case_sender = pd.read_csv(RAW / "GSDB_V4.csv").set_index("case_id")["sanctioning_state"].astype(str)
sender_tokens = case_sender.str.split(r",\s*")
is_un = sender_tokens.apply(lambda t: "UN" in t)
is_eu = sender_tokens.apply(lambda t: bool({"EU", "EEC"} & set(t)))
is_us = sender_tokens.apply(lambda t: "United States" in t)
is_ru = sender_tokens.apply(lambda t: bool({"Russia", "Soviet Union"} & set(t)))   # ADDED 2026-10-20

rc = panel[["sanctioned_state_iso3", "year", "case_id"]].copy()
rc["case"] = rc["case_id"].astype(str).str.split(",")
rc = rc.explode("case")
rc["case"] = rc["case"].str.strip().astype(int)
assert rc["case"].isin(case_sender.index).all(), "case id missing in GSDB_V4.csv"
rc = rc.drop_duplicates(["sanctioned_state_iso3", "year", "case"])
rc["un"], rc["eu"], rc["us"] = rc["case"].map(is_un), rc["case"].map(is_eu), rc["case"].map(is_us)
rc["ru"] = rc["case"].map(is_ru)
cases_cy = (rc.groupby(["sanctioned_state_iso3", "year"])
              .agg(n_cases_received=("case", "nunique"),
                   un_sanction=("un", "max"), eu_sanction=("eu", "max"), us_sanction=("us", "max"),
                   ru_sanction=("ru", "max"))
              .reset_index().rename(columns={"sanctioned_state_iso3": "country_iso3"}))
cases_cy["any_sanction"] = (cases_cy["n_cases_received"] > 0).astype(int)
for c in ["un_sanction", "eu_sanction", "us_sanction", "ru_sanction"]:
    cases_cy[c] = cases_cy[c].astype(int)
received_sanctions = received_sanctions.merge(cases_cy, on=["country_iso3", "year"], how="left")
print("case-based measures: target-years", len(cases_cy), "| with UN case:", int(cases_cy["un_sanction"].sum()),
      "| EU:", int(cases_cy["eu_sanction"].sum()), "| US:", int(cases_cy["us_sanction"].sum()),
      "| Russia/SU:", int(cases_cy["ru_sanction"].sum()))

# =====================================================================
# STEP 5c — ADDED 2026-10-20: FLOWS — new and lifted cases (received side)
# =====================================================================
# n_cases_received is a stock (cases in force). For dynamic models (panel VAR,
# Granger tests) we need events: cases that START or END for a target in year t.
# Built from the cleaned dyadic data (after all drop/recode/Yugoslavia rules), so
# that  n_cases(t) = n_cases(t-1) + n_new_cases(t) - n_lifted_cases(t)  holds for
# every state that exists in t-1 and t (checked below), with
#   n_cases(t) = n_cases(t-1) + n_new_cases(t) + n_joined_cases(t) - n_lifted_cases(t).
#   new    : case in force for the target in t, not in t-1, and the case BEGINS in t
#            (GSDB_V4.csv `begin` = t). This is the sanction decision (the event).
#   joined : case in force for the target in t, not in t-1, but begun earlier, for a
#            state that existed in t-1: the state became a target of an existing
#            group case (CoCom/Comecon successors 1992, EU accession 2004/07/13 under
#            case 559, ...). Not a new decision -> kept separate from `new`.
#   (inherited, not counted: a state entering the panel with cases begun earlier,
#    e.g. Serbia 2006, Czech Rep. 1993, cases begun before 1950.)
#   lifted : case in force in t-1 but not in t, for a state that still exists in t
#            (dated to the first year WITHOUT the case; normally GSDB `end` = t-1;
#            also covers leaving a targeted group, e.g. Mauritania/ECOWAS 2000, UK/EU 2021).
# Same logic as GSDB-R4 (Yalcin et al. 2024, Fig. 1 and Fig. 6b: new vs existing cases).
case_info = pd.read_csv(RAW / "GSDB_V4.csv").set_index("case_id")
obj_tokens = case_info["objective"].astype(str).str.split(r",\s*")
CONFLICT_OBJ = {"end_war", "territorial_conflict", "prevent_war"}
is_conflict_obj = obj_tokens.apply(lambda t: bool(CONFLICT_OBJ & set(t)))

fl = rc[["sanctioned_state_iso3", "year", "case"]].reset_index(drop=True)
fl["yr"] = pd.to_datetime(fl["year"]).dt.year
active = set(zip(fl["sanctioned_state_iso3"], fl["case"], fl["yr"]))
exists = set(zip(gw_cw["iso3c"], pd.to_datetime(gw_cw["year"]).dt.year))
FIRST_YEAR = 1950

def _existed_before(iso, t):
    return t - 1 >= FIRST_YEAR and (iso, t - 1) in exists

fl["prev"] = [(i, c, t - 1) in active for i, c, t in zip(fl["sanctioned_state_iso3"], fl["case"], fl["yr"])]
fl["begins"] = fl["case"].map(case_info["begin"]).eq(fl["yr"])
fl["existed_prev"] = [_existed_before(i, t) for i, t in zip(fl["sanctioned_state_iso3"], fl["yr"])]
fl["is_new"] = ~fl["prev"] & fl["begins"]
fl["joined"] = ~fl["prev"] & ~fl["begins"] & fl["existed_prev"]
fl["inherited"] = ~fl["prev"] & ~fl["begins"] & ~fl["existed_prev"]
print("case-target starts: new (case begins that year):", int(fl["is_new"].sum()),
      "| joined (existing case extended to the state):", int(fl["joined"].sum()),
      "| inherited at panel entry (not counted):", int(fl["inherited"].sum()))
print("joined, by case:", fl[fl["joined"]].groupby("case").size().to_dict())

new = fl[fl["is_new"]].copy()
for flag, ser in [("un", is_un), ("eu", is_eu), ("us", is_us)]:
    new[flag] = new["case"].map(ser)
new["arms"] = new["case"].map(case_info["arms"]).eq(1)
new["conflict_obj"] = new["case"].map(is_conflict_obj)
new_cy = (new.groupby(["sanctioned_state_iso3", "year"])
             .agg(n_new_cases=("case", "nunique"),
                  new_un_sanction=("un", "max"), new_eu_sanction=("eu", "max"), new_us_sanction=("us", "max"),
                  new_arms_sanction=("arms", "max"), new_conflict_obj_sanction=("conflict_obj", "max"))
             .reset_index())

# ADDED 2026-11-09: case-level file of NEW case-target-years, so that the empirics can build
# alternative sanction measures without re-running the pipeline (e.g. US cases only, without
# the ICC group case 685, by sanction type or objective). Does not change any other output.
new_cases_out = new[["sanctioned_state_iso3", "yr", "case", "un", "eu", "us", "arms", "conflict_obj"]].copy()
new_cases_out = new_cases_out.rename(columns={"sanctioned_state_iso3": "country_iso3", "yr": "year"})
for col in ["sanctioning_state", "trade", "descr_trade", "military", "financial", "travel", "other",
            "target_mult", "objective", "success"]:
    new_cases_out[col] = new_cases_out["case"].map(case_info[col])
for col in ["un", "eu", "us", "arms", "conflict_obj"]:
    new_cases_out[col] = new_cases_out[col].astype(int)
new_cases_out = new_cases_out.sort_values(["country_iso3", "year", "case"]).reset_index(drop=True)
new_cases_out.to_csv(OUT / "gsdb_new_cases.csv", index=False)
print("Wrote", OUT / "gsdb_new_cases.csv", new_cases_out.shape,
      "| case 685 (US, ICC signatories) new targets:", int(new_cases_out["case"].eq(685).sum()))

lift = fl[["sanctioned_state_iso3", "case", "yr"]].copy()
lift["yr"] = lift["yr"] + 1                                    # candidate first year without the case
lift = lift[[(i, c, t) not in active and (i, t) in exists and t <= fl["yr"].max()
             for i, c, t in zip(lift["sanctioned_state_iso3"], lift["case"], lift["yr"])]]
lift["year"] = pd.to_datetime(lift["yr"].astype(str), format="%Y")
lift_cy = (lift.groupby(["sanctioned_state_iso3", "year"])
               .agg(n_lifted_cases=("case", "nunique")).reset_index())
print("lifted case-target ends:", len(lift), "| GSDB end = year-1 for", int(lift["case"].map(case_info["end"]).eq(lift["yr"] - 1).sum()))

flows = (new_cy.merge(lift_cy, on=["sanctioned_state_iso3", "year"], how="outer")
               .rename(columns={"sanctioned_state_iso3": "country_iso3"}))
FLOW_COLS = ["n_new_cases", "n_lifted_cases", "new_un_sanction", "new_eu_sanction", "new_us_sanction",
             "new_arms_sanction", "new_conflict_obj_sanction"]
orig_dtypes = received_sanctions.dtypes.to_dict()
joined_cy = (fl[fl["joined"]].groupby(["sanctioned_state_iso3", "year"])
                .agg(n_joined_cases=("case", "nunique")).reset_index()
                .rename(columns={"sanctioned_state_iso3": "country_iso3"}))
flows = flows.merge(joined_cy, on=["country_iso3", "year"], how="outer")
FLOW_COLS.insert(2, "n_joined_cases")
received_sanctions = received_sanctions.merge(flows, on=["country_iso3", "year"], how="outer")
n_lift_only = int(received_sanctions["num_sanctioners"].isna().sum())
print("country-years with lifted cases but no case in force (rows added, counts = 0):", n_lift_only)
received_sanctions = received_sanctions.fillna({c: 0 for c in received_sanctions.columns
                                                if c not in ("country_iso3", "year")})
received_sanctions["new_sanction"] = (received_sanctions["n_new_cases"] > 0).astype(int)
received_sanctions["lifted_sanction"] = (received_sanctions["n_lifted_cases"] > 0).astype(int)
FLOW_COLS += ["new_sanction", "lifted_sanction"]
for c in received_sanctions.columns:              # keep the original columns' dtypes (values unchanged)
    if c not in ("country_iso3", "year"):
        received_sanctions[c] = received_sanctions[c].astype(orig_dtypes.get(c, "int64"))
received_sanctions = received_sanctions.sort_values(["country_iso3", "year"]).reset_index(drop=True)

# identity check: stock(t) = stock(t-1) + new(t) - lifted(t) for states existing in t-1 and t
chk = received_sanctions[["country_iso3", "year", "n_cases_received", "n_new_cases", "n_joined_cases", "n_lifted_cases"]].copy()
chk["yr"] = pd.to_datetime(chk["year"]).dt.year
full = pd.DataFrame(sorted(exists), columns=["country_iso3", "yr"])
full = full[full["yr"] >= FIRST_YEAR].merge(chk.drop(columns="year"), on=["country_iso3", "yr"], how="left").fillna(0)
full = full.sort_values(["country_iso3", "yr"])
full["stock_prev"] = full.groupby("country_iso3")["n_cases_received"].shift()
full["yr_prev"] = full.groupby("country_iso3")["yr"].shift()
cont = full[full["yr_prev"].eq(full["yr"] - 1)]
bad = cont[cont["n_cases_received"] != cont["stock_prev"] + cont["n_new_cases"] + cont["n_joined_cases"] - cont["n_lifted_cases"]]
print("stock-flow identity violations:", len(bad), "of", len(cont), "continuing state-years")
assert bad.empty, bad.head(20).to_string()
print("flows: state-years with a new case", int(received_sanctions["new_sanction"].sum()),
      "| with a lifted case", int(received_sanctions["lifted_sanction"].sum()))
# validation against GSDB-R4 Fig. 6(b): Russia 2022 = 25 new, 38 in force
ru = received_sanctions[received_sanctions["country_iso3"].eq("RUS")]
print("Russia 2014-2023 (in force / new / lifted):")
print(ru[pd.to_datetime(ru["year"]).dt.year >= 2014][["year", "n_cases_received", "n_new_cases", "n_joined_cases", "n_lifted_cases"]].to_string(index=False))

# duplicate check (printed to the log; should be empty)
dup_mask = received_sanctions.duplicated(subset=["year", "country_iso3"], keep=False)
print("duplicate country-years in received:", int(dup_mask.sum()))
print("target-years where name count != gwcode count:",
      int((received_sanctions["num_sanctioners"] != received_sanctions["num_sanctioners_gw"]).sum()), "of", len(received_sanctions))
print("sender-years where name count != gwcode count:",
      int((outgoing_sanctions["num_targets_sanctioned"] != outgoing_sanctions["num_targets_sanctioned_gw"]).sum()), "of", len(outgoing_sanctions))

received_sanctions.to_csv(OUT / "gsdb_received.csv", index=False)
outgoing_sanctions.to_csv(OUT / "gsdb_sent.csv", index=False)
print("Wrote", OUT / "gsdb_received.csv", received_sanctions.shape)
print("Wrote", OUT / "gsdb_sent.csv", outgoing_sanctions.shape)
