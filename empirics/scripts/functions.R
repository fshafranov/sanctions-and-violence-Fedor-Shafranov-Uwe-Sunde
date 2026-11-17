# =============================================================================
# functions.R — helper functions shared by the estimation scripts
#
# Sourced after 00_setup.R:
#   source(here::here("empirics", "scripts", "functions.R"))
#
# Contents
#   1. Lags              lag_by_year(), add_lags()
#   2. Estimation        fit_reaction_function(), half_panel_jackknife()
#   3. Tests / summaries wald_test(), coefficient_table(), largest_var_root()
#   4. Display           significance_stars()
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Lags
# -----------------------------------------------------------------------------

# Value of `variable` k years earlier for the same state.
# The lag is matched on the calendar year (year - k), not on the row above, so a
# gap in a state's series gives NA instead of silently taking an older value.
lag_by_year <- function(data, variable, k, state_id = "gwcode", year = "yr") {
  earlier_values <- data[, c(state_id, year, variable)]
  names(earlier_values)[3] <- "lagged_value"
  earlier_values[[year]] <- earlier_values[[year]] + k        # value of year t-k now sits in row t
  matched <- dplyr::left_join(data[, c(state_id, year)], earlier_values, by = c(state_id, year))
  matched$lagged_value
}

# Add lags 1..n_lags of every variable in `variables`, named <variable>_l<k>
# (e.g. new_sanction_l1, new_sanction_l2).
add_lags <- function(data, variables, n_lags) {
  for (variable in variables) {
    for (k in seq_len(n_lags)) {
      data[[paste0(variable, "_l", k)]] <- lag_by_year(data, variable, k)
    }
  }
  data
}

# Names of the lag columns of one variable: "x_l1", "x_l2", ...
lag_names <- function(variable, n_lags) paste0(variable, "_l", seq_len(n_lags))


# -----------------------------------------------------------------------------
# 2. Estimation
# -----------------------------------------------------------------------------

# One reaction function (one equation of the panel VAR), estimated by OLS:
#
#   outcome_it = sum_k a_k outcome_i,t-k + sum_k b_k other_i,t-k + controls + state FE + year FE + e_it
#
# n_lags = lags of the outcome itself; n_lags_other = lags of the other variable
# (equal by default; different only in the lag grid, Jaeger & Paserman Table 2).
#
# State and year fixed effects enter as dummies. Standard errors are clustered
# by state (allowing heteroskedasticity and serial correlation within a state).
# The lag columns must already exist (add_lags) and `data` must contain no NAs
# in the variables used, so that the cluster vector lines up with the rows.
# cluster_se = FALSE skips the covariance (faster; used inside the bootstrap).
fit_reaction_function <- function(data, outcome, other, n_lags, controls = character(0),
                                  n_lags_other = n_lags, cluster_se = TRUE) {
  regressors <- c(lag_names(outcome, n_lags),        # own lags
                  lag_names(other, n_lags_other),    # lags of the other variable (Granger block)
                  controls,
                  "factor(gwcode)", "factor(yr)")    # state and year fixed effects
  model <- lm(reformulate(regressors, response = outcome), data = data)

  if (cluster_se) model$vcov_clustered <- sandwich::vcovCL(model, cluster = data$gwcode, type = "HC1")
  model$n_states       <- dplyr::n_distinct(data$gwcode)
  model$year_range     <- range(data$yr)
  model
}

