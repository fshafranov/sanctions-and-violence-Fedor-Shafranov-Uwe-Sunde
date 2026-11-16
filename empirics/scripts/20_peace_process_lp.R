# =============================================================================
# 20_peace_process_lp.R — is the US effect a peace-process effect? (added 2026-11-16, user request)
#
# Concern (13 sections 5-8): the deaths decline after new US sanctions is concentrated in a few wars that ended soon
# after, so the US may sanction when a war is already winding down (settlements, talks). UCDP peace agreements and
# conflict terminations (data/clean/ucdp_peace/peace_cy.csv, clean_ucdp_peace.R) measure that directly.
# Same LP as 13 throughout: shock = new US cases without ICC 685 (count), response log(1 + UCDP deaths per 100k),
# shock second, 2 lags of shock and response, state + year FE, SE clustered by state; outcomes y(t+2), y(t..t+3).
# Samples: all state-years; in conflict in t-1 (>= 25 UCDP deaths).
#
#   (A) controls for peace agreements in the target state: t-2..t-1 (signed before), t-2..t (incl. the same year),
#       t-2..t+1 (incl. the next year: absorbs an anticipated settlement; partly a bad control, since a sanction
#       could also bring the agreement about -> an upper bound on what anticipation can explain); and the
#       before/from-2000 split with the t-2..t control
#   (B) the shock split: US cases with an agreement in the target in t-2..t ("peace process under way") vs without
#   (C) war termination as the outcome, in conflict in t-1: a conflict episode located in the state has its last
#       active year in t..t+2 (any; by peace agreement or ceasefire; by victory; by low activity) — linear probability
#   (D) reaction function: do agreements predict a new US case? new US case (0/1) in t on agreement dummies t-1,
#       t-2 (and t) with the violence and sanction history and FE
# Descriptive: share of US shock-years with an agreement in t-2..t and in t+1..t+2, by decade.
# Output: tables/peace_process_lp.md/.csv, figures/fig36_peace_process_lp.png
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
use_analysis_packages("fixest")

ICC_CASE <- 685
SHOCK <- "x"; RESPONSE <- "viol_lev"
OUTCOMES <- c(per_year_h2 = "Per year, h = 2", cumulative_h3 = "Cumulative, h = 0..3")
value_at <- function(data, variable, k) lag_by_year(data, variable, -k)
cumulative_to <- function(data, variable, h) Reduce(`+`, lapply(0:h, function(j) value_at(data, variable, j)))
any_in <- function(data, variable, ks) {   # 1 if variable > 0 in any of the years t + k, k in ks (NA if all missing)
  m <- sapply(ks, function(k) if (k == 0) data[[variable]] else lag_by_year(data, variable, -k))
  as.integer(rowSums(m > 0, na.rm = TRUE) > 0) * ifelse(rowSums(!is.na(m)) > 0, 1L, NA_integer_)
}

us_counts <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
  filter(us == 1, case != ICC_CASE) %>% count(iso3c = country_iso3, yr = year, name = "x")
peace <- read_csv(here("data", "clean", "ucdp_peace", "peace_cy.csv"), show_col_types = FALSE) %>% rename(yr = year)
d <- read_csv(file.path(SAMPLE_DATA, "analysis_panel.csv"), show_col_types = FALSE) %>%
  left_join(us_counts, by = c("iso3c", "yr")) %>% left_join(peace, by = c("gwcode", "yr")) %>%
  mutate(x = replace_na(x, 0L), across(starts_with(c("pa_", "term_")), ~ replace_na(.x, 0L)),
         term_peace = term_agreement + term_ceasefire) %>% arrange(gwcode, yr)
stopifnot(!anyDuplicated(d[c("gwcode", "yr")]))
d <- add_lags(d, c(SHOCK, RESPONSE), VAR_LAGS)
d$per_year_h2   <- value_at(d, RESPONSE, 2)
d$cumulative_h3 <- cumulative_to(d, RESPONSE, 3)
d$conflict_l1   <- lag_by_year(d, "viol_inc", 1)
for (k in -2:1) d[[paste0("pa_", ifelse(k < 0, paste0("l", -k), ifelse(k == 0, "t", paste0("f", k))))]] <-
  as.integer((if (k == 0) d$pa_n else lag_by_year(d, "pa_n", -k)) > 0)
d$process     <- any_in(d, "pa_n", -2:0)              # agreement in t-2..t
d$pa_next     <- any_in(d, "pa_n", 1:2)               # agreement in t+1..t+2
d$x_process   <- d$x * (d$process %in% 1)
d$x_noprocess <- d$x - d$x_process
d$shock_pre   <- d$x * (d$yr < 2000); d$shock_post <- d$x * (d$yr >= 2000)
for (v in c("term_n", "term_peace", "term_victory", "term_low_activity")) d[[paste0("end_", v)]] <- any_in(d, v, 0:2)
d$new_us <- as.integer(d$x > 0)
HISTORY <- c(lag_names(SHOCK, VAR_LAGS), lag_names(RESPONSE, VAR_LAGS), RESPONSE)
SAMPLES <- list("All state-years" = function(x) x, "In conflict in t-1" = function(x) filter(x, conflict_l1 %in% 1))

