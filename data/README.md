# Data construction: decisions log

Every cleaning and variable-construction decision in the pipeline, by dataset, with the script
where it happens. Kept up to date with each change (see the **Change log** at the end).
Tags: **[original]** = decision taken in the original notebooks (carried over unchanged in the
refactor); **[added YYYY-MM-DD]** = decision taken later; **[open]** = known question, not resolved.

Unit of observation everywhere: **Gleditsch–Ward (GW) state × year**. The state-year base covers 1946–2023;
the analysis panel covers **1950–2023** (11,989 country-years; see P6). Final file:
`data/processed/sanctions_violence/sanctions_violence_panel.csv`.

**Known gaps (accepted, documented):**

| Gap | Where | Details |
|---|---|---|
| GDP per capita 2020–23 missing for 12 states | P5 | no World Bank data: Abkhazia, Cuba, Eritrea, North Korea, Liechtenstein, Monaco, South Ossetia, South Sudan, **Syria**, Taiwan, **Venezuela**, **Yemen** → a model with `gdp_ext` loses these state-years after 2019 |
| GDELT ends in 2021 | G7 | GDELT measures missing for 2022–23 (all states) |
| Population 2020–23 missing for 2 states | P4 | Abkhazia, South Ossetia (no UN WPP data) |
| UCDP starts in 1989 | U4, U6 | organized-violence variables missing before 1989 |
| Yugoslavia attribution: remaining verification points | S3b, `README_yugoslavia.md` §10 | relatively resolved; controls `ex_yugo`, `ex_yugo_1991_2016` (P7) |
| GSDB covers sanctions between developing countries poorly | GSDB coverage, note below | only 78 of 1,547 cases are single-sender sanctions between developing countries (12–19 per decade) → our sanction measures are effectively sanctions by Western states and international organisations; possible cross-check with TIES (below) |
| GSDB has no counter-sanction / retaliation flag | note below | candidates + hand check in progress: `data/scripts/cleaning/gsdb_counter_sanctions_draft.csv` (not used yet) |
| Palestine: sanctions set aside, violence under Israel | S-rules (set aside), A3 | GSDB cases against Palestine (17, mostly 2023) are not counted, while UCDP and ACLED put West Bank/Gaza violence under Israel → planned "without Israel" sample check |


**Notes on GSDB coverage (added 2026-11-09).**

- *Developing-country senders.* GSDB is compiled from documented sanction regimes (UN, EU, US registers), earlier
  Western-compiled datasets and mostly English-language reporting. Sanctions by Western states and international
  organisations are recorded well; bilateral measures between developing countries (e.g. neighbours closing borders
  or banning trade) are thin: 78 of 1,547 cases are single-sender cases with sender and target outside the
  Western/major-power group; in 28 of them the target sanctioned the sender at some point (mostly long rivalries:
  India–Pakistan, India–Nepal, Malaysia–Indonesia 1963, Cambodia–Vietnam/Thailand, South Africa–Lesotho,
  Eritrea–Ethiopia). Such disputes are also often coded as conflict rather than sanctions, and in Africa reactions to
  coups come collectively from the AU/ECOWAS. Consequence: missing South–South sanctions bias the estimates only if
  they are related to violence; the paper should state that "sanctions" means sanctions by Western states and
  international organisations.
- *Multi-sender coding.* UN (and EU) cases are recorded as one row per member state, so e.g. Afghanistan appears as a
  "sender" in 85 cases, 83 of them UN cases (one own case: vs Pakistan 1961); North Korea is never a sender. The
  case-based measures (S9, S11) count a UN case once per target and are not affected; `num_sanctioners` is (S5).
- *Counter-sanctions.* No retaliation flag in GSDB; same-year moves (EU↔Russia 2014) cannot be ordered with annual
  dates. Mechanical rule (reverse dyad within ±2 years, UN cases excluded) gives 176 candidate cases, many of them
  regional-organisation cases flagged only through membership → hand classification needed (draft table above).
- *Possible solution: cross-check with TIES* (Threat and Imposition of Economic Sanctions; Morgan, Bapat & Kobayashi
  2014; 1945–2005). Event-level, includes threats as well as impositions, and records more sanctions by non-Western
  senders. Use: (i) compare GSDB and TIES South–South case counts for the overlapping years to see whether the gap is
  real or a GSDB artefact; (ii) re-run the main local projections with TIES impositions (and threats, as an
  anticipation measure) for 1989–2005. Limitation: ends in 2005, so it cannot cover the 2014 and 2020–23 waves.
  Download by the user (raw data to `data/raw/ties/`). **[open]**

---

## 1. State-year base — `data/scripts/cleaning/clean_base.R` → `data/clean/base/base.csv`

