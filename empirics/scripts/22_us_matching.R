# =============================================================================
# 22_us_matching.R — matched difference-in-differences for new US sanctions (added 2026-11-16, user request)
#
# Alternative design to the LP (D11): compare each state-year with a new US case to matched state-years of the SAME
# YEAR without one, and follow both groups over time.
#   Treated : state-year t in the window 1991-2019 with >= 1 new US case without ICC 685.
#   Controls: same calendar year t; no new US case in t-2..t+3 ("clean", as in LP-DiD 12); same conflict status in
#             t-1 (>= 25 UCDP deaths); the K nearest by Mahalanobis distance on log(1 + deaths per 100k) in t, t-1,
#             t-2, the sanction stock in t-1 (cases in force), a US sanction in force in t-1, and any new US case in
#             t-1..t-2. With replacement; treated events without a control within the caliper are dropped.
#   Outcome : change since year t, y(t+h) - y(t) (shock second: the base year is the sanction year, as in D11), and
#             the cumulative version sum_{j=0..h} (y(t+j) - y(t)). The difference in changes removes stable country
#             differences (like state FE); matching on the same year removes common shocks (like year FE).
#   Effect  : per event i, d_ih = treated change - mean change of its controls; ATT_h = mean of d_ih; SE clustered by
#             the treated country (matches treated as fixed — approximate, see notes). h = -5..-3 are placebos
#             (deaths before the sanction, beyond the matched years).
#   Samples : in conflict in t-1 (main, as notes 21) and all state-years.
#   Over the years: d_i2 and cumulative d_i,0..3 by shock year; rolling 9-year means with clustered 95% intervals,
#             and period means 1991-99 / 2000-09 / 2010-19.
# Other sender groups (17 Nov): --shock=any|un|western runs the same design for that group ("US" in the comments then
#   means that group); outputs go to results/{tables,figures}/senders/ with the group as prefix. Called by 24.
# Output: tables/us_matching.md/.csv, figures/fig40_us_matching_path.png, fig41_us_matching_over_time.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

ICC_CASE <- 685
K <- 3                 # controls per treated event
CALIPER_SD <- 0.5      # caliper on deaths in t, in SD of the sample
CLEAN <- -2:3          # no new US case in t + CLEAN for a control
H_PRE <- -5:-3; H_POST <- 1:8
MATCH_VARS <- c("viol_lev", "viol_lev_l1", "viol_lev_l2", "ctrl_stock", "us_force_l1", "ctrl_democracy")
EXACT <- "us_new_l12"

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
d$conflict_l1 <- lag_by_year(d, "viol_inc", 1)
d$us_force_l1 <- as.integer(lag_by_year(d, "us_sanction", 1) %in% 1)
d$us_new_l12  <- as.integer((replace_na(lag_by_year(d, "x", 1), 0) + replace_na(lag_by_year(d, "x", 2), 0)) > 0)
d$clean <- Reduce(`&`, lapply(CLEAN, function(k) replace_na((if (k == 0) d$x else lag_by_year(d, "x", -k)) == 0, TRUE)))
hn <- function(h) ifelse(h < 0, paste0("m", -h), as.character(h))
for (h in c(H_PRE, H_POST)) d[[paste0("dy_", hn(h))]] <- (if (h < 0) lag_by_year(d, "viol_lev", -h) else lead("viol_lev", h)) - d$viol_lev
for (h in H_POST) d[[paste0("dc_", h)]] <- Reduce(`+`, lapply(0:h, function(j) (if (j == 0) d$viol_lev else lead("viol_lev", j)) - d$viol_lev))
OUT_VARS <- c(paste0("dy_", hn(c(H_PRE, H_POST))), paste0("dc_", H_POST))

d$viol_lev_l3 <- lag_by_year(d, "viol_lev", 3); d$viol_lev_l4 <- lag_by_year(d, "viol_lev", 4)
base <- d %>% filter(in_window) %>% drop_na(all_of(c(MATCH_VARS, EXACT))) %>% mutate(conflict_l1 = conflict_l1 %in% 1)
SAMPLES <- c("In conflict in t-1" = TRUE, "All state-years" = FALSE)

