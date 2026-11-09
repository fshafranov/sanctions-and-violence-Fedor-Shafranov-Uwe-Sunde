# =============================================================================
# 15_specification_grid.R — local projections for every valid combination of the dimensions in
# empirics/specifications.R, for UCDP, ACLED and GDELT alike.
#
# Added 2026-11-09 (user). Model per specification (as 13_local_projections.R):
#   response(t+h) = b_h shock(t) + lags 1-2 of shock and response [+ same-year response (shock second)]
#                   [+ lagged controls] + year FE + (state | region) FE + e,     SE clustered by state
#   per-year (response in t+h) and cumulative (sum t..t+h) responses, h = 0..HORIZON_GRID
#   (shock second: h >= 1). s2v: shock = sanction measure, response = violence; v2s: the reverse.
#   Sample "in_conflict": shock years with UCDP conflict in t-1, for every source (option c).
# Unlike 14_conflict_sample_lp.R, other new sanctions are NOT a separate regressor (uniform grid).
#
# Output: empirics/results/tables/spec_grid_estimates.csv.gz      (latest run, all estimates)
#         empirics/results/spec_runs/spec_grid_<time>_<commit>.csv.gz (every run kept)
#         empirics/results/spec_runs/index.csv                     (one line per run: time, commit, counts)
# Run time: a few minutes (fixest, all horizons of one specification in one call).
# =============================================================================

source(here::here("empirics", "scripts", "00_setup.R"))
source(here::here("empirics", "scripts", "functions.R"))
source(here::here("empirics", "specifications.R"))
use_analysis_packages("fixest")
setFixest_notes(FALSE)

RUN_TIME <- format(Sys.time(), "%Y%m%d-%H%M%S")
GIT_COMMIT <- tryCatch(system("git rev-parse --short HEAD", intern = TRUE), error = function(e) "unknown")
GIT_DIRTY <- tryCatch(length(system("git status --porcelain -- empirics data/scripts", intern = TRUE)) > 0,
                      error = function(e) NA)


# --- 1. Data: one panel per source x window --------------------------------------------------------
sanctions <- build_sanction_measures()
panels <- list()
for (src in names(DIMENSIONS$source)) for (yrs in names(DIMENSIONS$years)) {
  panels[[paste(src, yrs)]] <- build_source_panel(src, yrs, sanctions)
  p <- panels[[paste(src, yrs)]]
  cat(sprintf("%-6s %-7s states %3d | window state-years %5d | years %d-%d\n", src, yrs, n_distinct(p$gwcode),
              sum(p$in_window), min(p$yr[p$in_window]), max(p$yr[p$in_window])))
}


# --- 2. One specification: all horizons, per year and cumulative, in one fixest call ---------------
estimate_spec <- function(spec) {
  data <- panels[[paste(spec[["source"]], spec[["years"]])]]
  if (spec[["sample"]] == "no_israel") data <- data %>% filter(gwcode != 666)
  sanction <- sanction_variable(spec[["measure"]], spec[["type"]])
  violence <- if (spec[["type"]] == "incidence") "violence_inc" else "violence_lev"
  shock    <- if (spec[["direction"]] == "s2v") sanction else violence
  response <- if (spec[["direction"]] == "s2v") violence else sanction

  data <- add_lags(data, c(shock, response), VAR_LAGS)
  horizons <- if (spec[["timing"]] == "second") 1:HORIZON_GRID else 0:HORIZON_GRID
  lhs <- character(0)
  # outcomes only inside the window (sanctions exist in every year, violence only inside the window)
  data$response_in_window <- ifelse(data$in_window, data[[response]], NA)
  for (h in 0:HORIZON_GRID) data[[paste0("f", h)]] <- lag_by_year(data, "response_in_window", -h)
  for (h in horizons) {
    data[[paste0("c", h)]] <- Reduce(`+`, lapply(0:h, function(j) data[[paste0("f", j)]]))
    lhs <- c(lhs, paste0("f", h), paste0("c", h))
  }
  rows <- data$in_window
  if (spec[["sample"]] == "in_conflict") rows <- rows & data$ucdp_conflict_l1 %in% 1
  data <- data[rows, ]

  regressors <- c(shock, lag_names(shock, VAR_LAGS), lag_names(response, VAR_LAGS),
                  if (spec[["timing"]] == "second") response,
                  if (spec[["controls"]] == "lagged") CONTROLS)
  data <- data %>% drop_na(all_of(regressors))
  fe <- if (spec[["fe"]] == "state") "gwcode + yr" else "region + yr"
  fits <- feols(as.formula(paste0("c(", paste(lhs, collapse = ", "), ") ~ ",
                                  paste(regressors, collapse = " + "), " | ", fe)),
                data = data, cluster = ~ gwcode)
  out <- lapply(seq_along(lhs), function(i) {
    fit <- fits[[i]]
    if (!shock %in% names(coef(fit))) return(NULL)                  # shock dropped (no variation)
    b <- unname(coef(fit)[shock]); s <- unname(se(fit)[shock])
    used <- data[obs(fit), ]
    tibble(horizon = as.integer(substring(lhs[i], 2)), kind = if (substr(lhs[i], 1, 1) == "f") "per year" else "cumulative",
           estimate = b, se = s, p_value = 2 * pnorm(-abs(b / s)), observations = nobs(fit),
           states = n_distinct(used$gwcode), shock_events = sum(used[[shock]] > 0))
  })
  bind_rows(out)
}


