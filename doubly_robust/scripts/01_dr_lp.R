# =============================================================================
# 01_dr_lp.R — doubly robust local projections (Jorda & Taylor 2016), base specification
#
# Question: does the "fewer deaths after US sanctions" LP result (13_local_projections.R) survive when
# sanctioned state-years are compared only with unsanctioned state-years that had a similar chance of being
# sanctioned (same violence and sanction history)?
#
# Steps (Jorda & Taylor 2016, EJ; Angrist, Jorda & Kuersteiner 2018, JBES):
#   1. Propensity score = reaction function as a logit:
#        P(D_it = 1 | X_it),  X = y_t-1, y_t-2, D_t-1, D_t-2 [, y_t if shock second] + region + 5-year period
#      D = any new US case without ICC case 685 (0/1); y = UCDP log(1 + deaths per 100k).
#   2. Overlap: distribution of p by treatment; trim p outside [TRIM, 1 - TRIM].
#   3. For each horizon h, four estimators of the effect of D_t on y_t+h (per year and cumulative):
#        LP (OLS)          y_t+h ~ D + X | state + year FE, all state-years (= script 13 with a 0/1 shock)
#        LP, overlap       the same, on the trimmed sample (separates trimming from weighting)
#        IPW               y_t+h ~ D | state + year FE, weights 1/p (treated), 1/(1-p) (controls)
#        IPWRA (DR)        y_t+h ~ D + X | state + year FE, same weights. Consistent if either the propensity
#                          model or the outcome regression is right (Wooldridge 2007; Jorda & Taylor's AIPW).
#        IPWRA, ATT        weights 1 (treated), p/(1-p) (controls): effect on the sanctioned state-years
#   4. Balance: standardised mean differences of X and of the placebo lags y_t-3, y_t-4 before/after weighting;
#      placebo LP: the same estimators with y_t-3, y_t-4 as outcome (should be ~0).
# Samples: all state-years in the window; state-years in conflict in t-1 (wars compared with wars).
# Standard errors clustered by state; they treat the propensity score as known (no first-stage correction).
#
# Input : empirics/results/data/analysis_panel.csv (01), data/clean/gsdb/gsdb_new_cases.csv
# Output: doubly_robust/results/tables/dr_lp_estimates.csv/.md, dr_balance.csv/.md, dr_propensity.csv/.md
#         doubly_robust/results/figures/dr1_overlap.png, dr2_balance.png, dr3_lp_paths.png, dr4_common_support.png (+ tables/dr_common_support.csv)
# =============================================================================

source(here::here("doubly_robust", "scripts", "00_setup.R"))
use_analysis_packages("fixest")

# =============================================================================
# 1. Data: treatment, outcome, history
# =============================================================================
new_cases <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE)
us_years <- new_cases %>% filter(us == 1, case != ICC_CASE) %>%
  distinct(iso3c = country_iso3, yr = year) %>% mutate(D = 1L)

gw_region <- function(code) cut(code, c(0, 199, 399, 626, 699, 999),
                                labels = c("Americas", "Europe", "Africa", "Middle East", "Asia"))

panel <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(us_years, by = c("iso3c", "yr")) %>%
  mutate(D = replace_na(D, 0L), y = viol_lev, region = gw_region(gwcode),
         period = factor(PERIOD_YEARS * floor(yr / PERIOD_YEARS))) %>%
  arrange(gwcode, yr)
panel <- add_lags(panel, c("y", "D"), max(VAR_LAGS, PLACEBO_LAGS))
panel$conflict_l1 <- lag_by_year(panel, "viol_inc", 1)

# check: D equals the incidence version of script 13's us_no_icc measure
stopifnot(sum(panel$D[panel$in_window]) == nrow(semi_join(us_years, filter(panel, in_window), by = c("iso3c", "yr"))))

value_at <- function(data, variable, k) lag_by_year(data, variable, -k)
cumulative_to <- function(data, variable, h) Reduce(`+`, lapply(0:h, function(j) value_at(data, variable, j)))

