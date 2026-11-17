# =============================================================================
# 26_us_staggered.R — exploratory ("try it and see", user 17 Nov 2026): US sanctions as STAGGERED ADOPTION
#
# Different estimand from the LP (D11) and the LP-DiD (25): treatment is ABSORBING. A state is "treated" from the
# year of its FIRST-EVER new US case (GSDB, without ICC case 685) onward. Cohort g = that year.
#   - cohorts 1991-2019 are estimated; states whose first US case came before 1991 are already treated -> dropped;
#     states never hit by a US case (through 2023) are the never-treated controls.
#   - outcome: log(1 + UCDP deaths per 100k) (viol_lev) and conflict incidence (viol_inc), 1989-2019.
#   - estimators: naive TWFE event study (biased under heterogeneous effects with staggered timing) and
#     Sun & Abraham (2021) interaction-weighted (fixest::sunab), never-treated as the reference; state + year FE,
#     SE clustered by state; relative periods -6..+8 (binned outside), reference period -1.
#   - extension: heterogeneity by pre-treatment US trade exposure (trade_us_share and trade_us_gdp in the cohort
#     year, i.e. mean over g-3..g-1): treated split at the median among treated, each half vs. all never-treated.
# Not in master.py; exploratory. Output: tables/us_staggered.csv, figures/fig48_us_staggered.png,
#   figures/fig49_us_staggered_trade.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

ICC_CASE <- 685
FIRST_YEAR <- 1991; LAST_YEAR <- 2019; WINDOW <- c(-6, 8)

first_us <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% group_by(iso3c = country_iso3) %>% summarise(cohort = min(year))
trade <- read_panel() %>% transmute(gwcode, yr, trade_us_share, trade_us_gdp)

d <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  filter(yr >= 1989, yr <= LAST_YEAR) %>%
  left_join(first_us, by = "iso3c") %>% left_join(trade, by = c("gwcode", "yr")) %>%
  filter(is.na(cohort) | cohort >= FIRST_YEAR) %>%                 # drop already-treated states
  mutate(cohort = ifelse(is.na(cohort) | cohort > LAST_YEAR, 10000, cohort),   # never treated (in window)
         rel = ifelse(cohort == 10000, -1000, yr - cohort),
         treated_post = as.integer(cohort != 10000 & yr >= cohort))

# Exposure at the cohort year (base variable = mean g-3..g-1) for the treated
exposure <- d %>% filter(cohort != 10000, yr == cohort) %>% select(gwcode, exp_share = trade_us_share, exp_gdp = trade_us_gdp)
d <- d %>% left_join(exposure, by = "gwcode")
cat("Treated states:", n_distinct(d$gwcode[d$cohort != 10000]), " never treated:", n_distinct(d$gwcode[d$cohort == 10000]),
    " dropped as already treated before 1991:", sum(first_us$cohort < FIRST_YEAR), "\n")
print(d %>% filter(cohort != 10000) %>% distinct(gw_name, cohort, exp_share) %>% arrange(cohort), n = 100)

# Ever-in-conflict states (any UCDP conflict year 1989-2019): the "conflict-prone" sample
conflict_states <- d %>% group_by(gwcode) %>% summarise(any = any(viol_inc == 1, na.rm = TRUE)) %>% filter(any) %>% pull(gwcode)

