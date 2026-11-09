# =============================================================================
# 18_africa.R — sanctions and violence in Africa (added 2026-11-09, user request)
#
# ACLED covers Africa from 1997 (49 states), so Africa is the one region where UCDP and ACLED can be compared on the
# same state-years over a long period (17_acled_ucdp_comparison.R). Panel local projections as in
# 13_local_projections.R (levels, shock second, state + year FE, 2 lags of shock and response, SE clustered by
# state), African states only (GW codes 400-626):
#
# Samples / outcomes (each with >= MIN_OBS years per state):
#   ucdp_main   : UCDP log(1 + deaths per 100k), 1989-2019 (window of the main analysis)
#   ucdp_same   : UCDP, on the state-years where ACLED and UCDP both exist (ACLED-covered, 1997-2023)
#   acled_same  : ACLED log(1 + fatalities per 100k), same state-years as ucdp_same
#   gdelt       : GDELT violent events per 10,000 events, 1979-2021 (thin-coverage years missing, as in 11)
# Shocks (number of new cases in t): all w/o ICC 685, US w/o 685, UN, EU, includes an arms embargo, conflict
#   objective (end_war, prevent_war, territorial_conflict; any mention).
# Samples: all African state-years; in conflict in t-1 (>= 25 UCDP deaths), as 14_conflict_sample_lp.R.
# Reverse direction: conflict year (>= 25 deaths in the source) -> any new sanction of the type (0/1), cumulative.
# Output: tables/africa_lp.csv, africa_lp.md; figures fig30_africa_sources.png (UCDP vs ACLED, same state-years),
#         fig31_africa_samples.png (UCDP main window: all vs in conflict), fig32_africa_gdelt.png,
#         fig33_africa_violence_to_sanctions.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
source(here::here("empirics", "specifications.R"))      # gw_region(), ICC_CASE, CONFLICT_OBJECTIVES, GDELT_THIN_EVENTS
use_analysis_packages("fixest")

HORIZON <- 8
SHOCKS <- c(no_icc = "All cases (w/o ICC 685)", us_no_icc = "US (w/o ICC 685)", un = "UN",
            eu = "EU", arms = "Includes an arms embargo", conflict_obj = "Conflict objective")
SAMPLE_LABELS <- c(ucdp_main = "UCDP, 1989-2019", ucdp_same = "UCDP, same state-years as ACLED",
                   acled_same = "ACLED, 1997-2023", gdelt = "GDELT, 1979-2021")

# --- 1. Data -----------------------------------------------------------------------------------------------
cases <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  mutate(no_icc = case != ICC_CASE, us_no_icc = us == 1 & case != ICC_CASE, un = un == 1, eu = eu == 1,
         arms = arms == 1,
         conflict_obj = map_lgl(str_split(objective, ",\\s*"), ~ any(.x %in% CONFLICT_OBJECTIVES)))
shocks <- cases %>% group_by(iso3c = country_iso3, yr = year) %>%
  summarise(across(all_of(names(SHOCKS)), ~ sum(.x), .names = "n_{.col}"), .groups = "drop")
for (s in names(SHOCKS)) shocks[[paste0("any_", s)]] <- as.integer(shocks[[paste0("n_", s)]] > 0)

africa <- read_panel() %>%
  filter(gw_region(gwcode) == "Africa", yr >= 1976, yr <= 2023) %>%
  mutate(ucdp_lev = log1p(cumulative_total_deaths_in_orgvio_best_pc),
         ucdp_inc = as.integer(cumulative_total_deaths_in_orgvio_best >= CONFLICT_MIN_DEATHS),
         acled_lev = log1p(acled_deaths_orgvio_pc),
         acled_inc = as.integer(acled_deaths_orgvio >= CONFLICT_MIN_DEATHS),
         gdelt_thin = !is.na(gdelt_total_events) & gdelt_total_events < GDELT_THIN_EVENTS,
         gdelt_lev = ifelse(gdelt_thin, NA, (assault_norm1000 + fight_norm1000 + mass_violence_norm1000) / 10)) %>%
  left_join(shocks, by = c("iso3c", "yr")) %>%
  mutate(across(c(starts_with("n_"), starts_with("any_")) & any_of(c(paste0("n_", names(SHOCKS)),
                                                                     paste0("any_", names(SHOCKS)))),
                ~ replace_na(.x, 0L))) %>%
  arrange(gwcode, yr)
