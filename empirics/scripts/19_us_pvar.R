# =============================================================================
# 19_us_pvar.R — panel VAR impulse responses for the US shock, by period (added 2026-11-16, user request)
#
# Question: does the panel VAR (the Jaeger & Paserman base case, 08_irf.R) give the same picture as the local
# projections of 13_local_projections.R section 8 for US sanctions, and is it more precise?
# 08 uses ALL new GSDB cases; here the shock is the number of new US cases without ICC case 685, as in 13.
#
# Model: bivariate VAR(2) in (viol_lev, x), x = new US cases w/o 685, viol_lev = log(1 + UCDP deaths per 100k),
#   state and year FE in both equations, no controls; IRF of viol_lev to a one-unit x shock, "simple" timing
#   (no same-year effect of x on violence = the LP's "shock second"). Per year h = 1..6 and cumulative 0..h.
# Samples: all years 1991-2019; separate VARs on shock years 1991-99, 2000-09, 2010-19, 2000-19 (own FE and
#   coefficients; lags reach back before the window).
# Inference: state-cluster bootstrap, N_BOOT draws; each draw resamples states once and re-estimates every sample on
#   it, so the draws also give the distribution of the 1991-99 minus 2000-19 (and 2010-19) differences.
# Not done: the in-conflict sample (conditioning a VAR on violence in t-1 breaks its own dynamics).
# Comparison: LP estimates of the same samples from tables/lp_us_over_time.csv and lp_us_effect_location.csv (13).
# Output: tables/pvar_us_periods.md/.csv, figures/fig35_pvar_us_periods.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")
set.seed(20261116)

N_BOOT <- as.integer(Sys.getenv("IRF_BOOT_DRAWS", "199"))
H <- 6
ICC_CASE <- 685
SAMPLES <- list("1991-2019" = c(1991, 2019), "1991-99" = c(1991, 1999), "2000-09" = c(2000, 2009),
                "2010-19" = c(2010, 2019), "2000-19" = c(2000, 2019))

us_counts <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% count(iso3c = country_iso3, yr = year, name = "x")
panel <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(us_counts, by = c("iso3c", "yr")) %>% mutate(x = replace_na(x, 0L)) %>% arrange(gwcode, yr)
panel <- add_lags(panel, c("x", "viol_lev"), VAR_LAGS)
REGRESSORS <- c(lag_names("viol_lev", VAR_LAGS), lag_names("x", VAR_LAGS))
samples <- lapply(SAMPLES, function(r) panel %>% filter(in_window, yr >= r[1], yr <= r[2]) %>%
                    drop_na(all_of(c("viol_lev", "x", REGRESSORS))))

# Response of violence to a unit US shock, h = 0..H (simple timing: response at h = 0 is 0)
var_irf <- function(d) {
  f <- function(y) feols(as.formula(paste(y, "~", paste(REGRESSORS, collapse = " + "), "| gwcode + yr")), d)
  Phi <- var_ma_coefficients(coef(f("viol_lev")), coef(f("x")), "viol_lev", "x", VAR_LAGS, H)
  sapply(Phi, function(P) P[1, 2])
}
point <- lapply(samples, var_irf)

# Bootstrap: one draw of states, applied to every sample
states <- unique(panel$gwcode)
draws <- replicate(N_BOOT, {
  drawn <- sample(states, length(states), replace = TRUE)
  lapply(samples, function(d) {
    db <- bind_rows(lapply(seq_along(drawn), function(i) mutate(d[d$gwcode == drawn[i], ], gwcode = i)))
    var_irf(db)
  })
}, simplify = FALSE)

summarise_stat <- function(est, boot) tibble(estimate = est, se = sd(boot), lower = unname(quantile(boot, 0.025)),
                                             upper = unname(quantile(boot, 0.975)),
                                             p_boot = min(1, 2 * min(mean(boot <= 0), mean(boot >= 0))))
rows <- list()
for (s in names(SAMPLES)) for (type in c("per_year", "cumulative")) for (h in 1:H) {
  stat <- function(r) if (type == "per_year") r[h + 1] else sum(r[1:(h + 1)])
  rows[[length(rows) + 1]] <- summarise_stat(stat(point[[s]]), sapply(draws, function(b) stat(b[[s]]))) %>%
    mutate(sample = s, type = type, horizon = h, observations = nrow(samples[[s]]),
           shock_years = sum(samples[[s]]$x > 0), .before = 1)
}
pvar <- bind_rows(rows)

# Differences between periods (same bootstrap draws)
diffs <- list()
for (cmp in list(c("1991-99", "2000-19"), c("1991-99", "2010-19"), c("1991-99", "2000-09"))) {
  for (spec in list(c("per_year", 2), c("cumulative", 3))) {
    h <- as.integer(spec[2])
    stat <- function(r) if (spec[1] == "per_year") r[h + 1] else sum(r[1:(h + 1)])
    diffs[[length(diffs) + 1]] <- summarise_stat(stat(point[[cmp[1]]]) - stat(point[[cmp[2]]]),
                                                 sapply(draws, function(b) stat(b[[cmp[1]]]) - stat(b[[cmp[2]]]))) %>%
      mutate(comparison = paste(cmp, collapse = " minus "), type = spec[1], horizon = h, .before = 1)
  }
}
diffs <- bind_rows(diffs)
write_csv(bind_rows(mutate(pvar, part = "irf"), mutate(diffs, part = "difference")),
          file.path(TABLES, "pvar_us_periods.csv"))