history_vars <- function(timing) c(lag_names("y", VAR_LAGS), lag_names("D", VAR_LAGS),
                                   if (timing == "shock second") "y")
SAMPLES <- c("All state-years" = "all", "In conflict in t-1" = "war")
TIMINGS <- c("shock second", "shock first")

sample_data <- function(s) {
  d <- panel %>% filter(in_window)
  if (s == "war") d <- d %>% filter(conflict_l1 == 1)
  d
}

# =============================================================================
# 2. Propensity score (logit reaction function)
# =============================================================================
fit_propensity <- function(d, timing) {
  X <- history_vars(timing)
  d <- d %>% drop_na(all_of(c("D", X)))
  # region / period dummies only where they vary (in-conflict sample is small)
  fe <- c("region", "period")[sapply(c("region", "period"), function(v) n_distinct(d[[v]]) > 1)]
  f <- as.formula(paste("D ~", paste(c(X, fe), collapse = " + ")))
  m <- glm(f, data = d, family = binomial())
  d$p <- predict(m, type = "response")
  list(data = d, model = m)
}

prop <- list(); prop_rows <- list()
for (s in names(SAMPLES)) for (tm in TIMINGS) {
  key <- paste(SAMPLES[[s]], tm)
  prop[[key]] <- fit_propensity(sample_data(SAMPLES[[s]]), tm)
  d <- prop[[key]]$data
  in_overlap <- d$p >= TRIM & d$p <= 1 - TRIM
  prop_rows[[key]] <- tibble(sample = s, timing = tm, state_years = nrow(d), treated = sum(d$D),
                             trimmed_controls = sum(!in_overlap & d$D == 0), trimmed_treated = sum(!in_overlap & d$D == 1),
                             p_treated_median = median(d$p[d$D == 1]), p_controls_median = median(d$p[d$D == 0]),
                             max_ate_weight = max(1 / d$p[in_overlap & d$D == 1]),
                             auc = { r <- rank(d$p); (sum(r[d$D == 1]) - sum(d$D) * (sum(d$D) + 1) / 2) /
                                       (sum(d$D) * sum(d$D == 0)) })
  print(summary(prop[[key]]$model)$coefficients[history_vars(tm), , drop = FALSE])
}
prop_table <- bind_rows(prop_rows)
write_csv(prop_table, file.path(TABLES, "dr_propensity.csv"))
writeLines(c("# Propensity model (logit reaction function): fit and overlap", "",
             knitr::kable(prop_table, digits = 3)), file.path(TABLES, "dr_propensity.md"))
print(as.data.frame(prop_table))

add_weights <- function(d) {
  d %>% filter(p >= TRIM, p <= 1 - TRIM) %>%
    mutate(w_ate = if_else(D == 1, 1 / p, 1 / (1 - p)),
           w_att = if_else(D == 1, 1, p / (1 - p)))
}

# =============================================================================
# 3. Balance: standardised mean differences before / after weighting
# =============================================================================
smd <- function(x, D, w = rep(1, length(x))) {
  m1 <- weighted.mean(x[D == 1], w[D == 1]); m0 <- weighted.mean(x[D == 0], w[D == 0])
  (m1 - m0) / sqrt((var(x[D == 1]) + var(x[D == 0])) / 2)
}
balance_rows <- list()
for (s in names(SAMPLES)) for (tm in TIMINGS) {
  d <- add_weights(prop[[paste(SAMPLES[[s]], tm)]]$data)
  vars <- c(history_vars(tm), paste0("y_l", PLACEBO_LAGS))
  for (v in vars) {
    ok <- !is.na(d[[v]])
    balance_rows[[length(balance_rows) + 1]] <- tibble(
      sample = s, timing = tm, variable = v, in_propensity = v %in% history_vars(tm),
      unweighted = smd(d[[v]][ok], d$D[ok]), ate_weighted = smd(d[[v]][ok], d$D[ok], d$w_ate[ok]),
      att_weighted = smd(d[[v]][ok], d$D[ok], d$w_att[ok]))
  }
}
balance <- bind_rows(balance_rows)
write_csv(balance, file.path(TABLES, "dr_balance.csv"))
writeLines(c("# Balance: standardised mean differences (treated - controls), trimmed sample", "",
             "Rule of thumb: |SMD| < 0.1 balanced. y_l3, y_l4 are not in the propensity model (placebo).", "",
             knitr::kable(balance, digits = 3)), file.path(TABLES, "dr_balance.md"))