# Half-panel jackknife (Dhaene & Jochmans 2015), the bias correction used by
# Juodis, Karavias & Sarafidis (2021) and Mei, Sheng & Shi (2026):
#
#   b_jackknife = 2 * b_full - (b_first_half + b_second_half) / 2
#
# The fixed-effects estimate b_full has a Nickell bias of order 1/T. Each half
# has twice that bias, so the combination removes the first-order term.
# The years of the estimation sample are split in two (the first half gets the
# extra year when the number of years is odd). In each half the model is
# re-estimated with its own state and year fixed effects; lags may reach back
# into the other half (they are predetermined regressors).
# Standard errors: the clustered covariance of the full-sample estimate, as in
# the Wald test of Juodis et al. (2021).
half_panel_jackknife <- function(data, outcome, other, n_lags, controls = character(0),
                                 n_lags_other = n_lags) {
  years       <- sort(unique(data$yr))
  first_years <- years[seq_len(ceiling(length(years) / 2))]

  model_full   <- fit_reaction_function(data, outcome, other, n_lags, controls, n_lags_other)
  model_first  <- fit_reaction_function(dplyr::filter(data, yr %in% first_years),
                                        outcome, other, n_lags, controls, n_lags_other)
  model_second <- fit_reaction_function(dplyr::filter(data, !yr %in% first_years),
                                        outcome, other, n_lags, controls, n_lags_other)

  # bias-correct only the slope coefficients (lags and controls), not the dummies
  slope_terms <- c(lag_names(outcome, n_lags), lag_names(other, n_lags_other), controls)
  jackknife_coefficients <- 2 * coef(model_full)[slope_terms] -
    (coef(model_first)[slope_terms] + coef(model_second)[slope_terms]) / 2

  structure(
    list(coefficients    = jackknife_coefficients,
         vcov_clustered  = model_full$vcov_clustered[slope_terms, slope_terms],
         full_model      = model_full,
         split_year      = max(first_years),        # last year of the first half
         nobs            = nobs(model_full),
         n_states        = model_full$n_states),
    class = "jackknife")
}


# -----------------------------------------------------------------------------
# 3. Tests and summaries
# -----------------------------------------------------------------------------

# Wald test that all coefficients in `terms` are zero, chi2 with length(terms)
# degrees of freedom. Works for an lm from fit_reaction_function() and for the
# list returned by half_panel_jackknife() (both carry `vcov_clustered`).
# Also returns the sum of the tested coefficients and its standard error.
wald_test <- function(model, terms) {
  coefficients <- coef(model)[terms]
  covariance   <- model$vcov_clustered[terms, terms, drop = FALSE]
  chi2 <- as.numeric(t(coefficients) %*% solve(covariance, coefficients))
  tibble(chi2     = chi2,
         df       = length(terms),
         p_value  = pchisq(chi2, df = length(terms), lower.tail = FALSE),
         sum_coef = sum(coefficients),
         sum_se   = sqrt(sum(covariance)))
}

# coef() for the jackknife list, so wald_test() can treat both objects alike
coef.jackknife <- function(object, ...) object$coefficients

# Slope coefficients (lags and controls) with clustered standard errors;
# fixed-effect dummies and the intercept are dropped.
coefficient_table <- function(model) {
  is_slope <- !grepl("^factor\\(|^\\(Intercept\\)$", names(coef(model)))
  estimate <- coef(model)[is_slope]
  std_error <- sqrt(diag(model$vcov_clustered))[names(estimate)]
  tibble(term = names(estimate), estimate = estimate, std_error = std_error,
         t_value = estimate / std_error, p_value = 2 * pnorm(-abs(estimate / std_error)))
}

# Stability of the bivariate VAR formed by the two equations: modulus of the
# largest eigenvalue of the companion matrix. Below 1 = stable (shocks die out).
# `coef_violence` and `coef_sender` are named coefficient vectors of the two
# equations; controls and fixed effects are treated as exogenous.
largest_var_root <- function(coef_violence, coef_sender, violence, sanction, n_lags) {
  # A_k: 2 x 2 matrix of lag-k coefficients, rows = equations (violence, sender),
  # columns = lagged variables (violence, sanction)
  lag_matrices <- lapply(seq_len(n_lags), function(k) {
    rbind(c(coef_violence[[paste0(violence, "_l", k)]], coef_violence[[paste0(sanction, "_l", k)]]),
          c(coef_sender[[paste0(violence, "_l", k)]],   coef_sender[[paste0(sanction, "_l", k)]]))
  })
  companion <- do.call(cbind, lag_matrices)
  if (n_lags > 1) {
    companion <- rbind(companion, cbind(diag(2 * (n_lags - 1)), matrix(0, 2 * (n_lags - 1), 2)))
  }
  max(Mod(eigen(companion, only.values = TRUE)$values))
}


# -----------------------------------------------------------------------------
# 4. Display
# -----------------------------------------------------------------------------

