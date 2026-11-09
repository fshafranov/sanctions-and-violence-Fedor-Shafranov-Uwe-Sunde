# =============================================================================
# functions_exposure.R — shared data builders and estimation for the exposure scripts (added 2026-11-09)
#   source(here::here("exposure", "scripts", "functions_exposure.R"))   (after 00_setup.R)
#
# Violence sources UCDP, ACLED, GDELT through the main project's builder build_source_panel() in
# empirics/specifications.R (same windows and variable names as the specification grid, which reproduces
# 13_local_projections.R exactly): violence_lev = log(1 + UCDP deaths per 100k) / log(1 + ACLED fatalities per
# 100k) / GDELT violent events per 10,000 events; in_window = the source's own coverage; ucdp_conflict_l1 =
# >= 25 UCDP deaths in t-1 for every source.
# =============================================================================
source(here::here("empirics", "specifications.R"))
use_analysis_packages("fixest")

HORIZON <- 8
SOURCES <- c(ucdp = "UCDP", acled = "ACLED", gdelt = "GDELT")
SOURCE_UNITS <- c(ucdp = "log(1 + UCDP deaths per 100k)", acled = "log(1 + ACLED fatalities per 100k)",
                  gdelt = "GDELT violent events per 10,000 events")
SHOCKS <- c(us = "n_new_exp_us", eu = "n_new_exp_eu", all = "n_new_exp_all")
SHOCK_LABELS <- c(us = "US cases (w/o ICC 685)", eu = "EU cases", all = "All cases (w/o ICC 685)")
GROUP_OF_SHOCK <- c(us = "us", eu = "eu", all = "senders")
MEASURES <- c(trade_gdp = "Trade with sender / GDP (log)", trade_gdp_w = "Trade with sender / GDP (winsorised p99)",
              trade_share = "Sender share of trade", arms_share = "Sender share of arms imports")
WINSOR_QUANTILE <- 0.99

# --- data --------------------------------------------------------------------------------------------------
exposure_shocks <- function() {
  read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
    filter(case != ICC_CASE) %>%
    group_by(iso3c = country_iso3, yr = year) %>%
    summarise(n_new_exp_us = sum(us), n_new_exp_eu = sum(eu), n_new_exp_all = n(), .groups = "drop")
}

exposure_data <- function(source) {
  panel <- read_panel()
  columns <- grep("^(trade|arms)_(us|eu|senders)_(gdp|share)$|^trade_(us|eu|senders)_zero_imputed$",
                  names(panel), value = TRUE)
  build_source_panel(source, "own", exposure_shocks()) %>%
    left_join(panel %>% select(gwcode, yr, all_of(columns)), by = c("gwcode", "yr")) %>%
    arrange(gwcode, yr)
}

value_at <- function(d, variable, k) lag_by_year(d, variable, -k)
cumulative_to <- function(d, variable, h) Reduce(`+`, lapply(0:h, function(j) value_at(d, variable, j)))

exposure_column <- function(shock_name, measure) {
  group <- GROUP_OF_SHOCK[[shock_name]]
  switch(sub("_w$", "", measure), trade_gdp = paste0("trade_", group, "_gdp"),
         trade_share = paste0("trade_", group, "_share"), arms_share = paste0("arms_", group, "_share"))
}