# =============================================================================
# 4. Local projections: OLS vs IPW vs IPWRA
# =============================================================================
fit_one <- function(d, outcome, X, weights = NULL) {
  d <- d %>% mutate(lp_outcome = .data[[outcome]]) %>% drop_na(all_of(c("lp_outcome", "D", X)))
  rhs <- paste(c("D", X), collapse = " + ")
  f <- as.formula(paste("lp_outcome ~", rhs, "| gwcode + yr"))
  fit <- if (is.null(weights)) feols(f, data = d, cluster = ~ gwcode) else
    feols(f, data = d, cluster = ~ gwcode, weights = as.formula(paste("~", weights)))
  tibble(estimate = unname(coef(fit)["D"]), se = unname(se(fit)["D"]), observations = nobs(fit),
         treated = sum(d$D[obs(fit)]))
}

ESTIMATORS <- c("LP (OLS)", "LP, overlap sample", "IPW", "IPWRA (doubly robust)", "IPWRA, ATT")
rows <- list()
for (s in names(SAMPLES)) for (tm in TIMINGS) {
  X <- history_vars(tm)
  full <- sample_data(SAMPLES[[s]])
  trimmed <- add_weights(prop[[paste(SAMPLES[[s]], tm)]]$data)
  h_min <- if (tm == "shock second") 1 else 0
  for (type in c("per year", "cumulative")) for (h in c(-rev(PLACEBO_LAGS), h_min:HORIZON)) {
    if (h < 0 && type == "cumulative") next
    make_outcome <- function(d) {
      d$out <- if (h < 0) d[[paste0("y_l", -h)]] else if (type == "cumulative") cumulative_to(d, "y", h) else value_at(d, "y", h)
      d
    }
    # outcomes need future values from the full panel, so build them there and join
    out_full <- make_outcome(panel)[, c("gwcode", "yr", "out")]
    f <- full %>% left_join(out_full, by = c("gwcode", "yr"))
    t <- trimmed %>% left_join(out_full, by = c("gwcode", "yr"))
    est <- list("LP (OLS)"              = fit_one(f, "out", X),
                "LP, overlap sample"    = fit_one(t, "out", X),
                "IPW"                   = fit_one(t, "out", character(0), "w_ate"),
                "IPWRA (doubly robust)" = fit_one(t, "out", X, "w_ate"),
                "IPWRA, ATT"            = fit_one(t, "out", X, "w_att"))
    for (e in names(est)) rows[[length(rows) + 1]] <-
      est[[e]] %>% mutate(sample = s, timing = tm, type = type, horizon = h, estimator = e, .before = 1)
  }
}
estimates <- bind_rows(rows) %>%
  mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se, p_value = 2 * pnorm(-abs(estimate / se)),
         placebo = horizon < 0)
write_csv(estimates, file.path(TABLES, "dr_lp_estimates.csv"))

stars <- function(p) case_when(p < 0.01 ~ "***", p < 0.05 ~ "**", p < 0.1 ~ "*", TRUE ~ "")
md_tab <- estimates %>% filter(horizon %in% c(-3, 2, 3), type == "per year" | horizon == 3) %>%
  mutate(cell = sprintf("%.3f%s (%.3f) [%d]", estimate, stars(p_value), se, treated),
         column = case_when(horizon < 0 ~ "placebo y(t-3)", type == "cumulative" ~ "cum. h = 0..3",
                            TRUE ~ paste0("h = ", horizon))) %>%
  select(sample, timing, estimator, column, cell) %>%
  pivot_wider(names_from = column, values_from = cell)