| # | Decision | Tag |
|---|---|---|
| B1 | State system = Gleditsch–Ward (`peacesciencer::create_stateyears(system = "gw")`), years 1946–2023. | [original] |
| B2 | CoW code added with `add_ccode_to_gw()`; GW letter code `gwc` joined from `states::gwstates`, keeping only years inside each state's spell (`start`–`end`), because `gwstates` can have several spells per state. | [original] |
| B3 | ISO3 (`iso3c`) from `countrycode(gwcode, "gwn", "iso3c")`. | [original] |
| B4 | Name fixes for encoding: gwcode 403 → "Sao Tome and Principe", 437 → "Ivory Coast". | [original] |
| B5 | Manual ISO3 where countrycode returns NA: microstates (DMA, GRD, LCA, VCT, ATG, KNA, MCO, LIE, AND, SMR, SYC, VUT, KIR, NRU, TON, TUV, MHL, PLW, FSM, WSM, STP, CIV) and historical states with their own period code: 315 CSK, 265 DDR, 345 YUG, 680 YMD, 678 YEM, 816 VDR, 817 VNM, 347 KSV. | [original] |
| B6 | Separate `successor_iso3c` for dissolved states (265/260→DEU, 315→CZE, 345→SRB, 680→YEM, 711→CHN, 817→VNM, 347→XKX). Not used in any merge so far. | [original] |
| B7 | Armed-conflict counts from peacesciencer's copy of UCDP/PRIO ACD (`ucdp_acd`), by `gwno_a` (government side A) and year: number of distinct `conflict_id`, all types (`n_conflicts_all`) and by `type_of_conflict` (intra 3+4, inter 2, extrasystemic 1). Missing → 0. | [original] |
| B8 | Democracy (`add_democracy`: `v2x_polyarchy`, `polity2`, `euds`, `aeuds`) and simulated GDP/population (`add_sim_gdp_pop`: `mrgdppc`, `pwtrgdp`, `pwtpop` + `sd_*`). GDP/population end in **2019**, Polity in 2020. | [original] |
| B9 | **Conflict-type counts fixed 2026-10-20.** Original filters used UCDP's numeric codes (`type_of_conflict %in% c(3,4)`, `== 2`, `== 1`), but peacesciencer stores the type as text (`"intrastate"`, `"II"` = internationalized intrastate, `"interstate"`, `"extrasystemic"`), so `n_conflicts_intra/inter/extra` were 0 everywhere (also in all original files). Filters now accept both codings; the script stops if any of the three is still all zero. **Verified on the Mac run of 2026-10-20 15:54:** country-years with ≥ 1 conflict: intra 1,745, inter 149, extra 56 (1,950 cells changed); `n_conflicts_all` unchanged. | [changed 2026-10-20] |
| B10 | **2006: only Serbia (changed 2026-10-20).** The GW list has Yugoslavia (345, to 2006) and Serbia (340, from 2006) both in 2006. The Yugoslavia-2006 row is dropped in `clean_base.R`, so 2006 is Serbia (and Montenegro, 341) only, consistent with GSDB and GDELT, which already code 2006 as Serbia. Panel: 12,309 rows. | [changed 2026-10-20] |
| B11 | **Democracy data update: `{isard}` 0.1.0 → 0.2.0 (recorded 2026-10-20).** `clean_base.R` gets democracy from `peacesciencer::add_democracy()`, which since peacesciencer 1.2.0 (CRAN 2025-07-17) takes its data from the `{isard}` package (`gw_democracy`). **peacesciencer itself did not change:** 1.2.0 both in the user's global R library and in the project environment. **What changed is `{isard}`:** the earlier outputs (baseline frozen 17:43) were built with the global library's **isard 0.1.0** (CRAN, April 2025); the project R environment (`renv.lock`, created 20 Oct 2026) installs **isard 0.2.0** (CRAN, 2026-06-25). Both versions confirmed on the Mac with `Rscript --vanilla -e 'packageVersion("isard")'` (global library) and `renv.lock`. isard 0.2.0 documents its sources as extended UDS from Marquez's `democracyData` 0.7.1 and V-Dem v15/v16 (the documentation states both); Polity unchanged. **Effect, old vs new `base.csv` (12,111 state-years with both):** `euds` correlation 0.998 (rank 0.998), but every cell changes: the extended UDS is a latent scale that is re-estimated when its sources are updated, so its location and unit move (new ≈ −0.48 + 1.11 × old, residual sd 0.066; median |diff| 0.42; 1,594 sign flips near zero); `aeuds` correlation 0.998, median |diff| 0.09 (anchored at the average democracy cut-point, so it shifts less); `v2x_polyarchy` correlation 0.9999, median |diff| 0.001 (V-Dem release revisions); `polity2` identical; `euds`/`aeuds` now non-missing in 198 more state-years. **Decision:** accept isard 0.2.0 (pinned in `renv.lock`, so reproducible from now on); no estimates used these variables yet. With country fixed effects the location shift is absorbed; only the ×1.11 scale changes the size of `euds` coefficients. To reproduce the old numbers: `renv::install("isard@0.1.0")`, then `renv::snapshot()`. Sources: peacesciencer NEWS.md (1.2.0: “add_democracy() now leans on {isard} for democracy data”), https://github.com/svmiller/peacesciencer/blob/master/NEWS.md; isard releases, https://cran.r-universe.dev/api/packages/isard; isard `gw_democracy` documentation, https://svmiller.com/isard/reference/gw_democracy.html. | [recorded 2026-10-20] |

## 2. Sanctions (GSDB v4) — `data/scripts/cleaning/clean_gsdb.py` → `data/clean/gsdb/`

Input: dyadic file `GSDB_V4_dyadic.dta` (one row = sender × target × year × case).

**Dropped rows** (if either side matches) [original]:

| Code | Rule | Reason |
|---|---|---|
| `""` | always | non-state senders/targets (e.g. terrorist organisations) |
| BYS | always | Byelorussian SSR UN seat |
| UKR | year ≤ 1990 | Ukrainian SSR UN seat |
| SVU | year ≥ 1990 | USSR tail; Russia takes over |
| RUS | year < 1990 | pre-1990 duplicates of USSR |
| KSV | year ≤ 2007 | premature Kosovo coding (case 663) |
| ARM, AZE, EST, LTU, LVA | year < 1991 | pre-independence |
| BIH, HRV, SVN | year < 1992 | pre-independence |
| SGP < 1965, GNB < 1974, MOZ < 1975 | | pre-independence |
| ERI | year < 1993 | pre-independence; US case 208 (1977–93) targets Eritrea separately from Ethiopia (case 209). Added 2026-10-20 (decision: drop, not assign to Ethiopia). |

**Set aside (kept out of the counts, not merged)** [original]: RHO (Rhodesia), PSE, HKG, ESH, VAT, MSR.
**[added 2026-10-20]** also case 179, Cyprus vs "Cyprus (Northern)" (1974–2023, 50 rows): GSDB codes Northern Cyprus as CYP,
so Cyprus would sanction itself; Northern Cyprus is not a GW state and is not separate in UCDP or GDELT either.
All set-aside rows are now saved to `data/clean/gsdb/gsdb_set_aside.csv` (Rhodesia 1,885, Palestine 887, Vatican 64,
Northern Cyprus 50, Spanish Sahara 42, Hong Kong 14, Montserrat 1).

**Self-sanctions dropped [added 2026-10-20]:** after the recoding, 9 rows have sender = target and are dropped
(listed in `data/clean/gsdb/gsdb_self_dyads_dropped.csv`): case 13 Germany → German Democratic Republic 1991–94
(GDR recoded to DEU from 1991); case 620 Serbia → Montenegro 2000–01 and case 420 Yugoslavia → Serbia/Montenegro 1991
(all YUG until 2005); case 35 South Vietnam → North Vietnam 1976 (both VDR from 1976). A state cannot sanction itself;
these are residues of merging states in the recoding.