# LP comparison (script 13): same samples, h = 2 and cumulative 0..3
lp_time <- read_csv(file.path(TABLES, "lp_us_over_time.csv"), show_col_types = FALSE)
lp_loc  <- read_csv(file.path(TABLES, "lp_us_effect_location.csv"), show_col_types = FALSE)
lp <- bind_rows(
  lp_loc %>% filter(group == "Full sample") %>% transmute(sample = "1991-2019", outcome, estimate, se, p_value),
  lp_time %>% filter(grepl("^Separate sample", check)) %>%
    transmute(sample = sub("^Separate sample (\\d{4})-\\d\\d(\\d\\d)$", "\\1-\\2", check), outcome, estimate, se, p_value)) %>%
  mutate(type = ifelse(outcome == "per_year_h2", "per_year", "cumulative"), horizon = ifelse(type == "per_year", 2L, 3L))
stopifnot(setequal(lp$sample, names(SAMPLES)))

# Figure: VAR paths with 95% bootstrap bands; LP estimate (h = 2 per year, h = 3 cumulative) as black point
TYPE_LABELS <- c(per_year = "Per year, t + h", cumulative = "Cumulative, h = 0..h")
plot_pvar <- pvar %>% mutate(sample = factor(sample, levels = names(SAMPLES)),
                             type = factor(TYPE_LABELS[type], levels = TYPE_LABELS))
plot_lp <- lp %>% mutate(sample = factor(sample, levels = names(SAMPLES)), type = factor(TYPE_LABELS[type], levels = TYPE_LABELS),
                         lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
fig35 <- ggplot(plot_pvar, aes(horizon, estimate)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_ribbon(aes(ymin = lower, ymax = upper), fill = PAPER_COLOURS[["blue"]], alpha = 0.15) +
  geom_line(colour = PAPER_COLOURS[["blue"]], linewidth = 0.7) + geom_point(colour = PAPER_COLOURS[["blue"]], size = 1) +
  geom_errorbar(data = plot_lp, aes(ymin = lower, ymax = upper), width = 0, colour = "#14171c",
                position = position_nudge(x = 0.18)) +
  geom_point(data = plot_lp, colour = "#14171c", shape = 18, size = 2.4, position = position_nudge(x = 0.18)) +
  facet_grid(type ~ sample, scales = "free_y") +
  scale_x_continuous(breaks = 1:H) +
  labs(title = "Deaths after a new US sanction: panel VAR by period, with the local projection for comparison",
       x = "Years after the sanction (h)", y = "Response of log(1 + UCDP deaths per 100k)",
       caption = paste0("Blue: VAR(", VAR_LAGS, ") impulse response, US cases without ICC case 685, no same-year effect, ",
                        "state and year FE, separate VAR per period; 95% band from ", N_BOOT, " state-cluster bootstrap draws.\n",
                        "Black: local projection of the same sample (script 13; h = 2 per year, h = 0..3 cumulative), ",
                        "95% interval, SE clustered by state.")) +
  theme_paper()
save_figure(fig35, "fig35_pvar_us_periods.png", 13, 6)

to_markdown_table <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
cell <- function(e, s, p) sprintf("%.3f%s (%.3f)", e, significance_stars(p), s)
compare <- pvar %>% filter((type == "per_year" & horizon == 2) | (type == "cumulative" & horizon == 3)) %>%
  transmute(sample, type, shock_years, VAR = cell(estimate, se, p_boot)) %>%
  left_join(lp %>% transmute(sample, type, LP = cell(estimate, se, p_value)), by = c("sample", "type")) %>%
  mutate(type = recode(type, per_year = "h = 2", cumulative = "cum. 0..3")) %>%
  pivot_wider(names_from = type, values_from = c(VAR, LP)) %>%
  mutate(sample = factor(sample, levels = names(SAMPLES))) %>% arrange(sample)
paths <- pvar %>% mutate(cell = cell(estimate, se, p_boot)) %>% select(sample, type, horizon, cell) %>%
  pivot_wider(names_from = horizon, names_prefix = "h", values_from = cell)
writeLines(c(
  "# Panel VAR for the US shock, by period", "",
  paste0("Generated by `empirics/scripts/19_us_pvar.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figure `fig35_pvar_us_periods.png`; all estimates `pvar_us_periods.csv`."), "",
  paste0("VAR(", VAR_LAGS, ") in log(1 + UCDP deaths per 100k) and new US cases without ICC 685, state and year FE, ",
         "no same-year effect of the shock; separate VAR per period of shock years. Cells: estimate (bootstrap SE), ",
         "stars from the ", N_BOOT, " state-cluster bootstrap draws (VAR) or clustered SE (LP)."), "",
  "## VAR vs local projection", "",
  to_markdown_table(compare),
  "## Period differences (VAR, same bootstrap draws)", "",
  to_markdown_table(diffs %>% transmute(comparison, outcome = ifelse(type == "per_year", "h = 2", "cum. 0..3"),
                                        difference = cell(estimate, se, p_boot),
                                        band = sprintf("[%.3f, %.3f]", lower, upper))),
  "## VAR paths, h = 1..6", "",
  to_markdown_table(paths),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. Shock years = state-years with a new US case in the VAR sample ",
  "(more than in the LP, which needs the outcome at t+h)."
), file.path(TABLES, "pvar_us_periods.md"))
cat("\nWrote", file.path(TABLES, "pvar_us_periods.md"), "\n")
