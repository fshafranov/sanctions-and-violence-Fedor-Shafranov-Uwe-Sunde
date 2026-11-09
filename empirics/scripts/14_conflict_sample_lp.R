# =============================================================================
# 14_conflict_sample_lp.R — do arms embargoes / conflict-aimed sanctions calm or shorten wars?
#
# Added 2026-11-09 (user, after the advisor meeting: "how did sanctions that were only an arms embargo, or
# aimed directly at reducing conflict, affect conflicts?"). Design agreed with the user on 9 Nov:
#
#   Sample  : state-years that were IN CONFLICT in t-1 (UCDP >= 25 deaths), shock years 1991-2019.
#             Compares wars that received an embargo in t with wars that did not, given the same violence history,
#             instead of comparing with all (mostly peaceful) state-years.
#   Shocks  : (1) new case that includes an arms embargo (main)
#             (2) new case with a conflict objective (end_war, prevent_war, territorial_conflict; any mention)
#             (3) arms embargo only (no trade/financial/travel/military/other measure in the case) — side check,
#                 only ~30 events in the sample
#             For each shock, all OTHER new cases in t enter as a separate regressor, so the comparison is with
#             "no new sanction", not with ordinary sanctions.
#   Outcomes: still in conflict in t+h (viol_inc, 0/1)  -> "does the war end sooner?"
#             log(1 + deaths per 100k) in t+h (viol_lev) -> "is it less deadly?"
#   Model   : y(t+h) = b_h shock_t + g other_t + [viol_inc, viol_lev in t-1, t-2] [+ same-year viol_inc, viol_lev]
#                      + lags of shock and other (t-1, t-2) + year FE + (state FE | region FE) + e
#             timing: shock second (main; same-year violence held fixed, h >= 1) and shock first (h >= 0).
#             Fixed effects: state FE (within-country, close to a duration model with few conflict years per
#             state) and region FE (5 GW regions) + violence history. Reported side by side.
#   SE clustered by state. Per-year and cumulative (sum over t..t+h) responses.
#
# Caveat: which wars get embargoes is not random (visibility, atrocities); the violence history only partly
# controls for it. Arms embargoes and conflict objectives overlap heavily (60 of 91 embargo state-years).
#
# Input : empirics/results/data/analysis_panel.csv (01), data/clean/gsdb/gsdb_new_cases.csv
# Output: empirics/results/tables/conflict_sample_lp.csv, conflict_sample_lp.md
#         empirics/results/figures/fig22_conflict_sample_lp.png
# =============================================================================

source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

HORIZON <- 6                        # wars are short; at h = 6 shock years <= 2013
CONFLICT_OBJECTIVES <- c("end_war", "prevent_war", "territorial_conflict")
OTHER_MEASURES <- c("trade", "military", "financial", "travel", "other")

SHOCKS <- c(arms_any      = "Arms embargo (any)",
            conflict_obj  = "Conflict objective",
            arms_only     = "Arms embargo only")
OUTCOMES <- c(viol_inc = "Still in conflict (0/1)", viol_lev = "log(1 + deaths per 100k)")


# --- 1. Data -----------------------------------------------------------------------------------
new_cases <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  mutate(arms_any     = arms == 1,
         arms_only    = arms == 1 & rowSums(across(all_of(OTHER_MEASURES))) == 0,
         conflict_obj = map_lgl(str_split(objective, ",\\s*"), ~ any(.x %in% CONFLICT_OBJECTIVES)))

# per state-year: is there a new case of each type, and a new case NOT of that type ("other")
by_state_year <- new_cases %>%
  group_by(iso3c = country_iso3, yr = year) %>%
  summarise(across(all_of(names(SHOCKS)), list(shock = ~ as.integer(any(.x)), other = ~ as.integer(any(!.x)))),
            .groups = "drop")