# --- estimation --------------------------------------------------------------------------------------------
# mode "linear"  : shock + shock x z (+ z unless "senders"); z standardised over the shock state-years
# mode "groups"  : separate shock coefficients by exposure group. Trade measures: terciles over the shock
#                  state-years. Arms shares (many exact zeros: e.g. 123 of 228 US-sanctioned state-years in the
#                  ACLED sample had 0 % US arms): "none" (0 %), "some" (below the median of the positive shares),
#                  "high" (above it). Exposure 2026-11-09, data/README.md 4c; exposure/ANALYSIS_PLAN.md E7.
# check "na_trade"    : trade with the sender missing where it was set to 0 for lack of a recorded flow (X5)
# check "in_conflict" : state-years with >= 25 UCDP deaths in t-1
estimate_paths <- function(d, source, shock_name, measure, check = "base", mode = "linear") {
  shock <- SHOCKS[[shock_name]]; group <- GROUP_OF_SHOCK[[shock_name]]; senders <- group == "senders"
  column <- exposure_column(shock_name, measure)
  raw <- d[[column]]
  if (measure == "trade_gdp") raw <- log1p(raw)
  if (measure == "trade_gdp_w") raw <- pmin(raw, quantile(raw[d$in_window], WINSOR_QUANTILE, na.rm = TRUE))
  if (check == "na_trade") raw[d[[paste0("trade_", group, "_zero_imputed")]] > 0] <- NA
  d$response <- d$violence_lev
  d <- add_lags(d, c(shock, "response"), VAR_LAGS)
  if (check == "in_conflict") d$in_window <- d$in_window & d$ucdp_conflict_l1 %in% 1
  in_shock <- d$in_window & d[[shock]] > 0 & !is.na(raw)
  history <- c(lag_names(shock, VAR_LAGS), lag_names("response", VAR_LAGS), "response")

  if (mode == "linear") {
    d$z <- (raw - mean(raw[in_shock])) / sd(raw[in_shock])
    if (senders) d$z[d[[shock]] == 0] <- 0                 # exposure to "the senders" exists only with a shock
    d$shock_x_z <- d[[shock]] * d$z
    terms <- c(shock, "shock_x_z"); labels <- c("shock (at mean exposure)", "shock x exposure (per SD)")
    regressors <- c(terms, if (!senders) "z", history)
    d$usable <- !is.na(d$z)
  } else {
    if (grepl("^arms", measure)) {
      positive_median <- median(raw[in_shock & raw > 0])
      group_of <- ifelse(raw == 0, "none", ifelse(raw <= positive_median, "some", "high"))
      levels_used <- c("none", "some", "high"); labels <- c("no arms from sender", "some (below median)",
                                                              "high (above median)")
    } else {
      cuts <- quantile(raw[in_shock], c(1 / 3, 2 / 3))
      group_of <- as.character(cut(raw, c(-Inf, cuts, Inf), labels = c("low", "mid", "high")))
      levels_used <- c("low", "mid", "high"); labels <- c("low exposure", "middle exposure", "high exposure")
    }
    for (k in levels_used) d[[paste0("shock_", k)]] <- d[[shock]] * (group_of %in% k)
    terms <- paste0("shock_", levels_used)
    regressors <- c(terms, history)
    d$usable <- !is.na(group_of) | d[[shock]] == 0
  }

  rows <- list()
  for (cumulative in c(FALSE, TRUE)) for (h in 1:HORIZON) {
    d$outcome <- if (cumulative) cumulative_to(d, "response", h) else value_at(d, "response", h)
    s <- d %>% filter(in_window, usable) %>% drop_na(all_of(c("outcome", regressors)))
    if (sum(s[[shock]] > 0) < 10) next                      # too few shock years at this horizon
    fit <- feols(as.formula(paste("outcome ~", paste(regressors, collapse = " + "), "| gwcode + yr")),
                 data = s, cluster = ~ gwcode, notes = FALSE)
    ct <- coeftable(fit)
    n_shock_years <- sum(s[[shock]] > 0)
    kind <- if (cumulative) "cumulative" else "per year"
    for (i in seq_along(terms)) {
      coefficient <- terms[i]; label <- labels[i]
      n_group <- sum(s[[coefficient]] > 0)
      found <- coefficient %in% rownames(ct)                 # dropped (collinear / empty group) -> NA
      rows[[length(rows) + 1]] <- tibble(
        source = source, check = check, mode = mode, shock = shock_name, measure = measure, horizon = h,
        type = kind, term = label,
        estimate = if (found) ct[coefficient, 1] else NA_real_, se = if (found) ct[coefficient, 2] else NA_real_,
        p_value = if (found) ct[coefficient, 4] else NA_real_,
        observations = nobs(fit), shock_years = n_shock_years, group_shock_years = n_group)
    }
  }
  bind_rows(rows)
}

add_labels <- function(r) r %>%
  mutate(lower = estimate - 1.96 * se, upper = estimate + 1.96 * se,
         source_label = factor(SOURCES[source], levels = SOURCES),
         shock_label = factor(SHOCK_LABELS[shock], levels = SHOCK_LABELS),
         measure_label = factor(MEASURES[measure], levels = MEASURES))

format_cell <- function(estimate, se, p) ifelse(is.na(estimate), "",
                                                 sprintf("%.3f%s (%.3f)", estimate, significance_stars(p), se))
to_markdown <- function(table) {
  c(paste0("| ", paste(names(table), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(table)), collapse = "|"), "|"),
    apply(table, 1, function(row) paste0("| ", paste(ifelse(is.na(row), "", row), collapse = " | "), " |")), "")
}
