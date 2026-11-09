# =============================================================================
# exposure/scripts/00_setup.R — setup for the exposure extension (added 2026-11-09)
#   source(here::here("exposure", "scripts", "00_setup.R"))
# Reuses the main project's setup (packages, PANEL path, global choices such as VAR_LAGS, CONTROLS) and helper
# functions, then points the output paths to exposure/results/ so the two projects never overwrite each other.
# =============================================================================
source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))

RESULTS <- here("exposure", "results")
FIGURES <- file.path(RESULTS, "figures")
TABLES  <- file.path(RESULTS, "tables")
for (d in c(FIGURES, TABLES)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# Exposure variables used with each sanction measure (columns of the panel; data/README.md section 4c)
EXPOSURE_FOR_SHOCK <- c(us = "trade_us", eu = "trade_eu", all = "trade_senders")
