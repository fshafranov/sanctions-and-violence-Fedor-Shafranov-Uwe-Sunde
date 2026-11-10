# =============================================================================
# 16_specification_curve.R — specification curves (Simonsohn, Simmons & Nelson 2020) from the grid of
# 15_specification_grid.R: for one question, the estimate of EVERY specification, sorted, with a panel
# below showing which choices each estimate uses.
#
# Added 2026-11-09 (user). Questions (QUESTIONS below; add new ones there):
#   deaths_h2      : log deaths 2 years after a new sanction (per year, shock second)
#   conflict_h2    : conflict (0/1) 2 years after a new sanction (per year, shock second)
#   deaths_cum3    : cumulative log deaths over t..t+3 after a new sanction (shock second)
#   sanctions_cum2 : cumulative new-sanction probability over t..t+2 after a conflict year (shock second)
# Timing is fixed to "shock second" (VAR timing) in every curve; shock first is in the grid but mixes in the
# same-year co-movement.
#
# Input : empirics/results/tables/spec_grid_estimates.csv.gz
# Output: empirics/results/figures/fig23_spec_curve_<question>.png, fig23b_spec_dimensions_<question>.png (shares by option),
#         empirics/results/tables/spec_curves.md
# =============================================================================

source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
source(here::here("empirics", "specifications.R"))

estimates <- read_csv(file.path(TABLES, "spec_grid_estimates.csv.gz"), show_col_types = FALSE)

# Levels outcomes have different units per source (UCDP/ACLED: log(1 + deaths per 100k); GDELT: violent events in %
# of all reported events). To compare them on one axis, levels estimates are divided by the standard deviation of
# the outcome in the estimation window of that source and window (all states) -> effect in SD units.
# Incidence outcomes (0/1) are probabilities in every source and stay unscaled. For v2s the outcome is a sanction
# measure (same units for all sources), so no scaling either.
sanctions <- build_sanction_measures()
outcome_sd <- bind_rows(lapply(names(DIMENSIONS$source), function(src) bind_rows(lapply(names(DIMENSIONS$years), function(yrs) {
  p <- build_source_panel(src, yrs, sanctions) %>% filter(in_window)
  tibble(source = src, years = yrs, outcome_sd = sd(p$violence_lev, na.rm = TRUE))
}))))
print(as.data.frame(outcome_sd), row.names = FALSE)
estimates <- estimates %>%
  left_join(outcome_sd, by = c("source", "years")) %>%
  mutate(scale = if_else(direction == "s2v" & type == "levels", outcome_sd, 1),
         estimate_raw = estimate, estimate = estimate / scale, se = se / scale)

QUESTIONS <- list(
  deaths_h2      = list(title = "Violence (levels, SD units) 2 years after a new sanction",
                        filter = quote(direction == "s2v" & type == "levels" & kind == "per year" & horizon == 2)),
  conflict_h2    = list(title = "Conflict (0/1) 2 years after a new sanction",
                        filter = quote(direction == "s2v" & type == "incidence" & kind == "per year" & horizon == 2)),
  deaths_cum3    = list(title = "Cumulative violence (levels, SD units) over t..t+3 after a new sanction",
                        filter = quote(direction == "s2v" & type == "levels" & kind == "cumulative" & horizon == 3)),
  sanctions_cum2 = list(title = "Cumulative new-sanction probability over t..t+2 after a conflict year",
                        filter = quote(direction == "v2s" & type == "incidence" & kind == "cumulative" & horizon == 2))
)
CURVE_DIMENSIONS <- c("source", "measure", "sample", "years", "fe", "controls")   # what varies along a curve
CURVE_LABELS <- c(source = "Violence source", measure = "Sanction measure", sample = "Sample", years = "Years",
                  fe = "Fixed effects", controls = "Controls")
SIGNIFICANCE_COLOURS <- c("negative, p < 0.05" = PAPER_COLOURS[["blue"]], "positive, p < 0.05" = PAPER_COLOURS[["orange"]],
                          "not significant" = "#a8a7a3")

label_option <- function(dimension, option) unname(DIMENSIONS[[dimension]][option])

