# =============================================================================
# 17_acled_ucdp_comparison.R — how do ACLED and UCDP differ? (descriptive; added 2026-11-09, user request)
#
# Why do LP results with ACLED differ from UCDP (13_local_projections.R section G; exposure/)? Four figures:
#   fig26_sources_coverage   : states with data per year and region, UCDP vs ACLED (ACLED coverage starts:
#                              Africa 1997, South/Southeast Asia 2010, Middle East 2015-17, most of the rest 2018-21;
#                              data/README.md A5)
#   fig27_sources_agreement  : log(1 + deaths per 100k), ACLED vs UCDP, state-years covered by both (1997-2023), by
#                              region, 45-degree line
#   fig28_sources_countries  : deaths per 100k over time in both sources, selected conflict countries
#   fig29_sources_us_shocks  : US sanction events (w/o ICC case 685) in each LP sample, by region and period —
#                              the events the two analyses actually use
# Samples as in the LPs (build_source_panel() in empirics/specifications.R, own window, >= MIN_OBS years per
# state): UCDP 1989-2019; ACLED covered state-years 1997-2023.
# Output: figures fig26-fig29, tables/acled_ucdp_comparison.md
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
source(here::here("empirics", "specifications.R"))

SOURCE_COLOURS <- c(UCDP = PAPER_COLOURS[["blue"]], ACLED = PAPER_COLOURS[["orange"]])
panel <- read_panel() %>%
  filter(yr >= 1989, yr <= 2023) %>%
  mutate(region = gw_region(gwcode),
         ucdp_pc = cumulative_total_deaths_in_orgvio_best_pc, acled_pc = acled_deaths_orgvio_pc,
         ucdp_has = !is.na(ucdp_pc), acled_has = acled_covered %in% 1 & !is.na(acled_pc))

# --- 1. Coverage: states with data per year -----------------------------------------------------------------
coverage <- panel %>%
  group_by(region, yr) %>%
  summarise(UCDP = sum(ucdp_has), ACLED = sum(acled_has), .groups = "drop") %>%
  pivot_longer(c(UCDP, ACLED), names_to = "source", values_to = "states") %>%
  mutate(source = factor(source, levels = names(SOURCE_COLOURS)))
fig26 <- ggplot(coverage, aes(yr, states, colour = source)) +
  geom_step(linewidth = 0.8) +
  facet_wrap(~ region, nrow = 1) +
  scale_colour_manual(values = SOURCE_COLOURS) +
  labs(title = "Which states and years each source covers",
       x = NULL, y = "States with data", colour = NULL,
       caption = paste0("UCDP organized violence: all states from 1989 (data end 2023 here). ACLED: from the year it ",
                        "starts covering a state (data/README.md A5); before that, missing.\nRegions: Gleditsch-Ward ",
                        "code ranges.")) +
  theme_paper() + theme(legend.position = "top")
save_figure(fig26, "fig26_sources_coverage.png", 12, 4.5)

# --- 2. Agreement where both exist -------------------------------------------------------------------------
both <- panel %>% filter(ucdp_has, acled_has)
agreement <- both %>% group_by(region) %>%
  summarise(state_years = n(), states = n_distinct(gwcode),
            correlation = cor(log1p(ucdp_pc), log1p(acled_pc)),
            ucdp_25 = mean(cumulative_total_deaths_in_orgvio_best >= CONFLICT_MIN_DEATHS),
            acled_25 = mean(acled_deaths_orgvio >= CONFLICT_MIN_DEATHS), .groups = "drop")
