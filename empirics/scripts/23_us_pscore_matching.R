# =============================================================================
# 23_us_pscore_matching.R — propensity-score matching for new US sanctions, with the lecture's matching estimand
# (added 2026-11-16, user request)
#
# Estimand (user's lecture slide, "Matching estimand"):
#   beta_M = integral [ E(Y | D = 1, X = x) - E(Y | D = 0, X = x) ] dF_X(x)
# i.e. the difference in outcomes between sanctioned and unsanctioned state-years with the same characteristics,
# averaged with the weights of the characteristics in the WHOLE population (ATE). By Rosenbaum & Rubin the
# comparison can condition on the propensity score p(x) instead of x. Also reported, with the other two natural weights:
#   ATT: weights dF_{X|D=1} (the sanctioned state-years; = script 22's estimand)
#   ATC: weights dF_{X|D=0} (the unsanctioned ones)
#
# Units: state-years 1991-2019 in the sample (all state-years, or in conflict in t-1) that are either treated (>= 1
#   new US case w/o ICC 685 and NO new US case in t-1..t-2: a "clean event") or clean controls (no new US case in
#   t-2..t+3, as in 22), with complete covariates. Why clean events: a control can never have a US case in t-1..t-2,
#   so treated events after a recent US case have no comparable control (first run: the score separated perfectly on
#   that variable, p = 1 for 28 war events). 22 drops the same events through its exact match.
# Propensity score: logit of D on deaths in t, t-1, t-2 (log scale), sanction stock in t-1, US sanction in force in
#   t-1, democracy (V-Dem, t-1), region dummies and 5-year period dummies.
#   Common support: units outside [max(min p | D=1, min p | D=0), min(max p | D=1, max p | D=0)] are trimmed.
# Outcome: change since the sanction year, y(t+h) - y(t) (cumulative: sum_{j=0..h}), as in 22.
# Estimators:
#   (NN) nearest-neighbour matching on the logit of the score, M = 3, with replacement, within the same calendar
#        year (so common shocks cancel). Each treated unit gets Y(0) imputed as the mean of its M nearest controls,
#        each control gets Y(1) imputed from its M nearest treated units (Abadie & Imbens 2006). ATE = mean over all
#        units of Y(1) - Y(0); ATT over the treated; ATC over the controls. Reported twice: without a caliper, and with
#        the conventional caliper of 0.2 SD of the logit (Austin 2011); with the caliper, units without a match inside
#        it are dropped (the estimand becomes the effect on the units that have comparable counterparts).
#   (SC) subclassification: N_BLOCKS blocks on quantiles of the score; within each block the difference in mean
#        outcomes; ATE weights = block share of all units (the integral over dF_X, written as a sum), ATT = share of
#        treated, ATC = share of controls. Pooled over years (no same-year restriction).
# Inference: cluster bootstrap over states (score re-estimated in each draw), N_BOOT draws. For NN matching with a
#   fixed number of matches the bootstrap is not formally valid (Abadie & Imbens 2008); read its SEs as approximate.
# Balance: covariates passed through the same imputation (standardized differences, ATT and ATC sides).
#   (NN-D) score + deaths (added 17 Nov): the score caliper plus a caliper of 0.5 SD on deaths in t (script 22's), nearest
#        on the standardized distance in both; so pairs have the same score AND a similar violence level in t.
# Other sender groups (17 Nov): --shock=any|un|western runs the same design for that group ("US" in the comments then
#   means that group); outputs go to results/{tables,figures}/senders/ with the group as prefix. Called by 24.
# Output: tables/us_pscore_matching.md/.csv, us_pscore_matched_pairs.csv (who is matched with whom),
#   figures/fig42_us_pscore_overlap.png, fig43_us_pscore_paths.png, fig44_us_pscore_who_matches_whom.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))

