# =============================================================================
# doubly_robust/scripts/00_setup.R — setup for the doubly robust LP project (added 2026-11-09)
#   source(here::here("doubly_robust", "scripts", "00_setup.R"))
# Reuses the main project's setup (packages, paths, VAR_LAGS, CONTROLS, SAMPLE_YEARS) and helper functions,
# then points the output paths to doubly_robust/results/ so the projects never overwrite each other.
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))

RESULTS <- here("doubly_robust", "results")
FIGURES <- file.path(RESULTS, "figures")
TABLES  <- file.path(RESULTS, "tables")
for (d in c(FIGURES, TABLES)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# Design choices (doubly_robust/README.md, "Choices to confirm"; DR1-DR6)
ICC_CASE <- 685
HORIZON  <- 6                    # years after the shock
PLACEBO_LAGS <- 3:4              # pre-sanction violence not used in the propensity model (balance / placebo)
TRIM     <- 0.01                 # DR4: drop state-years with propensity outside [TRIM, 1 - TRIM]
PERIOD_YEARS <- 5                # DR3: period dummies in the propensity model (5-year bins)
