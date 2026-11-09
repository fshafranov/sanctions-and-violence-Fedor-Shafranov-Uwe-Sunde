# =============================================================================
# 13_local_projections.R — plain panel local projections (Jorda 2005), no DiD
#
# Added 2026-11-09 after the advisor meeting: "try local projections without the
# difference-in-differences part; focus on LP, the panel VAR seems to do worse in
# the panel setting; US sanctions only, without the ICC case". This script is the
# LP counterpart of the VAR impulse responses in 08_irf.R; the LP-DiD of 12_lpdid.R
# (treated vs clean controls) stays a separate extension.
#
# For each horizon h = 0..HORIZON one regression:
#
#   y_i,t+h = beta_h * x_it + sum_{k=1..p} (a_hk y_i,t-k + b_hk x_i,t-k) [+ c_h * y_it] [+ controls]
#             + state FE + year FE + e_i,t+h
#
#   x = shock variable (sanction measure or violence), y = response variable, p = VAR_LAGS.
#   beta_h = response of y in t+h to x in t, holding the recent history of both fixed —
#   the LP analogue of the VAR impulse response, without iterating a fitted VAR forward
#   (robust to misspecified dynamics; Plagborg-Moller & Wolf 2021: same estimand in
#   population, LP has less bias but more variance at long horizons).
#
# Two timing assumptions (annual data cannot order events within a year):
#   "shock first"  : no same-year y on the right-hand side; x may affect y already in t
#                    (= Cholesky ordering with the shock variable first)
#   "shock second" : y_it added as a control; x cannot affect y in t (beta_0 = 0 by
#                    construction, not reported) — the timing of the VAR's base IRF
#                    (no same-year effect, 08_irf.R)
# Cumulative LP: the outcome is sum_{j=0..h} y_i,t+j, so beta_h is the cumulative response
# with a proper standard error (compare with the cumulative VAR IRF, Table irf_summary).
#
# Sanction measures (built here from data/clean/gsdb/gsdb_new_cases.csv, one row per new
# case-target-year written by clean_gsdb.py since 2026-11-09):
#   all          : any new GSDB case                       (= new_sanction / n_new_cases of the panel)
#   all_no_icc   : any new case except case 685
#   us           : any new case with the United States among the senders (= new_us_sanction)
#   us_no_icc    : US cases except case 685
# Case 685 = US military-aid cut to ICC Rome Statute signatories 2002-08, coded by GSDB as a
# group case against 108 states at once (data/README.md, S10): 108 of the 113 new-sanction
# state-years in 2002. A largely symbolic, policy-change sanction unrelated to violence.
#
# Violence, two sources:
#   UCDP  : viol_inc (>= 25 deaths), viol_lev = log(1 + deaths per 100k); sample of 01, shock years 1991-2019
#   ACLED : (added 2026-11-09, advisor) acled_inc = ACLED organized-violence fatalities >= 25,
#           acled_lev = log(1 + ACLED fatalities per 100k); state-years inside ACLED coverage (data/README.md A5),
#           1997-2023, states with >= MIN_OBS covered years (in practice Africa, South/Southeast Asia, Middle East)
#
# Input : empirics/results/data/analysis_panel.csv  (01)
#         data/processed/sanctions_violence/sanctions_violence_panel.csv (ACLED variables)
#         data/clean/gsdb/gsdb_new_cases.csv          (clean_gsdb.py)
# Output: empirics/results/tables/local_projections.csv, local_projections.md
#         empirics/results/figures/fig18_lp_sanctions_to_violence.png, fig19_lp_violence_to_sanctions.png (UCDP)
#         empirics/results/figures/fig20_lp_acled_sanctions_to_violence.png, fig21_lp_acled_violence_to_sanctions.png
#         empirics/results/tables/lp_us_effect_location.md/.csv, figures/fig24_lp_us_effect_location.png (section 5:
#         region / period / leave-one-country-out breakdown of the UCDP US effect)
#         empirics/results/tables/lp_us_objective_split.md/.csv (section 6: US effect by sanction objective)
#         empirics/results/figures/fig25_lp_us_paths_by_sample.png, tables/lp_us_paths_by_sample.csv (section 7: full paths)
# =============================================================================

source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

HORIZON <- 8                      # years after the shock; at h = 8 shocks are dated <= 2011
ICC_CASE <- 685
NEW_CASES <- here("data", "clean", "gsdb", "gsdb_new_cases.csv")

SANCTION_MEASURES <- c(all = "All GSDB cases", all_no_icc = "All cases, without ICC case 685",
                       us = "US cases", us_no_icc = "US cases, without ICC case 685")


# =============================================================================
# 1. Sanction measures from the case-level file
# =============================================================================
new_cases <- read_csv(NEW_CASES, show_col_types = FALSE)

measure_counts <- new_cases %>%
  mutate(all = 1L, all_no_icc = as.integer(case != ICC_CASE),
         us = us, us_no_icc = as.integer(us == 1 & case != ICC_CASE)) %>%
  group_by(iso3c = country_iso3, yr = year) %>%
  summarise(across(all_of(names(SANCTION_MEASURES)), sum), .groups = "drop") %>%
  rename_with(~ paste0("n_new_", .x), all_of(names(SANCTION_MEASURES)))