ICC_CASE <- 685
M <- 3; N_BLOCKS <- 5; CALIPER_LOGIT_SD <- 0.2; DEV_CALIPER_SD <- 0.5
N_BOOT <- as.integer(Sys.getenv("PS_BOOT_DRAWS", "200"))
CLEAN <- -2:3
H_PRE <- -5:-3; H_POST <- 1:8
COVS <- c("viol_lev", "viol_lev_l1", "viol_lev_l2", "ctrl_stock", "us_force_l1", "ctrl_democracy")
gw_region <- function(code) cut(code, c(0, 199, 399, 626, 699, 999),
                                labels = c("Americas", "Europe", "Africa", "Middle East", "Asia and Oceania"))

# --- data (as in 22) -----------------------------------------------------------------------------------------
# Sender group (added 17 Nov): --shock=us (default) | any | un | western, see shock_panel() in functions.R. For the US
# the in-force variable stays the panel's us_sanction (as before, so the US results are unchanged); for the other
# groups it is built from the GSDB case years. Variable names below say "us" but mean the chosen group.
SHOCK <- shock_arg(); SHOCK_LABEL <- SHOCK_LABELS[[SHOCK]]
sp <- shock_panel(SHOCK)
force <- if (SHOCK == "us") read_panel() %>% select(gwcode, yr, us_sanction) else NULL
d <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(select(sp, iso3c, yr, x, force_grp = force), by = c("iso3c", "yr"))
d <- (if (SHOCK == "us") left_join(d, force, by = c("gwcode", "yr")) else mutate(d, us_sanction = replace_na(force_grp, 0L))) %>%
  mutate(x = replace_na(x, 0L)) %>% arrange(gwcode, yr)
# outputs: the US files keep their names; other groups go to results/{tables,figures}/senders/ with a suffix
if (SHOCK != "us") {
  TABLES <- file.path(TABLES, "senders"); FIGURES <- file.path(FIGURES, "senders")
  dir.create(TABLES, showWarnings = FALSE); dir.create(FIGURES, showWarnings = FALSE)
}
out_file <- function(f) if (SHOCK == "us") f else sub("^(fig[0-9]+_)?us_", paste0("\\1", SHOCK, "_"), f)
relabel <- function(x) if (SHOCK == "us") x else gsub("\\bUS\\b", SHOCK_LABEL, x, perl = TRUE)
save_fig <- function(p, f, w, h) {   # titles and captions say "US"; other groups get their label
  if (SHOCK != "us") p <- p + do.call(labs, lapply(Filter(is.character, as.list(p$labels)), relabel))
  save_figure(p, out_file(f), w, h)
}
lead <- function(v, k) lag_by_year(d, v, -k)
d$viol_lev_l1 <- lag_by_year(d, "viol_lev", 1); d$viol_lev_l2 <- lag_by_year(d, "viol_lev", 2)
d$conflict_l1 <- lag_by_year(d, "viol_inc", 1) %in% 1
d$us_force_l1 <- as.integer(lag_by_year(d, "us_sanction", 1) %in% 1)
d$us_new_l12  <- as.integer((replace_na(lag_by_year(d, "x", 1), 0) + replace_na(lag_by_year(d, "x", 2), 0)) > 0)
d$clean <- Reduce(`&`, lapply(CLEAN, function(k) replace_na((if (k == 0) d$x else lag_by_year(d, "x", -k)) == 0, TRUE)))
hn <- function(h) ifelse(h < 0, paste0("m", -h), as.character(h))
for (h in c(H_PRE, H_POST)) d[[paste0("dy_", hn(h))]] <- (if (h < 0) lag_by_year(d, "viol_lev", -h) else lead("viol_lev", h)) - d$viol_lev
for (h in H_POST) d[[paste0("dc_", h)]] <- Reduce(`+`, lapply(0:h, function(j) (if (j == 0) d$viol_lev else lead("viol_lev", j)) - d$viol_lev))
OUT_VARS <- c(paste0("dy_", hn(c(H_PRE, H_POST))), paste0("dc_", H_POST))
d <- d %>% mutate(D = as.integer(x > 0), region = gw_region(gwcode),
                  period = cut(yr, c(1990, 1995, 2000, 2005, 2010, 2015, 2019)))
