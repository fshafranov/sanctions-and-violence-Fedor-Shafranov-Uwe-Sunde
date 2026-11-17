# 24 — The sanction effect by sender group: any sender, US, UN, Western rich

Script `empirics/scripts/24_sender_comparison.R` (≈ 17 min; runs 22 and 23 with `--shock=any|un|western`). Table
`results/tables/sender_comparison.md` / `.csv`; figures `fig45_sender_comparison.png` (all designs, h = 2 and
cumulative 0..3), `fig46_sender_lp_paths.png` (LP paths); per-group matching output in `tables/senders/`,
`figures/senders/`. User request (17 Nov): "compare UN sanctions vs US vs any sanction vs developed countries".

## Groups (new GSDB cases w/o ICC 685, 1991–2019; `shock_panel()` in functions.R)

| group | new cases | target-years | in conflict in t−1 |
|---|---|---|---|
| Any sender | 835 | 540 | 218 |
| United States (sender, almost always alone; never a UN case) | 245 | 244 | 114 |
| UN (sender "UN"; the US flag is 0 for all) | 71 | 67 | 50 |
| Western rich: **every** sender a Western rich state or the EU, UN excluded | 522 | 364 | 163 |

Western rich = OECD members of 1990 except Turkey, plus EU/EEC, Cyprus, Malta, Western European microstates (user:
"Western rich without backing from non-rich"; this drops EU cases joined by Albania, Serbia, Ukraine, Turkey etc., 38
of 128 EU cases). There were enough such cases, so the fallback ("at least one Western rich sender") was not needed.
Western rich contains the 245 US cases; the other 277 are mostly EU (84), Canada (53), Switzerland, Australia, Japan, UK.

Every design is run with the shock swapped and nothing else changed. In matching, controls are clean **for the same
group** (no new case of that group in t−2..t+3), and "in force" / "new case in t−1..t−2" refer to the group: the
comparison is "a new case of this group vs none of this group" (a UN control may have a US case). US in-force stays
the panel's `us_sanction` so the US numbers are unchanged; the US LP here equals script 21's path exactly (checked).

## Results, in conflict in t−1, h = 2 (SE) [events]

| design | Any | US | UN | Western rich |
|---|---|---|---|---|
| Base LP (D11), per case | −0.07*** [187] | **−0.25*** [85]** | −0.10 (0.09) [49] | −0.11*** [132] |
| Matched DiD (22), ATT | +0.12 (0.13) | **−0.29**** | +0.45 (0.32) [24] | −0.11 (0.12) |
| PS NN (23) | +0.04 | −0.11 | −0.22 (0.37) [30] | −0.04 |
| PS score + deaths (23) | −0.04 | −0.22 | +0.50 (0.99) [7] | +0.01 |

Extra check (not in the script): LP with Western rich cases **without the US** (277 cases, 76 shock years in wars):
h = 2 −0.110 (0.042), cumulative −0.251 (0.097); all state-years −0.042 (0.035). So the LP effect of Western rich
senders is not only the US cases.

## Reading

- **The US stands out.** It is the only group negative in every design, and the only one the matching designs
  confirm (22: −0.29**). In the LP its coefficient per case is 3–4 times the others.
- **Any sender:** small LP effect (−0.07***), zero or positive in every matching design. Adding all the other senders
  dilutes the US effect rather than adding to it.
- **Western rich:** LP −0.11*** in wars, the same size without the US cases; but matching gives ≈ 0 (−0.11 to +0.16,
  none significant). Weaker than the US and not robust to the design.
- **UN:** too few events to say anything. LP negative and growing (cumulative −0.51*, the steepest path in fig46), but
  wide; matching keeps 7–30 events and swings from −0.39 to +0.50. UN cases target the most violent conflicts (50 of
  67 target-years in conflict), where same-year clean controls are scarce.
- Per-case (LP) and per-event (matching) numbers are not on the same scale; compare signs and significance across
  groups within a design.
