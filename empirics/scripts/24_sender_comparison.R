# =============================================================================
# 24_sender_comparison.R — the sanction effect by sender group: any sender, US, UN, Western rich (added 2026-11-17,
# user request: "compare UN sanctions vs US vs any sanction vs developed countries")
#
# Sender groups (functions.R, shock_panel()): new GSDB cases without ICC case 685, 1991-2019,
#   any     : all cases
#   us      : the US is a sender (= the shock of D11, 22 and 23)
#   un      : UN cases
#   western : every sender is a Western rich state or the EU (user: Western rich without backing from non-rich
#             countries); overlaps with us (US cases are almost always unilateral)
# Designs, the same for every group:
#   (LP)  base local projection D11 with the shock swapped: count of new cases of the group, shock second, 2 lags of
#         shock and deaths, state + year FE, SE clustered by state; path h = -5..8, per year and cumulative.
#   (22)  matched difference-in-differences (covariate matching, ATT), run as 22_us_matching.R --shock=<group>
#   (23)  propensity-score matching (NN, NN with caliper, score + deaths, subclassification; ATT), 23 --shock=<group>
#   For each group the controls are clean for THAT group (no new case of the group in t-2..t+3), and the covariates
#   "in force" / "new case in t-1..t-2" refer to the group. So the comparison is "a new case of this group vs none of
#   this group", not vs no sanction at all (a UN control may have a US case).
# 22 and 23 for the US are the existing runs (master steps); for the other groups this script runs them
# (RUN_MATCHING=0 skips that and only collects). Runtime ~ 20 min (23's bootstrap, 3 groups).
# Output: tables/sender_comparison.md/.csv, tables/senders/<group>_lp_paths.csv and the 22/23 outputs per group,
#         figures/fig45_sender_comparison.png (h = 2 and cumulative 0..3, all designs), fig46_sender_lp_paths.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

GROUPS <- names(SHOCK_LABELS)
SENDERS_TABLES <- file.path(TABLES, "senders"); dir.create(SENDERS_TABLES, showWarnings = FALSE)
dir.create(file.path(FIGURES, "senders"), showWarnings = FALSE)
RUN_MATCHING <- Sys.getenv("RUN_MATCHING", "1") == "1"
PRE <- -5:-3; POST <- 1:8
hn <- function(h) ifelse(h < 0, paste0("m", -h), as.character(h))
value_at <- function(data, variable, k) lag_by_year(data, variable, -k)
SAMPLES <- list("All state-years" = function(z) z, "In conflict in t-1" = function(z) filter(z, conflict_l1 %in% 1))

# --- 1. Cases by group ----------------------------------------------------------------------------------------
panel <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>% arrange(gwcode, yr)
panel$conflict_l1 <- lag_by_year(panel, "viol_inc", 1)
counts <- bind_rows(lapply(GROUPS, function(g) {
  cs <- sender_cases(g) %>% filter(year >= 1991, year <= 2019)
  sp <- shock_panel(g)
  z <- panel %>% filter(in_window) %>% left_join(select(sp, iso3c, yr, x), by = c("iso3c", "yr")) %>% mutate(x = replace_na(x, 0L))
  tibble(group = g, label = SHOCK_LABELS[[g]], new_cases = nrow(cs), distinct_cases = n_distinct(cs$case),
         target_years_in_sample = sum(z$x > 0), target_years_in_conflict = sum(z$x > 0 & z$conflict_l1 %in% 1),
         also_us = sum(cs$us == 1), also_un = sum(cs$un == 1))
}))