writeLines(c("# Doubly robust LP: US cases without ICC (0/1) -> UCDP log deaths per 100k",
             "", "Estimate, stars, (clustered SE), [treated state-years]. Placebo: outcome y(t-3), should be ~0.", "",
             knitr::kable(md_tab)), file.path(TABLES, "dr_lp_estimates.md"))
print(as.data.frame(md_tab))

# =============================================================================
# 5. Figures
# =============================================================================
# Overlap: propensity by treatment, faceted by sample (shock second)
ov <- bind_rows(lapply(names(SAMPLES), function(s)
  prop[[paste(SAMPLES[[s]], "shock second")]]$data %>% transmute(sample = s, p, group = if_else(D == 1, "New US sanction", "No new US sanction"))))
p_ov <- ggplot(ov, aes(x = p)) +
  geom_histogram(bins = 40, fill = PAPER_COLOURS[["blue"]], colour = NA) +
  geom_vline(xintercept = TRIM, linetype = "dashed", colour = PAPER_COLOURS[["grey"]]) +
  scale_x_log10(labels = scales::label_number(accuracy = 0.001)) +
  facet_grid(group ~ sample, scales = "free_y") +
  labs(x = "Propensity score (log scale)", y = "State-years",
       title = "Overlap: how predictable are new US sanctions?",
       caption = paste0("Logit of a new US case (without ICC case 685) on y(t), y(t-1), y(t-2), D(t-1), D(t-2), region, 5-year period. ",
                        "Dashed line: trimming at p = ", TRIM, ". UCDP, 1989-2019.")) +
  theme_paper()
save_figure(p_ov, "dr1_overlap.png", 8, 5)

# Common support, drawn as in Jorda & Taylor (2016, Figure 2): kernel densities of the propensity score for
# treated (dashed) and control (solid) units on the full 0-1 scale, labelled directly. Shaded: region of common
# support by the min/max rule (from the larger of the two minima to the smaller of the two maxima).
cs_range <- ov %>% group_by(sample, group) %>% summarise(lo = min(p), hi = max(p), .groups = "drop") %>%
  group_by(sample) %>% summarise(lo = max(lo), hi = min(hi), .groups = "drop")
cs_dens <- ov %>% group_by(sample, group) %>%
  # smooth densities as in Jorda & Taylor: bandwidth 0.02 (the default rule picks ~0.005 here because the
  # propensity takes few distinct values, giving a spiky curve)
  reframe({ k <- density(p, from = 0, to = 1, n = 512, bw = 0.02); tibble(x = k$x, y = k$y) })
cs_labels <- cs_dens %>% group_by(sample, group) %>% slice_max(y, n = 1, with_ties = FALSE) %>%
  mutate(label = if_else(group == "New US sanction", "Distribution for treated units\n(new US sanction)",
                         "Distribution for control units\n(no new US sanction)"))
cs_counts <- ov %>% left_join(cs_range, by = "sample") %>% group_by(sample) %>%
  summarise(outside = sum(p < lo | p > hi), n = n(), .groups = "drop") %>% left_join(cs_range, by = "sample") %>%
  mutate(text = sprintf("Common support: %.3f to %.3f\n%d of %d state-years outside", lo, hi, outside, n))