africa$ucdp_conflict_l1 <- lag_by_year(africa, "ucdp_inc", 1)

same <- africa$acled_covered %in% 1 & !is.na(africa$ucdp_lev) & !is.na(africa$acled_lev)
WINDOWS <- list(
  ucdp_main  = list(response = "ucdp_lev",  incidence = "ucdp_inc",  window = africa$yr %in% SAMPLE_YEARS & !is.na(africa$ucdp_lev)),
  ucdp_same  = list(response = "ucdp_lev",  incidence = "ucdp_inc",  window = same),
  acled_same = list(response = "acled_lev", incidence = "acled_inc", window = same),
  gdelt      = list(response = "gdelt_lev", incidence = NA,          window = africa$yr %in% 1979:2021 & !is.na(africa$gdelt_lev)))

sample_data <- function(name) {
  w <- WINDOWS[[name]]
  d <- africa
  d$response <- ifelse(w$window, d[[w$response]], NA)
  d$conflict <- if (is.na(w$incidence)) NA else ifelse(w$window, d[[w$incidence]], NA)
  d$in_window <- w$window
  kept <- d %>% filter(in_window) %>% count(gwcode) %>% filter(n >= MIN_OBS) %>% pull(gwcode)
  d %>% filter(gwcode %in% kept)
}
DATA <- lapply(setNames(names(WINDOWS), names(WINDOWS)), sample_data)
coverage <- bind_rows(lapply(names(DATA), function(n) DATA[[n]] %>% filter(in_window) %>%
  summarise(sample = n, states = n_distinct(gwcode), state_years = n(), first = min(yr), last = max(yr))))
print(as.data.frame(coverage))

value_at <- function(d, variable, k) lag_by_year(d, variable, -k)
cumulative_to <- function(d, variable, h) Reduce(`+`, lapply(0:h, function(j) value_at(d, variable, j)))

# --- 2. Local projections ------------------------------------------------------------------------------------
lp <- function(d, shock, response, cumulative, conflict_only = FALSE) {
  d <- add_lags(d, c(shock, response), VAR_LAGS)
  history <- c(lag_names(shock, VAR_LAGS), lag_names(response, VAR_LAGS), response)
  if (conflict_only) d$in_window <- d$in_window & d$ucdp_conflict_l1 %in% 1
  rows <- list()
  for (h in 1:HORIZON) {
    d$outcome <- if (cumulative) cumulative_to(d, response, h) else value_at(d, response, h)
    s <- d %>% filter(in_window) %>% drop_na(all_of(c("outcome", shock, history)))
    n_shock <- sum(s[[shock]] > 0)
    if (n_shock < 10) next
    fit <- feols(as.formula(paste("outcome ~", paste(c(shock, history), collapse = " + "), "| gwcode + yr")),
                 data = s, cluster = ~ gwcode, notes = FALSE)
    ct <- coeftable(fit)
    if (!shock %in% rownames(ct)) next
    rows[[length(rows) + 1]] <- tibble(horizon = h, estimate = ct[shock, 1], se = ct[shock, 2],
                                       p_value = ct[shock, 4], observations = nobs(fit),
                                       states = n_distinct(s$gwcode), shock_years = n_shock)
  }
  bind_rows(rows)
}

