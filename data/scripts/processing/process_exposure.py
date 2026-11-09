"""
process_exposure.py — trade, capital-flow and arms exposure of each state-year to the US, the EU, the UN and the
actual senders of the year's new sanction cases.
ADDED 2026-11-09 (data/README.md, section 4c, X1-X8; user decisions T5, O1-O4).

Input : data/clean/base/base.csv                 GW state-years
        data/clean/imf/imts_dyadic.csv.gz         directed goods flows (flow_avg = mean of both reporting sides)
        data/clean/wdi/wdi_cy.csv                 trade/FDI % GDP, GDP current US$
        data/clean/sipri/sipri_tiv_dyadic.csv     arms deliveries supplier -> recipient (TIV)
        data/clean/gsdb/gsdb_new_cases.csv        new case-target-years
        data/clean/gsdb/gsdb_case_senders.csv     case x sender x target x year (cleaned GSDB dyads)
Output: data/processed/exposure/exposure_cy.csv  one row per GW state-year (merged into the panel by
                                                 process_sanctions_violence.py)

Sender groups (X2):
  us      : United States (GW 2)
  eu      : EU/EC member states in that year (EU_ACCESSION below; UK member to 2019)
  un      : all states = the target's total goods trade (a UN case has every UN member as sender in GSDB, e.g.
            183 senders for case 548), so un exposure equals total exposure by construction
  senders : all senders of the target's NEW cases in year t (GSDB dyads of those cases in t); only defined in years
            with a new case. Exposure is measured over t-3..t-1 to that fixed set of states.

Measures per group g (X3):
  trade_<g>_gdp    goods trade with g (exports + imports, IMF flow_avg) / target GDP (current US$, WDI), in %
  trade_<g>_share  goods trade with g / target's total goods trade (IMF), in %
  arms_<g>_tiv     arms delivered from g to the target (SIPRI TIV, millions)
  arms_<g>_share   arms from g / target's total arms imports, in % (missing when total arms imports are 0)
General: trade_gdp, exports_gdp, imports_gdp, fdi_in_gdp (WDI, goods and services), goods_trade_gdp (IMF),
  arms_imports_tiv (all SIPRI suppliers incl. non-state and unknown), arms_supplier_hhi (0-1, over the window's
  supplier totals), arms_to_rebels_tiv (deliveries to non-state groups hosted in the state, O2).

Timing (X4, user T5): base = mean over t-3..t-1 of the yearly values (mean of the available years; the number of
  years used is kept for the trade measures: trade_years); suffix _l1 = value in t-1; _t = value in t.
Zeros vs missing (X5, user 9 Nov): a target with IMF data in a year (any recorded flow) but no flow with group g
  has trade with g = 0 (base); a target without any IMF flow that year is missing. Robustness (NA version): treat
  values with trade_<g>_zero_imputed > 0 (number of window years set to 0; _t for year t) as missing. Arms: no SIPRI delivery = 0, flag
  arms_no_sipri_record = 1 (user T5). Shares are missing when the denominator is 0 or missing.
"""
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[3]
CLEAN = ROOT / "data" / "clean"
OUT = ROOT / "data" / "processed" / "exposure"
OUT.mkdir(parents=True, exist_ok=True)
FIRST_YEAR, LAST_YEAR = 1950, 2023
US = 2
# EC/EU accession year (ISO3 as in the base); United Kingdom left on 31 Jan 2020 -> member up to 2019
EU_ACCESSION = {"BEL": 1958, "FRA": 1958, "DEU": 1958, "ITA": 1958, "LUX": 1958, "NLD": 1958, "DNK": 1973,
                "IRL": 1973, "GBR": 1973, "GRC": 1981, "ESP": 1986, "PRT": 1986, "AUT": 1995, "FIN": 1995,
                "SWE": 1995, "CYP": 2004, "CZE": 2004, "EST": 2004, "HUN": 2004, "LVA": 2004, "LTU": 2004,
                "MLT": 2004, "POL": 2004, "SVK": 2004, "SVN": 2004, "BGR": 2007, "ROU": 2007, "HRV": 2013}
