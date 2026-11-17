# =============================================================================
# 25_lpdid_dgjt.R — LP-DiD for new US sanctions following the authors' reference code (added 2026-11-17, user request)
#
# Source: Dube, Girardi, Jorda & Taylor (2025), "A Local Projections Approach to Difference-in-Differences", Journal
#   of Applied Econometrics 40(7). Reference code: https://github.com/danielegirardi/lpdid/ (GPL-3.0):
#   - "R example files/LP_DiD_R_example_VW.R" (variance-weighted) and "LP_DiD_R_example_EW.R" (reweighted,
#     equally weighted ATT): estimation steps followed here (long differences y(t+h) - y(t-1), treatment indicator,
#     time FE only, SE clustered by unit, small-sample correction as reghdfe; reweighting by the inverse of the OLS
#     variance weights). Those R files cover ABSORBING treatment only.
#   - "STATA example files/LPDiD_nonabsorbing_example.do", variant 5b: clean-control windows for NON-absorbing
#     treatment, which is our case (a country can get a new US case again and again). Translated here with the
#     treatment "switch" = a new US case (one-off events):
#       E_t       = 1 if >= 1 new US case w/o ICC 685 in t (binary, as in the package; D11 uses the count)
#       CCS_0(t)  = no new case in t-L..t-1
#       CCS_h(t)  = CCS_{h-1}(t) and no new case in t+h          (h = 1..post): clean through t+h
#       CCS_m1    = CCS_0;  CCS_mk(t) = CCS_m(k-1)(t) and CCS_m(k-1)(t-1)   (pre horizons k = 2..pre)
#     Sample at horizon h: all state-years with CCS_h = 1, treated (E_t = 1) and controls (E_t = 0) alike, so treated
#     events are ALSO required to have no further US case in t+1..t+h (the do-file's 5b condition). L = 3 (main) and
#     L = 5 (the do-file's value) as a check.
#   Packages: the reference R code uses tsibble/slider/marginaleffects (not in this project's renv); the same steps are
#   done with lag_by_year() (gap-safe leads/lags by calendar year) and fixest. Not installed or downloaded.
# Differences from D11 (on purpose, this is the package's design): base year t-1 (so h = 0 includes the same-year
#   co-movement of sanctions and violence), no lagged-outcome controls, year FE only (no state FE: the long difference
#   removes them), binary treatment, clean controls.
# Samples: all state-years 1991-2019 and in conflict in t-1 (a pre-treatment condition, applied to treated and controls).
# Also: --shock=any|un|western (sender groups of 24; default us).
# Output: tables/lpdid_dgjt.md/.csv, figures/fig47_lpdid_dgjt.png (other groups: tables|figures/senders/)
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")
setFixest_ssc(ssc(adj = TRUE, cluster.adj = TRUE))   # as the reference code: match reghdfe

POST <- 8; PRE <- 5; POOL_POST <- 3; L_MAIN <- 3; L_CHECK <- 5
SHOCK <- shock_arg(); SHOCK_LABEL <- SHOCK_LABELS[[SHOCK]]
if (SHOCK != "us") {
  TABLES <- file.path(TABLES, "senders"); FIGURES <- file.path(FIGURES, "senders")
  dir.create(TABLES, showWarnings = FALSE); dir.create(FIGURES, showWarnings = FALSE)
}
out_file <- function(f) if (SHOCK == "us") f else sub("^(fig[0-9]+_)?", paste0("\\1", SHOCK, "_"), f)

d <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(select(shock_panel(SHOCK), iso3c, yr, x), by = c("iso3c", "yr")) %>%
  mutate(x = replace_na(x, 0L), E = as.integer(x > 0)) %>% arrange(gwcode, yr)
at <- function(v, k) lag_by_year(d, v, -k)            # value in t + k (k < 0: lag); NA outside the panel
d$conflict_l1 <- lag_by_year(d, "viol_inc", 1) %in% 1
# Outcomes (17 Nov, user: "do it on the event incidence as well"): log deaths and conflict incidence (0/1, >= 25 UCDP
# deaths in the year). Long differences of the incidence are changes in the probability of conflict (pp / 100); in the
# in-conflict sample y(t-1) = 1, so y(t+h) - y(t-1) = -1 when the conflict has stopped.
OUTCOMES <- c(viol_lev = "log(1 + deaths per 100k)", viol_inc = "Conflict incidence (0/1)")
for (o in names(OUTCOMES)) {
  L_y <- at(o, -1)
  for (h in 0:POST) d[[paste0(o, "_D", h, "y")]] <- at(o, h) - L_y
  for (k in 2:PRE)  d[[paste0(o, "_Dm", k, "y")]] <- at(o, -k) - L_y
  d[[paste0(o, "_pooled_post_y")]] <- Reduce(`+`, lapply(0:POOL_POST, function(j) at(o, j))) / (POOL_POST + 1) - L_y
  d[[paste0(o, "_pooled_pre_y")]]  <- Reduce(`+`, lapply(2:PRE, function(j) at(o, -j))) / (PRE - 1) - L_y
}
# event in t + k, treating years outside the panel as unknown (NA -> not clean)
ev <- function(k) at("E", k)

