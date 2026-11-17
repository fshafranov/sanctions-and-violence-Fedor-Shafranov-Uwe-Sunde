# =============================================================================
# 27_us_staggered_controls.R — exploratory (user 17 Nov 2026): the staggered-adoption design of 26 with OTHER
# CONTROL GROUPS. User: never-sanctioned states should not be the control.
#
# Treatment as in 26: absorbing, from the first-ever new US case (GSDB w/o ICC 685), cohorts 1991-2019, outcome
# log(1 + UCDP deaths per 100k), 1989-2019. Estimator: Callaway & Sant'Anna (2021), package `did` (doubly robust,
# no covariates, universal base period g-1, unbalanced panel, bootstrap SE clustered by state), event-time
# aggregation e = -6..8 and the average of e = 0..5. Control groups:
#   A  never sanctioned                         (as in 26; reference)
#   B  not yet treated only                     later-sanctioned states before their first US case; never-sanctioned
#                                               states dropped. Risk: anticipation (a state about to be sanctioned is
#                                               not a clean control) — the bias the user referred to.
#   C  not yet treated + never sanctioned       `did` default for control_group = "notyettreated"
#   D  last-treated cohorts                     first US case 2014-2019 serve as controls, estimation years <= 2013
#   E  already sanctioned (TWFE)                states first hit before 1991 kept as "always treated" controls in a
#                                               TWFE event study; forbidden comparison (their effects may still evolve)
# Trade exposure: each design repeated within High / Low US share of trade (median among treated, cohort year);
# never-sanctioned and already-sanctioned states classified by their mean US share 1989-2019 at the same cut-off,
# so controls are exposure-matched too (fixes the "High = Americas vs. all never-sanctioned" comparison of 26).
# Output: tables/us_staggered_controls.csv, figures/fig50_us_staggered_controls.png, fig51_us_staggered_controls_trade.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages(c("fixest", "did"))
set.seed(20261117)

ICC_CASE <- 685; FIRST_YEAR <- 1991; LAST_YEAR <- 2019; E_MIN <- -6; E_MAX <- 8; LAST_COHORTS_FROM <- 2014

first_us <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% group_by(iso3c = country_iso3) %>% summarise(first_case = min(year))
trade <- read_panel() %>% transmute(gwcode, yr, trade_us_share)
d_all <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  filter(yr >= 1989, yr <= LAST_YEAR) %>%
  left_join(first_us, by = "iso3c") %>% left_join(trade, by = c("gwcode", "yr")) %>%
  mutate(status = case_when(is.na(first_case) | first_case > LAST_YEAR ~ "never",
                            first_case < FIRST_YEAR ~ "already",
                            TRUE ~ "cohort"),
         cohort = ifelse(status == "cohort", first_case, 0))

# Exposure: treated = US share of trade in the cohort year (mean g-3..g-1); others = mean over 1989-2019
exposure <- d_all %>% group_by(gwcode) %>%
  summarise(exposure = if (first(status) == "cohort") trade_us_share[yr == first(cohort)][1] else mean(trade_us_share, na.rm = TRUE))
CUT <- median(exposure$exposure[exposure$gwcode %in% d_all$gwcode[d_all$status == "cohort"]], na.rm = TRUE)
d_all <- d_all %>% left_join(exposure, by = "gwcode") %>%
  mutate(exposure_group = ifelse(is.na(exposure), NA, ifelse(exposure >= CUT, "High", "Low")))
cat("Cut-off (median US share of trade among treated):", round(CUT, 2), "\n")
print(d_all %>% distinct(gwcode, status, exposure_group) %>% count(status, exposure_group))

