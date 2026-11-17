# =============================================================================
# 28_us_trade_interaction.R — the pre-specified US trade-exposure test (decision D12, ANALYSIS_PLAN.md, written
# 2026-11-17 before this script was run; user: one final specification).
#
# D11 base LP in the sample "in conflict in t-1" (new US cases w/o ICC 685, log(1 + UCDP deaths per 100k), shock
# second, 2 lags of shock and response, state + year FE, no controls, SE by state, 1991-2019), plus
#   E = exposure (mean t-3..t-1), standardised in the estimation sample, terms x, x * E, E.
# Measures: trade_us_share (US share of the target's trade) = D12, pre-specified;
#           trade_us_gdp (trade with the US, % of GDP) = post-hoc variant (user, after the D12 result).
# D12 primary: x * E at h = 2 per year with trade_us_share. Secondary: cumulative y(t..t+3); effect of x at the 25th
# and 75th percentile of E. Figures (added with the post-hoc variant): x and x * E over h = 1..6 per year (fig52);
# effect of one US case across the exposure distribution at h = 2 (fig53).
# Output: tables/us_trade_interaction.csv, tables/us_trade_interaction_paths.csv, fig52, fig53
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

ICC_CASE <- 685
HORIZONS <- 0:6
MEASURES <- c(trade_us_share = "US share of trade (%), pre-specified (D12)",
              trade_us_gdp = "Trade with the US (% of GDP), post-hoc")
value_at <- function(data, variable, k) lag_by_year(data, variable, -k)

# D11 data, as in 21_us_robustness.R
us_counts <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% count(iso3c = country_iso3, yr = year, name = "x")
trade <- read_panel() %>% select(gwcode, yr, all_of(names(MEASURES)))
d <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(us_counts, by = c("iso3c", "yr")) %>% left_join(trade, by = c("gwcode", "yr")) %>%
  mutate(x = replace_na(x, 0L)) %>% arrange(gwcode, yr)
d <- add_lags(d, c("x", "viol_lev"), VAR_LAGS)
for (h in HORIZONS) d[[paste0("y_h", h)]] <- value_at(d, "viol_lev", h)
d$per_year_h2   <- d$y_h2
d$cumulative_h3 <- Reduce(`+`, lapply(0:3, function(j) value_at(d, "viol_lev", j)))
d$conflict_l1   <- lag_by_year(d, "viol_inc", 1)
HISTORY <- c(lag_names("x", VAR_LAGS), lag_names("viol_lev", VAR_LAGS), "viol_lev")

fit <- function(outcome, measure) {
  s <- d %>% filter(in_window, conflict_l1 %in% 1) %>% drop_na(all_of(c(outcome, "x", measure, HISTORY)))
  s$E <- (s[[measure]] - mean(s[[measure]])) / sd(s[[measure]])
  f <- feols(as.formula(paste(outcome, "~ x + x:E + E +", paste(HISTORY, collapse = " + "), "| gwcode + yr")),
             data = s, cluster = ~ gwcode)
  list(f = f, s = s, measure = measure)
}
# effect of one US case at exposure value e (standardised): b_x + e * b_xE, with its SE
effect_at <- function(m, e) {
  b <- coef(m$f); V <- vcov(m$f)
  tibble(estimate = b[["x"]] + e * b[["x:E"]], se = sqrt(V["x", "x"] + e^2 * V["x:E", "x:E"] + 2 * e * V["x", "x:E"]))
}

# Table (D12 layout, both measures) -----------------------------------------------------------------------
tab <- list()
for (measure in names(MEASURES)) for (outcome in c("per_year_h2", "cumulative_h3")) {
  m <- fit(outcome, measure); ct <- coeftable(m$f)
  pct <- function(q) bind_cols(tibble(term = paste0("Effect of x at p", q * 100, " (", round(quantile(m$s[[measure]], q), 1), ")")),
                               effect_at(m, quantile(m$s$E, q)))
  tab[[length(tab) + 1]] <- bind_rows(
    tibble(term = c("x (at mean E)", "x * E (per SD)", "E"), estimate = ct[c("x", "x:E", "E"), 1], se = ct[c("x", "x:E", "E"), 2]),
    pct(0.25), pct(0.75)) %>%
    mutate(measure = !!measure, outcome = !!outcome, sd_measure = !!sd(m$s[[measure]]), observations = nobs(m$f),
           states = n_distinct(m$s$gwcode), shock_years = sum(m$s$x > 0))
}
tab <- bind_rows(tab) %>% mutate(p_value = 2 * pnorm(-abs(estimate / se))) %>% relocate(measure, outcome)
write_csv(tab, file.path(TABLES, "us_trade_interaction.csv"))
print(tab %>% select(measure, outcome, term, estimate, se, p_value, sd_measure, observations, shock_years), n = 30, width = 200)