clean_sets <- function(L) {   # CCS_h (h = 0..POST) and CCS_mk (k = 1..PRE) as logical columns
  cs <- list()
  cs[["0"]] <- Reduce(`&`, lapply(1:L, function(j) ev(-j) %in% 0))
  for (h in 1:POST) cs[[as.character(h)]] <- cs[[as.character(h - 1)]] & ev(h) %in% 0
  cs[["m1"]] <- cs[["0"]]
  for (k in 2:PRE) {
    prev <- cs[[paste0("m", k - 1)]]
    prev_lag <- lag_by_year(mutate(d, p = prev), "p", 1) %in% TRUE
    cs[[paste0("m", k)]] <- prev & prev_lag
  }
  cs
}

# Reweighting (reference EW code, get_reweights): residualise E on year FE in the clean sample; a treated unit's OLS
# weight = its residual / sum of treated residuals; controls take the weight of the treated in their year; weight
# observations by 1 / weight so that every treated event counts equally (equally weighted ATT).
reweights <- function(s) {
  r <- residuals(feols(E ~ 1 | yr, data = s, vcov = "iid"))
  s$num <- ifelse(s$E == 1, r, NA_real_)
  s$w <- s$num / sum(s$num, na.rm = TRUE)
  s <- s %>% group_by(yr) %>% mutate(g = suppressWarnings(max(w, na.rm = TRUE)), g = ifelse(is.infinite(g), NA_real_, g),
                                     w = ifelse(is.na(w), g, w)) %>% ungroup()
  1 / s$w
}

est <- function(s, y, weighting) {
  s <- s[!is.na(s[[y]]), ]
  if (sum(s$E) < 3) return(NULL)
  f <- if (weighting == "Reweighted (equal weights)") {
    s$rw <- reweights(s); s <- s[!is.na(s$rw), ]
    feols(as.formula(paste(y, "~ E | yr")), data = s, weights = ~ rw, cluster = ~ gwcode)
  } else feols(as.formula(paste(y, "~ E | yr")), data = s, cluster = ~ gwcode)
  ct <- coeftable(f)
  tibble(estimate = ct["E", 1], se = ct["E", 2], p_value = ct["E", 4], events = sum(s$E), observations = nobs(f))
}

SAMPLES <- list("All state-years" = function(z) z, "In conflict in t-1" = function(z) filter(z, conflict_l1))
WEIGHTINGS <- c("Variance-weighted (OLS)", "Reweighted (equal weights)")
rows <- list()
for (L in c(L_MAIN, L_CHECK)) {
  cs <- clean_sets(L)
  for (o in names(OUTCOMES)) for (s in names(SAMPLES)) for (wt in WEIGHTINGS) {
    base <- function(key) SAMPLES[[s]](d[cs[[key]] & d$in_window, ])
    tag <- function(r) mutate(r, outcome = OUTCOMES[[o]], sample = s, weighting = wt, L = L)
    for (h in 0:POST) rows[[length(rows) + 1]] <- est(base(as.character(h)), paste0(o, "_D", h, "y"), wt) %>%
      mutate(horizon = h) %>% tag()
    for (k in 2:PRE) rows[[length(rows) + 1]] <- est(base(paste0("m", k)), paste0(o, "_Dm", k, "y"), wt) %>%
      mutate(horizon = -k) %>% tag()
    rows[[length(rows) + 1]] <- est(base(as.character(POOL_POST)), paste0(o, "_pooled_post_y"), wt) %>%
      mutate(horizon = NA, pooled = paste0("post 0..", POOL_POST)) %>% tag()
    rows[[length(rows) + 1]] <- est(base(paste0("m", PRE)), paste0(o, "_pooled_pre_y"), wt) %>%
      mutate(horizon = NA, pooled = paste0("pre -", PRE, "..-2")) %>% tag()
  }
}
res <- bind_rows(rows) %>% mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
ref <- tidyr::expand_grid(outcome = unname(OUTCOMES), sample = names(SAMPLES), weighting = WEIGHTINGS, L = c(L_MAIN, L_CHECK)) %>%
  mutate(horizon = -1, estimate = 0, se = NA, lower = 0, upper = 0)
paths <- bind_rows(filter(res, !is.na(horizon)), ref) %>% arrange(outcome, sample, weighting, L, horizon)
write_csv(bind_rows(mutate(paths, part = "path"), mutate(filter(res, is.na(horizon)), part = "pooled")),
          file.path(TABLES, out_file("lpdid_dgjt.csv")))