# Callaway-Sant'Anna ----------------------------------------------------------------------------------------
cs <- function(data, control_group) {
  att <- att_gt(yname = "viol_lev", tname = "yr", idname = "gwcode", gname = "cohort", data = as.data.frame(data),
                control_group = control_group, base_period = "universal", allow_unbalanced_panel = TRUE,
                est_method = "dr", clustervars = "gwcode", bstrap = TRUE, biters = 999, print_details = FALSE)
  dyn <- aggte(att, type = "dynamic", min_e = E_MIN, max_e = E_MAX, na.rm = TRUE)
  post <- aggte(att, type = "dynamic", min_e = 0, max_e = 5, na.rm = TRUE)
  bind_rows(tibble(h = dyn$egt, estimate = dyn$att.egt, se = dyn$se.egt),
            tibble(h = NA_real_, estimate = post$overall.att, se = post$overall.se)) %>%
    mutate(treated_states = n_distinct(data$gwcode[data$cohort > 0]),
           control_states = n_distinct(data$gwcode[data$cohort == 0]))
}
# TWFE event study with already-sanctioned states as controls (E)
twfe_already <- function(data) {
  data <- data %>% mutate(rel = ifelse(cohort > 0, pmin(pmax(yr - cohort, E_MIN), E_MAX), -1000))
  f <- feols(viol_lev ~ i(rel, ref = c(-1, -1000)) | gwcode + yr, data = data, cluster = ~ gwcode)
  ct <- coeftable(f)
  w <- feols(viol_lev ~ i(rel, ref = c(-1, -1000)) | gwcode + yr, data = data, cluster = ~ gwcode)
  post <- grepl("rel::[0-5]$", rownames(ct))
  V <- vcov(f)[post, post]
  bind_rows(tibble(h = as.numeric(sub("rel::", "", rownames(ct))), estimate = ct[, 1], se = ct[, 2]),
            tibble(h = NA_real_, estimate = mean(ct[post, 1]), se = sqrt(sum(V)) / sum(post))) %>%
    mutate(treated_states = n_distinct(data$gwcode[data$cohort > 0]),
           control_states = n_distinct(data$gwcode[data$cohort == 0]))
}

DESIGNS <- list(
  "A Never sanctioned" = function(z) cs(filter(z, status != "already"), "nevertreated"),
  "B Not yet treated only" = function(z) cs(filter(z, status == "cohort"), "notyettreated"),
  "C Not yet treated + never" = function(z) cs(filter(z, status != "already"), "notyettreated"),
  "D Last-treated cohorts (2014-19), years <= 2013" = function(z)
    cs(filter(z, status == "cohort", yr < LAST_COHORTS_FROM) %>% mutate(cohort = ifelse(cohort >= LAST_COHORTS_FROM, 0, cohort)),
       "nevertreated"),
  "E Already sanctioned before 1991 (TWFE)" = function(z) twfe_already(filter(z, status != "never"))
)
SUBSETS <- list("All" = function(z) z,
                "High US share of trade" = function(z) filter(z, exposure_group %in% "High"),
                "Low US share of trade" = function(z) filter(z, exposure_group %in% "Low"))

res <- list()
for (design in names(DESIGNS)) for (subset in names(SUBSETS)) {
  cat("Estimating:", design, "|", subset, "\n")
  out <- tryCatch(DESIGNS[[design]](SUBSETS[[subset]](d_all)), error = function(e) { message("  failed: ", conditionMessage(e)); NULL })
  if (!is.null(out)) res[[length(res) + 1]] <- mutate(out, design = design, subset = subset)
}
res <- bind_rows(res) %>% mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se, p_value = 2 * pnorm(-abs(estimate / se)))
write_csv(res, file.path(TABLES, "us_staggered_controls.csv"))
cat("\nATT, mean of e = 0..5:\n")
print(res %>% filter(is.na(h)) %>% select(design, subset, estimate, se, p_value, treated_states, control_states), n = 50, width = 200)

# Figures -------------------------------------------------------------------------------------------------------
plot_paths <- function(data, colour_by, title, file) {
  p <- data %>% filter(!is.na(h)) %>%
    ggplot(aes(h, estimate, colour = .data[[colour_by]])) +
    geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) + geom_vline(xintercept = -0.5, linetype = "dotted") +
    geom_pointrange(aes(ymin = lower, ymax = upper), position = position_dodge(width = 0.5), size = 0.2) +
    facet_wrap(~ design, ncol = 3) +
    scale_colour_manual(values = c("All" = PAPER_COLOURS[["blue"]], "High US share of trade" = PAPER_COLOURS[["orange"]],
                                   "Low US share of trade" = PAPER_COLOURS[["blue"]])) +
    labs(title = title, x = "Years relative to the first new US case",
         y = "log(1 + UCDP deaths per 100k), treated minus control", colour = NULL,
         caption = "Callaway-Sant'Anna (A-D, doubly robust, base period g-1, bootstrap SE by state); E: TWFE event study, end bins. 95% intervals.") +
    theme_paper() + theme(legend.position = if (n_distinct(data[[colour_by]]) > 1) "top" else "none")
  save_figure(p, file, 11, 6.5)
}
plot_paths(filter(res, subset == "All") %>% mutate(subset = "All"), "subset",
           "First US sanction: event study under five control groups", "fig50_us_staggered_controls.png")
plot_paths(filter(res, subset != "All"), "subset",
           "First US sanction by US share of trade, exposure-matched controls", "fig51_us_staggered_controls_trade.png")