significance_stars <- function(p_value) {
  dplyr::case_when(p_value < 0.01 ~ "***", p_value < 0.05 ~ "**", p_value < 0.10 ~ "*", TRUE ~ "")
}


# -----------------------------------------------------------------------------
# 5. Estimation sample (shared by 04, 08)
# -----------------------------------------------------------------------------

# Rows of the estimation window with the two VAR variables, their lags and the
# controls all available: one common sample for both equations of the VAR.
build_estimation_sample <- function(analysis, sanction, violence, n_lags, controls = character(0)) {
  needed_columns <- c(sanction, violence, lag_names(sanction, n_lags), lag_names(violence, n_lags), controls)
  add_lags(analysis, c(sanction, violence), n_lags) %>%
    dplyr::filter(in_window) %>%
    dplyr::filter(dplyr::if_all(dplyr::all_of(needed_columns), ~ !is.na(.x)))
}


# -----------------------------------------------------------------------------
# 6. Impulse responses of the bivariate VAR (used by 08)
# -----------------------------------------------------------------------------

# Moving-average coefficients Phi_0..Phi_H of the VAR, variable order (violence, sanction):
#   Phi_0 = I,  Phi_h = sum_{j=1..min(h,p)} Phi_{h-j} A_j
# A_j = 2 x 2 matrix of lag-j coefficients (rows = equations, columns = lagged variables).
var_ma_coefficients <- function(coef_violence, coef_sender, violence, sanction, n_lags, horizon) {
  A <- lapply(seq_len(n_lags), function(k) {
    rbind(c(coef_violence[[paste0(violence, "_l", k)]], coef_violence[[paste0(sanction, "_l", k)]]),
          c(coef_sender[[paste0(violence, "_l", k)]],   coef_sender[[paste0(sanction, "_l", k)]]))
  })
  Phi <- vector("list", horizon + 1)
  Phi[[1]] <- diag(2)
  for (h in seq_len(horizon)) {
    Phi[[h + 1]] <- Reduce(`+`, lapply(seq_len(min(h, n_lags)), function(j) Phi[[h - j + 1]] %*% A[[j]]))
  }
  Phi
}

# Impulse responses for one identification scheme.
#   impact = 2 x 2 matrix of same-year effects of the two shocks (columns = shocks):
#     "simple" (Jaeger & Paserman fn. 12): identity, no same-year effect on the other variable
#     Cholesky orderings: lower-triangular factor of the residual covariance, rescaled so
#     that each shock moves its own variable by one unit on impact (comparable to "simple")
# Returns a long table: horizon, shock, response, value (one-unit shock).
impulse_responses <- function(Phi, impact) {
  variables <- c("violence", "sanction")
  rows <- lapply(seq_along(Phi), function(h) {
    theta <- Phi[[h]] %*% impact
    expand.grid(response = variables, shock = variables, stringsAsFactors = FALSE) %>%
      dplyr::mutate(horizon = h - 1,
                    value = theta[cbind(match(response, variables), match(shock, variables))])
  })
  dplyr::bind_rows(rows)
}

# Same-year impact matrices for the three identification schemes, from the
# residual covariance Sigma of the two equations (order: violence, sanction).
impact_matrices <- function(Sigma) {
  unit_scale <- function(P) P %*% diag(1 / diag(P))              # own impact = 1
  violence_first <- t(chol(Sigma))                               # violence can affect sanctions in the same year
  reorder <- c(2, 1)
  sanction_first <- t(chol(Sigma[reorder, reorder]))[reorder, reorder]   # sanctions can affect violence in the same year
  list(simple              = diag(2),
       cholesky_sanction_first = unit_scale(sanction_first),
       cholesky_violence_first = unit_scale(violence_first))
}


# -----------------------------------------------------------------------------
# 7. Figures (shared look; same palette as 02_descriptives.R)
# -----------------------------------------------------------------------------

PAPER_COLOURS <- c(blue = "#2a78d6", orange = "#eb6834", aqua = "#1baf7a",
                   violet = "#6250d6", grey = "#8a8984")