add_sanction_measures <- function(data) {
  data <- data %>%
    left_join(measure_counts, by = c("iso3c", "yr")) %>%
    mutate(across(paste0("n_new_", names(SANCTION_MEASURES)), ~ replace_na(.x, 0L))) %>%
    arrange(gwcode, yr)
  for (m in names(SANCTION_MEASURES)) {
    data[[paste0("new_", m)]] <- as.integer(data[[paste0("n_new_", m)]] > 0)   # incidence (0/1)
  }
  data
}
analysis <- add_sanction_measures(read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE))

# The rebuilt "all" measure must reproduce the panel's flow variables exactly
stopifnot(all(analysis$n_new_all == analysis$n_new_cases),
          all(analysis$new_all == analysis$new_sanction))

# ACLED panel: from the processed panel, state-years inside ACLED coverage, 1997-2023; controls built as in 01
ACLED_MIN_DEATHS <- CONFLICT_MIN_DEATHS
acled <- read_panel() %>%
  filter(yr >= 1995, yr <= 2023) %>%
  transmute(gwcode, gw_name, iso3c, yr, n_cases_received, gdp = gdp_ext, v2x_polyarchy, acled_covered,
            acled_deaths = acled_deaths_orgvio,
            acled_inc = as.integer(acled_deaths >= ACLED_MIN_DEATHS),
            acled_lev = log1p(acled_deaths_orgvio_pc),
            # UCDP on the same state-years, to separate "other data source" from "other sample"
            ucdp_inc = as.integer(cumulative_total_deaths_in_orgvio_best >= CONFLICT_MIN_DEATHS),
            ucdp_lev = log1p(cumulative_total_deaths_in_orgvio_best_pc)) %>%
  arrange(gwcode, yr)
acled$gdp_growth      <- log(acled$gdp) - log(lag_by_year(acled, "gdp", 1))
acled$ctrl_stock      <- lag_by_year(acled, "n_cases_received", 1)
acled$ctrl_gdp_growth <- lag_by_year(acled, "gdp_growth", 1)
acled$ctrl_democracy  <- lag_by_year(acled, "v2x_polyarchy", 1)
acled$in_window <- acled$acled_covered %in% 1 & !is.na(acled$acled_lev)
acled_states <- acled %>% filter(in_window) %>% count(gwcode) %>% filter(n >= MIN_OBS) %>% pull(gwcode)
acled <- add_sanction_measures(acled %>% filter(gwcode %in% acled_states))
cat("\nACLED sample:", length(acled_states), "states,", sum(acled$in_window), "covered state-years",
    min(acled$yr[acled$in_window]), "-", max(acled$yr[acled$in_window]), "\n")

measure_summary <- analysis %>% filter(in_window) %>%
  summarise(across(all_of(paste0("new_", names(SANCTION_MEASURES))), sum)) %>%
  pivot_longer(everything(), names_to = "measure", values_to = "state_years_with_new_case") %>%
  mutate(measure = sub("^new_", "", measure), label = SANCTION_MEASURES[measure])
cat("\nState-years with a new case in", min(SAMPLE_YEARS), "-", max(SAMPLE_YEARS), ":\n")
print(as.data.frame(measure_summary), row.names = FALSE)


# =============================================================================
# 2. Local projections
# =============================================================================

# Future value (k > 0) and cumulative sum y_t + ... + y_t+h of a variable
value_at <- function(data, variable, k) lag_by_year(data, variable, -k)
cumulative_to <- function(data, variable, h) Reduce(`+`, lapply(0:h, function(j) value_at(data, variable, j)))

# One impulse-response path: shock x -> response y, horizons 0..HORIZON
local_projection <- function(data, shock, response, timing, controls = character(0), cumulative = FALSE) {
  data <- add_lags(data, c(shock, response), VAR_LAGS)
  history <- c(lag_names(shock, VAR_LAGS), lag_names(response, VAR_LAGS))
  same_year <- if (timing == "shock second") response else character(0)
  horizons <- if (timing == "shock second") 1:HORIZON else 0:HORIZON   # beta_0 = 0 by construction
  rows <- list()
  for (h in horizons) {
    data$lp_outcome <- if (cumulative) cumulative_to(data, response, h) else value_at(data, response, h)
    sample_h <- data %>% filter(in_window) %>%
      drop_na(all_of(c("lp_outcome", shock, history, same_year, controls)))
    formula_h <- as.formula(paste("lp_outcome ~", paste(c(shock, history, same_year, controls), collapse = " + "),
                                  "| gwcode + yr"))
    fit <- feols(formula_h, data = sample_h, cluster = ~ gwcode)
    estimate <- unname(coef(fit)[shock]); se <- unname(se(fit)[shock])
    rows[[length(rows) + 1]] <- tibble(horizon = h, estimate = estimate, se = se,
                                       lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
                                       p_value = 2 * pnorm(-abs(estimate / se)),
                                       observations = nobs(fit), states = n_distinct(sample_h$gwcode),
                                       shock_years = sum(sample_h[[shock]] > 0))
  }
  bind_rows(rows)
}

