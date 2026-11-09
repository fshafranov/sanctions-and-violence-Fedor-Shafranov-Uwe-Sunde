# =============================================================================
# specifications.R — the specification table: every dimension along which the analysis can vary,
# with the BASE choice listed first, and ONE data builder used for every violence source.
#
# Added 2026-11-09 (user: "keep the base definitions, play around with data combinations, and use the
# same permutations for UCDP, ACLED and GDELT"). Rules:
#   * The base definitions stay fixed (ANALYSIS_PLAN.md). A variant is a new option in a dimension below,
#     with a short description, the date and who asked for it.
#   * Every sanction measure / sample / window is defined ONCE here and therefore applies to all three
#     violence sources automatically.
#   * Every run of the grid (15_specification_grid.R) is logged with date and git commit (results/spec_runs/).
#
# Sourced by 15_specification_grid.R and 16_specification_curve.R after 00_setup.R and functions.R.
# =============================================================================

# --- 1. Dimensions (first option = base) -----------------------------------------------------------
DIMENSIONS <- list(
  direction = c(s2v = "Sanctions -> violence", v2s = "Violence -> sanctions"),
  source    = c(ucdp = "UCDP", acled = "ACLED", gdelt = "GDELT"),
  measure   = c(all          = "All new cases",
                no_icc       = "All, without ICC case 685",          # advisor 9 Nov
                us           = "US cases",                           # advisor 9 Nov
                us_no_icc    = "US, without ICC case 685",           # advisor 9 Nov
                arms         = "Includes an arms embargo",           # user 9 Nov
                conflict_obj = "Conflict objective (any mention)",   # user 9 Nov
                sender_units = "Sender units (UN, EU = 1 each)",     # user 9 Nov, levels only
                breadth      = "Breadth (number of measure types)"), # user 9 Nov, levels only
  type      = c(levels = "Levels", incidence = "Incidence"),
  sample    = c(all_states = "All states",
                in_conflict = "In conflict in t-1 (UCDP)",           # option (c), user 9 Nov; s2v only
                no_israel  = "Without Israel"),                      # Palestine asymmetry, user 9 Nov
  years     = c(own = "Own coverage", common = "Common window"),     # user 9 Nov: both
  fe        = c(state = "State + year FE", region = "Region + year FE"),
  timing    = c(second = "Shock second", first = "Shock first"),
  controls  = c(none = "No controls", lagged = "Lagged controls")
)
BASE_SPEC <- c(direction = "s2v", source = "ucdp", measure = "all", type = "levels", sample = "all_states",
               years = "own", fe = "state", timing = "second", controls = "none")

LEVELS_ONLY_MEASURES <- c("sender_units", "breadth")   # incidence would equal "all"
HORIZON_GRID <- 6                                       # h = 0..6 (ACLED panels are short)
ICC_CASE <- 685
CONFLICT_OBJECTIVES <- c("end_war", "prevent_war", "territorial_conflict")
MEASURE_TYPES <- c("arms", "military", "trade", "financial", "travel", "other")

# Own coverage per source (shock years; outcomes are restricted to the same window)
OWN_WINDOW <- list(ucdp = SAMPLE_YEARS,          # 1989-2019, base (D4)
                   acled = 1997:2023,            # within ACLED coverage (data/README A5)
                   gdelt = 1979:2021)            # GDELT 1.0
COMMON_WINDOW <- 1997:2021                       # state-years observed in all three (ACLED coverage, GDELT end)
GDELT_THIN_EVENTS <- 100                         # as 11_gdelt.R: < 100 GDELT events -> GDELT measures missing

gw_region <- function(code) cut(code, c(0, 199, 399, 626, 699, 999),
                                labels = c("Americas", "Europe", "Africa", "Middle East", "Asia and Oceania"))


# --- 2. Sanction measures (state-year), from the case-level file -------------------------------------
build_sanction_measures <- function() {
  cases <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE)
  cases <- cases %>%
    mutate(no_icc       = case != ICC_CASE,
           us_case      = us == 1,
           us_no_icc    = us == 1 & case != ICC_CASE,
           arms_case    = arms == 1,
           conflict_obj = map_lgl(str_split(objective, ",\\s*"), ~ any(.x %in% CONFLICT_OBJECTIVES)),
           # sender units: names in GSDB's case-level sender field; "UN" (all members) and "EU" count once each
           sender_list  = str_split(sanctioning_state, ",\\s*"))
  per_year <- cases %>%
    group_by(iso3c = country_iso3, yr = year) %>%
    summarise(n_new_all = n(), n_new_no_icc = sum(no_icc), n_new_us = sum(us_case),
              n_new_us_no_icc = sum(us_no_icc), n_new_arms = sum(arms_case),
              n_new_conflict_obj = sum(conflict_obj),
              n_new_sender_units = length(unique(unlist(sender_list))),
              n_new_breadth = sum(colSums(across(all_of(MEASURE_TYPES))) > 0),
              .groups = "drop")
  for (m in c("all", "no_icc", "us", "us_no_icc", "arms", "conflict_obj")) {
    per_year[[paste0("new_", m)]] <- as.integer(per_year[[paste0("n_new_", m)]] > 0)
  }
  per_year
}


