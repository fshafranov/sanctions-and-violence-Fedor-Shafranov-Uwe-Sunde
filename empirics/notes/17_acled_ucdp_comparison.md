# 17 — How ACLED and UCDP differ (descriptive)

Script `empirics/scripts/17_acled_ucdp_comparison.R`, run 2026-11-09 (user request). Table
`empirics/results/tables/acled_ucdp_comparison.md`; figures fig26–fig29.

- **Coverage (fig26).** UCDP covers every state from 1989. ACLED starts in Africa in 1997, South/Southeast Asia
  2010, the Middle East 2015–17, and the Americas, Europe and most of Asia only 2018–21 (data/README.md A5). With
  ≥ 10 covered years required, the ACLED LP sample is essentially Africa plus parts of Asia and the Middle East.
- **Agreement where both exist (fig27, 1997–2023).** Correlation of log(1 + deaths per 100k): Europe 0.99, Middle
  East 0.96, Asia 0.96, Africa 0.85, **Americas 0.39**. ACLED is higher at low levels (no 25-deaths-per-conflict
  threshold): ≥ 25 deaths in 43 % vs 34 % of African state-years. In the Americas ACLED records many fatalities
  where UCDP has none — likely gang, cartel and militia violence (Mexico, Brazil, …) outside UCDP's conflict
  definition (interpretation, not checked event by event).
- **Countries (fig28).** Where both run in parallel (Nigeria, Sudan, DR Congo, Somalia after 2005, Myanmar) the
  series move together; ACLED often a bit higher. ACLED is missing exactly for the 1990s wars in Iraq, Afghanistan,
  Somalia and Colombia.
- **US sanction events used by each analysis (fig29).** UCDP sample: 244 US events (63 in 1989–96, 74 in 1997–2009,
  107 in 2010–19), spread over all regions. ACLED sample: 142, none before 1997, 119 of them in 2010–23, 116 in
  Africa; none in the Americas or Europe.

**Reading.** ACLED and UCDP measure violence similarly where both exist (except in the Americas). The different
LP results come from **different samples**: the UCDP decline in deaths after US sanctions is a 1991–2009
phenomenon with influential cases in the Balkans, Iraq and the Americas (notes/13, section 5) — events the ACLED
sample does not contain. This matches section G of notes/13 (UCDP on the ACLED state-years = ACLED result).