match_sample <- function(conflict_only) {
  pool <- if (conflict_only) filter(base, conflict_l1) else base
  S_inv <- solve(cov(pool[MATCH_VARS]))
  caliper <- CALIPER_SD * sd(pool$viol_lev)
  treated <- pool %>% filter(x > 0)
  controls <- pool %>% filter(x == 0, clean)
  pairs <- list(); dropped <- 0
  for (i in seq_len(nrow(treated))) {
    tr <- treated[i, ]
    cand <- controls %>% filter(yr == tr$yr, conflict_l1 == tr$conflict_l1, gwcode != tr$gwcode,
                                .data[[EXACT]] == tr[[EXACT]], abs(viol_lev - tr$viol_lev) <= caliper)
    if (nrow(cand) == 0) { dropped <- dropped + 1; next }
    diff <- as.matrix(cand[MATCH_VARS]) - matrix(unlist(tr[MATCH_VARS]), nrow(cand), length(MATCH_VARS), byrow = TRUE)
    dist <- sqrt(rowSums((diff %*% S_inv) * diff))
    take <- order(dist)[seq_len(min(K, length(dist)))]
    pairs[[length(pairs) + 1]] <- bind_rows(mutate(tr, role = "treated", event = i, distance = 0),
                                            mutate(cand[take, ], role = "control", event = i, distance = dist[take]))
  }
  list(pairs = bind_rows(pairs), dropped = dropped, treated = nrow(treated))
}