p_cs <- ggplot() +
  geom_rect(data = cs_range, aes(xmin = lo, xmax = hi, ymin = -Inf, ymax = Inf), fill = "grey90") +
  geom_line(data = cs_dens, aes(x, y, colour = group, linetype = group), linewidth = 0.8) +
  geom_text(data = cs_labels, aes(x = x + 0.04, y = y, label = label, colour = group), hjust = 0, vjust = 0.5, size = 3) +
  geom_text(data = cs_counts, aes(x = 0.98, y = Inf, label = text), hjust = 1, vjust = 1.3, size = 2.8, colour = "grey30") +
  scale_colour_manual(values = c("New US sanction" = PAPER_COLOURS[["orange"]], "No new US sanction" = PAPER_COLOURS[["blue"]])) +
  scale_linetype_manual(values = c("New US sanction" = "dashed", "No new US sanction" = "solid")) +
  scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2)) +
  facet_wrap(~ sample, scales = "free_y") +
  labs(x = "Estimated probability of treatment (new US sanction)", y = "Density",
       title = "Overlap check: distributions of the treatment propensity score",
       caption = paste0("Kernel densities as in Jorda & Taylor (2016, Fig. 2). Logit of a new US case (without ICC case 685) on y(t), y(t-1), y(t-2), ",
                        "D(t-1), D(t-2), region, 5-year period;\nno country FE (Jorda & Taylor include them). Shaded: common support (min/max rule). UCDP, 1989-2019, shock second.")) +
  theme_paper() + theme(legend.position = "none")
save_figure(p_cs, "dr4_common_support.png", 9, 4.5)
write_csv(cs_counts %>% select(-text), file.path(TABLES, "dr_common_support.csv"))
print(as.data.frame(cs_counts %>% select(-text)))

# Balance (love plot), shock second
p_bal <- balance %>% filter(timing == "shock second") %>%
  pivot_longer(c(unweighted, ate_weighted, att_weighted), names_to = "weighting", values_to = "smd") %>%
  mutate(weighting = factor(weighting, c("unweighted", "ate_weighted", "att_weighted"),
                            c("Unweighted", "IPW (ATE)", "IPW (ATT)")),
         variable = paste0(variable, if_else(in_propensity, "", " (placebo)"))) %>%
  ggplot(aes(x = smd, y = variable, colour = weighting)) +
  geom_vline(xintercept = c(-0.1, 0.1), colour = "grey70", linetype = 2) +
  geom_vline(xintercept = 0, colour = "grey40") +
  geom_point(size = 2) +
  scale_colour_manual(values = unname(PAPER_COLOURS[c("grey", "blue", "orange")])) +
  facet_wrap(~ sample) +
  labs(x = "Standardised mean difference (sanctioned - not sanctioned)", y = NULL,
       title = "Balance on the violence and sanction history",
       caption = "Trimmed sample. y = log(1 + UCDP deaths per 100k), D = new US case. Placebo variables are not in the propensity model.") +
  theme_paper()
save_figure(p_bal, "dr2_balance.png", 8, 4)

# Paths, shock second
p_paths <- estimates %>% filter(timing == "shock second", estimator != "LP, overlap sample") %>%
  mutate(estimator = factor(estimator, ESTIMATORS), type = factor(type, c("per year", "cumulative"))) %>%
  ggplot(aes(x = horizon, y = estimate, ymin = lower, ymax = upper, colour = estimator)) +
  geom_hline(yintercept = 0, colour = "grey40") +
  geom_vline(xintercept = 0, colour = "grey80", linetype = 2) +
  geom_pointrange(position = position_dodge(width = 0.6), size = 0.25) +
  scale_colour_manual(values = unname(PAPER_COLOURS[c("grey", "aqua", "blue", "orange")])) +
  facet_grid(type ~ sample, scales = "free_y") +
  scale_x_continuous(breaks = -max(PLACEBO_LAGS):HORIZON, minor_breaks = NULL) +   # whole years only (user 10 Nov)
  labs(x = "Years after the new US sanction (negative = placebo on earlier violence)", y = "Effect on log(1 + deaths per 100k)",
       title = "US sanctions and deaths: OLS vs propensity-weighted local projections",
       caption = "Shock second (y(t) controlled). State and year FE, SEs clustered by state, 95% intervals ignore first-stage uncertainty. UCDP 1989-2019.") +
  theme_paper()
save_figure(p_paths, "dr3_lp_paths.png", 9, 6)