# Specifications: as in the VAR, incidence pairs 0/1 with 0/1, levels pairs counts with log deaths
make_specs <- function(violence_inc, violence_lev) {
  specs <- list()
  for (m in names(SANCTION_MEASURES)) {
    specs[[length(specs) + 1]] <- list(direction = "sanctions -> violence", measure = m, spec = "incidence",
                                       shock = paste0("new_", m), response = violence_inc)
    specs[[length(specs) + 1]] <- list(direction = "sanctions -> violence", measure = m, spec = "levels",
                                       shock = paste0("n_new_", m), response = violence_lev)
    specs[[length(specs) + 1]] <- list(direction = "violence -> sanctions", measure = m, spec = "incidence",
                                       shock = violence_inc, response = paste0("new_", m))
    specs[[length(specs) + 1]] <- list(direction = "violence -> sanctions", measure = m, spec = "levels",
                                       shock = violence_lev, response = paste0("n_new_", m))
  }
  specs
}
CONTROL_SETS <- list("FE only" = character(0), "with controls" = CONTROLS)
TIMINGS <- c("shock first", "shock second")
SOURCES <- list(UCDP  = list(data = analysis, specs = make_specs("viol_inc", "viol_lev")),
                ACLED = list(data = acled,    specs = make_specs("acled_inc", "acled_lev")),
                "UCDP, ACLED sample" = list(data = acled, specs = make_specs("ucdp_inc", "ucdp_lev")))

results <- list()
for (source_name in names(SOURCES)) for (s in SOURCES[[source_name]]$specs) for (control_label in names(CONTROL_SETS))
  for (timing in TIMINGS) for (cumulative in c(FALSE, TRUE)) {
  results[[length(results) + 1]] <-
    local_projection(SOURCES[[source_name]]$data, s$shock, s$response, timing, CONTROL_SETS[[control_label]], cumulative) %>%
    mutate(source = source_name, direction = s$direction, measure = s$measure,
           measure_label = SANCTION_MEASURES[[s$measure]], spec = s$spec, controls = control_label, timing = timing,
           type = if (cumulative) "cumulative" else "per year", .before = 1)
}
results <- bind_rows(results)
write_csv(results, file.path(TABLES, "local_projections.csv"))


# =============================================================================
# 3. Figures (per-year responses, FE only, both timings)
# =============================================================================
lp_figure <- function(dir, title, caption, src = "UCDP") {
  plot_data <- results %>%
    filter(source == src, direction == dir, controls == "FE only", type == "per year") %>%
    mutate(measure_label = factor(measure_label, levels = SANCTION_MEASURES),
           spec = factor(spec, levels = c("incidence", "levels")))
  colours <- c("shock first" = PAPER_COLOURS[["orange"]], "shock second" = PAPER_COLOURS[["blue"]])
  ggplot(plot_data, aes(horizon, estimate, colour = timing, fill = timing)) +
    geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
    geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.12, colour = NA) +
    geom_line(linewidth = 0.7) + geom_point(size = 1) +
    facet_grid(spec ~ measure_label, scales = "free_y") +
    scale_colour_manual(values = colours) + scale_fill_manual(values = colours) +
    scale_x_continuous(breaks = 0:HORIZON) +
    labs(title = title, x = "Years after the shock (h)", y = "Response in t + h", colour = NULL, fill = NULL,
         caption = caption) +
    theme_paper()
}
lp_caption <- paste0("Panel local projections, state and year FE, ", VAR_LAGS, " lags of both variables, no other controls; ",
                     "95% bands, SE clustered by state.\nShock first: no same-year response variable on the right-hand side; ",
                     "shock second: same-year response variable controlled for (no effect in t).")
save_figure(lp_figure("sanctions -> violence",
                      "Local projections: violence after a new sanction",
                      paste0("Incidence: new sanction (0/1) -> conflict year (0/1). Levels: number of new cases -> log(1 + deaths per 100k).\n",
                             lp_caption)),
            "fig18_lp_sanctions_to_violence.png", 12, 6.5)
save_figure(lp_figure("violence -> sanctions",
                      "Local projections: new sanctions after violence",
                      paste0("Incidence: conflict year (0/1) -> new sanction (0/1). Levels: log(1 + deaths per 100k) -> number of new cases.\n",
                             lp_caption)),
            "fig19_lp_violence_to_sanctions.png", 12, 6.5)
acled_note <- paste0("ACLED organized-violence fatalities (state-based + non-state + one-sided), ", length(acled_states),
                     " states with >= ", MIN_OBS, " covered years, 1997-2023. ")
save_figure(lp_figure("sanctions -> violence",
                      "Local projections with ACLED: violence after a new sanction",
                      paste0(acled_note, "Incidence: new sanction (0/1) -> >= 25 ACLED fatalities (0/1). ",
                             "Levels: number of new cases -> log(1 + ACLED fatalities per 100k).\n", lp_caption), "ACLED"),
            "fig20_lp_acled_sanctions_to_violence.png", 12, 6.5)
save_figure(lp_figure("violence -> sanctions",
                      "Local projections with ACLED: new sanctions after violence",
                      paste0(acled_note, "Incidence: >= 25 ACLED fatalities (0/1) -> new sanction (0/1). ",
                             "Levels: log(1 + ACLED fatalities per 100k) -> number of new cases.\n", lp_caption), "ACLED"),
            "fig21_lp_acled_violence_to_sanctions.png", 12, 6.5)