results <- list()
for (sample_name in names(DATA)) for (s in names(SHOCKS)) for (cumulative in c(FALSE, TRUE)) {
  for (conflict_only in c(FALSE, TRUE)) {
    if (conflict_only && !sample_name %in% c("ucdp_main", "acled_same")) next
    r <- lp(DATA[[sample_name]], paste0("n_", s), "response", cumulative, conflict_only)
    if (nrow(r)) results[[length(results) + 1]] <- r %>%
      mutate(direction = "sanctions -> violence", sample = sample_name, shock = s,
             type = if (cumulative) "cumulative" else "per year",
             subsample = if (conflict_only) "In conflict in t-1" else "All state-years", .before = 1)
  }
  # reverse direction: conflict year -> any new sanction of the type (cumulative probability)
  if (sample_name != "gdelt" && s %in% c("no_icc", "us_no_icc", "un", "eu")) {
    d <- DATA[[sample_name]]
    d[[paste0("any_", s)]][!d$in_window] <- NA
    r <- lp(d, "conflict", paste0("any_", s), cumulative)
    if (nrow(r)) results[[length(results) + 1]] <- r %>%
      mutate(direction = "violence -> sanctions", sample = sample_name, shock = s,
             type = if (cumulative) "cumulative" else "per year", subsample = "All state-years", .before = 1)
  }
}
results <- bind_rows(results) %>%
  mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
         sample_label = factor(SAMPLE_LABELS[sample], levels = SAMPLE_LABELS),
         shock_label = factor(SHOCKS[shock], levels = SHOCKS))
write_csv(results, file.path(TABLES, "africa_lp.csv"))

# --- 3. Figures ----------------------------------------------------------------------------------------------
path_plot <- function(data, colour_by, colours, title, ylab, caption) {
  ggplot(data, aes(horizon, estimate, colour = .data[[colour_by]], fill = .data[[colour_by]])) +
    geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
    geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.12, colour = NA) +
    geom_line(linewidth = 0.7) + geom_point(size = 1) +
    facet_wrap(~ shock_label, nrow = 2) +
    scale_colour_manual(values = colours) + scale_fill_manual(values = colours) +
    scale_x_continuous(breaks = 1:HORIZON) +
    labs(title = title, x = "Years after the shock (h)", y = ylab, colour = NULL, fill = NULL, caption = caption) +
    theme_paper() + theme(legend.position = "top")
}
lp_note <- paste0("Panel local projections, African states (GW 400-626), shock second, state and year FE, ", VAR_LAGS,
                  " lags; 95% bands, SE clustered by state; >= ", MIN_OBS, " years per state.")

fig30 <- path_plot(
  results %>% filter(direction == "sanctions -> violence", sample %in% c("ucdp_same", "acled_same"),
                     subsample == "All state-years", type == "per year"),
  "sample_label", setNames(c(PAPER_COLOURS[["blue"]], PAPER_COLOURS[["orange"]]), SAMPLE_LABELS[c("ucdp_same", "acled_same")]),
  "Africa: violence after a new sanction, UCDP and ACLED on the same state-years",
  "Response of log(1 + deaths per 100k) in t + h",
  paste0(lp_note, "\nSame state-years: ACLED-covered (1997-2023) and UCDP available."))
save_figure(fig30, "fig30_africa_sources.png", 12, 6.5)

fig31 <- path_plot(
  results %>% filter(direction == "sanctions -> violence", sample == "ucdp_main", type == "per year"),
  "subsample", c("All state-years" = PAPER_COLOURS[["blue"]], "In conflict in t-1" = PAPER_COLOURS[["violet"]]),
  "Africa: violence after a new sanction, UCDP 1989-2019",
  "Response of log(1 + UCDP deaths per 100k) in t + h",
  paste0(lp_note, "\nIn conflict: >= 25 UCDP deaths in t-1 (wars compared with wars, as script 14). Missing points: < 10 shock years."))
save_figure(fig31, "fig31_africa_samples.png", 12, 6.5)

