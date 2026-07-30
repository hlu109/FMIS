# =============================================
# Simple yearly breakdown of spending/projects

plf_gis_year <- plf_gis %>% 
  group_by(completion_year) %>% 
  summarise(n = n(),
            n_gis = sum(has_gis),
            pct_gis = n_gis / n,
            cost = sum(total_cost_mills),
            cost_gis = sum(total_cost_mills[has_gis == 1]),
            cost_pct_gis = cost_gis / cost)


# =============================================
# Breakdown by work types

work_types <- c(
  "has_new_construction",
  "has_reconstruction",
  "has_rehabilitation",
  "has_maintenance",
  "has_pe",
  "has_row"
)


work_type_labels <- c(
  has_new_construction = "New Construction",
  has_reconstruction   = "Reconstruction",
  has_rehabilitation   = "Rehabilitation",
  has_maintenance      = "Maintenance",
  has_pe = "Preliminary Engineering",
  has_row = "Right of Way"
)

summarise_gis_year <- function(df, wt, mode, year_var) {
  if (mode == "only") {
    other <- setdiff(work_types, wt)
    df <- df %>% filter(.data[[wt]] == 1, if_all(all_of(other), ~ .x == 0))
  } else {
    df <- df %>% filter(.data[[wt]] == 1)
  }
  
  df %>%
    group_by({{year_var}}) %>%
    summarise(
      n     = n(),
      n_gis = sum(has_gis),
      cost      = sum(total_cost_mills),
      cost_gis  = sum(total_cost_mills[has_gis == 1]),
      .groups = "drop"
    ) %>%
    mutate(
      pct_gis      = n_gis / n,
      cost_pct_gis = cost_gis / cost,
      work_type    = wt,
      definition   = mode
    )
}

plf_gis_year_type <- tidyr::expand_grid(
  wt   = work_types,
  mode = c("has", "only")
) %>%
  purrr::pmap_dfr(function(wt, mode) summarise_gis_year(plf_gis, wt, mode, completion_year)) %>%
  mutate(
    work_type  = factor(work_type, levels = work_types, labels = work_type_labels),
    definition = factor(definition,
                        levels = c("has", "only"),
                        labels = c("Has this type", "Has only this type"))
  )

plf_gis_year_authconst_type <- tidyr::expand_grid(
  wt   = work_types,
  mode = c("has", "only")
) %>%
  purrr::pmap_dfr(function(wt, mode) summarise_gis_year(plf_gis, wt, mode, auth_year)) %>%
  mutate(
    work_type  = factor(work_type, levels = work_types, labels = work_type_labels),
    definition = factor(definition,
                        levels = c("has", "only"),
                        labels = c("Has this type", "Has only this type"))
  )

# state df helper function

make_state_df <- function(data) {
  df <- inner_join(
    us_map() %>% mutate(state_fips = as.numeric(fips)),
    data %>% 
      filter(completion_year >= 2015) %>% 
      group_by(state_fips) %>% 
      summarise(n = n(),
                n_gis = sum(has_gis),
                pct_gis = n_gis / n,
                cost = sum(total_cost_mills),
                cost_gis = sum(total_cost_mills[has_gis == 1]),
                cost_pct_gis = cost_gis / cost,
                avg_detail_codes = mean(num_detail_codes),
                avg_cost = mean(total_cost_mills)),
    by = "state_fips"
  )
}