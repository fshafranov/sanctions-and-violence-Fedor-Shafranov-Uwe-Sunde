"""Write the world map used by the dashboard as dashboard/page/world.js.

Source: Natural Earth 1:110m countries ("naturalearth_lowres"), as shipped with pyogrio in the
project venv, so nothing is downloaded. Each country shape gets rules that say which Gleditsch-Ward
code (UCDP country_id) it shows in which years, so that e.g. South Sudan is drawn as part of Sudan
before 2011 and Serbia, Montenegro and Kosovo as Yugoslavia (345) before 2006.

Run: uv run python dashboard/build_world_geometry.py
"""

import json
from pathlib import Path

import geopandas as gpd
import pandas as pd
import pyogrio

ROOT = Path(__file__).resolve().parents[1]
SHP = Path(pyogrio.__file__).parent / "tests/fixtures/naturalearth_lowres/naturalearth_lowres.shp"
OUT = ROOT / "dashboard" / "page" / "world.js"
END = 2100

world = gpd.read_file(SHP)
world = world[world["iso_a3"] != "ATA"]          # Antarctica: no data, takes a fifth of the map

panel = pd.read_csv(ROOT / "data/processed/sanctions_violence/sanctions_violence_panel.csv",
                    usecols=["gwcode", "iso3c", "year"], low_memory=False)
iso_to_gw = panel.dropna().drop_duplicates("iso3c", keep="last").set_index("iso3c")["gwcode"].astype(int).to_dict()

BY_NAME = {   # shapes whose iso_a3 is -99 or that UCDP files under another state
    "France": [[220, 1989, END]],
    "Norway": [[385, 1989, END]],
    "N. Cyprus": [[352, 1989, END]],
    "Somaliland": [[520, 1989, END]],
    "Kosovo": [[345, 1989, 2005], [340, 2006, 2007], [347, 2008, END]],
}
BY_ISO = {
    "SRB": [[345, 1989, 2005], [340, 2006, END]],
    "MNE": [[345, 1989, 2005], [341, 2006, END]],
    "SSD": [[625, 1989, 2010], [626, 2011, END]],
    "ERI": [[530, 1989, 1992], [531, 1993, END]],
    "VNM": [[816, 1989, END]],
    "PSE": [[666, 1989, END]],     # UCDP locates Israeli-Palestinian violence in Israel
    "ESH": [[600, 1989, END]],     # Western Sahara under Morocco
}


def rules(row):
    if row["name"] in BY_NAME:
        return BY_NAME[row["name"]]
    if row["iso_a3"] in BY_ISO:
        return BY_ISO[row["iso_a3"]]
    gw = iso_to_gw.get(row["iso_a3"])
    return [[gw, 1989, END]] if gw else []


def rnd(coords):
    if isinstance(coords[0], (int, float)):
        return [round(coords[0], 2), round(coords[1], 2)]
    return [rnd(c) for c in coords]


features = []
for _, row in world.iterrows():
    geom = json.loads(gpd.GeoSeries([row.geometry]).to_json())["features"][0]["geometry"]
    geom["coordinates"] = rnd(geom["coordinates"])
    features.append({"type": "Feature", "properties": {"n": row["name"], "r": rules(row)}, "geometry": geom})

missing = [f["properties"]["n"] for f in features if not f["properties"]["r"]]
print("shapes without a GW code:", missing)
text = "window.cdWorld = " + json.dumps({"type": "FeatureCollection", "features": features}, separators=(",", ":")) + ";\n"
OUT.write_text(text)
print(OUT, f"{len(text) / 1024:.0f} KB", len(features), "shapes")