# --- 2. Base LP (D11) path per group --------------------------------------------------------------------------
lp_rows <- list()
for (g in GROUPS) {
  d <- panel %>% left_join(select(shock_panel(g), iso3c, yr, x), by = c("iso3c", "yr")) %>%
    mutate(x = replace_na(x, 0L)) %>% arrange(gwcode, yr)
  d <- add_lags(d, c("x", "viol_lev"), VAR_LAGS)
  for (h in c(PRE, POST)) {
    d[[paste0("py_", hn(h))]] <- if (h < 0) lag_by_year(d, "viol_lev", -h) else value_at(d, "viol_lev", h)
    if (h > 0) d[[paste0("cy_", h)]] <- Reduce(`+`, lapply(0:h, function(j) value_at(d, "viol_lev", j)))
  }
  PATH_VARS <- c(paste0("py_", hn(c(PRE, POST))), paste0("cy_", POST))
  HISTORY <- c(lag_names("x", VAR_LAGS), lag_names("viol_lev", VAR_LAGS), "viol_lev")
  for (s in names(SAMPLES)) {
    z <- SAMPLES[[s]](d) %>% filter(in_window) %>% drop_na(all_of(c("x", HISTORY)))
    m <- feols(as.formula(paste0("c(", paste(PATH_VARS, collapse = ", "), ") ~ x + ", paste(HISTORY, collapse = " + "),
                                 " | gwcode + yr")), data = z, cluster = ~ gwcode)
    out <- bind_rows(lapply(seq_along(PATH_VARS), function(i) { ct <- coeftable(m[[i]])
      tibble(var = PATH_VARS[i], estimate = ct["x", 1], se = ct["x", 2], p_value = ct["x", 4], observations = nobs(m[[i]]),
             shock_years = sum(z$x[!is.na(z[[PATH_VARS[i]]])] > 0)) })) %>%
      mutate(group = g, sample = s, horizon = as.integer(sub("^m", "-", sub("^.y_", "", var))),
             type = ifelse(startsWith(var, "py_"), "Per year, t + h", "Cumulative, t..t + h"),
             lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
    lp_rows[[length(lp_rows) + 1]] <- out
  }
  if (g != "us") write_csv(filter(bind_rows(lp_rows), group == g), file.path(SENDERS_TABLES, paste0(g, "_lp_paths.csv")))
}
lp <- bind_rows(lp_rows)
# check: the US LP here must equal script 21's base path
us21 <- read_csv(file.path(TABLES, "us_paths.csv"), show_col_types = FALSE)
chk <- lp %>% filter(group == "us") %>% inner_join(us21, by = c("var", "sample"), suffix = c("", "_21"))
stopifnot(nrow(chk) > 0, max(abs(chk$estimate - chk$estimate_21)) < 1e-8)
cat("US LP equals script 21's base path (", nrow(chk), "coefficients)\n")

# --- 3. Matching designs per group ----------------------------------------------------------------------------
if (RUN_MATCHING) for (g in setdiff(GROUPS, "us")) for (sc in c("22_us_matching.R", "23_us_pscore_matching.R")) {
  cat("Running", sc, "--shock=", g, "\n")
  status <- system2(file.path(R.home("bin"), "Rscript"), c(shQuote(here("empirics", "scripts", sc)), paste0("--shock=", g)),
                    stdout = FALSE, stderr = FALSE)
  if (status != 0) stop(sc, " --shock=", g, " failed (status ", status, ")")
}
file_of <- function(g, f) if (g == "us") file.path(TABLES, f) else file.path(SENDERS_TABLES, sub("^us_", paste0(g, "_"), f))
m22 <- bind_rows(lapply(GROUPS, function(g) read_csv(file_of(g, "us_matching.csv"), show_col_types = FALSE) %>%
  filter(part == "path", var %in% c("dy_2", "dc_3")) %>%
  transmute(group = g, sample, var, design = "Matched DiD, covariates (22)", estimate, se, p_value, units = events)))
m23 <- bind_rows(lapply(GROUPS, function(g) read_csv(file_of(g, "us_pscore_matching.csv"), show_col_types = FALSE) %>%
  filter(part == "estimates", estimand == "ATT", var %in% c("dy_2", "dc_3")) %>%
  transmute(group = g, sample, var, design = paste0("PS: ", estimator, " (23)"), estimate, se, p_value, units)))
lp_main <- lp %>% filter(var %in% c("py_2", "cy_3")) %>%
  transmute(group, sample, var = recode(var, py_2 = "dy_2", cy_3 = "dc_3"), design = "Base LP (D11)", estimate, se, p_value,
            units = shock_years)
DESIGNS <- c("Base LP (D11)", "Matched DiD, covariates (22)", "PS: NN matching (23)", "PS: NN matching, caliper 0.2 SD (23)",
             "PS: NN matching, score + deaths (23)", "PS: Subclassification (23)")
all_est <- bind_rows(lp_main, m22, m23) %>%
  mutate(outcome = factor(recode(var, dy_2 = "h = 2", dc_3 = "Cumulative 0..3"), levels = c("h = 2", "Cumulative 0..3")), lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
         label = factor(unname(SHOCK_LABELS[group]), levels = unname(SHOCK_LABELS)), design = factor(design, levels = rev(DESIGNS)))
write_csv(bind_rows(mutate(all_est, part = "estimates"), mutate(lp, part = "lp path"), mutate(counts, part = "cases")),
          file.path(TABLES, "sender_comparison.csv"))

# --- 4. Figures ---------------------------------------------------------------------------------------------------
COLS4 <- setNames(c(PAPER_COLOURS[["grey"]], PAPER_COLOURS[["blue"]], PAPER_COLOURS[["orange"]], PAPER_COLOURS[["aqua"]]), SHOCK_LABELS)
fig45 <- ggplot(all_est, aes(estimate, design, colour = label)) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_pointrange(aes(xmin = lower, xmax = upper), position = position_dodge(width = 0.7), size = 0.25, linewidth = 0.5) +
  facet_grid(sample ~ outcome, scales = "free_x") +
  scale_colour_manual(values = COLS4, breaks = unname(rev(SHOCK_LABELS))) + guides(colour = guide_legend(reverse = TRUE)) +
  labs(title = "Effect of a new sanction on deaths, by sender group and design",
       x = "Effect on log(1 + UCDP deaths per 100k) (LP: per new case; matching: ATT of >= 1 new case)", y = NULL, colour = NULL,
       caption = paste0("New GSDB cases w/o ICC 685, 1991-2019. Western rich: every sender a Western rich state or the EU (UN cases excluded; ",
                        "includes US cases). 95% intervals: LP and 22 clustered by state,\n23 state-cluster bootstrap. Controls are clean ",
                        "for the same group only (e.g. a UN control may have a US case). LP coefficient is per case, matching per event.")) +
  theme_paper() + theme(legend.position = "top")
save_figure(fig45, "fig45_sender_comparison.png", 12, 9)

# h = -2..0 (per year) and h = 0 (cumulative) are controlled: y(t), y(t-1), y(t-2) are regressors, so the shock
# coefficient on them is exactly 0. Drawn as hollow points at 0 so the path is continuous (no gap).
zeros <- lp %>% distinct(group, sample) %>%
  tidyr::expand_grid(bind_rows(tibble(type = "Per year, t + h", horizon = -2:0), tibble(type = "Cumulative, t..t + h", horizon = 0L))) %>%
  mutate(estimate = 0, lower = 0, upper = 0, controlled = TRUE)
lpp <- bind_rows(mutate(lp, controlled = FALSE), zeros) %>%
  mutate(label = factor(unname(SHOCK_LABELS[group]), levels = unname(SHOCK_LABELS)),
         type = factor(type, levels = c("Per year, t + h", "Cumulative, t..t + h")),
         sample = factor(sample, levels = c("In conflict in t-1", "All state-years"))) %>% arrange(horizon)
fig46 <- ggplot(lpp, aes(horizon, estimate, colour = label, fill = label, group = label)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3, linetype = "dotted") +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.10, colour = NA) +
  geom_line(linewidth = 0.8) +
  geom_point(data = filter(lpp, !controlled), size = 1.1) +
  geom_point(data = filter(lpp, controlled), size = 1.4, shape = 21, fill = "#fcfcfb", stroke = 0.6) +
  facet_grid(type ~ sample, scales = "free_y") +
  scale_colour_manual(values = COLS4) + scale_fill_manual(values = COLS4) +
  scale_x_continuous(breaks = c(PRE, -2:0, POST)) +
  labs(title = "Base local projection (D11) with the shock by sender group",
       x = "Years relative to the shock (h)", y = "Effect of one new case on log(1 + deaths per 100k)",
       colour = NULL, fill = NULL,
       caption = paste0("Shock second, 2 lags of shock and deaths, state + year FE, 95% intervals clustered by state. h < -2: placebo. Outcomes end 2019.\n",
                        "Hollow points: h = -2..0 are controlled (deaths in t, t-1, t-2 are regressors), so the effect there is 0 by construction.")) +
  theme_paper() + theme(legend.position = "top")
