# ==============================================================================
# Regressions of FMIS construction duration on PR-511 mileage.
# Tests whether project duration scales with mileage. 
# ==============================================================================
# Setup 
library(haven)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(modelsummary)
library(fixest)

options(width = 300)

user <- Sys.info()[["user"]]
if (user == "andersonkovesci") {
  project_root <- "/Users/andersonkovesci/Dropbox/FHWA cost data"
  output_dir <- file.path(project_root, "Output", "Andy")
  data_dir <- file.path(project_root, "Data")
  raw_data_dir <- file.path(data_dir, "Raw")
  intermediate_data_dir <- file.path(data_dir, "Intermediate")

} else if (user == "hl2266") {
  project_root <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
  output_dir <- file.path(project_root, "Output", "Hannah")
  data_dir <- file.path(project_root, "Data")
  raw_data_dir <- file.path(data_dir, "Raw")
  intermediate_data_dir <- file.path(data_dir, "Intermediate")
} else {
  stop("Set your user paths")
}

source(file.path(getwd(), "utils/fig_utils.R"))

# ==============================================================================
regr_dir <- file.path(output_dir, "duration_regression")
dir.create(regr_dir, recursive = TRUE, showWarnings = FALSE)

# ==============================================================================
# Helpers

# format the fixed effects rows for modelsummary output 
gof_map_combined <- modelsummary::gof_map
fe_rows <- data.frame(
  raw = c(
    "FE: factor(state_fips)", "FE: state_fips",
    "FE: factor(authconstyear)", "FE: authconstyear",
    "FE: factor(completion_year)", "FE: completion_year"
  ),
  clean = c(
    "State FE", "State FE",
    "Authorization year FE", "Authorization year FE",
    "Completion year FE", "Completion year FE"
  ),
  fmt = 0,
  omit = FALSE,
  stringsAsFactors = FALSE
)
for (i in seq_len(nrow(fe_rows))) {
  idx <- which(gof_map_combined$raw == fe_rows$raw[i])
  if (length(idx) > 0) {
    gof_map_combined$clean[idx] <- fe_rows$clean[i]
  } else {
    gof_map_combined <- rbind(gof_map_combined, fe_rows[i, , drop = FALSE])
  }
}

# ==============================================================================
# Data 

cpi_df <- read_dta(file.path(intermediate_data_dir, "CPI_2025.dta"))

# FMIS project panel
fmis_panel <- read_dta(file.path(intermediate_data_dir, "project_level_FMIS_lite.dta")) %>%
  filter(fp_ic == 1, has_new_construction == 1) %>%
  filter(!is.na(authconstdate), !is.na(completedate)) %>%
  mutate(
    const_duration = as.numeric(completedate - authconstdate) / 365.25,
    authconstyear = as.integer(format(authconstdate, "%Y")),
    state_fips = as.numeric(state_fips),
    county_fips = as.numeric(county_fips),
    countyid = as.numeric(countyid)
  )
# adjust for inflation 
fmis_panel <- fmis_panel %>%
  rename(year = completion_year) %>%
  left_join(cpi_df, by = "year") %>%
  mutate(total_cost_mills_adj = total_cost_mills / cpi) %>%
  rename(completion_year = year) %>%
  mutate(
    fpn_prefix = substr(str_trim(federal_project_number), 1, 3),
    route = suppressWarnings(as.integer(gsub("[^0-9]", "", fpn_prefix)))
  )

fmis_panel <- fmis_panel %>%
  select(
    recipientid, federal_project_number,
    state_fips, county_fips, countyid, route,
    const_duration, authconstyear, completion_year,
    total_cost_mills_adj
  )

# PR-511 cell mileage 
pr511 <- read_dta(
  file.path(intermediate_data_dir, "PR511_hubbardmazzeo_chained.dta")) %>%
  filter(!is.na(open_year)) %>%
  mutate(
    st = as.integer(st),
    county = as.integer(county),
    county_fips = as.numeric(sprintf("%02d%03d", st, county)),
    route = as.integer(route),
    open_year = as.integer(open_year)
  )

cty_yr_mi <- pr511 %>%
  group_by(county_fips, open_year) %>%
  summarise(mi = sum(chain_len, na.rm = TRUE), .groups = "drop")

cty_rt_yr_mi <- pr511 %>%
  group_by(county_fips, route, open_year) %>%
  summarise(mi = sum(chain_len, na.rm = TRUE), .groups = "drop")

# Joined panels per obs level 
# (always join on completion_year regardless of year FE variable)
panel_cty <- fmis_panel %>%
  inner_join(cty_yr_mi, by = c("county_fips", "completion_year" = "open_year"))

panel_cty_rt <- fmis_panel %>%
  filter(!is.na(route)) %>%
  inner_join(cty_rt_yr_mi, by = c("county_fips", "route", "completion_year" = "open_year"))

# TODO: decide how to handle zero years? 