EU_EXIT = {"GBR": 2020}

base = pd.read_csv(CLEAN / "base" / "base.csv", usecols=["gwcode", "year", "iso3c"])
base["year"] = base["year"].astype(str).str[:4].astype(int)
base = base[base.year.between(FIRST_YEAR, LAST_YEAR)]
eu_members = {(gw, y) for gw, y, iso in base.itertuples(index=False)
              if iso in EU_ACCESSION and EU_ACCESSION[iso] <= y < EU_EXIT.get(iso, 9999)}

# --- 1. Yearly building blocks: trade and arms with every partner -------------------------------
flows = pd.read_csv(CLEAN / "imf" / "imts_dyadic.csv.gz", usecols=["origin_gwcode", "destination_gwcode", "year", "flow_avg"])
trade = pd.concat([  # undirected: target i, partner j, exports + imports
    flows.rename(columns={"origin_gwcode": "gwcode", "destination_gwcode": "partner"}),
    flows.rename(columns={"destination_gwcode": "gwcode", "origin_gwcode": "partner"}),
]).groupby(["gwcode", "partner", "year"], as_index=False)["flow_avg"].sum()
trade_total = trade.groupby(["gwcode", "year"])["flow_avg"].sum().rename("goods_trade_usd")

tiv = pd.read_csv(CLEAN / "sipri" / "sipri_tiv_dyadic.csv")
arms = (tiv.dropna(subset=["recipient_gwcode"]).astype({"recipient_gwcode": int})
           .rename(columns={"recipient_gwcode": "gwcode", "supplier_gwcode": "partner"}))
arms_total = arms.groupby(["gwcode", "year"])["tiv"].sum().rename("arms_imports_tiv")
rebels = (tiv[tiv.recipient_type.eq("non_state") & tiv.recipient_host_gwcode.notna()]
             .astype({"recipient_host_gwcode": int})
             .groupby(["recipient_host_gwcode", "year"])["tiv"].sum().rename("arms_to_rebels_tiv"))
rebels.index.names = ["gwcode", "year"]

wdi = pd.read_csv(CLEAN / "wdi" / "wdi_cy.csv").set_index(["gwcode", "year"])
yearly = base[["gwcode", "year"]].set_index(["gwcode", "year"])
yearly = yearly.join(wdi[["trade_pct_gdp", "exports_pct_gdp", "imports_pct_gdp", "fdi_inflows_pct_gdp",
                          "gdp_current_usd"]]).join(trade_total).join(arms_total).join(rebels)
yearly["arms_no_sipri_record"] = yearly["arms_imports_tiv"].isna().astype(int)
yearly[["arms_imports_tiv", "arms_to_rebels_tiv"]] = yearly[["arms_imports_tiv", "arms_to_rebels_tiv"]].fillna(0)
yearly["goods_trade_gdp"] = 100 * yearly["goods_trade_usd"] / yearly["gdp_current_usd"]


def with_group(table, value, members_of):
    """Yearly sum of `value` with the partners in a group: members_of(gwcode, year) -> set of partner GW codes."""
    keep = [p in members_of(g, y) for g, p, y in zip(table.gwcode, table.partner, table.year)]
    return table[keep].groupby(["gwcode", "year"])[value].sum()


# --- 2. Group exposures per year (us, eu, un) ----------------------------------------------------
eu_by_year = {}
for (p, y) in eu_members:
    eu_by_year.setdefault(y, set()).add(p)
groups = {"us": lambda g, y: {US}, "eu": lambda g, y: eu_by_year.get(y, set())}   # un = total, below

for name, members_of in groups.items():
    yearly[f"trade_{name}_usd"] = with_group(trade, "flow_avg", members_of)
    yearly[f"arms_{name}_tiv"] = with_group(arms.dropna(subset=["partner"]).astype({"partner": int}), "tiv", members_of)
yearly["trade_un_usd"] = yearly["goods_trade_usd"]
yearly["arms_un_tiv"] = yearly["arms_imports_tiv"]