**Recoded codes** (both sides; conditions test the original code) [original]:
DHY→BEN, HVO→BFA (and names Dahomey→Benin, Upper Volta→Burkina Faso); GIB→GBR, COK→NZL, NIU→NZL;
SVU→RUS (< 1990); SRB, MNE→YUG (≤ 2005); DDR→DEU (≥ 1991); CSK→CZE (≥ 1993); CZE, SVK→CSK (≤ 1992); VNM→VDR (≥ 1976).
Eritrea before 1993 is *not* recoded to Ethiopia; its rows are dropped (decision 2026-10-20).

**Variables** (aggregated to country-year):

| Variable | Definition | Tag |
|---|---|---|
| `num_sanctioners` | number of distinct sender **names** sanctioning the country that year | [original] |
| `num_sanctioners_gw` | number of distinct sender **GW states** (recoded ISO3 matched to `gwcode` of the base by year) | [added 2026-10-20] |
| `n_arms_received`, `n_military_received`, `n_trade_received`, `n_financial_received`, `n_travel_received`, `n_other_received` | number of sender–target–case rows with that sanction type | [original] |
| `num_targets_sanctioned` | number of distinct target **names** the country sanctions | [original] |
| `num_targets_sanctioned_gw` | number of distinct target **GW states** | [added 2026-10-20] |
| `n_*_sent` | as above, sender side | [original] |
| `n_cases_received` | number of distinct GSDB **cases** (sanction episodes) against the country that year | [added 2026-10-20] |
| `any_sanction` | 1 if the country is the target of at least one case that year | [added 2026-10-20] |
| `un_sanction`, `eu_sanction`, `us_sanction`, `ru_sanction` | 1 if at least one case against the country that year was imposed by the UN / the EU or EEC / the United States / Russia or the Soviet Union (`ru_sanction` added 2026-10-20) (sender as named in the case file `GSDB_V4.csv`; for joint cases, e.g. "EU, United States", each named sender counts) | [added 2026-10-20] |
| `n_new_cases`, `new_sanction` | **Flow.** Number of cases that **begin** in year t (GSDB `begin` = t) against the country / 1 if at least one. Main event variable for dynamic models (S11) | [added 2026-10-20] |
| `new_un_sanction`, `new_eu_sanction`, `new_us_sanction`, `new_arms_sanction`, `new_conflict_obj_sanction` | 1 if at least one new case that year was imposed by the UN / EU or EEC / US; includes an arms embargo; has a conflict-related objective (`end_war`, `territorial_conflict` or `prevent_war`) | [added 2026-10-20] |
| `n_joined_cases` | Number of cases begun **earlier** that newly cover the country in t (it joined a targeted group: Comecon successors 1992, EU accession under case 559, …). Not a sanction decision; kept so the stock–flow identity holds | [added 2026-10-20] |
| `n_lifted_cases`, `lifted_sanction` | **Flow.** Number of cases in force in t−1 but not in t (dated to the first year without the case) / 1 if at least one | [added 2026-10-20] |