# =============================================================================
# 4. Markdown summary
# =============================================================================
format_cell <- function(estimate, se, p) sprintf("%.3f%s (%.3f)", estimate, significance_stars(p), se)
to_markdown <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
summary_table <- function(dir, kind, ctrl, shown, src = "UCDP") {
  results %>%
    filter(source == src, direction == dir, type == kind, controls == ctrl, horizon %in% shown) %>%
    mutate(cell = format_cell(estimate, se, p_value),
           measure_label = factor(measure_label, levels = SANCTION_MEASURES)) %>%
    arrange(spec, timing, measure_label) %>%
    select(spec, timing, measure = measure_label, horizon, cell) %>%
    pivot_wider(names_from = horizon, values_from = cell, names_prefix = "h = ")
}
SHOWN <- c(0, 1, 2, 3, 5, 8)
markdown <- c(
  "# Panel local projections (Jorda), no DiD", "",
  paste0("Generated by `empirics/scripts/13_local_projections.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures: `fig18_lp_sanctions_to_violence.png`, `fig19_lp_violence_to_sanctions.png`. ",
         "All estimates: `local_projections.csv`."), "",
  paste0("Specification: y(t+h) on the shock x(t), ", VAR_LAGS, " lags of x and y, state and year FE; SE clustered by state; ",
         "estimation years ", min(SAMPLE_YEARS) + VAR_LAGS, "–", max(SAMPLE_YEARS), " for the shock year t (outcomes up to ",
         max(SAMPLE_YEARS), ", so the sample shrinks with h). Cells: coefficient (SE). ",
         "*Shock second*: y(t) controlled for, so h = 0 is zero by construction."), "",
  "## Sanction measures (state-years with a new case in the window)", "",
  to_markdown(measure_summary %>% select(label, state_years_with_new_case)),
  "## A. Sanctions → violence, per-year response, FE only", "",
  to_markdown(summary_table("sanctions -> violence", "per year", "FE only", SHOWN)),
  "## B. Sanctions → violence, cumulative response Σ y(t..t+h), FE only", "",
  to_markdown(summary_table("sanctions -> violence", "cumulative", "FE only", SHOWN)),
  "## C. Violence → sanctions, per-year response, FE only", "",
  to_markdown(summary_table("violence -> sanctions", "per year", "FE only", SHOWN)),
  "## D. Violence → sanctions, cumulative response, FE only", "",
  to_markdown(summary_table("violence -> sanctions", "cumulative", "FE only", SHOWN)),
  "## E. With controls (lagged sanction stock, GDP growth, democracy): cumulative responses", "",
  "Note: the stock control counts case 685 also in the *without ICC* variants.", "",
  to_markdown(summary_table("sanctions -> violence", "cumulative", "with controls", SHOWN)),
  to_markdown(summary_table("violence -> sanctions", "cumulative", "with controls", SHOWN)),
  paste0("## F. ACLED instead of UCDP (", length(acled_states), " states with >= ", MIN_OBS,
         " covered years; shock years ", min(acled$yr[acled$in_window]) + VAR_LAGS, "–2023)"), "",
  "Violence: ACLED organized-violence fatalities (state-based + non-state + one-sided); incidence = ≥ 25 fatalities, ",
  "levels = log(1 + fatalities per 100,000). New-case state-years in the ACLED sample:", "",
  to_markdown(acled %>% filter(in_window) %>%
                summarise(across(all_of(paste0("new_", names(SANCTION_MEASURES))), sum)) %>%
                pivot_longer(everything(), names_to = "measure", values_to = "state_years_with_new_case") %>%
                mutate(measure = SANCTION_MEASURES[sub("^new_", "", measure)])),
  "### F1. Sanctions → violence, per-year response, FE only", "",
  to_markdown(summary_table("sanctions -> violence", "per year", "FE only", SHOWN, "ACLED")),
  "### F2. Sanctions → violence, cumulative response, FE only", "",
  to_markdown(summary_table("sanctions -> violence", "cumulative", "FE only", SHOWN, "ACLED")),
  "### F3. Violence → sanctions, cumulative response, FE only", "",
  to_markdown(summary_table("violence -> sanctions", "cumulative", "FE only", SHOWN, "ACLED")),
  "### F4. With controls, cumulative responses", "",
  to_markdown(summary_table("sanctions -> violence", "cumulative", "with controls", SHOWN, "ACLED")),
  to_markdown(summary_table("violence -> sanctions", "cumulative", "with controls", SHOWN, "ACLED")),
  "## G. Same sample, two sources: ACLED vs UCDP on the ACLED state-years (cumulative, FE only)", "",
  "Separates the effect of the data source from the effect of the sample (states, years 1997–2023).", "",
  to_markdown(results %>%
                filter(source != "UCDP", direction == "sanctions -> violence", spec == "levels", type == "cumulative",
                       controls == "FE only", horizon %in% SHOWN, measure %in% c("all", "us_no_icc")) %>%
                mutate(cell = format_cell(estimate, se, p_value)) %>%
                select(source, timing, measure = measure_label, horizon, cell) %>%
                pivot_wider(names_from = horizon, values_from = cell, names_prefix = "h = ") %>%
                arrange(measure, timing, source)),
  to_markdown(results %>%
                filter(source != "UCDP", direction == "violence -> sanctions", spec == "incidence", type == "cumulative",
                       controls == "FE only", horizon %in% SHOWN, measure %in% c("all", "us_no_icc")) %>%
                mutate(cell = format_cell(estimate, se, p_value)) %>%
                select(source, timing, measure = measure_label, horizon, cell) %>%
                pivot_wider(names_from = horizon, values_from = cell, names_prefix = "h = ") %>%
                arrange(measure, timing, source)),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. Incidence: 0/1 shock and 0/1 response (linear probability). ",
  "Levels: number of new cases and log(1 + deaths per 100,000)."
)
writeLines(markdown, file.path(TABLES, "local_projections.md"))

