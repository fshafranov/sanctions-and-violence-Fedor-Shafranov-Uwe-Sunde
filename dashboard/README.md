# Conflict dynamics dashboard

Exploration page for how organized violence, US conflict participation and US sanctions changed over 1989–2025
(question behind it: why the US sanction effect on deaths is concentrated in 1991–2009, notes/13 sections 5–7).
Descriptive only; nothing here feeds the estimation.

**Live page (current):** https://claude.ai/artifact/Y319frVGvn6JgWuWZWLxf7 — plain HTML + Plotly, private
(share from the page's Share menu).
**Older version:** https://claude.ai/artifact/5WW6ZmKtA14iAmm1wm7d7Z — built on claude.ai's "Data" dashboard type
(source panel per number), laggy with this much interaction; superseded, kept for reference.

## Build (run in order from the project root)

```bash
uv run python dashboard/build_dashboard_data.py   # -> dashboard/data/*.csv
uv run python dashboard/build_world_geometry.py   # -> dashboard/page/world.js
uv run python dashboard/build_plotly_page.py      # -> dashboard/plotly/conflict_dynamics.html
```

Then republish `dashboard/plotly/conflict_dynamics.html` to the same artifact URL (ask Claude, pass the URL).
Not part of `master.py` (outputs are not used by the analysis).

| File | Role |
|---|---|
| `build_dashboard_data.py` | UCDP OV country-year (`data/clean/ucdp_ov`), UCDP/PRIO conflicts (`data/raw/ucdp_prio`), GSDB new cases (`data/clean/gsdb`), panel `us_sanction` → seven CSVs in `data/` |
| `build_world_geometry.py` | Natural Earth 1:110m from the pyogrio test fixture in `.venv` (no download), with GW-code rules by year (South Sudan → Sudan before 2011, Eritrea → Ethiopia before 1993, Serbia/Montenegro/Kosovo → Yugoslavia 345 before 2006, Palestine → Israel, W. Sahara → Morocco) |
| `build_plotly_page.py` | period summary + heatmap order computed in Python, all data embedded as JSON in `plotly/template.html` |
| `plotly/template.html` | the page source (edit this, then rebuild) |
| `page/index.html` | page source of the older Data-type version |
| `dev/` | `harness.html` + `bundle_harness.py`: stand-in for the Data-type runtime to time the old page locally; `plotly_preview.html` (git-ignored) = local preview of the Plotly page with a doctype wrapper |

## Panel "Who the US sanctioned in a year" (added 16 Nov 2026)

`build_dashboard_data.py` step 6 writes `data/us_active.csv`: every GSDB case with the United States among the senders
in force against a target per year 1989–2023 (from `data/clean/gsdb/gsdb_case_senders.csv`, after the cleaning
rules), status new / ongoing / joined / inherited, plus lifted (first year without the case). Matches the panel's
`us_sanction` exactly (checked in the script). ICC case 685 hidden by default (checkbox).

## Definitions (also on the page, "Definitions and data")

- Deaths = UCDP organized violence best estimate (state-based + non-state + one-sided), by country of location.
- Country in conflict = ≥ 25 deaths in the year.
- US a party = GW code 2 as side A/B (primary) or secondary warring party in UCDP/PRIO v26.1; country = among the
  conflict's `gwno_loc`.
- New US case = GSDB V4 case with the US among senders, start year, target as named by GSDB, without ICC case 685
  (= the LP shock). UN cases are not US cases. US sanction in force = panel `us_sanction`. GSDB ends 2023.
- Change in target deaths = deaths t+2 vs t−1 for US cases on targets with ≥ 25 deaths in t−1, one per country-year.

## Findings it surfaced (16 Nov 2026)

| Period | Conflict country-years under a US sanction in force | Conflict deaths under one | US conflict-years |
|---|---|---|---|
| 1989–99 | 46% | 31% (≈ 61% without Rwanda 1994) | 3 |
| 2000–09 | 62% | 54% | 25 |
| 2010–19 | 62% | 85% | 64 |
| 2020–23 | 78% | 94% | 45 (to 2025) |

1990s US cases often hit conflicts with no US sanction yet; later nearly every deadly conflict already had one, so a
new case is an increment. Consistent with the larger 1990s LP effect — a reading, not a test.
Bosnia: US arms embargo case 422 (1991) is dated to Yugoslavia; Bosnia carries it in force 1992–96 (attribution rules,
`data/README_yugoslavia.md`) but has no new US case; UN case 470 targeted Belgrade; UCDP never codes the US as a party
in Bosnia (Kosovo 1999 is under Serbia).

## Design notes

- Colors: three violence types = reference palette slots 1–3 (validated all-pairs, light and dark); every US mark in
  ink, because no fourth hue passes the colour-blindness checks next to them. Map/heatmap: one-hue blue log scale.
- Performance: year changes coalesced to one redraw per animation frame; map shapes built once per width and only
  recoloured; `Plotly.react` for updates. 30-step slider drag at 1600px: no long tasks.
- Not yet checked: phone width and dark mode on the live page; the "Deadliest countries" chart measured 240px tall once
  (expected ≈ 390px) — check.