units_all <- d %>% filter(in_window, (D == 1 & us_new_l12 == 0) | clean) %>% drop_na(all_of(COVS))
SAMPLES <- list("In conflict in t-1" = function(z) filter(z, conflict_l1), "All state-years" = function(z) z)

# --- estimation on one set of units ------------------------------------------------------------------------
PS_FORMULA <- as.formula(paste("D ~", paste(COVS, collapse = " + "), "+ region + period"))
add_score <- function(u) {
  fit <- glm(PS_FORMULA, data = u, family = binomial())
  u$lp <- predict(fit, type = "link"); u$ps <- plogis(u$lp)
  lo <- max(min(u$ps[u$D == 1]), min(u$ps[u$D == 0])); hi <- min(max(u$ps[u$D == 1]), max(u$ps[u$D == 0]))
  u$on_support <- u$ps >= lo & u$ps <= hi
  attr(u, "fit") <- fit
  u
}
# Impute the missing potential outcome of every unit (and of covariates, for balance) from its M nearest units of
# the other group in the same year, by the logit of the score. Returns a matrix of imputed values per variable.
# dev_caliper (absolute, log deaths) adds a second caliper on deaths in t; then the M nearest are chosen by the
# combined distance sqrt((d logit / sd logit)^2 + (d deaths / sd deaths)^2) instead of the logit alone.
# attr "matches": one row per (unit, matched unit) pair, row indices into u.
impute_nn <- function(u, vars, caliper = Inf, dev_caliper = Inf) {   # caliper in units of the logit (absolute)
  out <- matrix(NA_real_, nrow(u), length(vars), dimnames = list(NULL, vars))
  sd_lp <- sd(u$lp); sd_dev <- sd(u$viol_lev); pairs <- list()
  for (y in unique(u$yr)) {
    idx <- which(u$yr == y); tr <- idx[u$D[idx] == 1]; co <- idx[u$D[idx] == 0]
    if (length(tr) == 0 || length(co) == 0) next
    vals <- as.matrix(u[vars])
    fill <- function(from, to) {   # for each unit in `from`, mean over its M nearest in `to`
      dist <- abs(outer(u$lp[from], u$lp[to], "-"))
      ddev <- abs(outer(u$viol_lev[from], u$viol_lev[to], "-"))
      rank_d <- if (is.finite(dev_caliper)) sqrt((dist / sd_lp)^2 + (ddev / sd_dev)^2) else dist
      for (r in seq_along(from)) {
        inside <- which(dist[r, ] <= caliper & ddev[r, ] <= dev_caliper)
        if (length(inside) == 0) next
        nn <- to[inside[order(rank_d[r, inside])[seq_len(min(M, length(inside)))]]]
        out[from[r], ] <<- colMeans(vals[nn, , drop = FALSE], na.rm = TRUE)
        pairs[[length(pairs) + 1]] <<- tibble(i = from[r], j = nn)
      }
    }
    fill(tr, co); fill(co, tr)
  }
  out[is.nan(out)] <- NA
  attr(out, "matches") <- bind_rows(pairs)
  out
}
estimate <- function(u) {
  u <- add_score(u); s <- u[u$on_support, ]
  imp <- impute_nn(s, c(OUT_VARS, COVS))
  impc <- impute_nn(s, OUT_VARS, caliper = CALIPER_LOGIT_SD * sd(s$lp))
  # score + deaths: the score caliper and, in addition, deaths in t within DEV_CALIPER_SD SD (script 22's caliper)
  impd <- impute_nn(s, c(OUT_VARS, COVS), caliper = CALIPER_LOGIT_SD * sd(s$lp), dev_caliper = DEV_CALIPER_SD * sd(s$viol_lev))
  nn_rows <- function(y, yh, label) {
    ok <- !is.na(y) & !is.na(yh); tau <- ifelse(s$D == 1, y - yh, yh - y)   # Y(1) - Y(0), observed one filled in
    tibble(estimator = label, estimand = c("ATE", "ATT", "ATC"),
           estimate = c(mean(tau[ok]), mean(tau[ok & s$D == 1]), mean(tau[ok & s$D == 0])),
           units = c(sum(ok), sum(ok & s$D == 1), sum(ok & s$D == 0)))
  }
  rows <- list()
  for (v in OUT_VARS) {
    y <- s[[v]]
    # subclassification on score quantiles (pooled), blocks need both groups
    sv <- s[!is.na(y), ]; sv$y <- y[!is.na(y)]
    br <- unique(quantile(sv$lp, seq(0, 1, length.out = N_BLOCKS + 1)))
    sv$block <- cut(sv$lp, br, include.lowest = TRUE)
    bl <- sv %>% group_by(block) %>% summarise(n = n(), n1 = sum(D == 1), n0 = sum(D == 0),
                                               diff = mean(y[D == 1]) - mean(y[D == 0]), .groups = "drop") %>%
      filter(n1 > 0, n0 > 0)
    rows[[v]] <- bind_rows(
      nn_rows(y, imp[, v], "NN matching"), nn_rows(y, impc[, v], "NN matching, caliper 0.2 SD"),
      nn_rows(y, impd[, v], "NN matching, score + deaths"),
      tibble(estimator = "Subclassification", estimand = c("ATE", "ATT", "ATC"),
             estimate = c(weighted.mean(bl$diff, bl$n), weighted.mean(bl$diff, bl$n1), weighted.mean(bl$diff, bl$n0)),
             units = c(sum(bl$n), sum(bl$n1), sum(bl$n0)))) %>% mutate(var = v, .before = 1)
  }
  bal <- bind_rows(lapply(COVS, function(v) {
    sdp <- sd(u[[v]]); g1 <- s$D == 1; g0 <- s$D == 0
    tibble(variable = v, before = (mean(u[[v]][u$D == 1]) - mean(u[[v]][u$D == 0])) / sdp,
           after_att = mean(s[[v]][g1] - imp[g1, v], na.rm = TRUE) / sdp,
           after_atc = mean(imp[g0, v] - s[[v]][g0], na.rm = TRUE) / sdp,
           after_att_sd = mean(s[[v]][g1] - impd[g1, v], na.rm = TRUE) / sdp)
  }))
  # who is compared with whom: the treated side (each sanctioned event and its matched controls), two designs
  key <- s %>% transmute(iso3c, yr, lp, ps, viol_lev, dy_2)
  who <- bind_rows(
    attr(imp, "matches") %>% mutate(design = "Score only (NN, no caliper)"),
    attr(impd, "matches") %>% mutate(design = "Score + deaths in t (calipers)")) %>%
    filter(s$D[i] == 1) %>%
    bind_cols(rename_with(key[.$i, ], ~ paste0(.x, "_t")), rename_with(key[.$j, ], ~ paste0(.x, "_c"))) %>% select(-i, -j)
  list(est = bind_rows(rows), balance = bal, units = u, who = who)
}

