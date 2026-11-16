"""Bundle dev/harness.html with the dashboard's data, page and map into one self-contained HTML file.

The harness stands in for the claude.ai dashboard runtime (dash.data / dash.draw / dash.calc) so the page
can be opened and timed locally. Output: the path given as argv[1] (default dashboard/dev/harness_bundle.html).
Run: uv run python dashboard/dev/bundle_harness.py [out.html]
"""

import json
import sys
from pathlib import Path

DASH = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else DASH / "dev" / "harness_bundle.html"

harness = (DASH / "dev" / "harness.html").read_text()
files = {p.stem: p.read_text() for p in sorted((DASH / "data").glob("*.csv"))}
page = (DASH / "page" / "index.html").read_text()
world = (DASH / "page" / "world.js").read_text()

inline = (
    "<script>window.__CSV = " + json.dumps(files) + ";\nwindow.__PAGE = " + json.dumps(page).replace("</", "<\\/") + ";</script>\n"
    "<script>" + world + "</script>\n"
)
harness = harness.replace(
    "await (await fetch('../data/' + id + '.csv')).text()", "window.__CSV[id]"
).replace(
    "await (await fetch('../page/index.html')).text()", "window.__PAGE"
).replace(
    "if (s.src) { await new Promise((res) => { const n = document.createElement('script'); n.src = '../page/' + s.getAttribute('src'); n.onload = res; document.body.appendChild(n); }); }",
    "if (s.src) { /* world.js is inlined above */ }",
).replace("</head>", inline + "</head>")
assert "window.__CSV[id]" in harness and "world.js is inlined" in harness
out.write_text(harness)
print(out, f"{out.stat().st_size / 1024:.0f} KB")