spec_curve <- function(name, question) {
  data <- estimates %>% filter(!!question$filter, timing == "second") %>%
    arrange(estimate) %>%
    mutate(rank = row_number(),
           significance = case_when(p_value < 0.05 & estimate < 0 ~ "negative, p < 0.05",
                                    p_value < 0.05 & estimate > 0 ~ "positive, p < 0.05",
                                    TRUE ~ "not significant"),
           is_base = source == BASE_SPEC[["source"]] & measure == BASE_SPEC[["measure"]] &
                     sample == BASE_SPEC[["sample"]] & years == BASE_SPEC[["years"]] &
                     fe == BASE_SPEC[["fe"]] & controls == BASE_SPEC[["controls"]])
  if (nrow(data) == 0) return(NULL)

  # One ggplot, stacked with facet_grid: the estimate panel on top, one panel per dimension below.
  # All panels share a continuous y axis. In a dimension panel, option j sits at y = OFFSET * d + position * step;
  # the axis breaks/labels functions turn these positions back into option names (estimate panel: plain numbers).
  # With space = "free_y" panel heights follow the y ranges, so `step` sets how tall the dashboard is relative
  # to the estimate panel (estimate panel ~ 16 steps, each option ~ 1 step).
  est <- data %>% mutate(panel = "Estimate (95% CI)", low = estimate - 1.96 * se, high = estimate + 1.96 * se)
  step <- diff(range(c(est$low, est$high))) / 16
  OFFSET <- 1000
  positions <- numeric(0); dash <- list(); pads <- list()
  for (d in seq_along(CURVE_DIMENSIONS)) {
    dimension <- CURVE_DIMENSIONS[d]
    options <- names(DIMENSIONS[[dimension]])[names(DIMENSIONS[[dimension]]) %in% data[[dimension]]]
    k <- length(options)
    y_of <- setNames(OFFSET * d + (k - seq_len(k) + 1) * step, options)      # first option on top
    positions <- c(positions, setNames(unname(y_of), DIMENSIONS[[dimension]][options]))
    dash[[d]] <- tibble(rank = data$rank, significance = data$significance,
                        panel = CURVE_LABELS[[dimension]], y = unname(y_of[data[[dimension]]]))
    pads[[d]] <- tibble(rank = 1, panel = CURVE_LABELS[[dimension]], y = OFFSET * d + c(0.4, k + 0.6) * step)
  }
  panel_levels <- c("Estimate (95% CI)", unname(CURVE_LABELS[CURVE_DIMENSIONS]))
  as_panel <- function(x) mutate(x, panel = factor(panel, levels = panel_levels))
  est <- as_panel(est); dash <- as_panel(bind_rows(dash)); pads <- as_panel(bind_rows(pads))
  axis_breaks <- function(limits) {
    if (min(limits) > OFFSET / 2) positions[positions >= limits[1] & positions <= limits[2]] else pretty(limits, 4)
  }
  axis_labels <- function(breaks) {
    ifelse(breaks > OFFSET / 2, names(positions)[sapply(breaks, function(b) which.min(abs(positions - b)))],
           format(breaks, trim = TRUE))
  }

  figure <- ggplot() +
    geom_hline(data = as_panel(tibble(panel = "Estimate (95% CI)")), aes(yintercept = 0),
               colour = "#52514e", linewidth = 0.3) +
    geom_linerange(data = est, aes(rank, ymin = low, ymax = high, colour = significance), alpha = 0.35, linewidth = 0.3) +
    geom_point(data = est, aes(rank, estimate, colour = significance), size = 0.8) +
    geom_point(data = filter(est, is_base), aes(rank, estimate), shape = 21, size = 3, stroke = 0.9,
               colour = "black", fill = NA) +
    geom_point(data = dash, aes(rank, y, colour = significance), shape = 124, size = 1.6) +
    geom_blank(data = pads, aes(rank, y)) +
    facet_grid(panel ~ ., scales = "free_y", space = "free_y") +
    scale_y_continuous(breaks = axis_breaks, labels = axis_labels, expand = expansion(mult = 0.02)) +
    scale_colour_manual(values = SIGNIFICANCE_COLOURS) +
    labs(title = paste0("Specification curve: ", question$title),
         subtitle = paste0(nrow(data), " specifications, shock second; circled = base specification"),
         x = "Specifications, sorted by estimate", y = NULL, colour = NULL) +
    theme_paper() +
    theme(legend.position = "top", strip.text.y = element_text(angle = 0, hjust = 0),
          axis.text.x = element_blank(), panel.grid.minor = element_blank())
  save_figure(figure, paste0("fig23_spec_curve_", name, ".png"), 12, 10)
  data
}

# --- Summaries ---------------------------------------------------------------------------------------
to_markdown <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
summarise_curve <- function(data) {
  data %>% summarise(specifications = n(), median = round(median(estimate), 3),
                     share_negative = round(mean(estimate < 0), 2),
                     share_sig_negative = round(mean(p_value < 0.05 & estimate < 0), 2),
                     share_sig_positive = round(mean(p_value < 0.05 & estimate > 0), 2))
}