cat("\nCumulative responses at h = 2, 5 and 8 (FE only):\n")
print(as.data.frame(results %>% filter(type == "cumulative", controls == "FE only", horizon %in% c(2, 5, 8)) %>%
                      transmute(source, direction, spec, measure, timing, horizon,
                                cell = format_cell(estimate, se, p_value)) %>%
                      pivot_wider(names_from = horizon, values_from = cell, names_prefix = "h=")),
      row.names = FALSE)
cat("\nWrote", file.path(TABLES, "local_projections.md"), "\n")


# =============================================================================
# 5. Where does the UCDP US effect come from? (added 2026-11-09, after section G)
#
# The full-sample UCDP result (US cases without ICC, levels, shock second: lower log deaths at h = 2) is absent
# on the ACLED state-years with both sources (section G). Here the full-sample UCDP estimate is taken apart:
#   (a) leave out one GW region at a time, and each region alone (if >= 5 shock years)
#   (b) shock-year period interaction: separate beta for shocks in 1991-99, 2000-09, 2010-19
#   (c) leave one country out (every state with a US shock), and dropping the k most influential states together
#       (k = 1..5; ranked by the single-drop shift; an adversarial check, fragile by construction)
#   (d) the shock events of the most influential states, with log deaths t-2 .. t+3
# Outcomes: per-year y(t+2) and cumulative y(t..t+3), FE only, shock second.
# Output: tables/lp_us_effect_location.md/.csv, figures/fig24_lp_us_effect_location.png
# =============================================================================
gw_region <- function(code) cut(code, c(0, 199, 399, 626, 699, 999),
                                labels = c("Americas", "Europe", "Africa", "Middle East", "Asia and Oceania"))
LOC_SHOCK <- "n_new_us_no_icc"; LOC_RESPONSE <- "viol_lev"
LOC_OUTCOMES <- c(per_year_h2 = "Per year, h = 2", cumulative_h3 = "Cumulative, h = 0..3")
TOP_K <- 5

loc_data <- add_lags(analysis, c(LOC_SHOCK, LOC_RESPONSE), VAR_LAGS) %>%
  mutate(region = gw_region(gwcode),
         period = cut(yr, c(-Inf, 1999, 2009, Inf), labels = c("1991-99", "2000-09", "2010-19")))
loc_data$per_year_h2   <- value_at(loc_data, LOC_RESPONSE, 2)
loc_data$cumulative_h3 <- cumulative_to(loc_data, LOC_RESPONSE, 3)
for (p in levels(loc_data$period)) loc_data[[paste0("shock_", sub("-", "_", p))]] <- loc_data[[LOC_SHOCK]] * (loc_data$period == p)
loc_history <- c(lag_names(LOC_SHOCK, VAR_LAGS), lag_names(LOC_RESPONSE, VAR_LAGS), LOC_RESPONSE)  # shock second

loc_fit <- function(data, outcome, shock_terms = LOC_SHOCK) {
  sample_used <- data %>% filter(in_window) %>% drop_na(all_of(c(outcome, LOC_SHOCK, loc_history)))
  fit <- feols(as.formula(paste(outcome, "~", paste(c(shock_terms, loc_history), collapse = " + "), "| gwcode + yr")),
               data = sample_used, cluster = ~ gwcode)
  ct <- coeftable(fit)
  tibble(term = shock_terms, estimate = ct[shock_terms, 1], se = ct[shock_terms, 2],
         p_value = ct[shock_terms, 4], observations = nobs(fit),
         shock_years = sapply(shock_terms, function(t) sum(sample_used[[t]] > 0)))
}

shock_states <- loc_data %>% filter(in_window, .data[[LOC_SHOCK]] > 0) %>% distinct(gwcode, gw_name)
location <- list()
for (outcome in names(LOC_OUTCOMES)) {
  add <- function(rows, group, sample) location[[length(location) + 1]] <<-
    mutate(rows, outcome = outcome, group = group, sample = sample, .before = 1)
  add(loc_fit(loc_data, outcome), "Full sample", "All states, 1991-2019")
  for (r in levels(loc_data$region)) {
    add(loc_fit(filter(loc_data, region != r), outcome), "Without one region", paste("Without", r))
    only <- filter(loc_data, region == r)
    if (sum(only[[LOC_SHOCK]][only$in_window] > 0) >= 5) add(loc_fit(only, outcome), "One region only", paste(r, "only"))
  }
  periods <- loc_fit(loc_data, outcome, paste0("shock_", sub("-", "_", levels(loc_data$period))))
  for (i in seq_len(nrow(periods))) add(periods[i, ], "Shock-year period", paste("Shocks", levels(loc_data$period)[i]))
  for (i in seq_len(nrow(shock_states)))
    add(loc_fit(filter(loc_data, gwcode != shock_states$gwcode[i]), outcome), "Leave one country out",
        paste("Without", shock_states$gw_name[i]))
}
location <- bind_rows(location)

# (c) drop the k most influential states together (ranked by the single-drop estimate, cumulative outcome)
influential <- location %>% filter(group == "Leave one country out", outcome == "cumulative_h3") %>%
  arrange(desc(estimate)) %>% mutate(state = sub("^Without ", "", sample)) %>% pull(state)