fig27 <- ggplot(both, aes(log1p(ucdp_pc), log1p(acled_pc))) +
  geom_abline(slope = 1, intercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_point(alpha = 0.25, size = 0.9, colour = PAPER_COLOURS[["violet"]]) +
  geom_text(data = agreement, aes(x = Inf, y = -Inf, label = sprintf("r = %.2f\nn = %d", correlation, state_years)),
            hjust = 1.1, vjust = -0.3, size = 3, colour = "#52514e") +
  facet_wrap(~ region, nrow = 1) +
  coord_equal() +
  labs(title = "Where both sources exist, they agree closely — except in the Americas",
       x = "UCDP: log(1 + deaths per 100k)", y = "ACLED: log(1 + fatalities per 100k)",
       caption = paste0("State-years covered by both sources, 1997-2023. Line: equal values. ACLED counts all ",
                        "organized-violence fatalities without UCDP's 25-deaths-per-conflict threshold,\nso it is often ",
                        "higher at low levels (points above the line near the origin).\nAmericas: ACLED records many ",
                        "fatalities where UCDP has none — likely gang, cartel and militia violence (e.g. Mexico, Brazil) ",
                        "that falls outside UCDP's conflict definition.")) +
  theme_paper()
save_figure(fig27, "fig27_sources_agreement.png", 12, 4.5)

# --- 3. Selected countries over time ------------------------------------------------------------------------
COUNTRIES <- c("Nigeria", "Somalia", "Sudan", "Congo, Democratic Republic of (Zaire)", "Myanmar (Burma)",
               "Iraq", "Afghanistan", "Colombia")
countries <- panel %>% filter(gw_name %in% COUNTRIES) %>%
  transmute(gw_name, yr, UCDP = ifelse(ucdp_has, ucdp_pc, NA), ACLED = ifelse(acled_has, acled_pc, NA)) %>%
  pivot_longer(c(UCDP, ACLED), names_to = "source", values_to = "deaths_pc") %>%
  mutate(source = factor(source, levels = names(SOURCE_COLOURS)),
         gw_name = factor(gw_name, levels = COUNTRIES,
                          labels = c("Nigeria", "Somalia", "Sudan", "DR Congo", "Myanmar", "Iraq", "Afghanistan",
                                     "Colombia")))
fig28 <- ggplot(countries, aes(yr, log1p(deaths_pc), colour = source)) +
  geom_line(linewidth = 0.7, na.rm = TRUE) +
  facet_wrap(~ gw_name, nrow = 2) +
  scale_colour_manual(values = SOURCE_COLOURS) +
  labs(title = "Same countries, two sources",
       x = NULL, y = "log(1 + deaths per 100k)", colour = NULL,
       caption = paste0("ACLED line starts when ACLED covers the country (Iraq, Afghanistan from 2015-17; Colombia, ",
                        "Myanmar from 2010-18). UCDP 1989-2023.")) +
  theme_paper() + theme(legend.position = "top")
save_figure(fig28, "fig28_sources_countries.png", 12, 5.5)

# --- 4. US sanction events in each LP sample -----------------------------------------------------------------
us_cases <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% distinct(iso3c = country_iso3, yr = year) %>% mutate(us_shock = 1L)
lp_sample <- function(source) {
  build_source_panel(source, "own", us_cases %>% rename(n_new_us_shock = us_shock)) %>%
    filter(in_window, n_new_us_shock > 0) %>%
    transmute(source = SOURCES_LABEL[[source]], gwcode, gw_name, yr, region)
}
SOURCES_LABEL <- c(ucdp = "UCDP", acled = "ACLED")
events <- bind_rows(lp_sample("ucdp"), lp_sample("acled")) %>%
  mutate(period = cut(yr, c(-Inf, 1996, 2009, Inf), labels = c("1989-96", "1997-2009", "2010-23")),
         source = factor(source, levels = names(SOURCE_COLOURS)))
fig29 <- ggplot(events, aes(period, fill = source)) +
  geom_bar(position = position_dodge(preserve = "single"), width = 0.75) +
  facet_wrap(~ region, nrow = 1) +
  scale_fill_manual(values = SOURCE_COLOURS) +
  labs(title = "The US sanction events each analysis uses",
       x = "Year of the sanction", y = "State-years with a new US case", fill = NULL,
       caption = paste0("New US sanction cases (GSDB, without ICC case 685) inside each source's LP sample ",
                        "(own window, >= ", MIN_OBS, " years per state). UCDP: 1989-2019; ACLED: covered state-years ",
                        "1997-2023.\nThe UCDP decline in deaths after US sanctions comes from 1991-2009 (empirics/notes/13, ",
                        "section 5); ACLED has no 1989-96 and few non-African events before 2018.\nAmericas and Europe: ",
                        "ACLED covers them only from 2018-20 (< ", MIN_OBS, " years), so they are not in the ACLED sample.")) +
  theme_paper() + theme(legend.position = "top", axis.text.x = element_text(angle = 30, hjust = 1))
save_figure(fig29, "fig29_sources_us_shocks.png", 12, 5)

# --- 5. Summary table -----------------------------------------------------------------------------------------
event_counts <- events %>% count(source, region, period) %>%
  pivot_wider(names_from = c(source, period), values_from = n, values_fill = 0)
to_markdown <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
writeLines(c(
  "# ACLED vs UCDP", "",
  paste0("Generated by `empirics/scripts/17_acled_ucdp_comparison.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures fig26-fig29."), "",
  "## Agreement where both exist (1997-2023)", "",
  to_markdown(agreement %>% mutate(across(c(correlation, ucdp_25, acled_25), ~ sprintf("%.2f", .x)))),
  "ucdp_25 / acled_25: share of state-years with >= 25 deaths in each source.", "",
  "## US sanction events (w/o ICC 685) in each LP sample", "",
  to_markdown(events %>% count(source, region) %>% pivot_wider(names_from = source, values_from = n, values_fill = 0)),
  to_markdown(events %>% count(source, period) %>% pivot_wider(names_from = source, values_from = n, values_fill = 0))
), file.path(TABLES, "acled_ucdp_comparison.md"))
cat("\nWrote", file.path(TABLES, "acled_ucdp_comparison.md"), "\n")