# GW regions (standard code ranges)
gw_region <- function(code) cut(code, c(0, 199, 399, 626, 699, 999),
                                labels = c("Americas", "Europe", "Africa", "Middle East", "Asia and Oceania"))

panel <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(by_state_year, by = c("iso3c", "yr")) %>%
  mutate(across(matches("_(shock|other)$"), ~ replace_na(.x, 0L)), region = gw_region(gwcode)) %>%
  arrange(gwcode, yr)
panel <- add_lags(panel, c("viol_inc", "viol_lev", grep("_(shock|other)$", names(panel), value = TRUE)), VAR_LAGS)
for (h in 1:HORIZON) for (y in names(OUTCOMES)) panel[[paste0(y, "_f", h)]] <- lag_by_year(panel, y, -h)
panel$in_conflict_before <- panel$viol_inc_l1 %in% 1
sample_rows <- panel %>% filter(in_window, in_conflict_before, yr >= min(SAMPLE_YEARS) + VAR_LAGS)

event_counts <- sample_rows %>%
  summarise(state_years = n(), states = n_distinct(gwcode),
            across(all_of(paste0(names(SHOCKS), "_shock")), sum), any_new_sanction = sum(new_sanction))
cat("\nConflict sample (in conflict in t-1, ", min(SAMPLE_YEARS) + VAR_LAGS, "-", max(SAMPLE_YEARS), "):\n", sep = "")
print(as.data.frame(event_counts), row.names = FALSE)


# --- 2. Local projections ------------------------------------------------------------------------
future <- function(data, y, h) if (h == 0) data[[y]] else data[[paste0(y, "_f", h)]]

conflict_lp <- function(shock_name, outcome, timing, fixed_effects, cumulative) {
  shock <- paste0(shock_name, "_shock"); other <- paste0(shock_name, "_other")
  # viol_inc in t-1 is 1 for every row of this sample (sample rule), so only its second lag enters
  history <- c("viol_inc_l2", lag_names("viol_lev", VAR_LAGS),
               lag_names(shock, VAR_LAGS), lag_names(other, VAR_LAGS))
  same_year <- if (timing == "shock second") c("viol_inc", "viol_lev") else character(0)
  fe <- if (fixed_effects == "state FE") "gwcode + yr" else "region + yr"
  rows <- list()
  for (h in (if (timing == "shock second") 1:HORIZON else 0:HORIZON)) {
    data <- sample_rows
    data$lp_outcome <- if (cumulative) Reduce(`+`, lapply(0:h, function(j) future(data, outcome, j)))
                       else future(data, outcome, h)
    regressors <- c(shock, other, history, same_year)
    data <- data %>% drop_na(all_of(c("lp_outcome", regressors)))
    fit <- feols(as.formula(paste("lp_outcome ~", paste(regressors, collapse = " + "), "|", fe)),
                 data = data, cluster = ~ gwcode)
    estimate <- unname(coef(fit)[shock]); se <- unname(se(fit)[shock])
    rows[[length(rows) + 1]] <- tibble(horizon = h, estimate = estimate, se = se,
                                       lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
                                       p_value = 2 * pnorm(-abs(estimate / se)), observations = nobs(fit),
                                       states = n_distinct(data$gwcode), shock_events = sum(data[[shock]]))
  }
  shock_text <- SHOCKS[[shock_name]]; outcome_name <- outcome; outcome_text <- OUTCOMES[[outcome]]
  bind_rows(rows) %>% mutate(shock = shock_name, shock_label = shock_text, outcome = outcome_name,
                             outcome_label = outcome_text, timing = timing, fixed_effects = fixed_effects,
                             type = if (cumulative) "cumulative" else "per year", .before = 1)
}

results <- list()
for (s in names(SHOCKS)) for (y in names(OUTCOMES)) for (timing in c("shock second", "shock first"))
  for (fe in c("state FE", "region FE")) for (cumulative in c(FALSE, TRUE))
    results[[length(results) + 1]] <- conflict_lp(s, y, timing, fe, cumulative)