# --- point estimates and bootstrap -------------------------------------------------------------------------
set.seed(20261116)
results <- list(); balance <- list(); scores <- list(); info <- list(); boot_all <- list(); who <- list()
auc <- function(p, D) { r <- rank(p); n1 <- sum(D == 1); n0 <- sum(D == 0); (sum(r[D == 1]) - n1 * (n1 + 1) / 2) / (n1 * n0) }
for (s in names(SAMPLES)) {
  u <- SAMPLES[[s]](units_all)
  pt <- estimate(u)
  states <- unique(u$gwcode)
  boot <- bind_rows(lapply(seq_len(N_BOOT), function(b) {
    drawn <- sample(states, length(states), replace = TRUE)
    ub <- bind_rows(lapply(seq_along(drawn), function(i) mutate(u[u$gwcode == drawn[i], ], gwcode = i)))
    tryCatch(estimate(ub)$est %>% mutate(draw = b), error = function(e) NULL)
  }))
  boot_all[[s]] <- mutate(boot, sample = s)
  se <- boot %>% group_by(var, estimator, estimand) %>%
    summarise(se = sd(estimate, na.rm = TRUE), lower = quantile(estimate, 0.025, na.rm = TRUE),
              upper = quantile(estimate, 0.975, na.rm = TRUE), draws = sum(!is.na(estimate)), .groups = "drop")
  results[[s]] <- pt$est %>% left_join(se, by = c("var", "estimator", "estimand")) %>%
    mutate(sample = s, p_value = 2 * pnorm(-abs(estimate / se)))
  balance[[s]] <- mutate(pt$balance, sample = s)
  who[[s]] <- mutate(pt$who, sample = s)
  scores[[s]] <- pt$units %>% select(gwcode, yr, D, ps, on_support) %>% mutate(sample = s)
  info[[s]] <- tibble(sample = s, units = nrow(u), treated = sum(u$D), controls = sum(1 - u$D),
                      on_support = sum(pt$units$on_support), treated_on_support = sum(pt$units$on_support & pt$units$D == 1),
                      auc = auc(pt$units$ps, pt$units$D), boot_draws = n_distinct(boot$draw))
  cat(s, "done\n")
}
results <- bind_rows(results) %>%
  mutate(type = ifelse(startsWith(var, "dy_"), "Per year: y(t+h) - y(t)", "Cumulative: sum of y(t+j) - y(t), j = 0..h"),
         horizon = as.integer(sub("^m", "-", sub("^d._", "", var))))