top_drop <- list()
for (outcome in names(LOC_OUTCOMES)) for (k in 1:TOP_K) {
  dropped <- shock_states$gwcode[shock_states$gw_name %in% influential[1:k]]
  top_drop[[length(top_drop) + 1]] <- loc_fit(filter(loc_data, !gwcode %in% dropped), outcome) %>%
    mutate(outcome = outcome, group = "Drop the k most influential states",
           sample = paste0("k = ", k, " (", paste(influential[1:k], collapse = ", "), ")"), .before = 1)
}
location <- bind_rows(location, top_drop) %>% mutate(outcome_label = LOC_OUTCOMES[outcome])
write_csv(location, file.path(TABLES, "lp_us_effect_location.csv"))

# (d) shock events in the most influential states
events <- loc_data %>%
  mutate(`t-2` = lag_by_year(loc_data, LOC_RESPONSE, 2), `t-1` = lag_by_year(loc_data, LOC_RESPONSE, 1),
         t = .data[[LOC_RESPONSE]], `t+1` = value_at(loc_data, LOC_RESPONSE, 1), `t+2` = per_year_h2,
         `t+3` = value_at(loc_data, LOC_RESPONSE, 3)) %>%
  filter(in_window, .data[[LOC_SHOCK]] > 0, gw_name %in% influential[1:TOP_K]) %>%
  mutate(yr = as.integer(yr)) %>%
  select(state = gw_name, year = yr, new_us_cases = all_of(LOC_SHOCK), `t-2`, `t-1`, t, `t+1`, `t+2`, `t+3`) %>%
  mutate(across(where(is.double), ~ sprintf("%.2f", .x)))

# Figure: dot-and-whisker, one row per sample variant, facets by outcome (leave-one-country-out shown as its range)
plot_location <- location %>% filter(group != "Leave one country out") %>%
  mutate(group = factor(group, levels = c("Full sample", "Without one region", "One region only", "Shock-year period",
                                          "Drop the k most influential states")),
         sample = sub(" \\(.*", "", sample),
         sample = factor(sample, levels = rev(unique(sample))),
         lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
         outcome_label = factor(outcome_label, levels = LOC_OUTCOMES))
loco_range <- location %>% filter(group == "Leave one country out") %>% group_by(outcome_label) %>%
  summarise(lowest = min(estimate), highest = max(estimate), .groups = "drop") %>%
  mutate(outcome_label = factor(outcome_label, levels = LOC_OUTCOMES))
fig24 <- ggplot(plot_location, aes(estimate, sample)) +
  geom_rect(data = loco_range, aes(xmin = lowest, xmax = highest, ymin = -Inf, ymax = Inf), inherit.aes = FALSE,
            fill = PAPER_COLOURS[["blue"]], alpha = 0.10) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_errorbarh(aes(xmin = lower, xmax = upper), height = 0, colour = PAPER_COLOURS[["blue"]]) +
  geom_point(colour = PAPER_COLOURS[["blue"]], size = 1.6) +
  facet_grid(group ~ outcome_label, scales = "free", space = "free_y") +
  labs(title = "Where does the UCDP response to US sanctions come from?",
       x = "Response of log(1 + deaths per 100k) to one new US case (without ICC case 685)", y = NULL,
       caption = paste0("Panel local projections, shock second, state and year FE, ", VAR_LAGS,
                        " lags; 95% intervals, SE clustered by state. Shaded band: range of the ",
                        n_distinct(shock_states$gwcode), " leave-one-country-out estimates.\n",
                        "Drop k: the k states whose single removal moves the cumulative estimate most towards zero, ",
                        "removed together (", paste(influential[1:TOP_K], collapse = ", "), ").")) +
  theme_paper() + theme(strip.text.y = element_text(angle = 0, hjust = 0))
save_figure(fig24, "fig24_lp_us_effect_location.png", 11, 8)

location_cell <- function(rows) rows %>% mutate(cell = format_cell(estimate, se, p_value)) %>%
  select(group, sample, outcome_label, cell, shock_years) %>%
  pivot_wider(names_from = outcome_label, values_from = c(cell, shock_years))
loco_summary <- location %>% filter(group == "Leave one country out") %>% group_by(outcome_label) %>%
  summarise(states_dropped = n(), lowest = sprintf("%.3f", min(estimate)), highest = sprintf("%.3f", max(estimate)),
            share_p_below_0.05 = sprintf("%.2f", mean(p_value < 0.05)), .groups = "drop")
writeLines(c(
  "# Where does the UCDP response to US sanctions come from?", "",
  paste0("Generated by `empirics/scripts/13_local_projections.R` (section 5) on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figure `fig24_lp_us_effect_location.png`; all estimates `lp_us_effect_location.csv`."), "",
  "Shock: number of new US cases without ICC case 685; response: log(1 + UCDP deaths per 100k); shock second, ",
  "state and year FE, 2 lags of both. Cells: coefficient (SE); shock_years = state-years with a shock in the sample.", "",
  "## Regions, periods, most influential states", "",
  to_markdown(location_cell(filter(location, group != "Leave one country out"))),
  "## Leave one country out (each state with a US shock dropped once)", "",
  to_markdown(loco_summary),
  "Most influential single states (cumulative outcome, estimate closest to zero first):", "",
  to_markdown(location %>% filter(group == "Leave one country out", outcome == "cumulative_h3") %>%
                arrange(desc(estimate)) %>% head(10) %>% mutate(cell = format_cell(estimate, se, p_value)) %>%
                select(sample, cell)),
  "## US shock events in the five most influential states: log(1 + deaths per 100k) around the shock", "",
  to_markdown(events),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. Period = year of the shock; cumulative outcome needs t+3 <= 2019."
), file.path(TABLES, "lp_us_effect_location.md"))
cat("\nWrote", file.path(TABLES, "lp_us_effect_location.md"), "\n")