# --- 3. One panel per (source, years): uniform names violence_inc / violence_lev -------------------
# Returns all state-years 1976-2023 with sanction measures and controls; `violence_*` are missing outside
# the window (so outcomes and lags stay inside it); `ucdp_conflict_l1` (UCDP, never windowed) defines the
# in-conflict sample for every source (option c).
build_source_panel <- function(source, years, sanctions) {
  panel <- read_panel() %>%
    filter(yr >= 1976, yr <= 2023) %>%
    mutate(ucdp_inc = as.integer(cumulative_total_deaths_in_orgvio_best >= CONFLICT_MIN_DEATHS),
           ucdp_lev = log1p(cumulative_total_deaths_in_orgvio_best_pc),
           acled_inc = as.integer(acled_deaths_orgvio >= CONFLICT_MIN_DEATHS),
           acled_lev = log1p(acled_deaths_orgvio_pc),
           gdelt_viol = assault_norm1000 + fight_norm1000 + mass_violence_norm1000,
           gdelt_thin = !is.na(gdelt_total_events) & gdelt_total_events < GDELT_THIN_EVENTS) %>%
    group_by(gwcode) %>%
    mutate(gdelt_median = median(gdelt_viol[yr %in% 1979:2021], na.rm = TRUE)) %>%
    ungroup() %>%
    mutate(gdelt_lev = ifelse(gdelt_thin, NA, gdelt_viol / 10),
           gdelt_inc = ifelse(gdelt_thin, NA, as.integer(gdelt_viol > gdelt_median)),
           region = gw_region(gwcode)) %>%
    arrange(gwcode, yr)

  panel$ucdp_conflict_l1 <- lag_by_year(panel, "ucdp_inc", 1)
  panel$gdp_growth       <- log(panel$gdp_ext) - log(lag_by_year(panel, "gdp_ext", 1))
  panel$ctrl_stock       <- lag_by_year(panel, "n_cases_received", 1)
  panel$ctrl_gdp_growth  <- lag_by_year(panel, "gdp_growth", 1)
  panel$ctrl_democracy   <- lag_by_year(panel, "v2x_polyarchy", 1)

  panel$violence_inc <- panel[[paste0(source, "_inc")]]
  panel$violence_lev <- panel[[paste0(source, "_lev")]]
  window <- if (years == "own") panel$yr %in% OWN_WINDOW[[source]] else
    panel$yr %in% COMMON_WINDOW & panel$acled_covered %in% 1 &
      !is.na(panel$ucdp_lev) & !is.na(panel$acled_lev) & !is.na(panel$gdelt_lev)
  if (source == "acled") window <- window & panel$acled_covered %in% 1
  panel$violence_inc[!window] <- NA
  panel$violence_lev[!window] <- NA
  panel$in_window <- window & !is.na(panel$violence_lev)

  # sample rule as 01_prepare_sample.R: >= MIN_OBS years in the window; manual exclusions
  kept <- panel %>% filter(in_window) %>% count(gwcode) %>% filter(n >= MIN_OBS) %>% pull(gwcode)
  panel <- panel %>% filter(gwcode %in% kept, !gw_name %in% MANUAL_EXCLUDE$gw_name)

  panel <- panel %>%
    left_join(sanctions, by = c("iso3c", "yr")) %>%
    mutate(across(c(starts_with("n_new_"), starts_with("new_")) & !any_of(c("n_new_cases", "new_sanction")),
                  ~ replace_na(.x, 0L))) %>%
    select(gwcode, gw_name, iso3c, yr, region, in_window, ucdp_conflict_l1, violence_inc, violence_lev,
           starts_with("n_new_"), starts_with("new_"), all_of(CONTROLS)) %>%
    arrange(gwcode, yr)
  panel
}

# Variable names of a sanction measure in a given type
sanction_variable <- function(measure, type) {
  if (type == "incidence") paste0("new_", measure) else paste0("n_new_", measure)
}

# Is a combination estimated? (documented exclusions)
spec_is_valid <- function(spec) {
  if (spec[["measure"]] %in% LEVELS_ONLY_MEASURES && spec[["type"]] == "incidence") return(FALSE)
  if (spec[["direction"]] == "v2s" && spec[["sample"]] == "in_conflict") return(FALSE)
  TRUE
}