balance <- bind_rows(balance); scores <- bind_rows(scores); info <- bind_rows(info); who <- bind_rows(who)
write_csv(who, file.path(TABLES, out_file("us_pscore_matched_pairs.csv")))
write_csv(bind_rows(mutate(results, part = "estimates"), mutate(balance, part = "balance"), mutate(info, part = "sample")),
          file.path(TABLES, out_file("us_pscore_matching.csv")))

# --- figures ----------------------------------------------------------------------------------------------------
fig42 <- ggplot(scores, aes(ps, fill = factor(D, labels = relabel(c("No new US case (clean control)", "New US case"))))) +
  geom_histogram(aes(y = after_stat(density)), bins = 40, alpha = 0.55, position = "identity") +
  facet_wrap(~ sample, scales = "free") +
  scale_fill_manual(values = c(PAPER_COLOURS[["grey"]], PAPER_COLOURS[["blue"]])) +
  scale_x_continuous(trans = "sqrt", breaks = c(0.01, 0.05, 0.1, 0.2, 0.4, 0.6)) +
  labs(title = "Propensity score of a new US sanction: overlap", x = "Propensity score (square-root scale)", y = "Density",
       fill = NULL, caption = paste0("Clean events (no new US case in t-1..t-2) vs clean controls. Logit on deaths in t, t-1, t-2, sanction stock, US sanction in force, democracy, region, 5-year period; ",
                                     "AUC ", paste(sprintf("%.2f", info$auc), collapse = " / "), " (", paste(info$sample, collapse = " / "), ").")) +
  theme_paper() + theme(legend.position = "top")
save_fig(fig42, "fig42_us_pscore_overlap.png", 11, 5)

COLS3 <- c(ATE = PAPER_COLOURS[["orange"]], ATT = PAPER_COLOURS[["blue"]], ATC = PAPER_COLOURS[["grey"]])
pp <- results %>% filter(startsWith(estimator, "NN matching"), estimand %in% c("ATE", "ATT")) %>%
  mutate(segment = ifelse(horizon < 0, "pre", "post"), sample = factor(sample, levels = names(SAMPLES)),
         type = factor(type, levels = unique(results$type)))
