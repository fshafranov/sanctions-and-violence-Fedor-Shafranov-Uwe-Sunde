# =============================================================================
# 21_us_robustness.R — one robustness table for the US effect (added 2026-11-16, user request)
#
# Consolidates the checks of 13 (sections 5, 8), 19, 20 and doubly_robust/ against ONE fixed base specification
# (decision D11, ANALYSIS_PLAN.md):
#   local projection, shock = number of new US cases without ICC case 685, response = log(1 + UCDP deaths per 100k),
#   shock second (y_t controlled), 2 lags of shock and response, state + year FE, no controls, SE clustered by state;
#   outcomes y(t+2) and cumulative y(t..t+3); samples all state-years 1991-2019 and state-years in conflict in t-1.
# Every row changes exactly one thing relative to the base. All rows are reported, including the ones that weaken it.
#   estimated here: base; lagged controls; shock first; nonlinear history (deciles); peace-agreement controls;
#                   without the 5 most influential states (section 5); leave one country out (range);
#                   shocks before / from 2000 (one regression)
#   read in:        panel VAR (19, all state-years only); IPWRA doubly robust (doubly_robust/01, binary shock)
# Separate analyses stay in their scripts (they answer other questions): objective split (13.6), shock
# characteristics (13.8c), peace-process split, termination, reaction function (20), exposure (exposure/).
# Needs: 19_us_pvar.R, doubly_robust/scripts/01_dr_lp.R, data/clean/ucdp_peace (clean_ucdp_peace.R).
# Part B (added 2026-11-16, user: more than h = 2, and is it noise?): the base path over horizons h = -5..8, per year
#   and cumulative, both samples. h = -5..-3 are placebos (deaths BEFORE the shock, beyond the controlled lags y_t-1,
#   y_t-2, y_t; h = -2..0 are controlled and omitted). Permutation test: US shocks reshuffled across states within
#   each year and within the sample (in-conflict sample: among state-years in conflict in t-1 only), so the number of
#   US shocks per year in the sample is kept; lags rebuilt from the shuffled series, N_PERM draws, whole
#   path re-estimated -> the band that noise alone produces, a permutation p per horizon, and a family-wise p for
#   the largest |t| over h = 1..6 (does any horizon stand out more than chance across all horizons looked at?).
# Part C (added 2026-11-16, user: one figure for robustness across specifications): specification curve around the
#   base, all combinations of sample (all / in conflict), timing (shock second / first), lags (1 / 2 / 3), FE (state +
#   year / region + year), lagged controls (no / yes), history (linear / deciles), peace-agreement dummies (no / yes),
#   the 5 most influential states (kept / dropped), shock coding (count / 0-1) = 768 specifications per outcome.
# Output: tables/us_robustness.md/.csv, figures/fig37_us_robustness.png, tables/us_paths.csv, figures/fig38_us_paths.png,
#         tables/us_spec_curve.csv, figures/fig39_us_spec_curve_h2.png, fig39_us_spec_curve_cum3.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

ICC_CASE <- 685
TOP5 <- c("Yugoslavia", "Iraq", "Nepal", "Angola", "Liberia")   # 13 section 5: most influential states (cumulative)
OUTCOMES <- c(per_year_h2 = "Per year, h = 2", cumulative_h3 = "Cumulative, h = 0..3")
value_at <- function(data, variable, k) lag_by_year(data, variable, -k)

us_counts <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% count(iso3c = country_iso3, yr = year, name = "x")
peace <- read_csv(here("data", "clean", "ucdp_peace", "peace_cy.csv"), show_col_types = FALSE) %>%
  transmute(gwcode, yr = year, pa_n)
d <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(us_counts, by = c("iso3c", "yr")) %>% left_join(peace, by = c("gwcode", "yr")) %>%
  mutate(x = replace_na(x, 0L), pa_n = replace_na(pa_n, 0L)) %>% arrange(gwcode, yr)
d <- add_lags(d, c("x", "viol_lev"), VAR_LAGS)
d$per_year_h2   <- value_at(d, "viol_lev", 2)
d$cumulative_h3 <- Reduce(`+`, lapply(0:3, function(j) value_at(d, "viol_lev", j)))
d$conflict_l1   <- lag_by_year(d, "viol_inc", 1)
for (k in 0:2) d[[paste0("pa_", k)]] <- as.integer((if (k == 0) d$pa_n else lag_by_year(d, "pa_n", k)) > 0)
d$shock_pre <- d$x * (d$yr < 2000); d$shock_post <- d$x * (d$yr >= 2000)
SAMPLES <- list("All state-years" = function(z) z, "In conflict in t-1" = function(z) filter(z, conflict_l1 %in% 1))