# --- 3. Grid ------------------------------------------------------------------------------------
grid <- expand.grid(lapply(DIMENSIONS, names), stringsAsFactors = FALSE)
grid <- grid[apply(grid, 1, spec_is_valid), ]
grid$spec_id <- apply(grid[, names(DIMENSIONS)], 1, paste, collapse = "|")
grid$n_differences_from_base <- apply(grid[, names(DIMENSIONS)], 1,
                                      function(r) sum(r[names(BASE_SPEC)] != BASE_SPEC & names(BASE_SPEC) != "direction"))
cat("\nValid specifications:", nrow(grid), "\n")

started <- Sys.time()
results <- vector("list", nrow(grid))
for (i in seq_len(nrow(grid))) {
  spec <- unlist(grid[i, names(DIMENSIONS)])
  results[[i]] <- tryCatch(estimate_spec(spec) %>% mutate(spec_id = grid$spec_id[i], .before = 1),
                           error = function(e) { message("failed: ", grid$spec_id[i], " — ", conditionMessage(e)); NULL })
  if (i %% 250 == 0) cat(sprintf("  %d / %d specifications (%.0f s)\n", i, nrow(grid),
                                 as.numeric(difftime(Sys.time(), started, units = "secs"))))
}
estimates <- bind_rows(results) %>%
  left_join(grid, by = "spec_id") %>%
  relocate(all_of(names(DIMENSIONS)), n_differences_from_base, .after = spec_id) %>%
  mutate(run_time = RUN_TIME, git_commit = GIT_COMMIT)


# --- 4. Write and log ------------------------------------------------------------------------------
write_csv(estimates, file.path(TABLES, "spec_grid_estimates.csv.gz"))
runs_dir <- file.path(RESULTS, "spec_runs"); dir.create(runs_dir, showWarnings = FALSE)
write_csv(estimates, file.path(runs_dir, paste0("spec_grid_", RUN_TIME, "_", GIT_COMMIT, ".csv.gz")))
n_specs_estimated <- n_distinct(estimates$spec_id)
index_row <- tibble(run_time = RUN_TIME, git_commit = GIT_COMMIT, uncommitted_changes = GIT_DIRTY,
                    specifications = n_specs_estimated, estimates = nrow(estimates),
                    failed = nrow(grid) - n_specs_estimated,
                    seconds = round(as.numeric(difftime(Sys.time(), started, units = "secs"))))
index_file <- file.path(runs_dir, "index.csv")
write_csv(index_row, index_file, append = file.exists(index_file))
print(as.data.frame(index_row), row.names = FALSE)

cat("\nBase specification (UCDP, all cases, levels, all states, own window, state FE, shock second, no controls):\n")
print(as.data.frame(estimates %>% filter(n_differences_from_base == 0) %>%
                      select(direction, kind, horizon, estimate, se, p_value, observations) %>%
                      arrange(direction, kind, horizon)), digits = 3, row.names = FALSE)
