# =============================================================================
# 02_exposure_robustness.R — robustness of the exposure interaction (01_exposure_lp.R)
#
# Added 2026-11-09 (exposure/ANALYSIS_PLAN.md, E5, E7, E8). Same local projections as 01, for UCDP, ACLED and
# GDELT (each in its own window), exposure measures trade with sender / GDP (log) and sender share of arms imports,
# shocks US w/o ICC 685, EU, all cases w/o 685. Checks:
#   base         : as 01 (reference)
#   na_trade     : trade with the sender MISSING where it was set to 0 for lack of a recorded flow (flags
#                  trade_<g>_zero_imputed; data/README.md 4c X5, user 9 Nov) — trade only
#   in_conflict  : state-years with >= 25 UCDP deaths in t-1 (wars compared with wars, as empirics/14)
#   groups       : separate shock coefficients by exposure group instead of the linear interaction; trade: terciles;
#                  arms share: none / some (below the median of positive shares) / high (E7)
# Output: exposure/results/tables/exposure_robustness.csv/.md;
#         figures fig_e2_interaction_h2.png, fig_e2_interaction_cum3.png (interaction by check and source),
#                 fig_e3_groups_trade.png, fig_e3_groups_arms.png (group responses by source)
# =============================================================================
source(here::here("exposure", "scripts", "00_setup.R"))
source(here::here("exposure", "scripts", "functions_exposure.R"))

ROBUST_MEASURES <- c("trade_gdp", "arms_share")
CHECKS <- c(base = "Base (as 01)", na_trade = "No recorded trade = missing", in_conflict = "In conflict in t-1")

results <- list()
for (source in names(SOURCES)) {
  d <- exposure_data(source)
  for (shock_name in names(SHOCKS)) for (measure in ROBUST_MEASURES) {
    checks <- if (measure == "trade_gdp") names(CHECKS) else c("base", "in_conflict")
    for (check in checks)
      results[[length(results) + 1]] <- estimate_paths(d, source, shock_name, measure, check)
    results[[length(results) + 1]] <- estimate_paths(d, source, shock_name, measure, "base", mode = "groups")
  }
}
results <- add_labels(bind_rows(results)) %>% mutate(check_label = factor(CHECKS[check], levels = CHECKS))
write_csv(results, file.path(TABLES, "exposure_robustness.csv"))

# --- figures -----------------------------------------------------------------------------------------------
points <- c("per year" = 2, "cumulative" = 3)
measure_colours <- setNames(c(PAPER_COLOURS[["blue"]], PAPER_COLOURS[["orange"]]), MEASURES[ROBUST_MEASURES])
caption_base <- paste0("Panel local projections as in 01 (shock second, state and year FE, ", VAR_LAGS,
                       " lags); 95% intervals, SE clustered by state. Each source in its own window. ",
                       "Missing points: fewer than 10 shock years or group dropped.")

for (kind in names(points)) {
  h <- points[[kind]]
  what <- if (kind == "per year") "in t + 2" else "cumulative over t..t+3"
  interaction <- results %>%
    filter(mode == "linear", term == "shock x exposure (per SD)", type == kind, horizon == h) %>%
    mutate(check_label = factor(check_label, levels = rev(CHECKS)))
  fig <- ggplot(interaction, aes(estimate, check_label, colour = measure_label)) +
    geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
    geom_pointrange(aes(xmin = lower, xmax = upper), position = position_dodge(width = 0.5), size = 0.3,
                    na.rm = TRUE) +
    facet_grid(shock_label ~ source_label, scales = "free_x") +
    scale_colour_manual(values = measure_colours) +
    labs(title = paste0("Does exposure to the sender change the violence response (", what, ")?"),
         x = "Additional response per 1 SD more exposure (shock x exposure); units of each source", y = NULL,
         colour = NULL, caption = paste0(caption_base, "\nNo recorded trade = missing: trade only. ",
                                         "In conflict: >= 25 UCDP deaths in t-1.")) +
    theme_paper() + theme(legend.position = "bottom")
  save_figure(fig, paste0("fig_e2_interaction_", if (kind == "per year") "h2" else "cum3", ".png"), 12, 8)
}

for (measure in ROBUST_MEASURES) {
  groups <- results %>% filter(mode == "groups", measure == !!measure) %>%
    filter((type == "per year" & horizon == 2) | (type == "cumulative" & horizon == 3)) %>%
    mutate(point = factor(ifelse(type == "per year", "Per year, h = 2", "Cumulative, h = 0..3"),
                          levels = c("Per year, h = 2", "Cumulative, h = 0..3")),
           term = factor(term, levels = rev(unique(term))))
  fig <- ggplot(groups, aes(estimate, term, colour = point)) +
    geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
    geom_pointrange(aes(xmin = lower, xmax = upper), position = position_dodge(width = 0.5), size = 0.3,
                    na.rm = TRUE) +
    facet_grid(shock_label ~ source_label, scales = "free_x") +
    scale_colour_manual(values = c("Per year, h = 2" = PAPER_COLOURS[["blue"]],
                                   "Cumulative, h = 0..3" = "#52514e")) +
    labs(title = paste0("Violence response by group of exposure: ", MEASURES[[measure]]),
         x = "Response to one new case; units of each source", y = NULL, colour = NULL,
         caption = paste0(caption_base, "\n",
                          if (measure == "arms_share") paste0("Groups: no arms from the sender in t-3..t-1; some ",
                                                              "(below the median of positive shares); high (above).")
                          else "Groups: terciles of exposure over the sanctioned state-years.")) +
    theme_paper() + theme(legend.position = "bottom")
  save_figure(fig, paste0("fig_e3_groups_", sub("_.*", "", measure), ".png"), 12, 8)
}

# --- markdown ------------------------------------------------------------------------------------------------
summary_table <- function(r) r %>%
  filter((type == "per year" & horizon == 2) | (type == "cumulative" & horizon == 3)) %>%
  mutate(point = ifelse(type == "per year", "per year h = 2", "cumulative h = 0..3"),
         cell = paste0(format_cell(estimate, se, p_value), " [", group_shock_years, "]")) %>%
  select(source = source_label, shock = shock_label, exposure = measure_label, check = check_label, term, point, cell) %>%
  pivot_wider(names_from = point, values_from = cell) %>% arrange(source, shock, exposure, check, term)
writeLines(c(
  "# Exposure interaction: robustness (UCDP, ACLED, GDELT)", "",
  paste0("Generated by `exposure/scripts/02_exposure_robustness.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures `fig_e2_interaction_h2.png`, `fig_e2_interaction_cum3.png`, `fig_e3_groups_trade.png`, ",
         "`fig_e3_groups_arms.png`; all horizons in `exposure_robustness.csv`."), "",
  "Cells: coefficient (SE) [shock state-years with that term > 0].", "",
  "## A. Linear interaction", "",
  to_markdown(summary_table(results %>% filter(mode == "linear"))),
  "## B. Exposure groups (trade: terciles; arms: none / some / high)", "",
  to_markdown(summary_table(results %>% filter(mode == "groups"))),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01."
), file.path(TABLES, "exposure_robustness.md"))
cat("\nWrote", file.path(TABLES, "exposure_robustness.md"), "\n")