# --- figure -----------------------------------------------------------------------------------------------------
COLS2 <- setNames(c(PAPER_COLOURS[["blue"]], PAPER_COLOURS[["orange"]]), WEIGHTINGS)
pp <- paths %>% filter(L == L_MAIN) %>% mutate(sample = factor(sample, levels = rev(names(SAMPLES))), outcome = factor(outcome, levels = OUTCOMES))
chk <- paths %>% filter(L == L_CHECK, weighting == WEIGHTINGS[1]) %>% mutate(sample = factor(sample, levels = levels(pp$sample)), outcome = factor(outcome, levels = OUTCOMES))
fig47 <- ggplot(pp, aes(horizon, estimate, colour = weighting, fill = weighting)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(xintercept = -0.5, colour = "#52514e", linewidth = 0.3, linetype = "dotted") +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.12, colour = NA) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.2) +
  geom_point(data = chk, aes(horizon, estimate), inherit.aes = FALSE, shape = 4, size = 1.8, colour = "#14171c") +
  facet_grid(outcome ~ sample, scales = "free_y") +
  scale_colour_manual(values = COLS2) + scale_fill_manual(values = COLS2) +
  scale_x_continuous(breaks = -PRE:POST) +
  labs(title = paste0("LP-DiD (Dube, Girardi, Jorda & Taylor): violence after a new ", SHOCK_LABEL, " sanction"),
       x = "Years relative to the sanction (h); reference year h = -1",
       y = "y(t+h) - y(t-1)", colour = NULL, fill = NULL,
       caption = paste0("Treated: >= 1 new case in t, none in the ", L_MAIN, " years before and none in t+1..t+h; controls: none in t-", L_MAIN,
                        "..t+h (non-absorbing clean-control window, authors' example 5b).\nYear FE, 95% intervals clustered by state. ",
                        "Crosses: variance-weighted with a ", L_CHECK, "-year window. Outcomes end 2019.")) +
  theme_paper() + theme(legend.position = "top")
save_figure(fig47, out_file("fig47_lpdid_dgjt.png"), 12, 9)

# --- table ------------------------------------------------------------------------------------------------------
to_md <- function(table) c(paste0("| ", paste(names(table), collapse = " | "), " |"),
                           paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
                           apply(table, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "", r), collapse = " | "), " |")), "")
cell <- function(e, s, p) ifelse(is.na(s), "0 (ref.)", sprintf("%.3f%s (%.3f)", e, significance_stars(p), s))
writeLines(c(
  paste0("# LP-DiD (Dube, Girardi, Jorda & Taylor) for new ", SHOCK_LABEL, " sanctions"), "",
  paste0("Generated by `empirics/scripts/25_lpdid_dgjt.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figure `", out_file("fig47_lpdid_dgjt.png"), "`; all estimates `", out_file("lpdid_dgjt.csv"), "`. Steps follow the authors' R ",
         "example code (github.com/danielegirardi/lpdid), clean-control windows for non-absorbing treatment as in their Stata example 5b."), "",
  "Outcome y(t+h) - y(t-1), y = log(1 + UCDP deaths per 100k) or conflict incidence (0/1, >= 25 deaths); treatment = >= 1 new case in t; year FE; SE clustered by state.", "",
  paste0("## Event study, window L = ", L_MAIN, " (estimate (SE))"), "",
  to_md(paths %>% filter(L == L_MAIN) %>% mutate(cell = cell(estimate, se, p_value)) %>%
          select(outcome, sample, weighting, horizon, cell) %>% pivot_wider(names_from = horizon, names_prefix = "h", values_from = cell)),
  "## Events (treated) per horizon, L = 3", "",
  to_md(paths %>% filter(L == L_MAIN, weighting == WEIGHTINGS[1], horizon != -1, outcome == OUTCOMES[[1]]) %>% select(sample, horizon, events) %>%
          pivot_wider(names_from = horizon, names_prefix = "h", values_from = events)),
  "## Pooled (average of the long differences over the window)", "",
  to_md(res %>% filter(is.na(horizon)) %>% transmute(outcome, L, sample, weighting, pooled, cell = paste0(cell(estimate, se, p_value), " [", events, "]")) %>%
          pivot_wider(names_from = pooled, values_from = cell)),
  paste0("## Check: window L = ", L_CHECK), "",
  to_md(paths %>% filter(L == L_CHECK, horizon %in% c(-3, -2, 0, 1, 2, 3, 5)) %>% mutate(cell = cell(estimate, se, p_value)) %>%
          select(outcome, sample, weighting, horizon, cell) %>% pivot_wider(names_from = horizon, names_prefix = "h", values_from = cell)),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01."
), file.path(TABLES, out_file("lpdid_dgjt.md")))
cat("\nWrote", file.path(TABLES, out_file("lpdid_dgjt.md")), "\n")