att <- function(event_d, v) {   # mean of event-level differences, SE clustered by treated country
  z <- event_d %>% filter(!is.na(.data[[v]]))
  f <- feols(as.formula(paste(v, "~ 1")), z, cluster = ~ gwcode)
  tibble(estimate = coef(f)[[1]], se = se(f)[[1]], p_value = pvalue(f)[[1]], events = nrow(z), states = n_distinct(z$gwcode))
}
results <- list(); balance <- list(); events_all <- list(); info <- list(); adjusted <- list()
for (s in names(SAMPLES)) {
  m <- match_sample(SAMPLES[[s]])
  pr <- m$pairs
  info[[s]] <- tibble(sample = s, treated_events = m$treated, matched = n_distinct(pr$event), dropped = m$dropped,
                      controls_used = sum(pr$role == "control"), distinct_controls = n_distinct(paste(pr$gwcode[pr$role == "control"], pr$yr[pr$role == "control"])))
  ev <- pr %>% group_by(event) %>%
    summarise(gwcode = gwcode[role == "treated"], gw_name = gw_name[role == "treated"], yr = yr[role == "treated"],
              across(all_of(OUT_VARS), ~ .x[role == "treated"] - mean(.x[role == "control"], na.rm = TRUE)), .groups = "drop") %>%
    mutate(across(all_of(OUT_VARS), ~ ifelse(is.nan(.x), NA, .x)))
  # covariate gaps per event (treated minus mean of its controls), for the bias adjustment
  gaps <- pr %>% group_by(event) %>%
    summarise(across(all_of(MATCH_VARS), ~ .x[role == "treated"] - mean(.x[role == "control"]), .names = "gap_{.col}"), .groups = "drop")
  ev <- ev %>% left_join(gaps, by = "event")
  events_all[[s]] <- mutate(ev, sample = s)
  results[[s]] <- bind_rows(lapply(OUT_VARS, function(v) att(ev, v) %>% mutate(var = v))) %>% mutate(sample = s)
  # bias-adjusted (Abadie-Imbens style, linear): intercept of d_ih on the covariate gaps
  for (v in c("dy_2", "dc_3")) {
    z <- ev %>% filter(!is.na(.data[[v]]))
    f <- feols(as.formula(paste(v, "~", paste0("gap_", MATCH_VARS, collapse = " + "))), z, cluster = ~ gwcode)
    adjusted[[length(adjusted) + 1]] <- tibble(sample = s, var = v, estimate = coef(f)[["(Intercept)"]],
                                               se = se(f)[["(Intercept)"]], p_value = pvalue(f)[["(Intercept)"]], events = nrow(z))
  }
  # balance: standardized mean differences, matching variables and pre-period / other covariates not matched on
  bal_vars <- c(MATCH_VARS, EXACT, "ctrl_gdp_growth", "viol_lev_l3", "viol_lev_l4")
  poolx <- if (SAMPLES[[s]]) filter(base, conflict_l1) else base; prx <- pr
  smd <- function(a, b, v) (mean(a[[v]], na.rm = TRUE) - mean(b[[v]], na.rm = TRUE)) / sd(poolx[[v]], na.rm = TRUE)
  for (v in bal_vars) {
    balance[[length(balance) + 1]] <- tibble(sample = s, variable = v, matched_on = v %in% MATCH_VARS,
      before = smd(filter(poolx, x > 0), filter(poolx, x == 0, clean), v),
      after = smd(filter(prx, role == "treated"), filter(prx, role == "control"), v))
  }
}
results <- bind_rows(results) %>%
  mutate(type = ifelse(startsWith(var, "dy_"), "Per year: y(t+h) - y(t)", "Cumulative: sum of y(t+j) - y(t), j = 0..h"),
         horizon = as.integer(sub("^m", "-", sub("^d._", "", var))), lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
balance <- bind_rows(balance); info <- bind_rows(info); events_all <- bind_rows(events_all); adjusted <- bind_rows(adjusted)

# Over the years: event-level effects by shock year ----------------------------------------------------------
ROLL_HALF <- 4
over_time <- list()
for (s in names(SAMPLES)) for (v in c("dy_2", "dc_3")) {
  ev <- events_all %>% filter(sample == s, !is.na(.data[[v]]))
  for (centre in (1991 + ROLL_HALF):(2019 - ROLL_HALF)) {
    z <- filter(ev, abs(yr - centre) <= ROLL_HALF)
    if (nrow(z) < 5 || n_distinct(z$gwcode) < 3) next
    over_time[[length(over_time) + 1]] <- att(rename(z, val = all_of(v)), "val") %>% mutate(sample = s, var = v, centre = centre)
  }
  for (p in list(c(1991, 1999), c(2000, 2009), c(2010, 2019))) {
    z <- filter(ev, yr >= p[1], yr <= p[2])
    if (nrow(z) >= 3) over_time[[length(over_time) + 1]] <- att(rename(z, val = all_of(v)), "val") %>%
      mutate(sample = s, var = v, period = paste0(p[1], "-", substr(p[2], 3, 4)))
  }
}
over_time <- bind_rows(over_time) %>% mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
write_csv(bind_rows(mutate(results, part = "path"), mutate(over_time, part = "over time"),
                    mutate(balance, part = "balance"), mutate(info, part = "matching"), mutate(adjusted, part = "bias-adjusted")),
          file.path(TABLES, out_file("us_matching.csv")))
write_csv(events_all, file.path(TABLES, out_file("us_matching_events.csv")))

# Figures ----------------------------------------------------------------------------------------------------
COLS <- c("All state-years" = PAPER_COLOURS[["blue"]], "In conflict in t-1" = PAPER_COLOURS[["orange"]])
lp_file <- if (SHOCK == "us") file.path(TABLES, "us_paths.csv") else file.path(TABLES, paste0(SHOCK, "_lp_paths.csv"))   # base LP path (21; other groups: 24)
if (!file.exists(lp_file)) stop("needs the LP path ", lp_file, " (script 21 for the US, 24 for other sender groups)")
lp <- read_csv(lp_file, show_col_types = FALSE) %>%
  mutate(type = ifelse(startsWith(var, "py_"), "Per year: y(t+h) - y(t)", "Cumulative: sum of y(t+j) - y(t), j = 0..h"))
pl <- results %>% mutate(segment = ifelse(horizon < 0, "pre", "post"), sample = factor(sample, levels = names(COLS)),
                         type = factor(type, levels = unique(results$type)))
lpp <- lp %>% filter(horizon > 0) %>% mutate(sample = factor(sample, levels = names(COLS)), type = factor(type, levels = levels(pl$type)))
fig40 <- ggplot(pl, aes(horizon, estimate, group = segment)) +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3, linetype = "dotted") +
  geom_ribbon(aes(ymin = lower, ymax = upper, fill = sample), alpha = 0.18) +
  geom_line(aes(colour = sample), linewidth = 0.8) + geom_point(aes(colour = sample), size = 1.3) +
  geom_point(data = lpp, aes(horizon, estimate), inherit.aes = FALSE, shape = 4, size = 1.8, colour = "#14171c") +
  facet_grid(type ~ sample, scales = "free_y") +
  scale_colour_manual(values = COLS, guide = "none") + scale_fill_manual(values = COLS, guide = "none") +
  scale_x_continuous(breaks = c(H_PRE, 0, H_POST)) +
  labs(title = "Matched difference-in-differences: deaths before and after a new US sanction",
       x = "Years relative to the sanction (h); base year t; h = -2, -1 matched on", y = "Treated minus matched controls, change in log(1 + deaths per 100k) since t",
       caption = paste0("Each US sanction-year matched to ", K, " state-years of the same year with no US case in t-2..t+3, same conflict status in t-1, ",
                        "nearest on deaths in t, t-1, t-2, sanction history and democracy (Mahalanobis; caliper ", CALIPER_SD, " SD on deaths in t).\n",
                        "95% intervals, SE clustered by the treated country. Crosses: base local projection (script 21) for comparison. ",
                        "h < -2: placebo. Outcomes end 2019.")) +
  theme_paper()
save_fig(fig40, "fig40_us_matching_path.png", 12, 7)

ot <- over_time %>% filter(!is.na(centre)) %>% mutate(sample = factor(sample, levels = names(COLS)),
  var = factor(recode(var, dy_2 = "Per year, h = 2", dc_3 = "Cumulative, h = 0..3"), levels = c("Per year, h = 2", "Cumulative, h = 0..3")))