sc <- results %>% filter(estimator == "Subclassification", estimand == "ATE") %>%
  mutate(sample = factor(sample, levels = names(SAMPLES)), type = factor(type, levels = levels(pp$type)))
fig43 <- ggplot(pp, aes(horizon, estimate, colour = estimand, fill = estimand, group = interaction(estimand, segment))) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3, linetype = "dotted") +
  geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.15, colour = NA) +
  geom_line(linewidth = 0.8) + geom_point(size = 1.2) +
  geom_point(data = sc, aes(horizon, estimate), inherit.aes = FALSE, shape = 4, size = 1.8, colour = "#14171c") +
  facet_grid(type ~ sample + estimator, scales = "free_y") +
  scale_colour_manual(values = COLS3) + scale_fill_manual(values = COLS3) +
  scale_x_continuous(breaks = c(H_PRE, 0, H_POST)) +
  labs(title = "Propensity-score matching: the lecture's estimand (ATE) and the effect on the sanctioned (ATT)",
       x = "Years relative to the sanction (h); base year t", y = "Change in log(1 + deaths per 100k) since t, Y(1) - Y(0)",
       colour = NULL, fill = NULL,
       caption = paste0("Nearest-neighbour matching on the logit of the propensity score, ", M, " matches, same calendar year, both directions; ",
                        "ATE = average over all units (weights dF_X), ATT = over the sanctioned.\n95% bands from ", N_BOOT,
                        " state-cluster bootstrap draws (approximate for NN matching). Crosses: ATE by subclassification on ",
                        N_BLOCKS, " score blocks. h < -2: placebo. Outcomes end 2019.")) +
  theme_paper() + theme(legend.position = "top")
save_fig(fig43, "fig43_us_pscore_paths.png", 18, 7)

# fig44: who is compared with whom (in conflict). One row per sanctioned event, sorted by its score; blue = the
# event's deaths in t, grey = its matched unsanctioned countries (same year), names on the right.
w <- who %>% filter(sample == "In conflict in t-1") %>%
  mutate(event = paste(iso3c_t, yr_t), design = factor(design, levels = unique(who$design)))
ev <- w %>% filter(design == levels(w$design)[1]) %>% distinct(event, ps_t, viol_lev_t) %>% arrange(ps_t) %>%
  mutate(lab = sprintf("%s  (p = %.2f)", event, ps_t))
grid <- tidyr::expand_grid(ev, design = factor(levels(w$design), levels = levels(w$design)))
w <- w %>% mutate(lab = factor(ev$lab[match(event, ev$event)], levels = ev$lab))
grid <- grid %>% mutate(lab = factor(lab, levels = ev$lab))
names_c <- w %>% group_by(design, lab) %>%
  summarise(txt = paste(sprintf("%s %.2f", iso3c_c, ps_c), collapse = "  "), .groups = "drop") %>%
  right_join(grid %>% select(design, lab), by = c("design", "lab")) %>% mutate(txt = replace_na(txt, "no match within calipers"))