estimate <- function(data, outcome, label) {
  data <- data %>% mutate(rel_b = pmin(pmax(rel, WINDOW[1]), WINDOW[2]))
  twfe <- feols(as.formula(paste(outcome, "~ i(rel_b, ref = c(-1, -1000)) | gwcode + yr")),
                data = data %>% mutate(rel_b = ifelse(cohort == 10000, -1000, rel_b)), cluster = ~ gwcode)
  r <- range(data$rel[data$cohort != 10000])
  bins <- sprintf("list('%d' = %d:%d, '%d' = %d:%d)", WINDOW[1], r[1], WINDOW[1], WINDOW[2], WINDOW[2], r[2])
  sa <- feols(as.formula(paste0(outcome, " ~ sunab(cohort, yr, ref.p = -1, bin.rel = ", bins, ") | gwcode + yr")),
              data = data, cluster = ~ gwcode)
  path <- function(f, est) {
    ct <- coeftable(f); keep <- grepl("rel_b::|^yr::", rownames(ct))
    tibble(estimator = est, h = as.numeric(sub(".*::", "", rownames(ct)[keep])), estimate = ct[keep, 1], se = ct[keep, 2])
  }
  # ATT averaged over h = 0..5 (equal weight per relative period) from the Sun-Abraham path
  agg <- aggregate(sa, c("post05" = "yr::[0-5]:cohort"))
  tibble(spec = label, outcome = outcome) %>%
    bind_cols(bind_rows(path(twfe, "TWFE event study"), path(summary(sa, agg = "period"), "Sun-Abraham")) %>%
                bind_rows(tibble(estimator = "Sun-Abraham", h = NA_real_, estimate = agg[1, 1], se = agg[1, 2])))
}
res <- bind_rows(
  estimate(d, "viol_lev", "All states"),
  estimate(filter(d, gwcode %in% conflict_states), "viol_lev", "Ever-in-conflict states"),
  estimate(d, "viol_inc", "All states"),
  estimate(filter(d, gwcode %in% conflict_states), "viol_inc", "Ever-in-conflict states")
)
# Trade exposure: high vs low (median split among treated), each vs. all never-treated
for (var in c("exp_share", "exp_gdp")) {
  med <- median(exposure[[var]], na.rm = TRUE)
  for (grp in c("High", "Low")) {
    keep <- d$cohort == 10000 | (!is.na(d[[var]]) & (if (grp == "High") d[[var]] >= med else d[[var]] < med))
    lab <- paste0(grp, " US trade exposure (", ifelse(var == "exp_share", "share of trade", "% of GDP"), ")")
    res <- bind_rows(res, estimate(d[keep, ], "viol_lev", lab),
                     estimate(d[keep & d$gwcode %in% conflict_states, ], "viol_lev", paste(lab, "| ever in conflict")))
  }
}
res <- res %>% mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se, p_value = 2 * pnorm(-abs(estimate / se)))
write_csv(res, file.path(TABLES, "us_staggered.csv"))
cat("\nATT, mean of h = 0..5 (Sun-Abraham):\n")
print(res %>% filter(is.na(h)) %>% select(spec, outcome, estimate, se, p_value), n = 50, width = 200)

# Figures -----------------------------------------------------------------------------------------------------
fig47 <- res %>% filter(!is.na(h), spec %in% c("All states", "Ever-in-conflict states")) %>%
  bind_rows(tibble(h = -1, estimate = 0, se = 0) %>% tidyr::crossing(
    distinct(filter(res, spec %in% c("All states", "Ever-in-conflict states")), spec, outcome, estimator))) %>%
  mutate(outcome = recode(outcome, viol_lev = "log(1 + deaths per 100k)", viol_inc = "Conflict incidence (0/1)")) %>%
  ggplot(aes(h, estimate, colour = estimator)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) + geom_vline(xintercept = -0.5, linetype = "dotted") +
  geom_pointrange(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se), position = position_dodge(width = 0.5), size = 0.25) +
  facet_grid(outcome ~ spec, scales = "free_y") +
  scale_colour_manual(values = c("TWFE event study" = "grey55", "Sun-Abraham" = PAPER_COLOURS[["blue"]])) +
  labs(title = "Staggered adoption: violence around a state's first US sanction",
       x = "Years relative to the first new US case (end bins: <= -6, >= 8)", y = "Difference to never-sanctioned states",
       colour = NULL, caption = "State + year FE, reference h = -1, 95% intervals, SE clustered by state. States first hit before 1991 dropped.") +
  theme_paper() + theme(legend.position = "top")
save_figure(fig47, "fig48_us_staggered.png", 10, 6.5)

fig48 <- res %>% filter(!is.na(h), estimator == "Sun-Abraham", grepl("exposure", spec)) %>%
  mutate(exposure = ifelse(grepl("^High", spec), "High", "Low"),
         measure = ifelse(grepl("share of trade", spec), "US share of trade", "Trade with US, % of GDP"),
         sample = ifelse(grepl("ever in conflict", spec), "Ever-in-conflict states", "All states")) %>%
  ggplot(aes(h, estimate, colour = exposure)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) + geom_vline(xintercept = -0.5, linetype = "dotted") +
  geom_pointrange(aes(ymin = estimate - 1.96 * se, ymax = estimate + 1.96 * se), position = position_dodge(width = 0.5), size = 0.25) +
  facet_grid(sample ~ measure) +
  scale_colour_manual(values = c(High = PAPER_COLOURS[["orange"]], Low = PAPER_COLOURS[["blue"]])) +
  labs(title = "First US sanction by the target's US trade exposure (Sun-Abraham)",
       x = "Years relative to the first new US case", y = "log(1 + UCDP deaths per 100k), vs. never sanctioned",
       colour = "Exposure in the cohort year (median split)", caption = "Exposure = mean over g-3..g-1. 95% intervals, SE clustered by state.") +
  theme_paper() + theme(legend.position = "top")
save_figure(fig48, "fig49_us_staggered_trade.png", 10, 6.5)