| # | Decision | Tag |
|---|---|---|
| S1 | Target identified by (recoded) ISO3 code; senders counted by name in the original variables. Because names are not recoded, names and codes disagree for Serbia+Montenegro (≤2005), Germany+GDR (≥1991), North+South Vietnam (≥1976), NZ+Cook Islands+Niue, Czech Rep.+Slovakia (≤1992): name counts are higher by 1–2 in 66 target-years (received; 65 while the Slovenia rule was in place) and 1,965 sender-years (sent, mostly Yugoslavia 1992–2005). Both versions are kept. | [added 2026-10-20] |
| S2 | `_gw` counts: every sender code-year matches exactly one GW state; the script stops if an ISO3-year ever matches two states. Unmatched countries are not counted (only ERI 1977–92 as a target). | [added 2026-10-20] |
| S3 | **Slovenia:** no special zero rule (removed 2026-10-20). Since the Yugoslavia attribution (S3b), Slovenia keeps the UN/EC/EU/US **arms embargoes** 1992–96 and loses case 470 (UN trade/financial sanctions on the FRY): `num_sanctioners` 178–183, `n_trade_received`/`n_financial_received` 0. Sources and history: `data/README_yugoslavia.md`. | [changed 2026-10-20] |
| S3b | **Yugoslavia cases attributed per republic (2026-10-20).** GSDB copies the 15 "Yugoslavia" cases to all successor republics. Rule table `data/scripts/cleaning/gsdb_yugoslavia_attribution.csv`, applied in `clean_gsdb.py` step 4a: Slovenia, Croatia, Bosnia, Macedonia keep only the arms-embargo cases 419, 420, 422, 469 (as arms only; EU embargo until SVN/MKD 1996, HRV 2000, BIH 2006) and lose 421, 470, 619–621, 636–638, 660, 676, 732; Montenegro from 2006 loses all Yugoslavia cases; Serbia/Yugoslavia unchanged. 6,645 dyad-years affected (2,504 removed, 4,141 reduced to arms only); log in `data/clean/gsdb/gsdb_yugoslavia_attribution_log.csv`. **Full rules, sources, effects and open points: `data/README_yugoslavia.md`.** | [changed 2026-10-20] |
| S8 | **Kosovo**: no separate unit before independence. GW state 347 (KSV) exists from 2008. Before that Kosovo is part of Yugoslavia/Serbia (GW 345 to 2006, 340 from 2006): the 1998–2001 Kosovo-era sanctions are on "Yugoslavia" (GSDB codes SRB/MNE → recoded YUG ≤ 2005) and the 1998–99 Kosovo war deaths are under UCDP `country_id` 345. GSDB KSV rows ≤ 2007 (US case 663 from 2001) are dropped (drop rule KSV ≤ 2007); KSV rows from 2008 are kept (cases 663, 1211, 1366 as target; 1389 as sender). Open: copies of the Kosovo-era cases to BIH/HRV/MKD, see S3b. | [original], documented 2026-10-20 |
| S9 | **Alternative sanction measures (added 2026-10-20).** `num_sanctioners` counts senders, and GSDB records a UN (or EU) case as one row per member state, so the variable jumps to ~190 under any UN regime and mostly measures "under a UN/EU regime" (e.g. Haiti 2022: 192 senders but 6 cases). The case-based measures above count episodes and identify the imposing actor instead. Built in `clean_gsdb.py` step 5b, after all drop/recode/Yugoslavia rules; 0 when no case (from 1950). Means 1950–2023: `n_cases_received` 1.18 (max 46), `any_sanction` 0.43, `un_sanction` 0.04, `eu_sanction` 0.07, `us_sanction` 0.30, `ru_sanction` 0.04 (0.5–2% of states per year until 2013; 12–20% from 2014, mostly Russia's counter-sanctions on EU members, case 995, and later Western states). | [added 2026-10-20] |
| S10 | **Scan of GSDB targets (2026-10-20).** For each of the 1,547 cases, the targets in the dyadic file were compared with the target named in the case file. 36 cases have dyadic targets not named there: **(a)** the 15 "Yugoslavia" cases (fixed, S3b); **(b)** name variants only: Burma/Myanmar (127, 346, 347), Congo (584); **(c)** cases against a *group*, expanded to its members by GSDB's design: EU/EEC (205, 274, 559, 586, 995, 1239, 1240, 1339, 1449), Comecon (12, 13), League of Arab States (199), ECOWAS (599), "Western countries" (175, OAPEC oil embargo), EEU (1338), "Balkans" (663), ICC Rome Statute signatories (685). These mostly add one sender per member and are kept. **Decision 2026-10-20: kept as GSDB codes them.** Unlike Yugoslavia (S3b) and Cyprus (case 179), these are not coding errors but GSDB's documented treatment of sanctions against a group (each member is a target). Interpretation notes: **599** ECOWAS small-arms moratorium 1998–2023 gives every West African member ~15 senders for 25 years (raises `num_sanctioners` for e.g. Sierra Leone, Liberia, Côte d'Ivoire; counted once in `n_cases_received`); **13/12** CoCom and neutral states' export controls on all 26 Comecon members 1950–94 (~17–21 senders each); **685** US military-aid cut to ICC signatories 2002–08 (applied to 108 states; in practice only to non-exempt states without an Article 98 agreement). **179** Cyprus vs Northern Cyprus — resolved: set aside (see the set-aside rules above). | [decided 2026-10-20] |
| S11 | **Flow variables: new, joined and lifted cases (added 2026-10-20).** `n_cases_received` is a stock; panel VARs and Granger tests need events (cf. GSDB-R4, Yalcin et al. 2024, Fig. 1 and Fig. 6b: new vs existing cases). Built in `clean_gsdb.py` step 5c from the cleaned dyadic data (after all drop/recode/Yugoslavia rules), per target × case: **new** = in force in t, not in t−1, case begins in t; **joined** = in force in t, not in t−1, case begun earlier, state existed in t−1; **inherited** (not counted) = a state entering the panel with cases begun earlier (25 case-targets: e.g. Serbia 2006, Czech Rep. 1993, ex-Yugoslav republics 1992, cases 1–2 begun 1949); **lifted** = in force in t−1, not in t, state still exists in t. Identity `n_cases(t) = n_cases(t−1) + new + joined − lifted` holds for all 11,754 continuing state-years (the script stops otherwise). Counts 1950–2023: 1,944 new case-targets (1,217 state-years with ≥ 1 new case), 53 joined (cases 12, 13 CoCom/Comecon successors 1992; 559 EU accession; 195 Vietnam 1976; 199 Comoros 1993), 1,156 lifted (781 state-years; GSDB `end` = t−1 in 1,146; the other 10 are group exits such as Mauritania/ECOWAS 2000, UK/EU 2021, Syria/Arab League 2011, and the Yugoslavia attribution end years). 243 state-years with a lifted case but no case in force are added to `gsdb_received.csv` with all other counts 0. Group cases count once per member target (e.g. Russia's case 995 gives every EU member a new case in 2014). **Validation:** Russia 2014–2023 matches GSDB-R4 Fig. 6(b) exactly (2022: 25 new, 38 in force; 2023: 8 new, 46 in force); cases beginning per year match Fig. 1 (2021–23: 103, 119, 121). All existing columns unchanged. **[open]** Soviet Union 1990–91: no GSDB rows survive (SVU ≥ 1990 dropped, RUS rows start 1992), so GW 365 has 0 cases in 1990–91 and the CoCom cases 12/13 appear as lifted in 1990 and joined in 1992 — pre-existing gap in the stock, to be decided. | [added 2026-10-20] |
| S4 | Merge onto the base by `iso3c` × year (left join on the base); missing sanction counts → 0 in **all** years (no sanction recorded = no sanction). | [original] |
| S5 | Interpretation: GSDB codes UN sanctions as one row per UN member, so a single UN case gives ~190 senders (max 192: Haiti 2022–23, Guinea-Bissau 2012–14). `num_sanctioners` largely reflects UN/EU multilateral regimes. | note |
| S6 | Sanction type counts are summed over cases, not distinct senders. | [original] |
| S7 | Orphans (sanction rows with no base state-year) written to `data/processed/sanctions_violence/checks/orphans_*.csv`. Originally only Eritrea 1977–92 as a target; since the ERI drop rule (2026-10-20) both files are empty. | [original], changed 2026-10-20 |

## 3. Organized violence (UCDP OV-CY v26.1) — `clean_ucdp_ov.py` + `process_sanctions_violence.py`

| # | Decision | Tag |
|---|---|---|
| U1 | Serbia: UCDP keeps `country_id` 345 after the split; recoded to 340 **from 2006** (originally from 2007; changed 2026-10-20 together with B10, so Serbia 2006 gets its UCDP row; before, it had no UCDP match and was zero-filled). | [original], changed 2026-10-20 |
| U2 | Kept 44 variables: identifiers, existence flags (`sb/ns/os_exist`, intra/inter), government involvement flags, dyad counts, and best-estimate deaths by type and by victim category (parties, civilians, unknown). | [original] |
| U3 | Merge onto the base by `gwcode` × year. | [original] |
| U4 | Missing → 0 for years ≥ 1989 (UCDP coverage starts 1989); before 1989 left missing. | [original] |
| U5 | Per-capita versions `*_pc` = count / `pwtpop` / 10 = **per 100,000 population** (`pwtpop` in millions), for all counts and deaths; binary flags not converted. | [original] |
| U6 | **Pre-1989: missing (changed 2026-10-20).** Originally missing deaths were set to 0 before dividing, so `*_pc` was 0 for 1946–88 while the counts were missing; now missing like the counts. **2020–2023 (changed 2026-10-20):** the divisor is now `pop_ext` (P4) instead of `pwtpop`, so `*_pc` exists 1989–2023 (Abkhazia, South Ossetia: to 2019). Up to 2019 `pop_ext` = `pwtpop`, so all earlier values are unchanged. | [changed 2026-10-20] |
| U7 | `cumulative_total_deaths_*_in_orgvio` = sum over state-based, non-state and one-sided violence **within the year** (UCDP's naming), not cumulative over time. `parties + civilians + unknown = best` holds exactly. | note |
| U8 | Alternative source considered: OWID "deaths in armed conflicts" (same UCDP GED v26.1, but assigned by present-day borders, Palestine separate, no victim split, no combatant deaths). Kept UCDP OV-CY as main source; OWID in `data/raw/owid/` unused. | [added 2026-10-19] decision |

## 4. GDELT 1.0 conflict events — `clean_gdelt.py` + `process_sanctions_violence.py`

| # | Decision | Tag |
|---|---|---|
| G1 | Exact duplicates on Year × CountryCode × EventCode dropped (e.g. Burma/Myanmar listed twice). | [original] |
| G2 | Four CAMEO roots: COERCE → `coerce`, ASSAULT → `assault`, FIGHT → `fight`, USE UNCONVENTIONAL MASS VIOLENCE → `mass_violence`; plus `total_violence`. | [original] |
| G3 | `*_norm1000` = sum of GDELT `NormalizedEvents1000` (events per 1,000 of all events in the country-year) — corrects for media-coverage growth. | [original] |
| G4 | `*_goldstein` = Σ (`SumEvents` × `GoldsteinScale`), sign flipped so higher = more violent. Not normalised for coverage. | [original] |
| G5 | Event types absent in a country-year → 0. | [original] |
| G6 | **Country matching: fixed, hand-checked crosswalk** `data/scripts/cleaning/gdelt_country_crosswalk.csv` (all 258 GDELT names: FIPS code, name, ISO3, GW code, GW name for checking, note). Originally produced by `country_converter` at run time; audited 2026-10-20: all 189 sovereign-state names map to the GW state of the same name, except three wrong codes, now fixed in the table: Czech Republic (converter: 315 Czechoslovakia → 316; original fix), Yemen (680 South Yemen → 678; original fix), Vietnam (817 South Vietnam → 816). 47 territories have no GW code and 15 uninhabited/disputed islands no ISO3 (dropped); 'Myanmar' is an exact duplicate of 'Burma' (removed by G1). A new GDELT name not in the table stops the script. Freezing the table did not change any value. | [original], changed 2026-10-20 |
| G7 | Merge onto the base by `gwcode` × year. Missing → 0 only for 1979–2021 (GDELT coverage); **2022–2023 missing** (changed 2026-10-20; before, every country was 0 in 2022–23). | [original], changed 2026-10-20 |
| G8 | Merge leaves `Year`, `CountryCode`, `CountryName`, `iso3c_y` (GDELT) and renames the base ISO3 to `iso3c_x`. | [original] |
| G9 | **GDELT countries assigned to the GW state of the time (changed 2026-10-20).** GDELT reports events by present-day country. The table `data/scripts/cleaning/gdelt_gw_assignments.csv` (one row per country × period, with reason) assigns: Serbia, Montenegro, Kosovo (≤ 2005), Bosnia, Croatia, Slovenia (≤ 1991), Macedonia (≤ 1990) → Yugoslavia 345; Kosovo 2006–07 → Serbia 340; Czech Rep., Slovakia (≤ 1992) → Czechoslovakia 315; 14 Soviet republics (≤ 1990) → USSR 365; Eritrea (≤ 1992) → Ethiopia 530; South Sudan (≤ 2010) → Sudan 625; East Timor (≤ 1999) → Indonesia 850 (Vietnam → 816 is fixed in the crosswalk, G6). GDELT country-years re-assigned. Before: Yugoslavia 1979–2005, Vietnam 1979–2021, Czechoslovakia 1979–92 were 0 in every year and these events were dropped. | [changed 2026-10-20] |
| G10 | **Combining several GDELT countries in one state-year** (114 state-years, e.g. Yugoslavia 1990 = 7 units): `*_goldstein` are summed; `*_norm1000` are recomputed as Σ events of the type / Σ all GDELT events × 1,000 (each unit's share weighted by its `TotalEvents`; checked against the raw file). State-years with one GDELT country keep the original values. New columns: `gdelt_total_events` (all GDELT events in the state-year = denominator), `gdelt_n_units`. | [added 2026-10-20] |
| G11 | **Missing instead of 0** for states GDELT cannot separate from another country: German Democratic Republic (inside GDELT 'Germany' → 260), South Yemen (inside 'Yemen' → 678), Abkhazia and South Ossetia (inside 'Georgia'). Note: GW 260 and 678 therefore include East German / South Yemeni events before unification. | [added 2026-10-20] |
| G12 | Not assigned (events dropped, documented): non-sovereign territories (Gaza Strip, West Bank, Hong Kong, Puerto Rico, Western Sahara, overseas territories, …; note UCDP counts Gaza deaths under Israel); pre-independence colonies/trust territories (Namibia ≤ 1989, Brunei ≤ 1983, Marshall Isl., Micronesia, Palau, St Kitts, Belize, Vanuatu in their pre-independence years); East Timor 2000–01 (UN administration). Microstates with no GDELT row in a year keep 0 (= no conflict event reported). | note |
| G13 | Caveats for use: pre-2013 GDELT is a historical backfile with much lower and changing source volume. **Use `*_norm1000`** (events per 1,000 GDELT events in the country-year): normalising by the country-year total removes the volume trend and is compatible with year fixed effects (they then absorb remaining common shocks). `*_goldstein` is not normalised and trends upward; if used, divide by `gdelt_total_events` or rely on year effects. GDELT counts media reports, so coverage differs by country. | note |

## 4b. ACLED political violence — `acquire_acled.py` + `clean_acled.py` (added 2026-11-09)

| # | Decision | Tag |
|---|---|---|
| A1 | **Download** (`data/scripts/collection/acquire_acled.py`, run by the user with their myACLED login in the git-ignored `.env`): ACLED API, dyadic export (one row per event), `disorder_type` "Political violence" (battles, explosions/remote violence, violence against civilians, riots/mob violence), 1997–2025, selected columns, actor types as numeric codes (`inter_num=1`). Downloaded 9 Nov 2026: 1,398,003 events, no duplicate event ids. Raw files never committed (ACLED terms). | [added 2026-11-09] |
| A2 | **Years**: the account sees only events at least 12 months old (manifest: `date_recency` 12 months), so the download ends 9 Nov 2025; 2025 is incomplete. The GW base ends in 2023 → ACLED used **1997–2023**. | [added 2026-11-09] |
| A3 | **Country**: event location (`iso`, ISO 3166 numeric) → ISO3 (pycountry) → GW state of that year in the base. Exceptions: Kosovo (iso 0) → KSV (347); Vietnam → VDR (816); **Palestine → Israel (666)**, as UCDP codes the West Bank and Gaza. Dropped (no GW state): overseas territories (Puerto Rico 1,123 events, Mayotte, Réunion, French Caribbean, …) and international waters — 1,370 events, list in `data/clean/acled/acled_dropped.csv`. Abkhazia and South Ossetia cannot be separated from Georgia → missing (as GDELT, G11). | [added 2026-11-09] |
| A4 | **Violence types** (UCDP organized-violence analogue): *one-sided* = civilian targeting outside riots (all violence against civilians + explosions/remote violence against civilians); *state-based* = battles / explosions-remote violence with state forces (inter code 1) on either side; *non-state* = the same without state forces; `acled_*_orgvio` = sum of the three; *riots* kept separately and **not** in orgvio. External/other forces (code 8) count as non-state. No 25-death threshold per conflict (unlike UCDP). Variables: `acled_deaths_*`, `acled_events_*`, `acled_deaths_*_pc` (per 100,000, `pop_ext`). Country-month file `acled_cm.csv` for later within-year timing. | [added 2026-11-09] |
| A5 | **Coverage start** (`data/clean/acled/acled_coverage.csv`): before ACLED covers a country, "no event" is not zero → **missing**. Start years: Africa 1997 (island states Cape Verde, Comoros, Mauritius, Seychelles, São Tomé 2020); South and Southeast Asia 2010 (India 2016, Indonesia 2015, Philippines 2016, Malaysia 2018, Bhutan, Maldives, East Timor, Brunei, Singapore 2020); Middle East 2016 (Yemen, Saudi Arabia 2015, Syria 2017); Afghanistan 2017; Eastern Europe/Balkans/Russia/Ukraine, Caucasus, Central Asia, East Asia, Latin America and the Caribbean 2018; rest of Europe and the US 2020; Canada and Oceania 2021. Set from ACLED's coverage history and each country's first event year; the script stops if any event predates its start. **[check]** against ACLED's published coverage list. | [added 2026-11-09] |
| A6 | **Zero-filling** in `process_sanctions_violence.py`: inside the coverage window (start–2023) missing → 0, outside → missing; `acled_covered` = 1 inside. 2,167 covered state-years (48 per year 1997–2009, 195 per year from 2021). | [added 2026-11-09] |
| A7 | **Validation against UCDP** (covered state-years 1997–2019, n = 1,402): correlation of log(1 + deaths per 100k) 0.84; ≥ 25 deaths in 42% (ACLED) vs 34% (UCDP) of state-years; the two disagree in 174 state-years, mostly ACLED ≥ 25 and UCDP < 25 (148). | [added 2026-11-09] |

## 5. Processing — `data/scripts/processing/process_sanctions_violence.py`

| # | Decision | Tag |
|---|---|---|
| P1 | Merge order: base → sanctions (received, sent) → UCDP → GDELT, all left joins on the base (row count stays 12,310; no duplicate state-years). | [original] |
| P2 | The two intermediate stages are written to `intermediate/` and read back with pandas' default CSV parser, exactly as the old notebooks did, so outputs replicate bit for bit. | [added 2026-10-19] |
| P3 | `year` is stored as a date string (`1990-01-01`). | [original] |
| P4 | **Population extended to 2023 (`pop_ext`, `pop_ext_source`).** `pop_ext` = `pwtpop` up to 2019 (identical in every row); for 2020–2023 = `pwtpop`(2019) × growth of UN WPP population since 2019. Population source: **UN World Population Prospects 2024, as processed by Our World in Data** (total population on 1 July, same timing as `pwtpop`; includes the UN's Jan 2026 interim update for Togo), read by `clean_population.py` (country rows kept; OWID/UN aggregates dropped; Kosovo OWID_KOS → XKX). Chain-linking (growth rates, not levels) keeps all values to 2019 and avoids a jump: WPP and `pwtpop` levels differ by up to ~25% (e.g. Syria −15%, Lebanon +20%, Yemen −18% in 2019). Code mapping panel → WPP: KSV → XKX (Kosovo), VDR → VNM (Vietnam). No WPP data: Abkhazia, South Ossetia → missing 2020–23. `pwtpop` itself is unchanged and ends in 2019; GDP (`mrgdppc`) is not extended. | [added 2026-10-20] |
| P4b | **Robustness note on population.** For most countries `pwtpop` and WPP agree closely (median ratio 0.996–0.999 in every decade; 81–96% of country-years within ±10%), and annual growth 2011–19 correlates at 0.81 (median gap 0.3 pp). Because the 2020–23 extension uses only WPP *growth*, the level differences do not enter `pop_ext`. They remain for 1989–2019 in some conflict cases (2019: Syria −15%, Lebanon +20%, Yemen −18% vs WPP): per-capita deaths for these countries depend on the population source. Decision: keep `pwtpop`-based levels (consistent with GDP); a WPP-based robustness version can be added later. | note |
| P5 | **GDP per capita extended to 2023 (`gdp_ext`, `gdp_ext_source`).** Same method as P4: `gdp_ext` = `mrgdppc` up to 2019 (identical); 2020–2023 = `mrgdppc`(2019) × growth of World Bank GDP per capita, PPP (constant 2021 international $, WDI `NY.GDP.PCAP.PP.KD`) since 2019, as processed by Our World in Data (`clean_gdp.py`; Kosovo OWID_KOS → XKX). No World Bank data for 2019/2020–23 → `gdp_ext` missing 2020–23 for: Abkhazia, Cuba, Eritrea, North Korea, Liechtenstein, Monaco, South Ossetia, South Sudan, **Syria**, Taiwan, **Venezuela**, **Yemen** (743 of 788 state-years filled). `mrgdppc` itself is unchanged. | [added 2026-10-20] |
| P6 | **Panel starts in 1950** (first GSDB year). Before, 1946–49 (320 state-years) were in the panel with every sanction count set to 0 although GSDB has no data for those years. The state-year base (`clean_base.R`) still covers 1946–2023. | [changed 2026-10-20] |
| P7 | **Ex-Yugoslavia controls.** `ex_yugo` = 1 for Yugoslavia/FRY (345), Serbia (340), Montenegro (341), Macedonia (343), Croatia (344), Bosnia (346), Kosovo (347), Slovenia (349), all years. `ex_yugo_1991_2016` = 1 for these states in 1991–2016, the period of the GSDB attribution issue (S3b, `data/README_yugoslavia.md`). Use the time-varying dummy as a control or to exclude these state-years in robustness checks (the time-invariant one is absorbed by country fixed effects). | [added 2026-10-20] |
| P8 | **Merge leftovers removed** from the final panel: UCDP identifiers (`country`, `country_id`, `region`, `govt_name`) and GDELT identifiers (`Year`, `CountryCode`, `CountryName`, `iso3c_y`); `iso3c_x` renamed `iso3c`. (They remain in the intermediate files.) | [changed 2026-10-20] |
| P9 | **Replication check: baseline mode.** `check_replication.py` now compares the outputs with a frozen copy in `archive/baseline/` (8 files: clean datasets and the panel); every difference is reported. After an intentional, logged change, freeze a new baseline: `uv run python master.py --set-baseline`. The old comparison with the notebooks is kept as `--legacy` (valid up to the 2026-10-20 15:00 version). | [changed 2026-10-20] |

## 6. Estimation-sample choices (in `empirics/scripts/*.Rmd`, not in the data files)

| # | Decision | Tag |
|---|---|---|
| E1 | Panel identifier `gw_name` × year (one-to-one with `gwcode`). | [original] |
| E2 | PVAR sample: years ≥ 1989; GDP detrended by a country-specific linear trend (`mrgdppc_detrended`). | [original] |
| E3 | Countries dropped if any PVAR variable has < 10 non-missing obs; German Democratic Republic dropped manually. | [original] |
| E4 | Unit-root tests: units with ≥ 20 valid obs (`na_check`, defined only in a saved R session — **[open]**), zero-variance units dropped, plus German Democratic Republic and Moldova dropped manually. | [original] |
| E5 | **Sample coverage (to report).** In 1989–2019, 5,277 of 5,949 state-years have all four current PVAR variables (`num_sanctioners`, `cumulative_total_deaths_parties_in_orgvio_pc`, `v2x_polyarchy`, `mrgdppc`). Most excluded state-years are Caribbean and Pacific microstates without V-Dem data (Bahamas, Dominica, Grenada, St Lucia, St Vincent, Antigua, St Kitts, Belize: no `v2x_polyarchy` at all). With `gdp_ext` and `pop_ext` the sample can run to 2023 (except the states listed in P5). | note |

---

## Change log

| Date | Change | Effect on data |
|---|---|---|
| 2026-10-19 | Reorganised into `data/raw|clean|processed`, notebooks converted to scripts, `master.py` added. Pure refactor. | None (verified: identical to the old notebooks on the same machine; old files in `archive/legacy_outputs/`). |
| 2026-10-20 | Added `num_sanctioners_gw`, `num_targets_sanctioned_gw` (counts by GW state). | 2 new columns; all existing columns unchanged. `clean_gsdb.py` now reads `data/clean/base/base.csv`. |
| 2026-10-20 | Removed the Slovenia 1991–96 zero rule (S3). | Slovenia 1992–96: 7 received-sanction columns change (35 cells), e.g. `num_sanctioners` 0 → 178–183. The replication check lists this as a known change. |
| 2026-10-20 | Fixed conflict-type filters in `clean_base.R` (B9). | `n_conflicts_intra/inter/extra` now non-zero (1,745 / 149 / 56 country-years; verified on the Mac). `n_conflicts_all` unchanged. Replication check lists it as a known change. |
| 2026-10-20 | First full run on the Mac (incl. `clean_base.R`). | Replication check: all outputs **identical** to the old notebooks apart from the documented changes above — confirms the refactor (incl. the R step) and that the earlier last-digit differences were platform noise. |
| 2026-10-20 | 2006: dropped the Yugoslavia row (B10); UCDP Serbia recode from 2006 (U1). | Panel 12,310 → 12,309 rows. Serbia 2006 now carries the UCDP row (no violence that year, so only the identifier columns change). Not yet re-run in R: `base.csv` was edited by deleting that one line, which is what `clean_base.R` now produces; re-run `master.py --check` on the Mac to confirm. |
| 2026-10-20 | GDELT: year-specific state assignment (G9), weighted combination (G10), missing for non-separable states (G11), no zero-fill after 2021 (G7). | 2 new columns (`gdelt_total_events`, `gdelt_n_units`). GDELT values change for Yugoslavia, Vietnam, Czechoslovakia, USSR (1979–90), Ethiopia (≤1992), Sudan (≤2010), Indonesia (≤1999), Serbia 2006–07; GDR, South Yemen, Abkhazia, South Ossetia become missing; all countries missing in 2022–23. Unaffected state-years keep identical values. |
| 2026-10-20 | GDELT country matching frozen into `gdelt_country_crosswalk.csv` (G6); `country_converter` no longer used at run time. | None: `gdelt_cy.csv` and the panel are byte-identical to before. |
| 2026-10-20 | Full Mac run (16:12) with all changes, checked against the old outputs. | All outputs identical to the old notebooks except the documented changes (B9, B10, S3, U1, G7, G9–G11, new columns). |
| 2026-10-20 | GSDB: Eritrea rows before 1993 dropped (drop rule). | `num_targets_sanctioned` and `n_other_sent` of the USA 1977–92 fall by 1 in 16 years (32 cells); orphans files empty; `num_targets_sanctioned_gw` unchanged (Eritrea was never counted there). |
| 2026-10-20 | GSDB Yugoslavia cases attributed per republic (S3b, `data/README_yugoslavia.md`). | Received counts change for SVN, HRV, BIH, MKD (1991–2016) and MNE (2006–16), e.g. Croatia 1998–99 `num_sanctioners` 183–187 → 15; sender-side counts fall in 1,104 sender-years. Serbia/Yugoslavia unchanged. |
| 2026-10-20 | Per-capita UCDP variables: no zero-fill before dividing (U6). | All 30 `*_pc` columns missing instead of 0 for 1946–88 (5,572 rows); 1989–2019 unchanged. |
| 2026-10-20 | Population extended to 2023 with UN WPP 2024 growth rates (P4, U6); new script `clean_population.py`. | New columns `pop_ext`, `pop_ext_source`; `*_pc` filled for 2020–23 (23,400 cells, all states except Abkhazia, South Ossetia); values up to 2019 unchanged. |
| 2026-10-20 | Population source for the 2020–23 extension switched to OWID's processed WPP 2024 series (1 July) instead of the UN single-age file (1 January) (P4). | `pop_ext` and `*_pc` change slightly for 2020–23 only; ≤ 2019 unchanged. |

| 2026-10-20 | Panel starts 1950 (P6); ex-Yugoslavia dummies (P7); case-based sanction measures (S9); GDP extended to 2023 (P5); merge leftovers dropped, `iso3c` (P8); GSDB target scan documented (S10); replication check switched to baseline mode (P9). | Panel 11,989 rows × 130 columns; all values in the remaining common columns unchanged (verified against the previous version). |

| 2026-10-20 | GSDB: case 179 (Cyprus vs Northern Cyprus) set aside; 9 self-sanction rows from the recoding dropped; set-aside and dropped rows saved to files. | 58 cells in each sanction-count column change: Cyprus 1974–2023 (−1 sender, −1 case, −1 target; `any_sanction` 1 → 0 in 1974–86), Germany 1991–94, Yugoslavia 1991 and 2000–01, Vietnam 1976 (−1 sender and −1 target each). Nothing else changes. |

| 2026-10-20 | GSDB group cases (599, 12/13, 685) kept as coded (S10, decision); "Known gaps" table added; UN single-age population file deleted from `data/raw/population/` (not used since the switch to the OWID series). | None. Baseline frozen on the Mac at 17:27 is current. |

| 2026-10-20 | Added `ru_sanction` (case imposed by Russia or the Soviet Union; S9); Fig. 1 shows it. | 1 new column; nothing else changes. New baseline needed (`--set-baseline`). |


| 2026-10-20 | GSDB flow variables (S11): `n_new_cases`, `new_sanction`, `new_un/eu/us_sanction`, `new_arms_sanction`, `new_conflict_obj_sanction`, `n_joined_cases`, `n_lifted_cases`, `lifted_sanction`. | 10 new columns (panel 11,989 × 141); `gsdb_received.csv` +243 rows (lifted only, other counts 0); all existing values unchanged (verified). New baseline needed (`--set-baseline`). |

| 2026-10-20 | Democracy variables updated through the R environment: `{isard}` 0.2.0 (renv) instead of 0.1.0 (global library); peacesciencer 1.2.0 in both (B11). | `euds`, `aeuds` change in every row (re-estimated latent scale; corr. 0.998 with the old values), `v2x_polyarchy` in 8,707 cells (median |diff| 0.001), 198 more non-missing `euds`/`aeuds`; `polity2` unchanged. Accepted; new baseline to be frozen together with the GSDB flow variables (S11). |

---

| 2026-11-09 | `clean_gsdb.py` also writes `data/clean/gsdb/gsdb_new_cases.csv`: one row per new case-target-year (1,944 rows; case id, UN/EU/US/arms/conflict-objective flags, sender, type flags incl. `descr_trade`, objective, success). Used by `13_local_projections.R` for US-only and without-ICC-685 measures. | All other outputs byte-identical (md5 checked); panel unchanged, no new baseline needed. |

| 2026-11-09 | ACLED added (section 4b, A1–A7): `clean_acled.py` (new step in `master.py`), merge in `process_sanctions_violence.py`. | Panel 11,989 × 157: 16 new `acled_*` columns; all 141 existing columns identical (replication check: all outputs replicate exactly). New baseline needed (`--set-baseline`) to freeze the new columns. |

| 2026-11-09 | Known gaps extended (GSDB South–South coverage, no counter-sanction flag, Palestine asymmetry); notes on GSDB coverage incl. possible TIES cross-check. | Documentation only; no data changed. |

| 2026-11-09 | Data versioning with DVC: `data/clean`, `data/processed`, `empirics/results/data`, `data/raw/acled`, `archive/baseline/*.csv` tracked by DVC (pointer files in git, data in a local storage folder, `.dvc/config.local`); `master.py --dvc` stores a new version. Raw folders now git-ignored by name (a `data/raw/*/` wildcard made DVC skip `data/raw`). See README "Data versions (DVC)". | No data changed. |
| 2026-11-09 | Raw downloads (not yet cleaned or merged): World Bank WDI trade/exports/imports % GDP, FDI in/outflows % GDP, SIPRI arms imports/exports (TIV), GDP current US$ (`acquire_wdi.py` → `data/raw/wdi/`); IMF IMTS bilateral goods trade, all reporters × partners (`acquire_imf_trade.py` → `data/raw/imf_imts/`). Both git-ignored by name and added to the DVC targets. Coding choices for the merge to be decided with the user. | advisor: weight by trade exposure; SIPRI arms data |

## Data sources cited

- **Population (2020–23 extension):** UN, World Population Prospects (2024) – processed by Our World in Data. “Population – UN WPP” [dataset]. United Nations, “World Population Prospects”; United Nations, “World Population Prospects – Interim Update” [original data]. Retrieved 20 October 2026 from https://ourworldindata.org/explorers/population-and-demography (OWID indicator 951674, last updated 12 July 2024; metadata: https://api.ourworldindata.org/v1/indicators/951674.metadata.json). Original: United Nations, Department of Economic and Social Affairs, Population Division (2024). *World Population Prospects 2024*, Online Edition. License CC BY 3.0 IGO (UN); OWID processing CC BY 4.0.
- **GDP per capita (2020–23 extension):** Eurostat, OECD, IMF, and World Bank (2026) – with minor processing by Our World in Data. “GDP per capita – World Bank – In constant international-$” [dataset]. Eurostat, OECD, IMF, and World Bank, “World Development Indicators 129” [original data]. Retrieved 20 October 2026 from https://ourworldindata.org/grapher/gdp-per-capita-worldbank (OWID indicator 1294305, last updated 27 July 2026; metadata: https://api.ourworldindata.org/v1/indicators/1294305.metadata.json).
- Yugoslavia sanctions sources: see `data/README_yugoslavia.md`, section 11.
- **Trade and arms (raw, 2026-11-09):** World Bank (2026), World Development Indicators, API v2, last updated 8 Oct 2026 (arms transfers: SIPRI Arms Transfers Database as published in WDI). IMF (2026), International Trade in Goods by partner country (IMTS), SDMX API, dataflow IMF.STA:IMTS.