has_trade_data = yearly["goods_trade_usd"].notna()
for name in ["us", "eu", "un"]:
    # X5 (user 9 Nov): no recorded flow with g although the target has IMF data that year -> 0 (base);
    # flagged, so the robustness version can treat these values as missing
    yearly[f"trade_{name}_zero_imputed"] = (has_trade_data & yearly[f"trade_{name}_usd"].isna()).astype(int)
    yearly.loc[has_trade_data, f"trade_{name}_usd"] = yearly.loc[has_trade_data, f"trade_{name}_usd"].fillna(0)
    yearly[f"arms_{name}_tiv"] = yearly[f"arms_{name}_tiv"].fillna(0)


def ratios(frame, name):
    frame[f"trade_{name}_gdp"] = 100 * frame[f"trade_{name}_usd"] / frame["gdp_current_usd"]
    frame[f"trade_{name}_share"] = 100 * frame[f"trade_{name}_usd"] / frame["goods_trade_usd"]
    frame[f"arms_{name}_share"] = 100 * frame[f"arms_{name}_tiv"] / frame["arms_imports_tiv"].where(frame["arms_imports_tiv"] > 0)
    return frame


for name in ["us", "eu", "un"]:
    yearly = ratios(yearly, name)
yearly = yearly.reset_index()

# --- 3. Window values: mean over t-3..t-1, t-1, t -------------------------------------------------
def lagged(frame, column, k):
    shifted = frame[["gwcode", "year", column]].assign(year=frame["year"] + k)
    return frame[["gwcode", "year"]].merge(shifted, on=["gwcode", "year"], how="left")[column].to_numpy()


GENERAL = {"trade_pct_gdp": "trade_gdp", "exports_pct_gdp": "exports_gdp", "imports_pct_gdp": "imports_gdp",
           "fdi_inflows_pct_gdp": "fdi_in_gdp", "goods_trade_gdp": "goods_trade_gdp",
           "arms_imports_tiv": "arms_imports_tiv", "arms_to_rebels_tiv": "arms_to_rebels_tiv"}
GROUPED = [f"{m}_{g}_{s}" for g in ["us", "eu", "un"] for m, s in
           [("trade", "gdp"), ("trade", "share"), ("arms", "tiv"), ("arms", "share")]]
out = yearly[["gwcode", "year"]].copy()
for source, target in list(GENERAL.items()) + [(c, c) for c in GROUPED]:
    window = np.column_stack([lagged(yearly, source, k) for k in (1, 2, 3)])
    with np.errstate(all="ignore"):
        out[target] = pd.DataFrame(window).mean(axis=1, skipna=True).to_numpy()   # mean of available years
    out[f"{target}_l1"] = window[:, 0]
    out[f"{target}_t"] = yearly[source].to_numpy()
for name in ["us", "eu"]:   # number of window years (t-3..t-1) in which trade with g was set to 0 (X5); _t for t
    out[f"trade_{name}_zero_imputed"] = np.nansum(np.column_stack([lagged(yearly, f"trade_{name}_zero_imputed", k)
                                                                   for k in (1, 2, 3)]), axis=1).astype(int)
    out[f"trade_{name}_zero_imputed_t"] = yearly[f"trade_{name}_zero_imputed"].to_numpy()
out["trade_years"] = np.column_stack([~np.isnan(lagged(yearly, "goods_trade_usd", k)) for k in (1, 2, 3)]).sum(axis=1)
out["arms_no_sipri_record"] = lagged(yearly, "arms_no_sipri_record", 1)          # flag for t-1
out["arms_no_sipri_record_t"] = yearly["arms_no_sipri_record"].to_numpy()

# supplier concentration (HHI) of arms imports over the window t-3..t-1
window_arms = pd.concat([arms.assign(year=arms.year + k) for k in (1, 2, 3)])
window_arms["partner"] = window_arms["partner"].fillna(-1)                      # non-state/unknown suppliers pooled
shares = window_arms.groupby(["gwcode", "year", "partner"])["tiv"].sum()
shares = shares / shares.groupby(level=[0, 1]).transform("sum")
hhi = (shares ** 2).groupby(level=[0, 1]).sum().rename("arms_supplier_hhi").reset_index()
out = out.merge(hhi, on=["gwcode", "year"], how="left")

