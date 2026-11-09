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