# =============================================================================
# 6. Objective split of the US effect (anticipation check; added 2026-11-09)
#
# If senders impose measures when a war's end is expected (or as part of a settlement), the deaths decline after US
# cases should be concentrated in cases whose stated objective is the war itself. Split of the US cases without ICC
# into (i) conflict objective (end_war, prevent_war, territorial_conflict; any mention, as in 14 and
# specifications.R) and (ii) all other objectives; both counts and their lags enter one regression.
# Two samples: all state-years, and state-years in conflict in t-1 (wars compared with wars, as in 14).
# Also reported: end_war mention alone vs everything else.
# Caveat: the objective split cannot separate "the sanction ended the war" from "the war was ending anyway"; a
# concentration in conflict-objective cases is what both stories predict. A decline after NON-conflict cases is
# harder to explain by anticipated war ends.
# Output: tables/lp_us_objective_split.md/.csv
# =============================================================================
CONFLICT_OBJECTIVES <- c("end_war", "prevent_war", "territorial_conflict")
objective_counts <- new_cases %>%
  filter(us == 1, case != ICC_CASE) %>%
  mutate(objectives = str_split(objective, ",\\s*"),
         conflict_obj = map_lgl(objectives, ~ any(.x %in% CONFLICT_OBJECTIVES)),
         end_war = map_lgl(objectives, ~ "end_war" %in% .x)) %>%
  group_by(iso3c = country_iso3, yr = year) %>%
  summarise(us_conflict_obj = sum(conflict_obj), us_other_obj = sum(!conflict_obj),
            us_end_war = sum(end_war), us_not_end_war = sum(!end_war), .groups = "drop")
obj_data <- analysis %>% left_join(objective_counts, by = c("iso3c", "yr")) %>%
  mutate(across(starts_with("us_"), ~ replace_na(.x, 0L))) %>% arrange(gwcode, yr)
stopifnot(all(obj_data$us_conflict_obj + obj_data$us_other_obj == obj_data$n_new_us_no_icc))
obj_data$conflict_l1 <- lag_by_year(obj_data, "viol_inc", 1)

SPLITS <- list("Conflict objective vs other" = c("us_conflict_obj", "us_other_obj"),
               "End war mentioned vs other"  = c("us_end_war", "us_not_end_war"))
OBJ_SAMPLES <- c("All state-years" = "all", "In conflict in t-1" = "war")
objective_rows <- list()
for (split_name in names(SPLITS)) for (sample_name in names(OBJ_SAMPLES)) for (outcome in names(LOC_OUTCOMES)) {
  shocks <- SPLITS[[split_name]]
  d <- add_lags(obj_data, c(shocks, LOC_RESPONSE), VAR_LAGS)
  d$per_year_h2 <- value_at(d, LOC_RESPONSE, 2); d$cumulative_h3 <- cumulative_to(d, LOC_RESPONSE, 3)
  history <- c(unlist(lapply(shocks, lag_names, VAR_LAGS)), lag_names(LOC_RESPONSE, VAR_LAGS), LOC_RESPONSE)
  sample_used <- d %>% filter(in_window, OBJ_SAMPLES[[sample_name]] == "all" | conflict_l1 %in% 1) %>%
    drop_na(all_of(c(outcome, shocks, history)))
  fit <- feols(as.formula(paste(outcome, "~", paste(c(shocks, history), collapse = " + "), "| gwcode + yr")),
               data = sample_used, cluster = ~ gwcode)
  ct <- coeftable(fit)
  diff_test <- {   # p-value of H0: both objective groups have the same coefficient
    v <- vcov(fit)[shocks, shocks]; b <- coef(fit)[shocks]
    z <- unname((b[1] - b[2]) / sqrt(v[1, 1] + v[2, 2] - 2 * v[1, 2])); 2 * pnorm(-abs(z))
  }
  objective_rows[[length(objective_rows) + 1]] <- tibble(
    split = split_name, sample = sample_name, outcome = outcome, outcome_label = LOC_OUTCOMES[[outcome]],
    shock = shocks, estimate = ct[shocks, 1], se = ct[shocks, 2], p_value = ct[shocks, 4],
    p_equal = diff_test, shock_years = sapply(shocks, function(s) sum(sample_used[[s]] > 0)),
    observations = nobs(fit), states = n_distinct(sample_used$gwcode))
}
objective_results <- bind_rows(objective_rows)
write_csv(objective_results, file.path(TABLES, "lp_us_objective_split.csv"))

SHOCK_LABELS <- c(us_conflict_obj = "Conflict objective", us_other_obj = "Other objectives",
                  us_end_war = "End war mentioned", us_not_end_war = "End war not mentioned")