fig32 <- path_plot(
  results %>% filter(direction == "sanctions -> violence", sample == "gdelt", type == "per year"),
  "sample_label", setNames(PAPER_COLOURS[["aqua"]], SAMPLE_LABELS[["gdelt"]]),
  "Africa: media-reported violence after a new sanction (GDELT)",
  "Response of GDELT violent events per 10,000 events in t + h",
  paste0(lp_note, "\nGDELT 1.0, 1979-2021; years with < ", GDELT_THIN_EVENTS, " events missing."))
save_figure(fig32, "fig32_africa_gdelt.png", 12, 6.5)

fig33 <- ggplot(results %>% filter(direction == "violence -> sanctions", type == "cumulative"),
                aes(horizon, estimate, colour = sample_label, fill = sample_label)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.10, colour = NA) +
  geom_line(linewidth = 0.7) + geom_point(size = 1) +
  facet_wrap(~ shock_label, nrow = 1) +
  scale_colour_manual(values = setNames(c(PAPER_COLOURS[["grey"]], PAPER_COLOURS[["blue"]], PAPER_COLOURS[["orange"]]),
                                        SAMPLE_LABELS[c("ucdp_main", "ucdp_same", "acled_same")])) +
  scale_fill_manual(values = setNames(c(PAPER_COLOURS[["grey"]], PAPER_COLOURS[["blue"]], PAPER_COLOURS[["orange"]]),
                                      SAMPLE_LABELS[c("ucdp_main", "ucdp_same", "acled_same")])) +
  scale_x_continuous(breaks = 1:HORIZON) +
  labs(title = "Africa: new sanctions after a conflict year",
       x = "Years after the conflict year (h)", y = "Cumulative change in the probability of a new case, t..t+h",
       colour = NULL, fill = NULL,
       caption = paste0("Shock: >= 25 deaths in the source (UCDP or ACLED) in t; response: any new case of the type ",
                        "(0/1), cumulative. ", lp_note)) +
  theme_paper() + theme(legend.position = "top")
save_figure(fig33, "fig33_africa_violence_to_sanctions.png", 13, 4.8)

# --- 4. Markdown -----------------------------------------------------------------------------------------------
format_cell <- function(estimate, se, p) sprintf("%.3f%s (%.3f)", estimate, significance_stars(p), se)
to_markdown <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
table_for <- function(dir, kind) results %>%
  filter(direction == dir, type == kind, horizon %in% c(1, 2, 3, 5, 8)) %>%
  mutate(cell = format_cell(estimate, se, p_value)) %>%
  group_by(sample_label, subsample, shock_label) %>% mutate(shock_years = max(shock_years)) %>% ungroup() %>%
  select(sample = sample_label, subsample, shock = shock_label, shock_years, horizon, cell) %>%
  pivot_wider(names_from = horizon, values_from = cell, names_prefix = "h = ") %>%
  arrange(sample, subsample, shock)
writeLines(c(
  "# Sanctions and violence in Africa", "",
  paste0("Generated by `empirics/scripts/18_africa.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures fig30-fig33; all estimates `africa_lp.csv`."), "",
  "Local projections, African states (GW 400-626), shock second, state + year FE, 2 lags, SE clustered by state. ",
  "Cells: coefficient (SE); shock_years = state-years with a shock (h = 1 sample).", "",
  "## Samples", "", to_markdown(coverage),
  "## A. Sanctions -> violence, per year", "", to_markdown(table_for("sanctions -> violence", "per year")),
  "## B. Sanctions -> violence, cumulative t..t+h", "", to_markdown(table_for("sanctions -> violence", "cumulative")),
  "## C. Violence -> sanctions, cumulative probability of a new case", "",
  to_markdown(table_for("violence -> sanctions", "cumulative")),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. GDELT units: violent events per 10,000 events."
), file.path(TABLES, "africa_lp.md"))
cat("\nWrote", file.path(TABLES, "africa_lp.md"), "\n")