xmax <- max(c(w$viol_lev_t, w$viol_lev_c), na.rm = TRUE)
fig44 <- ggplot() +
  geom_segment(data = w, aes(x = viol_lev_t, xend = viol_lev_c, y = lab, yend = lab), colour = PAPER_COLOURS[["grey"]], linewidth = 0.3, alpha = 0.6) +
  geom_point(data = w, aes(viol_lev_c, lab), colour = PAPER_COLOURS[["grey"]], size = 1.3) +
  geom_point(data = grid, aes(viol_lev_t, lab), colour = PAPER_COLOURS[["blue"]], size = 1.8) +
  geom_text(data = names_c, aes(x = xmax + 0.2, y = lab, label = txt), hjust = 0, size = 2.1, colour = "#52514e") +
  facet_wrap(~ design, nrow = 1) +
  scale_x_continuous(limits = c(0, xmax + 3.6), breaks = 0:floor(xmax)) +
  labs(title = "Who is compared with whom: sanctioned country-years (blue) and their matched unsanctioned countries (grey)",
       x = "Deaths in the sanction year t, log(1 + UCDP deaths per 100k)", y = "Sanctioned event (sorted by propensity score)",
       caption = paste0("In conflict in t-1. Each row: a new US sanction (clean event) and its ", M, " nearest unsanctioned countries in the same year; ",
                        "right: their ISO codes and propensity scores.\nLeft: nearest on the logit of the score, no caliper. Right: within ",
                        CALIPER_LOGIT_SD, " SD of the logit and ", DEV_CALIPER_SD, " SD of deaths in t, nearest on both (standardized).")) +
  theme_paper() + theme(axis.text.y = element_text(size = 6), panel.grid.major.y = element_line(colour = "#ecebe8", linewidth = 0.2))
save_fig(fig44, "fig44_us_pscore_who_matches_whom.png", 15, 13)

# --- table ----------------------------------------------------------------------------------------------------
to_md <- function(table) c(paste0("| ", paste(names(table), collapse = " | "), " |"),
                           paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
                           apply(table, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "", r), collapse = " | "), " |")), "")
cell <- function(e, s, p) sprintf("%.3f%s (%.3f)", e, significance_stars(p), s)
main <- results %>% filter(var %in% c("dy_2", "dc_3")) %>%
  mutate(outcome = recode(var, dy_2 = "h = 2", dc_3 = "cum. 0..3"), cell = paste0(cell(estimate, se, p_value), " [", units, "]")) %>%
  select(sample, estimator, estimand, outcome, cell) %>% pivot_wider(names_from = outcome, values_from = cell)
writeLines(relabel(c(
  "# Propensity-score matching for new US sanctions (lecture estimand)", "",
  paste0("Generated by `empirics/scripts/23_us_pscore_matching.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures `fig42_us_pscore_overlap.png`, `fig43_us_pscore_paths.png`, `fig44_us_pscore_who_matches_whom.png`; all estimates `us_pscore_matching.csv`, pairs `us_pscore_matched_pairs.csv`."), "",
  "Estimand: beta_M = integral [E(Y|D=1,X=x) - E(Y|D=0,X=x)] dF_X(x) (ATE; weights = distribution of x among all units), ",
  "with the propensity score in place of x. ATT / ATC use the distribution among the sanctioned / unsanctioned. ",
  "Y = change in log(1 + UCDP deaths per 100k) since the sanction year. Cells: estimate (bootstrap SE) [units].", "",
  "## Sample, score and common support", "", to_md(info %>% mutate(auc = sprintf("%.2f", auc))),
  "## Estimates", "", to_md(main),
  "## Path (NN matching, both versions)", "",
  to_md(results %>% filter(startsWith(estimator, "NN matching")) %>% mutate(cell = cell(estimate, se, p_value), t = ifelse(startsWith(var, "dy_"), "per year", "cumulative")) %>%
          select(sample, estimator, estimand, t, horizon, cell) %>% pivot_wider(names_from = horizon, names_prefix = "h", values_from = cell)),
  "## Balance (standardized differences; after = through the same NN imputation)", "",
  to_md(balance %>% mutate(across(c(before, after_att, after_atc, after_att_sd), ~ sprintf("%.2f", .x))) %>%
          pivot_wider(names_from = sample, values_from = c(before, after_att, after_atc, after_att_sd))),
  "after_att_sd: ATT side of the score + deaths design.", "",
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01 (normal approximation with the bootstrap SE). The bootstrap is not formally ",
  "valid for NN matching with a fixed number of matches (Abadie & Imbens 2008); subclassification has no such problem."
)), file.path(TABLES, out_file("us_pscore_matching.md")))
cat("\nWrote", file.path(TABLES, out_file("us_pscore_matching.md")), "\n")