BASE_HISTORY <- c(lag_names("x", VAR_LAGS), lag_names("viol_lev", VAR_LAGS), "viol_lev")
fit <- function(data, outcome, terms = "x", history = BASE_HISTORY, extra = character(0), deciles = FALSE) {
  s <- data %>% filter(in_window) %>% drop_na(all_of(c(outcome, terms, history, extra)))
  rhs <- c(terms, history, extra)
  if (deciles) {   # nonlinear history: decile dummies of y_t, y_t-1, y_t-2 within the sample
    s <- s %>% mutate(dec0 = ntile(viol_lev, 10), dec1 = ntile(viol_lev_l1, 10), dec2 = ntile(viol_lev_l2, 10))
    rhs <- c(rhs, "i(dec0)", "i(dec1)", "i(dec2)")
  }
  feols(as.formula(paste(outcome, "~", paste(rhs, collapse = " + "), "| gwcode + yr")), data = s, cluster = ~ gwcode)
}
row_of <- function(f, term, sample, outcome, check, group, used_data = NULL) {
  ct <- coeftable(f)
  tibble(group = group, check = check, sample = sample, outcome = outcome, estimate = ct[term, 1], se = ct[term, 2],
         p_value = ct[term, 4], lower = estimate - 1.96 * se, upper = estimate + 1.96 * se, observations = nobs(f))
}

rows <- list()
add <- function(r) rows[[length(rows) + 1]] <<- r
for (sample_name in names(SAMPLES)) for (outcome in names(OUTCOMES)) {
  ds <- SAMPLES[[sample_name]](d)
  base <- fit(ds, outcome)
  add(row_of(base, "x", sample_name, outcome, "Base", "Base"))
  add(row_of(fit(ds, outcome, extra = CONTROLS), "x", sample_name, outcome,
             "Lagged controls (sanction stock, GDP growth, democracy)", "Specification"))
  add(row_of(fit(ds, outcome, history = setdiff(BASE_HISTORY, "viol_lev")), "x", sample_name, outcome,
             "Shock first (no same-year violence control)", "Specification"))
  add(row_of(fit(ds, outcome, deciles = TRUE), "x", sample_name, outcome,
             "Nonlinear history (deciles of y in t, t-1, t-2)", "Specification"))
  add(row_of(fit(ds, outcome, extra = c("pa_0", "pa_1", "pa_2")), "x", sample_name, outcome,
             "Peace-agreement dummies t-2..t (UCDP)", "Specification"))
  add(row_of(fit(filter(ds, !gw_name %in% TOP5), outcome), "x", sample_name, outcome,
             "Without the 5 most influential states", "Sample"))
  states <- ds %>% filter(in_window, x > 0) %>% distinct(gwcode) %>% pull(gwcode)
  loo <- sapply(states, function(g) coef(fit(filter(ds, gwcode != g), outcome))[["x"]])
  loo_p <- sapply(states, function(g) pvalue(fit(filter(ds, gwcode != g), outcome))[["x"]])
  add(tibble(group = "Sample", check = "Leave one country out (range)", states_dropped = length(states),
             sample = sample_name, outcome = outcome, estimate = median(loo), se = NA_real_, p_value = max(loo_p),
             lower = min(loo), upper = max(loo), observations = NA_integer_))
  fp <- fit(ds, outcome, terms = c("shock_pre", "shock_post"))
  add(row_of(fp, "shock_pre", sample_name, outcome, "Shocks 1991-99", "Period"))
  add(row_of(fp, "shock_post", sample_name, outcome, "Shocks 2000-19", "Period"))
}

# Read-in estimators --------------------------------------------------------------------------------------
pvar_file <- file.path(TABLES, "pvar_us_periods.csv")
dr_file <- here("doubly_robust", "results", "tables", "dr_lp_estimates.csv")
stopifnot(file.exists(pvar_file), file.exists(dr_file))
pvar <- read_csv(pvar_file, show_col_types = FALSE) %>%
  filter(part == "irf", sample == "1991-2019", (type == "per_year" & horizon == 2) | (type == "cumulative" & horizon == 3)) %>%
  transmute(group = "Estimator", check = "Panel VAR(2), bootstrap (script 19)", sample = "All state-years",
            outcome = ifelse(type == "per_year", "per_year_h2", "cumulative_h3"), estimate, se, p_value = p_boot,
            lower, upper, observations)