fit <- function(data, outcome, terms, controls = character(0), history = HISTORY) {
  s <- data %>% filter(in_window) %>% drop_na(all_of(c(outcome, terms, controls, history)))
  feols(as.formula(paste(outcome, "~", paste(c(terms, controls, history), collapse = " + "), "| gwcode + yr")),
        data = s, cluster = ~ gwcode)
}
rows_of <- function(f, terms, ...) {
  ct <- coeftable(f)
  tibble(..., term = terms, estimate = ct[terms, 1], se = ct[terms, 2], p_value = ct[terms, 4], observations = nobs(f))
}
diff_p <- function(f, a, b) { v <- vcov(f); unname(2 * pnorm(-abs((coef(f)[a] - coef(f)[b]) / sqrt(v[a, a] + v[b, b] - 2 * v[a, b])))) }

# (A) controls and (B) split ---------------------------------------------------------------------------------
CONTROL_SETS <- list("No peace controls (base)" = character(0),
                     "Agreements t-2, t-1" = c("pa_l2", "pa_l1"),
                     "Agreements t-2 .. t" = c("pa_l2", "pa_l1", "pa_t"),
                     "Agreements t-2 .. t+1" = c("pa_l2", "pa_l1", "pa_t", "pa_f1"))
res <- list()
for (sample_name in names(SAMPLES)) for (outcome in names(OUTCOMES)) {
  ds <- SAMPLES[[sample_name]](d)
  for (cs in names(CONTROL_SETS)) {
    f <- fit(ds, outcome, SHOCK, CONTROL_SETS[[cs]])
    res[[length(res) + 1]] <- rows_of(f, SHOCK, part = "A", sample = sample_name, outcome = outcome, variant = cs)
    if (cs %in% c("No peace controls (base)", "Agreements t-2 .. t")) {
      f2 <- fit(ds, outcome, c("shock_pre", "shock_post"), CONTROL_SETS[[cs]])
      res[[length(res) + 1]] <- rows_of(f2, c("shock_pre", "shock_post"), part = "A period", sample = sample_name,
                                        outcome = outcome, variant = cs) %>%
        mutate(p_equal = diff_p(f2, "shock_pre", "shock_post"))
    }
  }
  fb <- fit(ds, outcome, c("x_process", "x_noprocess"), "process")
  used <- ds %>% filter(in_window) %>% drop_na(all_of(c(outcome, "x_process", "process", HISTORY)))
  res[[length(res) + 1]] <- rows_of(fb, c("x_process", "x_noprocess"), part = "B", sample = sample_name,
                                    outcome = outcome, variant = "Split by agreement in t-2..t") %>%
    mutate(p_equal = diff_p(fb, "x_process", "x_noprocess"),
           shock_years = c(sum(used$x_process > 0), sum(used$x_noprocess > 0)))
}

# (C) termination as outcome (in conflict in t-1) -------------------------------------------------------------
END_LABELS <- c(end_term_n = "Any termination", end_term_peace = "By peace agreement or ceasefire",
                end_term_victory = "By victory", end_term_low_activity = "By low activity / actor ceases")
war <- filter(d, conflict_l1 %in% 1)
for (v in names(END_LABELS)) {
  f <- fit(war, v, SHOCK)
  res[[length(res) + 1]] <- rows_of(f, SHOCK, part = "C", sample = "In conflict in t-1", outcome = v,
                                    variant = END_LABELS[[v]]) %>%
    mutate(mean_outcome = mean(war[[v]][war$in_window], na.rm = TRUE))
}

# (D) reaction function -----------------------------------------------------------------------------------
RF_HISTORY <- c(lag_names(SHOCK, VAR_LAGS), lag_names(RESPONSE, VAR_LAGS))
for (sample_name in names(SAMPLES)) for (terms in list(c("pa_l1", "pa_l2"), c("pa_t", "pa_l1", "pa_l2"))) {
  f <- fit(SAMPLES[[sample_name]](d), "new_us", terms, history = RF_HISTORY)
  res[[length(res) + 1]] <- rows_of(f, terms, part = "D", sample = sample_name, outcome = "new_us",
                                    variant = paste("Agreements", paste(terms, collapse = ", "))) %>%
    mutate(mean_outcome = mean(SAMPLES[[sample_name]](d) %>% filter(in_window) %>% pull(new_us)))
}
res <- bind_rows(res)

shares <- d %>% filter(in_window, x > 0) %>%
  mutate(period = cut(yr, c(-Inf, 1999, 2009, Inf), labels = c("1991-99", "2000-09", "2010-19"))) %>%
  group_by(period) %>%
  summarise(us_shock_years = n(), in_conflict_t1 = mean(conflict_l1 %in% 1), agreement_t2_t = mean(process %in% 1),
            agreement_t1_t2 = mean(pa_next %in% 1), war_ends_t_t2 = mean(end_term_n %in% 1), .groups = "drop")
write_csv(bind_rows(res, mutate(shares, part = "shares")), file.path(TABLES, "peace_process_lp.csv"))

