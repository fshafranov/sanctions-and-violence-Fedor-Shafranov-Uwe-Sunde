"""Build the standalone Plotly dashboard: dashboard/plotly/conflict_dynamics.html.

Reads the CSVs written by build_dashboard_data.py (dashboard/data/) and the map from
build_world_geometry.py (dashboard/page/world.js), computes the period summary and the heatmap
order here, and embeds everything as JSON in dashboard/plotly/template.html. The page needs no
data requests at runtime; it loads Plotly and d3 from jsDelivr / cdnjs.

Run (after the two builders above):  uv run python dashboard/build_plotly_page.py
"""

import json
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd

DASH = Path(__file__).resolve().parent
DATA = DASH / "data"
TEMPLATE = DASH / "plotly" / "template.html"
OUT = DASH / "plotly" / "conflict_dynamics.html"
PERIODS = ["1989-99", "2000-09", "2010-19", "2020-25"]


def period(y: int) -> str:
    return "1989-99" if y <= 1999 else "2000-09" if y <= 2009 else "2010-19" if y <= 2019 else "2020-25"


def nint(v):
    return None if pd.isna(v) else int(v)


years = pd.read_csv(DATA / "year_violence.csv")
conf = pd.read_csv(DATA / "conflicts_year.csv")
cy = pd.read_csv(DATA / "country_year_all.csv")
cp = pd.read_csv(DATA / "country_period.csv")
cases = pd.read_csv(DATA / "us_cases.csv")
usconf = pd.read_csv(DATA / "us_conflicts.csv")
world = (DASH / "page" / "world.js").read_text()

# --- Period summary (same definitions as the notes on the page) ------------------------------
rows = []
for p in PERIODS:
    ys = years[years["year"].apply(period) == p]
    cs = conf[(conf["year"] >= 1989) & (conf["year"].apply(period) == p)]
    us = cases[cases["period"] == p]
    in_conf = us[us["deaths_before"] >= 25]
    ep = in_conf.drop_duplicates(["country", "year"], keep="last")
    ep = ep[ep["deaths_after2"].notna() & (ep["deaths_before"] > 0)]
    change = ((ep["deaths_after2"] - ep["deaths_before"]) / ep["deaths_before"]).median() if len(ep) else np.nan
    c = cy[(cy["year"].apply(period) == p) & (cy["deaths"] >= 25) & cy["us_sanction"].notna()]
    under = c[c["us_sanction"] == 1]
    rows.append({
        "period": p,
        "deaths": int(ys["total"].sum()),
        "avg_countries": round(float(ys["countries_in_conflict"].mean()), 1),
        "wars_per_year": round(float(cs["wars"].mean()), 1),
        "us_conflict_years": int(cs["us_conflicts"].sum()),
        "us_cases": int(len(us)),
        "us_cases_conflict": int(len(in_conf)),
        "us_conflict_obj": int(us["conflict_obj"].sum()),
        "us_force_cy_pct": round(100 * len(under) / len(c)) if len(c) else None,
        "us_force_deaths_pct": round(100 * under["deaths"].sum() / c["deaths"].sum()) if len(c) else None,
        "median_change_pct": None if pd.isna(change) else round(100 * change),
    })
summary = pd.DataFrame(rows)
print(summary.to_string(index=False))

# --- Country lookup and compact country-year rows ---------------------------------------------
countries = cy.drop_duplicates("gwcode").set_index("gwcode")[["country", "region"]]
cy_rows = [[int(r.gwcode), int(r.year), int(r.deaths), int(r.state_based), int(r.non_state), int(r.one_sided),
            int(r.us_new_cases), nint(r.us_sanction), int(r.us_party)] for r in cy.itertuples()]

# Heatmap: 40 deadliest countries since 1989, ordered by deaths-weighted mean year
tot = cy.groupby("gwcode")["deaths"].sum().nlargest(40)
mid = (cy[cy["gwcode"].isin(tot.index)].assign(w=lambda d: d["deaths"] * d["year"])
       .groupby("gwcode").apply(lambda d: d["w"].sum() / d["deaths"].sum(), include_groups=False))
heat_order = [int(g) for g in mid.sort_values().index]

top = cp[cp["rank"] <= 12][["gwcode", "period", "deaths", "peak_year", "us_new_cases", "us_party_years", "rank"]]
top_rows = [[int(r.gwcode), r.period, int(r.deaths), nint(r.peak_year), int(r.us_new_cases), int(r.us_party_years), int(r.rank)]
            for r in top.itertuples()]

payload = {
    "built": date.today().isoformat(),
    "years": years.astype(object).where(years.notna(), None).to_dict("records"),
    "conflicts": conf.to_dict("records"),
    "periods": summary.astype(object).where(summary.notna(), None).to_dict("records"),
    "countries": {int(g): [r.country, r.region] for g, r in countries.iterrows()},
    "cy_cols": ["gw", "year", "deaths", "sb", "ns", "os", "us_new", "us_force", "us_party"],
    "cy": cy_rows,
    "heat_order": heat_order,
    "top": top_rows,
    "cases": cases.astype(object).where(cases.notna(), None).to_dict("records"),
    "usconf": usconf.to_dict("records"),
}
blob = json.dumps(payload, separators=(",", ":"), default=lambda o: o.item() if hasattr(o, "item") else str(o))
blob = blob.replace("</", "<\\/")

html = TEMPLATE.read_text()
assert "__DATA__" in html and "__WORLD__" in html
html = html.replace("__DATA__", blob).replace("__WORLD__", world.replace("</", "<\\/"))
OUT.write_text(html)
print(OUT, f"{len(html) / 1024:.0f} KB")