save_figure(fig46, "fig46_sender_lp_paths.png", 12, 8)

# --- 5. Table ---------------------------------------------------------------------------------------------------
to_md <- function(table) c(paste0("| ", paste(names(table), collapse = " | "), " |"),
                           paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
                           apply(table, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "", r), collapse = " | "), " |")), "")
cell <- function(e, s, p, n) sprintf("%.3f%s (%.3f) [%d]", e, significance_stars(p), s, as.integer(n))
wide <- function(o) all_est %>% filter(var == o) %>% mutate(cell = cell(estimate, se, p_value, units),
                                                          design = factor(design, levels = DESIGNS)) %>%
  arrange(sample, design) %>% select(sample, design, label, cell) %>% pivot_wider(names_from = label, values_from = cell)
writeLines(c(
  "# Effect of a new sanction by sender group", "",
  paste0("Generated by `empirics/scripts/24_sender_comparison.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures `fig45_sender_comparison.png`, `fig46_sender_lp_paths.png`; all numbers `sender_comparison.csv`; ",
         "per-group matching output in `tables/senders/` and `figures/senders/`."), "",
  "Groups: new GSDB cases without ICC 685. Western rich = every sender a Western rich state or the EU (OECD members of 1990 ",
  "except Turkey, EU/EEC, Cyprus, Malta, Western European microstates), UN cases excluded; it contains the US cases. ",
  "Matching controls are clean for the same group only.", "",
  "## Cases (1991-2019)", "", to_md(counts),
  "## h = 2: estimate (SE) [LP: shock years in the sample; matching: treated events]", "", to_md(wide("dy_2")),
  "## Cumulative 0..3", "", to_md(wide("dc_3")),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. LP: effect of one more new case (count), SE clustered by state. Matching: ",
  "ATT of a state-year with >= 1 new case vs matched state-years with none of that group; 22 SE clustered by treated ",
  "country (controls fixed), 23 state-cluster bootstrap (approximate for NN)."
), file.path(TABLES, "sender_comparison.md"))
cat("\nWrote", file.path(TABLES, "sender_comparison.md"), "\n")