# Paths h = 0..6 and the marginal effect across exposure -----------------------------------------------------
paths <- list(); margins <- list(); shocks <- list()
for (measure in names(MEASURES)) {
  for (h in HORIZONS[-1]) {   # h = 0 is zero by construction (shock second: y_t is controlled)
    m <- fit(paste0("y_h", h), measure); ct <- coeftable(m$f)
    paths[[length(paths) + 1]] <- tibble(measure = measure, h = h, term = c("x (at mean exposure)", "x * exposure (per SD)"),
                                         estimate = ct[c("x", "x:E"), 1], se = ct[c("x", "x:E"), 2])
  }
  m <- fit("y_h2", measure)
  grid <- seq(quantile(m$s[[measure]], 0.01), quantile(m$s[[measure]], 0.99), length.out = 100)
  margins[[measure]] <- bind_cols(tibble(measure = measure, exposure = grid),
                                  effect_at(m, (grid - mean(m$s[[measure]])) / sd(m$s[[measure]])))
  shocks[[measure]] <- m$s %>% filter(x > 0, .data[[measure]] <= max(grid)) %>%
    transmute(measure = measure, exposure = .data[[measure]], gw_name)
}
paths <- bind_rows(paths) %>% mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
                                     p_value = 2 * pnorm(-abs(estimate / se)))
write_csv(paths, file.path(TABLES, "us_trade_interaction_paths.csv"))

fig52 <- paths %>% mutate(measure = factor(MEASURES[measure], levels = MEASURES)) %>%
  ggplot(aes(h, estimate)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = PAPER_COLOURS[["blue"]], alpha = 0.18) +
  geom_line(colour = PAPER_COLOURS[["blue"]]) + geom_point(colour = PAPER_COLOURS[["blue"]], size = 1.6) +
  facet_grid(term ~ measure, scales = "free_y") +
  scale_x_continuous(breaks = HORIZONS[-1]) +
  labs(title = "US sanctions in wars: does the effect depend on US trade exposure?",
       x = "Years after the new US case (h)", y = "Response of log(1 + UCDP deaths per 100k)",
       caption = paste("D11 local projection, state-years in conflict in t-1, plus exposure (mean t-3..t-1, standardised) and its interaction with the shock.",
                       "Top row: effect of one new US case at mean exposure. Bottom row: interaction (change in that effect per SD of exposure). 95% bands, SE by state.", sep = "\n")) +
  theme_paper()
save_figure(fig52, "fig52_us_trade_interaction_paths.png", 10, 6.5)

fig53 <- ggplot(bind_rows(margins) %>% mutate(measure = factor(MEASURES[measure], levels = MEASURES)), aes(exposure, estimate)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_ribbon(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se), fill = PAPER_COLOURS[["blue"]], alpha = 0.18) +
  geom_line(colour = PAPER_COLOURS[["blue"]]) +
  geom_rug(data = bind_rows(shocks) %>% mutate(measure = factor(MEASURES[measure], levels = MEASURES)),
           aes(x = exposure), inherit.aes = FALSE, sides = "b", alpha = 0.6, length = unit(0.04, "npc")) +
  facet_wrap(~ measure, scales = "free_x") +
  labs(title = "Effect of one new US case on deaths two years later, by the target's US trade exposure",
       x = "Exposure of the target to the US (mean t-3..t-1), 1st-99th percentile of the sample",
       y = "Response of log(1 + UCDP deaths per 100k) at h = 2",
       caption = "Linear interaction, so the line is straight by construction. Ticks: state-years with a new US case. 95% band, SE by state.") +
  theme_paper()
save_figure(fig53, "fig53_us_trade_interaction_margins.png", 10, 5)