writeLines(c(
  "# US effect by sanction objective (anticipation check)", "",
  paste0("Generated by `empirics/scripts/13_local_projections.R` (section 6) on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". All estimates: `lp_us_objective_split.csv`."), "",
  "US cases without ICC case 685, split by GSDB objective; both parts and their lags in one regression; response ",
  "log(1 + UCDP deaths per 100k); shock second, state and year FE. Conflict objective = end_war, prevent_war or ",
  "territorial_conflict mentioned. p(equal) = test that the two coefficients are equal. Cells: coefficient (SE) [shock years].", "",
  to_markdown(objective_results %>%
                mutate(cell = paste0(format_cell(estimate, se, p_value), " [", shock_years, "]"),
                       shock = SHOCK_LABELS[shock], p_equal = sprintf("%.2f", p_equal)) %>%
                select(split, sample, outcome = outcome_label, shock, cell, p_equal) %>%
                pivot_wider(names_from = outcome, values_from = c(cell, p_equal))),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. In-conflict sample: UCDP >= 25 deaths in t-1."
), file.path(TABLES, "lp_us_objective_split.md"))
cat("\nWrote", file.path(TABLES, "lp_us_objective_split.md"), "\n")


# =============================================================================
# 7. Full horizon paths for the section-5/6 samples (added 2026-11-09, user request)
#
# Sections 5 and 6 summarise each sample by h = 2 and the cumulative h = 0..3 only. Here the whole path h = 1..8
# (per year and cumulative) for: full sample; shock-year periods (one regression with period-specific shocks);
# without the five most influential states (section 5); state-years in conflict in t-1.
# Same specification: US cases without ICC, log(1 + UCDP deaths per 100k), shock second, state and year FE.
# Output: figures/fig25_lp_us_paths_by_sample.png, tables/lp_us_paths_by_sample.csv
# =============================================================================
path_data <- loc_data %>% left_join(obj_data %>% select(gwcode, yr, conflict_l1), by = c("gwcode", "yr"))
top_dropped <- shock_states$gwcode[shock_states$gw_name %in% influential[1:TOP_K]]
PERIOD_SHOCKS <- paste0("shock_", sub("-", "_", levels(loc_data$period)))
PATH_SAMPLES <- list(
  list(label = "Full sample",                  filter = function(d) d,                                shocks = LOC_SHOCK),
  list(label = "By shock period",              filter = function(d) d,                                shocks = PERIOD_SHOCKS),
  list(label = "Without the 5 most\ninfluential states", filter = function(d) filter(d, !gwcode %in% top_dropped), shocks = LOC_SHOCK),
  list(label = "In conflict in t-1",           filter = function(d) filter(d, conflict_l1 %in% 1),   shocks = LOC_SHOCK))
SHOCK_NAMES <- c(setNames(c("1991-99", "2000-09", "2010-19"), PERIOD_SHOCKS), setNames("All years", LOC_SHOCK))

path_rows <- list()
for (s in PATH_SAMPLES) for (cumulative in c(FALSE, TRUE)) for (h in 1:HORIZON) {
  d <- path_data
  d$lp_outcome <- if (cumulative) cumulative_to(d, LOC_RESPONSE, h) else value_at(d, LOC_RESPONSE, h)
  sample_used <- s$filter(d) %>% filter(in_window) %>% drop_na(all_of(c("lp_outcome", LOC_SHOCK, loc_history)))
  fit <- feols(as.formula(paste("lp_outcome ~", paste(c(s$shocks, loc_history), collapse = " + "), "| gwcode + yr")),
               data = sample_used, cluster = ~ gwcode)
  ct <- coeftable(fit)
  path_rows[[length(path_rows) + 1]] <- tibble(
    sample = s$label, shock = SHOCK_NAMES[s$shocks], type = if (cumulative) "Cumulative, h = 0..h" else "Per year, t + h",
    horizon = h, estimate = ct[s$shocks, 1], se = ct[s$shocks, 2], p_value = ct[s$shocks, 4],
    shock_years = sapply(s$shocks, function(x) sum(sample_used[[x]] > 0)), observations = nobs(fit))
}
paths <- bind_rows(path_rows) %>%
  mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
         sample = factor(sample, levels = sapply(PATH_SAMPLES, `[[`, "label")),
         type = factor(type, levels = c("Per year, t + h", "Cumulative, h = 0..h")),
         shock = factor(shock, levels = c("All years", "1991-99", "2000-09", "2010-19")))
write_csv(paths, file.path(TABLES, "lp_us_paths_by_sample.csv"))

path_colours <- c("All years" = "#52514e", "1991-99" = PAPER_COLOURS[["blue"]],
                  "2000-09" = PAPER_COLOURS[["orange"]], "2010-19" = PAPER_COLOURS[["aqua"]])
fig25 <- ggplot(paths, aes(horizon, estimate, colour = shock, fill = shock)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.7) + geom_point(size = 1) +
  facet_wrap(type ~ sample, nrow = 2, scales = "free_y", labeller = label_wrap_gen(multi_line = TRUE)) +   # own y-scale per panel: the wide 2010s band would flatten the rest
  scale_colour_manual(values = path_colours) + scale_fill_manual(values = path_colours) +
  scale_x_continuous(breaks = 1:HORIZON) +
  labs(title = "Deaths after a new US sanction, years 1 to 8, by sample",
       x = "Years after the sanction (h)", y = "Response of log(1 + UCDP deaths per 100k)", colour = "Shock years",
       fill = "Shock years",
       caption = paste0("Panel local projections, one regression per horizon: US cases without ICC case 685; shock second ",
                        "(deaths in t controlled), ", VAR_LAGS, " lags of both, state and year FE; 95% bands, SE clustered by state.\n",
                        "By shock period: one regression with separate coefficients for shocks in each period. ",
                        "Five most influential states: ", paste(influential[1:TOP_K], collapse = ", "),
                        ". Samples shrink with h (outcomes end 2019). Y-scales differ between panels.")) +
  theme_paper()
save_figure(fig25, "fig25_lp_us_paths_by_sample.png", 13, 7)