theme_paper <- function() {
  ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = "#fcfcfb", colour = NA),
      panel.background = ggplot2::element_rect(fill = "#fcfcfb", colour = NA),
      panel.grid.major = ggplot2::element_line(colour = "#e6e5e1", linewidth = 0.4),
      panel.grid.minor = ggplot2::element_blank(),
      strip.text   = ggplot2::element_text(face = "bold", hjust = 0, colour = "#0b0b0b"),
      plot.title   = ggplot2::element_text(face = "bold", size = 12, colour = "#0b0b0b"),
      plot.title.position = "plot",
      plot.caption = ggplot2::element_text(colour = "#8a8984", size = 7.5, hjust = 0),
      plot.caption.position = "plot",
      legend.position = "top", legend.justification = "left", legend.title = ggplot2::element_blank()
    )
}

save_figure <- function(plot, file_name, width, height) {
  ggplot2::ggsave(file.path(FIGURES, file_name), plot, width = width, height = height, dpi = 200, bg = "#fcfcfb")
  cat("Wrote", file.path(FIGURES, file_name), "\n")
}

# --- sanctions by sender group (added 2026-11-17, user request: UN vs US vs any vs Western rich) ------------------
# GSDB new cases without ICC case 685, 1 row per case and target. Groups:
#   any     : every case
#   us      : the US is a sender (in 1991-2019 almost always alone; never a UN case)
#   un      : UN cases (sender "UN" only; the US flag is 0 for all of them)
#   western : EVERY sender is a Western rich state or the EU/EEC (OECD members of 1990 except Turkey, the EU/EEC,
#             Cyprus, Malta and the Western European microstates); UN cases excluded. User's definition: Western rich
#             without backing from non-rich countries (e.g. EU cases joined by Albania, Serbia, Ukraine, Turkey drop out).
WESTERN_RICH <- c("United States", "EU", "EEC", "Canada", "Norway", "Liechtenstein", "Iceland", "Switzerland", "Japan",
                  "Australia", "United Kingdom", "France", "Germany", "Netherlands", "Denmark", "Sweden", "New Zealand",
                  "Spain", "Belgium", "Italy", "Greece", "Ireland", "Finland", "Austria", "Portugal", "Luxembourg",
                  "Cyprus", "Malta", "Monaco", "Andorra", "San Marino")
SHOCK_LABELS <- c(any = "Any sender", us = "United States", un = "UN", western = "Western rich (all senders)")
sender_cases <- function(shock, icc_case = 685) {
  stopifnot(shock %in% names(SHOCK_LABELS))
  ends <- read_csv(here("data", "raw", "gsdb", "GSDB_V4.csv"), show_col_types = FALSE) %>%
    group_by(case = case_id) %>% summarise(end = max(end), .groups = "drop")
  cases <- read_csv(here("data", "clean", "gsdb", "gsdb_new_cases.csv"), show_col_types = FALSE) %>%
    filter(case != icc_case) %>% left_join(ends, by = "case")
  senders <- strsplit(gsub("Korea, South", "Korea South", gsub("Congo, Democratic Republic of the", "DR Congo",
                                                              cases$sanctioning_state)), ",\\s*")
  cases$western <- vapply(senders, function(s) all(trimws(s) %in% WESTERN_RICH), logical(1)) & cases$un == 0
  keep <- switch(shock, any = rep(TRUE, nrow(cases)), us = cases$us == 1, un = cases$un == 1, western = cases$western)
  cases[keep, ]
}
# Per target-year: x = number of new cases of the group; force = a case of the group in force (begin <= yr <= end).
shock_panel <- function(shock) {
  cs <- sender_cases(shock)
  counts <- cs %>% count(iso3c = country_iso3, yr = year, name = "x")
  force <- cs %>% rowwise() %>% reframe(iso3c = country_iso3, yr = year:end) %>% distinct() %>% mutate(force = 1L)
  full_join(counts, force, by = c("iso3c", "yr")) %>% mutate(x = replace_na(x, 0L), force = replace_na(force, 0L))
}
# --shock=<group> on the command line (master.py passes it); default us.
shock_arg <- function(default = "us") {
  a <- grep("^--shock=", commandArgs(trailingOnly = TRUE), value = TRUE)
  if (length(a)) sub("^--shock=", "", a[1]) else default
}