# Figure: (A) and (B), dot and whisker
TERM_LABELS <- c(x = "All US cases", shock_pre = "Shocks 1991-99", shock_post = "Shocks 2000-19",
                 x_process = "Agreement in t-2..t", x_noprocess = "No agreement in t-2..t")
plot_ab <- res %>% filter(part %in% c("A", "A period", "B")) %>%
  mutate(row = ifelse(part == "B", paste0("Split: ", TERM_LABELS[term]),
                      ifelse(part == "A period", paste0(variant, ": ", TERM_LABELS[term]), variant)),
         row = factor(row, levels = rev(unique(row))),
         block = recode(part, A = "Peace-agreement controls", `A period` = "By shock period", B = "Shock split"),
         block = factor(block, levels = c("Peace-agreement controls", "By shock period", "Shock split")),
         outcome = factor(OUTCOMES[outcome], levels = OUTCOMES),
         lower = estimate - 1.96 * se, upper = estimate + 1.96 * se)
fig36 <- ggplot(plot_ab, aes(estimate, row, colour = sample)) +
  geom_vline(xintercept = 0, colour = "#52514e", linewidth = 0.3) +
  geom_errorbarh(aes(xmin = lower, xmax = upper), height = 0, position = position_dodge(width = 0.6)) +
  geom_point(size = 1.6, position = position_dodge(width = 0.6)) +
  facet_grid(block ~ outcome, scales = "free", space = "free_y") +
  scale_colour_manual(values = c("All state-years" = PAPER_COLOURS[["blue"]], "In conflict in t-1" = PAPER_COLOURS[["orange"]])) +
  labs(title = "Does the US effect survive accounting for peace agreements?",
       x = "Response of log(1 + UCDP deaths per 100k) to one new US case (without ICC case 685)", y = NULL, colour = NULL,
       caption = paste0("Panel local projections, shock second, ", VAR_LAGS, " lags, state and year FE; 95% intervals, SE clustered by state. ",
                        "Agreements: UCDP Peace Agreement Dataset v22.2, located by the conflict's location.\n",
                        "Controls are dummies for an agreement in the target state in the years shown; t+1 partly absorbs effects ",
                        "of the sanction itself (upper bound for anticipation).")) +
  theme_paper() + theme(legend.position = "top", strip.text.y = element_text(angle = 0, hjust = 0))
save_figure(fig36, "fig36_peace_process_lp.png", 12, 7)

to_md <- function(table) c(paste0("| ", paste(names(table), collapse = " | "), " |"),
                           paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
                           apply(table, 1, function(r) paste0("| ", paste(ifelse(is.na(r), "", r), collapse = " | "), " |")), "")
cell <- function(e, s, p) sprintf("%.3f%s (%.3f)", e, significance_stars(p), s)
ab_table <- res %>% filter(part %in% c("A", "A period", "B")) %>%
  mutate(cell = paste0(cell(estimate, se, p_value), ifelse(is.na(p_equal), "", sprintf(" [p= %.2f]", p_equal))),
         term = TERM_LABELS[term], outcome = OUTCOMES[outcome]) %>%
  select(sample, variant, term, outcome, cell) %>% pivot_wider(names_from = outcome, values_from = cell)
writeLines(c(
  "# Peace agreements and the US effect", "",
  paste0("Generated by `empirics/scripts/20_peace_process_lp.R` on ", format(Sys.time(), "%Y-%m-%d %H:%M"),
         ". Figure `fig36_peace_process_lp.png`; all estimates `peace_process_lp.csv`."), "",
  "Shock: new US cases without ICC 685; response log(1 + UCDP deaths per 100k); shock second, 2 lags, state and year FE. ",
  "Agreements: UCDP Peace Agreement Dataset v22.2 (data/clean/ucdp_peace). Cells: coefficient (SE); [p=] test of equal coefficients.", "",
  "## Share of US shock-years with a peace agreement or a war ending nearby", "",
  to_md(shares %>% mutate(across(where(is.double), ~ sprintf("%.2f", .x)))),
  "## (A) Peace-agreement controls, (B) shock split", "",
  to_md(ab_table),
  "## (C) War termination after a US case (in conflict in t-1; linear probability, outcome = episode's last active year in t..t+2)", "",
  to_md(res %>% filter(part == "C") %>% transmute(outcome = variant, coefficient = cell(estimate, se, p_value),
                                                  mean_outcome = sprintf("%.3f", mean_outcome), observations)),
  "## (D) Do agreements predict a new US case? (new US case 0/1 in t)", "",
  to_md(res %>% filter(part == "D") %>% transmute(sample, variant, term, coefficient = cell(estimate, se, p_value),
                                                  mean_outcome = sprintf("%.3f", mean_outcome), observations)),
  "*Notes:* * p<0.1, ** p<0.05, *** p<0.01. Agreement data end in 2021; termination = UCDP Conflict Termination v4-2024."
), file.path(TABLES, "peace_process_lp.md"))
cat("\nWrote", file.path(TABLES, "peace_process_lp.md"), "\n")