# --- 4. Exposure to the actual senders of the year's new cases ------------------------------------
new_cases = pd.read_csv(CLEAN / "gsdb" / "gsdb_new_cases.csv")
senders = pd.read_csv(CLEAN / "gsdb" / "gsdb_case_senders.csv").dropna(subset=["sanctioning_gwcode", "sanctioned_gwcode"])
senders = senders.merge(new_cases[["country_iso3", "year", "case"]].rename(columns={"country_iso3": "sanctioned_state_iso3"}),
                        on=["sanctioned_state_iso3", "year", "case"])
pairs = (senders[["sanctioned_gwcode", "year", "sanctioning_gwcode"]].drop_duplicates()
         .astype(int).rename(columns={"sanctioned_gwcode": "gwcode", "sanctioning_gwcode": "partner", "year": "t"}))
pairs = pairs[pairs.gwcode != pairs.partner]
n_senders = pairs.groupby(["gwcode", "t"]).size().rename("n_sender_states")
arms_pairs = arms.dropna(subset=["partner"]).astype({"partner": int}).groupby(["gwcode", "partner", "year"],
                                                                                as_index=False)["tiv"].sum()
per_year = []
for k in (1, 2, 3):                       # value in t-k for the senders of the cases that begin in t
    p = pairs.assign(year=pairs.t - k)
    p = p.merge(trade, on=["gwcode", "partner", "year"], how="left").merge(arms_pairs, on=["gwcode", "partner", "year"], how="left")
    agg = p.groupby(["gwcode", "t", "year"]).agg(trade_s=("flow_avg", "sum"), recorded=("flow_avg", "count"),
                                                arms_s=("tiv", "sum")).reset_index()
    per_year.append(agg)
per_year = pd.concat(per_year).merge(yearly[["gwcode", "year", "goods_trade_usd", "gdp_current_usd", "arms_imports_tiv"]],
                                     on=["gwcode", "year"], how="left")
per_year.loc[per_year.goods_trade_usd.isna(), "trade_s"] = np.nan          # no IMF data that year -> missing (X5)
per_year["zero_imputed"] = (per_year.goods_trade_usd.notna() & per_year.recorded.eq(0)).astype(int)
per_year["trade_senders_gdp"] = 100 * per_year.trade_s / per_year.gdp_current_usd
per_year["trade_senders_share"] = 100 * per_year.trade_s / per_year.goods_trade_usd.where(per_year.goods_trade_usd > 0)
per_year["arms_senders_tiv"] = per_year.arms_s
per_year["arms_senders_share"] = 100 * per_year.arms_s / per_year.arms_imports_tiv.where(per_year.arms_imports_tiv > 0)
sender_exposure = (per_year.groupby(["gwcode", "t"])[["trade_senders_gdp", "trade_senders_share", "arms_senders_tiv",
                                                      "arms_senders_share"]].mean()      # mean over available years
                   .join(per_year.groupby(["gwcode", "t"])["zero_imputed"].sum().rename("trade_senders_zero_imputed"))
                   .join(n_senders).reset_index().rename(columns={"t": "year"}))
rows = sender_exposure
out = out.merge(pd.DataFrame(rows), on=["gwcode", "year"], how="left")

assert not out.duplicated(["gwcode", "year"]).any()
out.to_csv(OUT / "exposure_cy.csv", index=False)
window = out[out.year.between(1991, 2019)]
print(f"exposure: {len(out)} state-years {out.year.min()}-{out.year.max()}, {out.shape[1]} columns")
print("non-missing 1991-2019:", window[["trade_gdp", "goods_trade_gdp", "trade_us_gdp", "trade_eu_gdp",
                                        "arms_us_share", "trade_senders_gdp", "arms_supplier_hhi"]].notna().sum().to_dict())
print("sender-exposure state-years (years with a new case):", int(out["n_sender_states"].notna().sum()))