evp <- events_all %>% select(sample, gw_name, yr, dy_2, dc_3) %>% pivot_longer(c(dy_2, dc_3), names_to = "var", values_to = "d") %>%
  filter(!is.na(d)) %>% mutate(sample = factor(sample, levels = names(COLS)),
  var = factor(recode(var, dy_2 = "Per year, h = 2", dc_3 = "Cumulative, h = 0..3"), levels = levels(ot$var)))
lim <- evp %>% group_by(var) %>% summarise(q = quantile(abs(d), 0.97))
evp <- evp %>% left_join(lim, by = "var") %>% mutate(d_shown = pmax(pmin(d, q), -q))
fig41 <- ggplot() +
  geom_hline(yintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_point(data = evp, aes(yr, d_shown, colour = sample), alpha = 0.35, size = 1.1) +
  geom_ribbon(data = ot, aes(centre, ymin = lower, ymax = upper, fill = sample), alpha = 0.2) +
  geom_line(data = ot, aes(centre, estimate, colour = sample), linewidth = 0.9) +
  facet_grid(var ~ sample, scales = "free_y") +
  scale_colour_manual(values = COLS, guide = "none") + scale_fill_manual(values = COLS, guide = "none") +
  scale_x_continuous(breaks = seq(1991, 2019, 4)) +
  labs(title = "Effect of a new US sanction by the year it was imposed (matched difference-in-differences)",
       x = "Year of the US sanction", y = "Treated minus matched controls",
       caption = paste0("Dots: one US sanction event each (effects larger in absolute value than the 97th percentile drawn at the edge). ",
                        "Line and band: mean over events in a 9-year window of shock years, 95% interval clustered by country.\n",
                        "Late windows lose events at the cumulative horizon (outcomes end 2019).")) +
  theme_paper()
save_fig(fig41, "fig41_us_matching_over_time.png", 12, 7)

# Table ----------------------------------------------------------------------------------------------------
to_md <- function(table) c(paste0("| ", paste(names(table), collapse = " | "), " |"),
                           paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
                           apply(table, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "", r), collapse = " | "), " |")), "")
cell <- function(e, s, p) sprintf("%.3f%s (%.3f)", e, significance_stars(p), s)
writeLines(relabel(c(
  "# Matched difference-in-differences for new US sanctions", "",
  paste0("Generated by `empirics/scripts/22_us_matching.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figures `fig40_us_matching_path.png`, `fig41_us_matching_over_time.png`; estimates `us_matching.csv`, ",
         "event-level effects `us_matching_events.csv`."), "",
  paste0("Each US sanction-year (new US case w/o ICC 685, 1991-2019) matched to ", K, " state-years of the same year with no new US ",
         "case in t-2..t+3, the same conflict status in t-1 and the same value of ", EXACT, ", nearest (Mahalanobis; caliper ", CALIPER_SD, " SD on deaths in t) on: ",
         paste(MATCH_VARS, collapse = ", "), ". Outcome: change in log(1 + UCDP deaths per 100k) since the sanction year t. ",
         "Cells: mean treated-minus-control difference (SE clustered by treated country) [events]."), "",
  "## Matching", "", to_md(info),
  "## Balance (standardized mean differences, treated minus controls)", "",
  to_md(balance %>% mutate(before = sprintf("%.2f", before), after = sprintf("%.2f", after)) %>%
          pivot_wider(names_from = sample, values_from = c(before, after))),
  "## Path", "",
  to_md(results %>% mutate(cell = paste0(cell(estimate, se, p_value), " [", events, "]"),
                           type = ifelse(startsWith(var, "dy_"), "per year", "cumulative")) %>%
          select(sample, type, horizon, cell) %>% pivot_wider(names_from = horizon, names_prefix = "h", values_from = cell)),
  "## Bias-adjusted (event-level difference regressed on the treated-minus-control covariate gaps; intercept)", "",
  to_md(adjusted %>% transmute(sample, outcome = recode(var, dy_2 = "h = 2", dc_3 = "cum. 0..3"),
                               adjusted = paste0(cell(estimate, se, p_value), " [", events, "]"))),
  "## By period of the sanction", "",
  to_md(over_time %>% filter(!is.na(period)) %>% mutate(cell = paste0(cell(estimate, se, p_value), " [", events, "]"),
                                                       var = recode(var, dy_2 = "h = 2", dc_3 = "cum. 0..3")) %>%
          select(sample, var, period, cell) %>% pivot_wider(names_from = period, values_from = cell)),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. SEs treat the matched controls as fixed (no adjustment for matching ",
  "uncertainty; Abadie-Imbens). Rolling 9-year windows: `us_matching.csv`, part `over time`."
)), file.path(TABLES, out_file("us_matching.md")))
cat("\nWrote", file.path(TABLES, out_file("us_matching.md")), "\n")