dr <- read_csv(dr_file, show_col_types = FALSE) %>%
  filter(timing == "shock second", estimator == "IPWRA (doubly robust)",
         (type == "per year" & horizon == 2) | (type == "cumulative" & horizon == 3)) %>%
  transmute(group = "Estimator", check = "IPWRA doubly robust, any new US case 0/1 (doubly_robust/)", sample,
            outcome = ifelse(type == "per year", "per_year_h2", "cumulative_h3"), estimate, se, p_value, lower, upper,
            observations)
res <- bind_rows(bind_rows(rows), pvar, dr) %>% arrange(factor(group, levels = c("Base", "Specification", "Sample", "Period", "Estimator")))
write_csv(res, file.path(TABLES, "us_robustness.csv"))

# Figure ----------------------------------------------------------------------------------------------------
GROUPS <- c("Base", "Specification", "Sample", "Period", "Estimator")
plot_data <- res %>% mutate(check = factor(check, levels = rev(unique(res$check))), group = factor(group, levels = GROUPS),
                            outcome = factor(OUTCOMES[outcome], levels = OUTCOMES), is_range = is.na(se))
base_lines <- res %>% filter(check == "Base") %>%
  mutate(outcome = factor(OUTCOMES[outcome], levels = OUTCOMES), group = factor(group, levels = GROUPS))
COLS <- c("All state-years" = PAPER_COLOURS[["blue"]], "In conflict in t-1" = PAPER_COLOURS[["orange"]])
fig37 <- ggplot(plot_data, aes(estimate, check, colour = sample)) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(data = base_lines, aes(xintercept = estimate, colour = sample), linetype = "dashed", linewidth = 0.3,
             show.legend = FALSE) +
  geom_errorbarh(aes(xmin = lower, xmax = upper, linewidth = is_range), height = 0, position = position_dodge(width = 0.6)) +
  geom_point(aes(shape = is_range), size = 1.8, position = position_dodge(width = 0.6)) +
  scale_linewidth_manual(values = c(`FALSE` = 0.5, `TRUE` = 1.8), guide = "none") +
  scale_shape_manual(values = c(`FALSE` = 16, `TRUE` = 124), guide = "none") +
  scale_colour_manual(values = COLS) +
  facet_grid(group ~ outcome, scales = "free", space = "free_y") +
  labs(title = "The US effect: base specification and robustness checks",
       x = "Response of log(1 + UCDP deaths per 100k) to one new US case (without ICC case 685)", y = NULL, colour = NULL,
       caption = paste0("Base: local projection, shock second, ", VAR_LAGS, " lags of shock and response, state and year FE, no controls; ",
                        "each row changes one thing. 95% intervals, SE clustered by state (VAR: bootstrap).\n",
                        "Dashed line: base estimate. Leave one country out: thick bar = range of the estimates (every state with a shock dropped once), mark = median. ",
                        "Doubly robust row uses a 0/1 shock; VAR not estimated for the in-conflict sample.")) +
  theme_paper() + theme(legend.position = "top", strip.text.y = element_text(angle = 0, hjust = 0))
save_figure(fig37, "fig37_us_robustness.png", 12, 7.5)

# Table -----------------------------------------------------------------------------------------------------
cell <- function(e, s, p, lo, hi, n) ifelse(is.na(s), sprintf("median %.3f [%.3f, %.3f], max p %.3f, %d states", e, lo, hi, p, as.integer(n)),
                                         sprintf("%.3f%s (%.3f)", e, significance_stars(p), s))
tab <- res %>% mutate(cell = cell(estimate, se, p_value, lower, upper, states_dropped), column = paste(sample, OUTCOMES[outcome], sep = ", ")) %>%
  select(group, check, column, cell) %>% pivot_wider(names_from = column, values_from = cell)
to_md <- function(table) c(paste0("| ", paste(names(table), collapse = " | "), " |"),
                           paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
                           apply(table, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "—", r), collapse = " | "), " |")), "")