# ==============================================================================
# Regressions
# ==============================================================================

levels_cfg <- list(
  cty = list(
    panel = panel_cty,
    # mi_var = "cty_yr_mi",
    cell_keys = c("county_fips"),
    label = "county"
  ),
  cty_rt = list(
    panel = panel_cty_rt,
    # mi_var = "cty_rt_yr_mi",
    cell_keys = c("county_fips", "route"),
    label = "county x route"
  )
)

for (lvl in names(levels_cfg)) {
  cfg <- levels_cfg[[lvl]]

  # count number of projects per cell x year as an extra optional control (always using completion year since that's what the PR-511 was matched by)
  df <- cfg$panel %>%
    filter(const_duration > 0, mi > 0) %>%
    group_by(across(all_of(c(cfg$cell_keys, "completion_year")))) %>%
    mutate(n_proj = n()) %>% 
    ungroup()
  
  # filter time range
  df_auth <- df %>%
    filter(authconstyear >= 1960, authconstyear <= 1995) %>%
    mutate(
      log_const_duration = log(const_duration),
      log_mi = log(mi)
    )
  df_completion <- df %>%
    filter(completion_year >= 1960, completion_year <= 1995) %>%
    mutate(
      log_const_duration = log(const_duration),
      log_mi = log(mi)
    )
 
  # compute baseline FMIS observation counts and spending before PR-511 matching for a footnote reference
  fmis_baseline <- fmis_panel
  if (lvl == "cty_rt") {
    fmis_baseline <- fmis_baseline %>%
      filter(!is.na(route))
  }
  n_baseline_auth <- fmis_baseline %>%
    filter(authconstyear >= 1960, authconstyear <= 1995) %>%
    nrow()
  n_baseline_completion <- fmis_baseline %>%
    filter(completion_year >= 1960, completion_year <= 1995) %>%
    nrow()
  spend_baseline_auth <- fmis_baseline %>%
    filter(authconstyear >= 1960, authconstyear <= 1995) %>%
    summarise(spend = sum(total_cost_mills_adj, na.rm = TRUE)) %>%
    pull(spend)
  spend_baseline_completion <- fmis_baseline %>%
    filter(completion_year >= 1960, completion_year <= 1995) %>%
    summarise(spend = sum(total_cost_mills_adj, na.rm = TRUE)) %>%
    pull(spend)

  spend_matched_auth <- df_auth %>%
    summarise(spend = sum(total_cost_mills_adj, na.rm = TRUE)) %>%
    pull(spend)
  spend_matched_completion <- df_completion %>%
    summarise(spend = sum(total_cost_mills_adj, na.rm = TRUE)) %>%
    pull(spend)
  spend_share_auth <- 100 * spend_matched_auth / spend_baseline_auth
  spend_share_completion <- 100 * spend_matched_completion / spend_baseline_completion

  # regression models
  m1 <- feols(
    const_duration ~ mi | factor(state_fips) + factor(authconstyear),
    data = df_auth,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  m2 <- feols(
    const_duration ~ mi | factor(state_fips) + factor(completion_year),
    data = df_completion,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  m3 <- feols(
    const_duration ~ mi + n_proj | factor(state_fips) + factor(authconstyear),
    data = df_auth,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  m4 <- feols(
    const_duration ~ mi + n_proj | factor(state_fips) + factor(completion_year),
    data = df_completion,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  log_m1 <- feols(
    log_const_duration ~ log_mi | factor(state_fips) + factor(authconstyear),
    data = df_auth,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  log_m2 <- feols(
    log_const_duration ~ log_mi | factor(state_fips) + factor(completion_year),
    data = df_completion,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  log_m3 <- feols(
    log_const_duration ~ log_mi + n_proj | factor(state_fips) + factor(authconstyear),
    data = df_auth,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )
  log_m4 <- feols(
    log_const_duration ~ log_mi + n_proj | factor(state_fips) + factor(completion_year),
    data = df_completion,
    weights = ~total_cost_mills_adj,
    vcov = ~county_fips
  )

  models_list <- list(
    "Years (1)" = m1,
    "Years (2)" = m2,
    "Years (3)" = m3,
    "Years (4)" = m4,
    "Log years (1)" = log_m1,
    "Log years (2)" = log_m2,
    "Log years (3)" = log_m3,
    "Log years (4)" = log_m4
  )

  coef_map <- setNames(
    c(
      "Miles",
      "Log miles",
      sprintf("Number of FMIS projects in same %s x completion year cell", cfg$label)
    ),
    c("mi", "log_mi", "n_proj")
  )

  regression_notes <- c(
    "Significance levels: + p<0.1, * p<0.05, ** p<0.01, *** p<0.001.",
    "Standard errors clustered at the county level and reported in parentheses.",
    "Observations are at the FMIS project level.",
    sprintf("PR-511 mileage is aggregated to the %s level and merged with the FMIS panel using %s variables and setting PR-511 opening year equal to the FMIS completion year.", cfg$label, cfg$label),
    sprintf(
      "PR-511 mileage is duplicated across multiple FMIS projects in the same %s x opening year cell.",
      cfg$label
    ),
    "Sample contains FMIS projects with at least one Interstate Construction reimbursement, at least one new-construction improvement type, and non-missing construction authorization and completion dates.",
    "Time range is restricted so that the FE year variable (authorization or completion year respectively) is between 1960 and 1995.",
    "Sample restricted to observations with positive duration and mileage.",  
    "Regressions are weighted by project cost. Cost is inflation-adjusted to 2025 USD.",
    "Route is inferred from the first 3 characters of the federal project number.",
    sprintf(
      "The number of valid FMIS projects before matching to PR-511 mileage is %s (when restricting authorization year to 1960-1995) or %s (when restricting completion year to 1960-1995). (The gap relative to the regression observation counts above reflects projects with no PR-511 segment opening in the same %s x completion year cell.) This matched sample captures %.1f%% of inflation-adjusted spending in the authorization-year window and %.1f%% in the completion-year window.",
      format(n_baseline_auth, big.mark = ","),
      format(n_baseline_completion, big.mark = ","),
      cfg$label,
      spend_share_auth,
      spend_share_completion
    )
  )

  modelsummary(
    models_list,
    title = sprintf(
      "Duration between construction authorization and completion vs. PR-511 mileage (%s level), 1960-1995",
      cfg$label
    ),
    stars = c("+" = 0.1, "*" = 0.05, "**" = 0.01, "***" = 0.001),
    estimate = "{estimate}{stars}",
    statistic = "({std.error})",
    fmt = 2,
    coef_map = coef_map,
    # coef_omit = "^\\(Intercept\\)",
    gof_map = gof_map_combined,
    gof_omit = "IC|Log|Adj|Std.Errors",
    notes = regression_notes,
    output = file.path(
      regr_dir,
      sprintf("duration_vs_mi_regression_%s.html", lvl)
    )
  )


# ==============================================================================
# Figures
# ==============================================================================

  # Scatter plots: duration vs PR-511 miles 
  p_auth <- ggplot(df_auth, aes(x = mi, y = const_duration)) +
    geom_point(alpha = 0.25) +
    labs(
      title = str_wrap(
        sprintf(
          "Duration between FMIS construction authorization and completion vs. PR-511 mileage (%s level, authorization year 1960-1995)",
          cfg$label
        ),
        width = 80
      ),
      x = "Miles",
      y = "Years"
    )
  ggsave(
    filename = file.path(
      regr_dir,
      sprintf("scatter_duration_vs_mi_%s_authyr.png", lvl)
    ),
    plot = p_auth,
    width = 8,
    height = 6,
    bg = "white"
  )

  p_completion <- ggplot(df_completion, aes(x = mi, y = const_duration)) +
    geom_point(alpha = 0.25) +
    labs(
      title = str_wrap(
        sprintf(
          "Duration between FMIS construction authorization and completion vs. PR-511 mileage (%s level, completion year 1960-1995)",
          cfg$label
        ),
        width = 80
      ),
      x = "Miles",
      y = "Years"
    )
  ggsave(
    filename = file.path(
      regr_dir,
      sprintf("scatter_duration_vs_mi_%s_completionyr.png", lvl)
    ),
    plot = p_completion,
    width = 8,
    height = 6,
    bg = "white"
  )

  p_auth_log <- ggplot(
    df_auth,
    aes(x = log_mi, y = log_const_duration)
  ) +
    geom_point(alpha = 0.25) +
    labs(
      title = str_wrap(
        sprintf(
          "Log duration between FMIS construction authorization and completion vs. log PR-511 mileage (%s level, authorization year 1960-1995)",
          cfg$label
        ),
        width = 80
      ),
      x = "Log miles",
      y = "Log years"
    )
  ggsave(
    filename = file.path(
      regr_dir,
      sprintf("scatter_log_duration_vs_log_mi_%s_authyr.png", lvl)
    ),
    plot = p_auth_log,
    width = 8,
    height = 6,
    bg = "white"
  )

  p_completion_log <- ggplot(
    df_completion,
    aes(x = log_mi, y = log_const_duration)
  ) +
    geom_point(alpha = 0.25) +
    labs(
      title = str_wrap(
        sprintf(
          "Log duration between FMIS construction authorization and completion vs. log PR-511 mileage (%s level, completion year 1960-1995)",
          cfg$label
        ),
        width = 80
      ),
      x = "Log miles",
      y = "Log years"
    )
  ggsave(
    filename = file.path(
      regr_dir,
      sprintf("scatter_log_duration_vs_log_mi_%s_completionyr.png", lvl)
    ),
    plot = p_completion_log,
    width = 8,
    height = 6,
    bg = "white"
  )
}