markdown <- c("# Specification curves", "",
              paste0("Generated by `empirics/scripts/16_specification_curve.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
                     " from the grid run ", unique(estimates$run_time), " (commit ", unique(estimates$git_commit), ")."), "",
              "Each curve: all specifications for one question (timing shock second). Levels estimates (sanctions -> violence) ",
              "are in standard deviations of the outcome of each source and window, so UCDP, ACLED and GDELT are comparable; ",
              "incidence estimates are in probability units. Share columns: fraction of all ",
              "specifications; significant = p < 0.05. 'By dimension' shows the median estimate and share significant ",
              "for each option, i.e. which choices move the answer.", "")
# Companion figure (added 2026-11-10, user: the dashboard below the curve is hard to read): for every option of
# every dimension, the share of its specifications that are significantly negative / not significant /
# significantly positive, with the median estimate as a label. Same specifications as the curve.
dimension_shares_figure <- function(name, question, data) {
  shares <- bind_rows(lapply(CURVE_DIMENSIONS, function(d)
    data %>% group_by(option = .data[[d]]) %>%
      summarise(n = n(), median = median(estimate),
                `negative, p < 0.05` = mean(significance == "negative, p < 0.05"),
                `not significant` = mean(significance == "not significant"),
                `positive, p < 0.05` = mean(significance == "positive, p < 0.05"), .groups = "drop") %>%
      mutate(dimension = CURVE_LABELS[[d]],
             option = factor(map_chr(option, ~ label_option(d, .x)), levels = rev(unname(DIMENSIONS[[d]]))))))
  long <- shares %>%
    pivot_longer(c(`negative, p < 0.05`, `not significant`, `positive, p < 0.05`), names_to = "significance", values_to = "share") %>%
    mutate(significance = factor(significance, c("positive, p < 0.05", "not significant", "negative, p < 0.05")),
           dimension = factor(dimension, unname(CURVE_LABELS[CURVE_DIMENSIONS])))
  labels <- shares %>% mutate(dimension = factor(dimension, unname(CURVE_LABELS[CURVE_DIMENSIONS])),
                              text = sprintf("median %+.2f, %d specifications", median, n))
  figure <- ggplot(long, aes(x = share, y = option, fill = significance)) +
    geom_col(width = 0.7) +
    geom_text(data = labels, aes(x = 1.02, y = option, label = text), inherit.aes = FALSE,
              hjust = 0, size = 2.6, colour = "#52514e") +
    facet_grid(dimension ~ ., scales = "free_y", space = "free_y", switch = "y") +
    scale_x_continuous(labels = scales::percent, breaks = seq(0, 1, 0.25), limits = c(0, 1.45), expand = c(0, 0)) +
    scale_fill_manual(values = SIGNIFICANCE_COLOURS, breaks = c("negative, p < 0.05", "not significant", "positive, p < 0.05")) +
    labs(title = paste0("Which choices move the answer: ", question$title),
         subtitle = paste0("Share of specifications with each option, by result (", nrow(data),
                           " specifications, shock second)"),
         x = "Share of the specifications that use this option", y = NULL, fill = NULL) +
    theme_paper() +
    theme(strip.placement = "outside", strip.text.y.left = element_text(angle = 0, hjust = 1),
          panel.grid.major.y = element_blank())
  save_figure(figure, paste0("fig23b_spec_dimensions_", name, ".png"), 9, 7)
}

for (name in names(QUESTIONS)) {
  data <- spec_curve(name, QUESTIONS[[name]])
  if (is.null(data)) next
  dimension_shares_figure(name, QUESTIONS[[name]], data)
  by_dimension <- bind_rows(lapply(CURVE_DIMENSIONS, function(d)
    data %>% group_by(option = .data[[d]]) %>% summarise_curve() %>%
      mutate(dimension = d, option = map_chr(option, ~ label_option(d, .x)), .before = 1)))
  base_row <- data %>% filter(is_base)
  markdown <- c(markdown, paste0("## ", QUESTIONS[[name]]$title), "",
                paste0("Figure `fig23_spec_curve_", name, ".png`. Base specification: ",
                       if (nrow(base_row)) sprintf("%.3f (SE %.3f, p = %.3f)", base_row$estimate, base_row$se, base_row$p_value) else "n/a", "."), "",
                to_markdown(summarise_curve(data)), to_markdown(by_dimension))
}
writeLines(markdown, file.path(TABLES, "spec_curves.md"))
cat("Wrote", file.path(TABLES, "spec_curves.md"), "\n")