results <- bind_rows(results)
write_csv(results, file.path(TABLES, "conflict_sample_lp.csv"))


# --- 3. Figure: per-year responses, shock second, both FE versions -------------------------------
plot_data <- results %>%
  filter(type == "per year", timing == "shock second") %>%
  mutate(shock_label = factor(shock_label, levels = SHOCKS), outcome_label = factor(outcome_label, levels = OUTCOMES))
colours <- c("state FE" = PAPER_COLOURS[["blue"]], "region FE" = PAPER_COLOURS[["orange"]])
figure <- ggplot(plot_data, aes(horizon, estimate, colour = fixed_effects, fill = fixed_effects)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.7) + geom_point(size = 1.1) +
  facet_grid(outcome_label ~ shock_label, scales = "free_y") +
  scale_colour_manual(values = colours) + scale_fill_manual(values = colours) +
  scale_x_continuous(breaks = 1:HORIZON) +
  labs(title = "Wars that received a sanction vs wars that did not (sample: in conflict in t-1)",
       x = "Years after the sanction (h)", y = "Difference in t + h", colour = NULL, fill = NULL,
       caption = paste0("Local projections on state-years with >= 25 UCDP deaths in t-1, shock years ",
                        min(SAMPLE_YEARS) + VAR_LAGS, "-", max(SAMPLE_YEARS), ". Controls: conflict (0/1) and log deaths ",
                        "in t, t-1, t-2 (shock second), lags of the shock and of other new sanctions,\nother new ",
                        "sanctions in t, year FE and state or region FE. 95% bands, SE clustered by state.")) +
  theme_paper()
save_figure(figure, "fig22_conflict_sample_lp.png", 11, 6.5)


# --- 4. Markdown ---------------------------------------------------------------------------------
format_cell <- function(estimate, se, p) sprintf("%.3f%s (%.3f)", estimate, significance_stars(p), se)
to_markdown <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
table_for <- function(kind, tim) {
  results %>% filter(type == kind, timing == tim) %>%
    mutate(cell = format_cell(estimate, se, p_value), shock_label = factor(shock_label, levels = SHOCKS)) %>%
    arrange(outcome, shock_label, fixed_effects) %>%
    select(outcome = outcome_label, shock = shock_label, fixed_effects, horizon, cell) %>%
    pivot_wider(names_from = horizon, values_from = cell, names_prefix = "h = ")
}
events_h1 <- results %>% filter(horizon == 1, type == "per year", timing == "shock second", outcome == "viol_inc") %>%
  select(shock = shock_label, fixed_effects, observations, states, shock_events)
markdown <- c(
  "# Conflict-sample local projections: arms embargoes and conflict-aimed sanctions", "",
  paste0("Generated by `empirics/scripts/14_conflict_sample_lp.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figure `fig22_conflict_sample_lp.png`; all estimates `conflict_sample_lp.csv`."), "",
  "Sample: state-years in conflict in t−1 (≥ 25 UCDP deaths). Coefficient = difference in the outcome h years later ",
  "between wars that received the sanction type in t and wars that received no new sanction (other new sanctions ",
  "enter separately), holding the violence history fixed. Cells: coefficient (SE).", "",
  "## Sample and events", "", to_markdown(event_counts), to_markdown(events_h1),
  "## A. Per year, shock second (main)", "", to_markdown(table_for("per year", "shock second")),
  "## B. Cumulative, shock second", "",
  "For *still in conflict* the cumulative value is the number of extra conflict years over t+1..t+h (plus t).", "",
  to_markdown(table_for("cumulative", "shock second")),
  "## C. Per year, shock first", "", to_markdown(table_for("per year", "shock first")),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01; SE clustered by state."
)
writeLines(markdown, file.path(TABLES, "conflict_sample_lp.md"))
cat("\nPer year, shock second:\n")
print(as.data.frame(table_for("per year", "shock second")), row.names = FALSE)
