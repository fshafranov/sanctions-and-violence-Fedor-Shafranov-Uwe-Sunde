# =============================================================================
# clean_ucdp_peace.R — UCDP peace agreements and conflict terminations -> GW country-year flags
# (added 2026-11-16; data/README.md section 4e, P2-P4)
#
# Input : data/raw/ucdp_peace/ucdp-peace-agreements-222.xlsx            (one row per agreement, 1975-2021)
#         data/raw/ucdp_peace/UCDPConflictTerminationDataset_v4_2024_Conflict.csv  (conflict-year, episodes)
#         data/raw/ucdp_prio/UcdpPrioConflict_v26_1.csv                  (conflict -> location gwno_loc)
# Output: data/clean/ucdp_peace/peace_cy.csv   gwcode x year 1975-2024, only state-years with an event
#
# Country of an event = every GW code in the conflict's gwno_loc (UCDP/PRIO; an interstate conflict counts for every
# location state). Agreements: location of the conflict in the agreement year (any year of the conflict if that row
# is missing); agreements listing several conflicts count once per state. Terminations: one row per conflict episode
# with an end year (c_ep_endyear = LAST year of activity; the first calm year is c_ep_endyear + 1).
#   pa_n        agreements signed in the year (any type)
#   pa_full / pa_partial / pa_process     by pa_type (1 full, 2 partial, 3 peace process)
#   pa_ceasefire                          agreement contains a ceasefire provision (cease = 1)
#   term_n      conflict episodes whose last active year is this year
#   term_agreement (outcome 1), term_ceasefire (2), term_victory (3, 4), term_low_activity (5, 6)
# Written in R because the agreement file is xlsx (readxl is in renv; the Python env has no xlsx reader).
# =============================================================================
suppressPackageStartupMessages({ library(dplyr); library(readr); library(tidyr); library(stringr) })
root <- here::here()
raw  <- file.path(root, "data", "raw")
out  <- file.path(root, "data", "clean", "ucdp_peace"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
split_codes <- function(s) str_split(as.character(s), ",\\s*")

prio <- read_csv(file.path(raw, "ucdp_prio", "UcdpPrioConflict_v26_1.csv"), col_types = cols(.default = col_character())) %>%
  transmute(conflict_id = as.character(conflict_id), year = as.integer(year), gwno_loc = as.character(gwno_loc))
loc_year <- prio %>% mutate(gwcode = split_codes(gwno_loc)) %>% unnest(gwcode) %>%
  transmute(conflict_id, year, gwcode = as.integer(gwcode)) %>% distinct()
loc_any <- loc_year %>% distinct(conflict_id, gwcode)

# --- agreements ---------------------------------------------------------------------------------
pa <- readxl::read_excel(file.path(raw, "ucdp_peace", "ucdp-peace-agreements-222.xlsx")) %>%
  transmute(paid, conflict_id = split_codes(conflict_id), year = as.integer(year),
            pa_type = as.integer(pa_type), cease = as.integer(cease)) %>%
  unnest(conflict_id) %>% mutate(conflict_id = str_trim(conflict_id))
stopifnot(!anyNA(pa$year), all(pa$pa_type %in% 1:3))
pa_in_year <- pa %>% inner_join(loc_year, by = c("conflict_id", "year"), relationship = "many-to-many")
pa_fallback <- pa %>% anti_join(loc_year, by = c("conflict_id", "year")) %>% inner_join(loc_any, by = "conflict_id",
                                                                                       relationship = "many-to-many")
unmatched <- pa %>% anti_join(loc_any, by = "conflict_id")
cat("agreement-conflict rows:", nrow(pa), "| located in the agreement year:", n_distinct(pa_in_year$paid),
    "agreements | via another year of the conflict:", n_distinct(pa_fallback$paid),
    "| conflict id not in UCDP/PRIO:", nrow(unmatched), "\n")
pa_cy <- bind_rows(pa_in_year, pa_fallback) %>% distinct(paid, gwcode, year, pa_type, cease) %>%
  group_by(gwcode, year) %>%
  summarise(pa_n = n(), pa_full = sum(pa_type == 1), pa_partial = sum(pa_type == 2), pa_process = sum(pa_type == 3),
            pa_ceasefire = sum(cease == 1, na.rm = TRUE), .groups = "drop")

# --- terminations ---------------------------------------------------------------------------------
term <- read_csv(file.path(raw, "ucdp_peace", "UCDPConflictTerminationDataset_v4_2024_Conflict.csv"),
                 col_types = cols(.default = col_character())) %>%
  filter(!is.na(c_ep_endyear)) %>% distinct(c_epid, .keep_all = TRUE) %>%
  transmute(c_epid, year = as.integer(as.numeric(c_ep_endyear)), outcome = as.integer(as.numeric(c_outcome)), gwcode = split_codes(gwno_loc)) %>%
  unnest(gwcode) %>% mutate(gwcode = as.integer(gwcode)) %>% distinct()
cat("terminated episodes:", n_distinct(term$c_epid), "| outcome missing:", sum(is.na(term$outcome)), "\n")
print(table(term %>% distinct(c_epid, outcome) %>% pull(outcome), useNA = "ifany"))
term_cy <- term %>% group_by(gwcode, year) %>%
  summarise(term_n = n_distinct(c_epid), term_agreement = sum(outcome == 1, na.rm = TRUE),
            term_ceasefire = sum(outcome == 2, na.rm = TRUE), term_victory = sum(outcome %in% 3:4),
            term_low_activity = sum(outcome %in% 5:6), .groups = "drop")

peace_cy <- full_join(pa_cy, term_cy, by = c("gwcode", "year")) %>%
  mutate(across(-c(gwcode, year), ~ replace_na(.x, 0L))) %>%
  filter(year >= 1975) %>% arrange(gwcode, year)
stopifnot(!anyDuplicated(peace_cy[c("gwcode", "year")]))
write_csv(peace_cy, file.path(out, "peace_cy.csv"))
cat("Wrote", file.path(out, "peace_cy.csv"), nrow(peace_cy), "state-years |",
    "with an agreement:", sum(peace_cy$pa_n > 0), "| with a termination:", sum(peace_cy$term_n > 0), "\n")
print(peace_cy %>% mutate(decade = 10 * (year %/% 10)) %>% group_by(decade) %>%
        summarise(agreement_state_years = sum(pa_n > 0), termination_state_years = sum(term_n > 0)) %>% as.data.frame())