writeLines(c(
  "# The US effect: base specification and robustness", "",
  paste0("Generated by `empirics/scripts/21_us_robustness.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figure `fig37_us_robustness.png`; all estimates `us_robustness.csv`."), "",
  "Base (decision D11): local projection, shock = new US cases without ICC 685, response log(1 + UCDP deaths per 100k), ",
  "shock second, 2 lags of shock and response, state and year FE, no controls, SE clustered by state, shock years 1991-2019. ",
  "Each row changes one thing. Cells: coefficient (SE).", "",
  to_md(tab),
  paste0("*Notes:* * p<0.1, ** p<0.05, *** p<0.01. Most influential states (13 section 5): ", paste(TOP5, collapse = ", "),
         ". Peace agreements: UCDP v22.2. VAR: 199 state-cluster bootstrap draws. Doubly robust: Jorda-Taylor IPWRA with a 0/1 shock.")
), file.path(TABLES, "us_robustness.md"))
cat("\nWrote", file.path(TABLES, "us_robustness.md"), "\n")


# =============================================================================
# Part B: the whole path, placebo horizons, permutation inference
# =============================================================================
N_PERM <- as.integer(Sys.getenv("PERM_DRAWS", "300"))
PRE <- -5:-3; POST <- 1:8; FW <- 1:6
hn <- function(h) ifelse(h < 0, paste0("m", -h), as.character(h))   # py_m5 = y(t-5)
for (h in c(PRE, POST)) {
  d[[paste0("py_", hn(h))]] <- if (h < 0) lag_by_year(d, "viol_lev", -h) else value_at(d, "viol_lev", h)
  if (h > 0) d[[paste0("cy_", h)]] <- Reduce(`+`, lapply(0:h, function(j) value_at(d, "viol_lev", j)))
}
PATH_VARS <- c(paste0("py_", hn(c(PRE, POST))), paste0("cy_", POST))
path_fit <- function(data) {   # one fixest multi-LHS call; each outcome keeps its own non-missing sample
  s <- data %>% filter(in_window) %>% drop_na(all_of(c("x", BASE_HISTORY)))
  m <- feols(as.formula(paste0("c(", paste(PATH_VARS, collapse = ", "), ") ~ x + ", paste(BASE_HISTORY, collapse = " + "),
                               " | gwcode + yr")), data = s, cluster = ~ gwcode)
  bind_rows(lapply(seq_along(PATH_VARS), function(i) { ct <- coeftable(m[[i]])
    tibble(var = PATH_VARS[i], estimate = ct["x", 1], se = ct["x", 2], p_value = ct["x", 4], observations = nobs(m[[i]]),
           shock_years = sum(s$x[!is.na(s[[PATH_VARS[i]]])] > 0)) }))
}
permute_shock <- function(data, in_sample) {   # shuffle x across states within year x (in sample / not), rebuild lags
  data %>% mutate(cell = in_sample) %>% group_by(yr, cell) %>% mutate(x = sample(x)) %>% ungroup() %>%
    select(-cell) %>% arrange(gwcode, yr) %>%
    { z <- .; for (k in seq_len(VAR_LAGS)) z[[paste0("x_l", k)]] <- lag_by_year(z, "x", k); z }
}
set.seed(20261116)
paths <- list(); perms <- list()
for (sample_name in names(SAMPLES)) {
  ds <- SAMPLES[[sample_name]](d)
  obs <- path_fit(ds) %>% mutate(sample = sample_name)
  keep <- paste(ds$gwcode, ds$yr)
  in_s <- paste(d$gwcode, d$yr) %in% keep
  draws <- bind_rows(lapply(seq_len(N_PERM), function(b) {
    z <- permute_shock(d, in_s)   # shuffle within year among the sample's state-years (same shock count per year)
    path_fit(z[paste(z$gwcode, z$yr) %in% keep, ]) %>% mutate(draw = b)
  }))
  perms[[sample_name]] <- draws %>% mutate(sample = sample_name)
  obs <- obs %>% left_join(draws %>% group_by(var) %>%
                             summarise(null_lo = quantile(estimate, 0.025), null_hi = quantile(estimate, 0.975), .groups = "drop"),
                           by = "var") %>%
    mutate(p_perm = sapply(seq_len(n()), function(i) mean(abs(draws$estimate[draws$var == var[i]]) >= abs(estimate[i]))))
  # family-wise: largest |t| over the per-year (and, separately, cumulative) horizons 1..6
  for (prefix in c("py_", "cy_")) {
    v <- paste0(prefix, FW)
    t_obs <- max(abs(obs$estimate[obs$var %in% v] / obs$se[obs$var %in% v]))
    t_null <- draws %>% filter(var %in% v) %>% group_by(draw) %>% summarise(m = max(abs(estimate / se))) %>% pull(m)
    obs$p_familywise[obs$var %in% v] <- mean(t_null >= t_obs)
  }
  paths[[sample_name]] <- obs
  cat(sample_name, ": permutations done\n")
}
paths <- bind_rows(paths) %>%
  mutate(type = ifelse(startsWith(var, "py_"), "Per year, t + h", "Cumulative, t .. t + h"),
         horizon = as.integer(sub("^m", "-", sub("^.y_", "", var))), lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
write_csv(paths, file.path(TABLES, "us_paths.csv"))

plot_paths <- paths %>% mutate(type = factor(type, levels = c("Per year, t + h", "Cumulative, t .. t + h")),
                               segment = ifelse(horizon < 0, "pre", "post"))
fig38 <- ggplot(plot_paths, aes(horizon, estimate, group = segment)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3, linetype = "dotted") +
  geom_ribbon(aes(ymin = null_lo, ymax = null_hi), fill = "#8a8984", alpha = 0.25) +
  geom_ribbon(aes(ymin = lower, ymax = upper, fill = sample), alpha = 0.15) +
  geom_line(aes(colour = sample), linewidth = 0.7) + geom_point(aes(colour = sample), size = 1.2) +
  facet_grid(type ~ sample, scales = "free_y") +
  scale_colour_manual(values = COLS, guide = "none") + scale_fill_manual(values = COLS, guide = "none") +
  scale_x_continuous(breaks = c(PRE, 0, POST)) +
  labs(title = "Deaths before and after a new US sanction, with the band that random shocks produce",
       x = "Years relative to the sanction (h); h = -2..0 are controlled in the base and not shown",
       y = "Response of log(1 + UCDP deaths per 100k)",
       caption = paste0("Base specification (D11), one regression per horizon. Coloured band: 95% interval, SE clustered by state. ",
                        "Grey band: 2.5-97.5% of the estimates when US shocks are\nreshuffled across the sample's states within each year (",
                        N_PERM, " permutations), i.e. what noise alone produces. h < 0: placebo (deaths before the shock). ",
                        "Outcomes end 2019, so long horizons lose late shocks.")) +
  theme_paper()
save_figure(fig38, "fig38_us_paths.png", 12, 7)

path_tab <- paths %>%
  mutate(cell = sprintf("%.3f (%.3f) p_perm %.3f", estimate, se, p_perm)) %>%
  select(sample, type, horizon, cell) %>% pivot_wider(names_from = horizon, names_prefix = "h", values_from = cell)
fw_tab <- paths %>% filter(!is.na(p_familywise)) %>% distinct(sample, type, p_familywise)
write(c("", "## Part B: the whole path, placebo horizons and permutation inference", "",
        paste0("Base specification, h = -5..-3 (placebo) and 1..8. Cells: estimate (clustered SE) and the permutation p ",
               "(share of ", N_PERM, " within-year reshuffles of the US shocks with |estimate| at least as large). ",
               "Figure `fig38_us_paths.png`; estimates and noise bands `us_paths.csv`."), "",
        to_md(path_tab),
        "Family-wise permutation p (largest |t| over h = 1..6 against the same statistic under reshuffling):", "",
        to_md(fw_tab %>% mutate(p_familywise = sprintf("%.3f", p_familywise)))),
      file.path(TABLES, "us_robustness.md"), append = TRUE)
cat("Appended part B to", file.path(TABLES, "us_robustness.md"), "\n")


# =============================================================================
# Part C: specification curve around the base
# =============================================================================
gw_region <- function(code) cut(code, c(0, 199, 399, 626, 699, 999),
                                labels = c("Americas", "Europe", "Africa", "Middle East", "Asia and Oceania"))
g <- d %>% mutate(xb = as.integer(x > 0), region = as.character(gw_region(gwcode)))
g <- add_lags(g, c("x", "xb", "viol_lev"), 3)
g <- g %>% mutate(dec_t = ntile(viol_lev, 10), dec_1 = ntile(viol_lev_l1, 10), dec_2 = ntile(viol_lev_l2, 10))
DIMS <- list(sample   = c(all = "All state-years", war = "In conflict in t-1"),
             timing   = c(second = "Shock second", first = "Shock first"),
             lags     = c(`2` = "2 lags", `1` = "1 lag", `3` = "3 lags"),
             fe       = c(state = "State + year FE", region = "Region + year FE"),
             controls = c(no = "No controls", yes = "Lagged controls"),
             history  = c(linear = "Linear history", deciles = "Decile dummies"),
             peace    = c(no = "No peace dummies", yes = "Peace dummies t-2..t"),
             top5     = c(kept = "All states", dropped = "Without top-5 states"),
             shock    = c(count = "Count of new cases", binary = "Any new case (0/1)"))
DIM_LABELS <- c(sample = "Sample", timing = "Timing", lags = "Lags", fe = "Fixed effects", controls = "Controls",
                history = "History", peace = "Peace agreements", top5 = "Influential states", shock = "Shock coding")
grid <- expand.grid(lapply(DIMS, names), stringsAsFactors = FALSE)
spec_fit <- function(spec, outcome) {
  sv <- if (spec$shock == "count") "x" else "xb"; L <- as.integer(spec$lags)
  hist <- c(lag_names(sv, L), lag_names("viol_lev", L), if (spec$timing == "second") "viol_lev")
  extra <- c(if (spec$controls == "yes") CONTROLS, if (spec$peace == "yes") c("pa_0", "pa_1", "pa_2"),
             if (spec$history == "deciles") c(if (spec$timing == "second") "i(dec_t)", "i(dec_1)", if (L >= 2) "i(dec_2)"))
  z <- g %>% filter(in_window)
  if (spec$sample == "war") z <- filter(z, conflict_l1 %in% 1)
  if (spec$top5 == "dropped") z <- filter(z, !gw_name %in% TOP5)
  z <- drop_na(z, all_of(c(outcome, sv, hist, if (spec$controls == "yes") CONTROLS)))
  fe <- if (spec$fe == "state") "gwcode + yr" else "region + yr"
  f <- feols(as.formula(paste(outcome, "~", paste(c(sv, hist, extra), collapse = " + "), "|", fe)), data = z, cluster = ~ gwcode)
  ct <- coeftable(f)
  c(estimate = ct[sv, 1], se = ct[sv, 2], p_value = ct[sv, 4], observations = nobs(f))
}
curve <- bind_rows(lapply(names(OUTCOMES), function(outcome) {
  bind_cols(grid, as_tibble(do.call(rbind, lapply(seq_len(nrow(grid)), function(i) spec_fit(grid[i, ], outcome))))) %>%
    mutate(outcome = outcome)
})) %>%
  mutate(is_base = sample %in% c("all", "war") & timing == "second" & lags == "2" & fe == "state" & controls == "no" &
           history == "linear" & peace == "no" & top5 == "kept" & shock == "count",
         significance = case_when(p_value < 0.05 & estimate < 0 ~ "negative, p < 0.05",
                                  p_value < 0.05 & estimate > 0 ~ "positive, p < 0.05", TRUE ~ "not significant"))
write_csv(curve, file.path(TABLES, "us_spec_curve.csv"))

SIG_COLS <- c("negative, p < 0.05" = PAPER_COLOURS[["blue"]], "positive, p < 0.05" = PAPER_COLOURS[["orange"]],
              "not significant" = "#a8a7a3")
draw_curve <- function(outcome_name, file) {
  data <- curve %>% filter(outcome == outcome_name) %>% arrange(estimate) %>% mutate(rank = row_number())
  est <- data %>% mutate(panel = "Estimate (95% CI)", low = estimate - 1.96 * se, high = estimate + 1.96 * se)
  step <- diff(range(c(est$low, est$high))) / 16; OFFSET <- 1000
  positions <- numeric(0); dash <- list(); pads <- list()
  for (k in seq_along(DIMS)) {
    dim <- names(DIMS)[k]; opts <- names(DIMS[[dim]]); n <- length(opts)
    y_of <- setNames(OFFSET * k + (n - seq_len(n) + 1) * step, opts)
    positions <- c(positions, setNames(unname(y_of), DIMS[[dim]]))
    dash[[k]] <- tibble(rank = data$rank, significance = data$significance, panel = DIM_LABELS[[dim]], y = unname(y_of[data[[dim]]]))
    pads[[k]] <- tibble(rank = 1, panel = DIM_LABELS[[dim]], y = OFFSET * k + c(0.4, n + 0.6) * step)
  }
  lev <- c("Estimate (95% CI)", unname(DIM_LABELS))
  as_panel <- function(x) mutate(x, panel = factor(panel, levels = lev))
  est <- as_panel(est); dash <- as_panel(bind_rows(dash)); pads <- as_panel(bind_rows(pads))
  brk <- function(l) if (min(l) > OFFSET / 2) positions[positions >= l[1] & positions <= l[2]] else pretty(l, 4)
  lab <- function(b) ifelse(b > OFFSET / 2, names(positions)[sapply(b, function(v) which.min(abs(positions - v)))], format(b, trim = TRUE))
  shares <- data %>% group_by(sample) %>% summarise(neg = mean(significance == "negative, p < 0.05"),
                                                    pos = mean(significance == "positive, p < 0.05"), med = median(estimate))
  sub <- paste0(nrow(data), " specifications; circled = base (one per sample). Significant negative: ",
                paste0(DIMS$sample[shares$sample], " ", round(100 * shares$neg), "%", collapse = ", "),
                "; significant positive: ", paste0(round(100 * shares$pos), "%", collapse = " / "), ".")
  fig <- ggplot() +
    geom_hline(data = as_panel(tibble(panel = "Estimate (95% CI)")), aes(yintercept = 0), colour = "#52514e", linewidth = 0.3) +
    geom_linerange(data = est, aes(rank, ymin = low, ymax = high, colour = significance), alpha = 0.35, linewidth = 0.3) +
    geom_point(data = est, aes(rank, estimate, colour = significance), size = 0.7) +
    geom_point(data = filter(est, is_base), aes(rank, estimate), shape = 21, size = 3, stroke = 0.9, colour = "black", fill = NA) +
    geom_point(data = dash, aes(rank, y, colour = significance), shape = 124, size = 1.4) +
    geom_blank(data = pads, aes(rank, y)) +
    facet_grid(panel ~ ., scales = "free_y", space = "free_y") +
    scale_y_continuous(breaks = brk, labels = lab, expand = expansion(mult = 0.02)) +
    scale_colour_manual(values = SIG_COLS) +
    labs(title = paste0("Specification curve: response of log(1 + UCDP deaths per 100k) to a new US case, ", OUTCOMES[[outcome_name]]),
         subtitle = sub, x = "Specifications, sorted by estimate", y = NULL, colour = NULL,
         caption = paste0("Each column is one specification; the marks below show its choices. US cases without ICC case 685, ",
                          "shock years 1991-2019, SE clustered by state. Top-5 states: ", paste(TOP5, collapse = ", "), ".")) +
    theme_paper() + theme(legend.position = "top", strip.text.y = element_text(angle = 0, hjust = 0),
                          axis.text.x = element_blank(), panel.grid.minor = element_blank())
  save_figure(fig, file, 12, 10)
}
draw_curve("per_year_h2", "fig39_us_spec_curve_h2.png")
draw_curve("cumulative_h3", "fig39_us_spec_curve_cum3.png")

curve_sum <- bind_rows(
  curve %>% group_by(outcome, sample) %>% mutate(dimension = "all", option = "all") ,
  bind_rows(lapply(setdiff(names(DIMS), "sample"), function(dm) curve %>% mutate(dimension = dm, option = .data[[dm]])))) %>%
  group_by(outcome, sample, dimension, option) %>%
  summarise(specs = n(), median = sprintf("%.3f", median(estimate)), min = sprintf("%.3f", min(estimate)),
            max = sprintf("%.3f", max(estimate)), sig_negative = sprintf("%.0f%%", 100 * mean(significance == "negative, p < 0.05")),
            sig_positive = sprintf("%.0f%%", 100 * mean(significance == "positive, p < 0.05")), .groups = "drop") %>%
  mutate(outcome = OUTCOMES[outcome], sample = DIMS$sample[sample],
         option = ifelse(dimension == "all", "all", mapply(function(dm, o) DIMS[[dm]][[o]], dimension, option)))
write(c("", "## Part C: specification curve around the base", "",
        paste0(nrow(grid), " specifications per outcome (all combinations of the dimensions below). Figures ",
               "`fig39_us_spec_curve_h2.png`, `fig39_us_spec_curve_cum3.png`; estimates `us_spec_curve.csv`."), "",
        to_md(curve_sum)), file.path(TABLES, "us_robustness.md"), append = TRUE)
cat("Appended part C to", file.path(TABLES, "us_robustness.md"), "\n")
