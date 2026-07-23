plf_join <- read_csv(file.path(data_dir, "geocoding/project_level_FMIS_geocoded.csv"))

#===========================================
# Summarize at project (depreciated), county, and state level

# note that there are 8553 unique projects out of the 9946 observations from the 10k sample (old version)
plf_projects <- plf_join %>% 
  group_by(federal_project_number) %>%
  summarise(
    n_projects = n(),
    n_geocoded = sum(geocoded, na.rm = T),
    total_spending = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm =
                               T)
  ) %>% 
  mutate(pct_proj_geo = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending)

plf_states <- plf_join %>%
  mutate(state_fips = sprintf("%02d", state_fips)) %>% 
  group_by(state_fips) %>%
  summarise(
    n_projects = n(),
    n_geocoded = sum(geocoded, na.rm = T),
    total_spending = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm =
                               T)
  ) %>% 
  mutate(pct_proj_geo = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending) %>% 
  inner_join(
    us_map(regions="states",
           exclude = "PR"),
    by = join_by(state_fips == fips)
  ) %>% 
  st_as_sf()

plf_counties <- plf_join %>%
  # keep single counties only
  filter(!is.na(county_fips), county_fips != "", !str_detect(county_fips, ";")) %>%
  mutate(county_fips = str_pad(as.character(county_fips), 5, side = "left", pad = "0")) %>%
  filter(str_sub(county_fips, 3, 5) != "999") %>%
  group_by(county_fips) %>%
  summarise(
    n_projects        = n(),
    n_geocoded        = sum(geocoded, na.rm = T),
    total_spending    = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm = T)
  ) %>%
  mutate(pct_proj_geo     = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending) %>%
  right_join(
    us_map(regions = "counties",
           exclude = "PR"),
    by = join_by(county_fips == fips)
  ) %>%
  st_as_sf()

# state outlines for overlay
plf_state_borders <- us_map(regions = "states") %>% st_as_sf()

# make state-decade level df for state-decade map
plf_states_decade <- plf_join %>%
  mutate(state_fips = sprintf("%02d", state_fips),
         decade = paste0((year %/% 10) * 10, "-", ((year %/% 10) * 10) + 9)
  ) %>% 
  group_by(state_fips, decade) %>%
  summarise(
    n_projects = n(),
    n_geocoded = sum(geocoded, na.rm = T),
    total_spending = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm =
                               T)
  ) %>% 
  mutate(pct_proj_geo = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending) %>% 
  inner_join(
    us_map(regions="states",
           exclude = "PR"),
    by = join_by(state_fips == fips)
  ) %>% 
  st_as_sf()

#=============================================================
# filter for one PR511 year ever (depreciated with this being prefiltered in new raw data)
one_pr511_year_counties <- read_dta(file.path(data_dir, "one_year_counties.dta")) %>%
  mutate(county_fips = paste0(
    sprintf("%02d", st),
    sprintf("%03d", county)
  )) %>% 
  pull(county_fips)

one_year_counties_re <- paste(one_pr511_year_counties, collapse = "|")

plf_join_oneyear <- plf_join %>% 
  mutate(county_fips = sprintf("%05d", as.numeric(county_fips))) %>%
  filter(str_detect(county_fips, one_year_counties_re))

plf_projects_oneyear <- plf_join_oneyear %>% 
  group_by(federal_project_number) %>%
  summarise(
    n_projects = n(),
    n_geocoded = sum(geocoded, na.rm = T),
    total_spending = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm =
                               T)
  ) %>% 
  mutate(pct_proj_geo = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending)

plf_states_oneyear <- plf_join_oneyear %>%
  mutate(state_fips = sprintf("%02d", state_fips)) %>% 
  group_by(state_fips) %>%
  summarise(
    n_projects = n(),
    n_geocoded = sum(geocoded, na.rm = T),
    total_spending = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm =
                               T)
  ) %>% 
  mutate(pct_proj_geo = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending) %>% 
  inner_join(
    us_map(regions="states",
           exclude = "PR"),
    by = join_by(state_fips == fips)
  ) %>% 
  st_as_sf()

plf_counties_oneyear <- plf_join_oneyear %>%
  # keep single counties only
  filter(!is.na(county_fips), county_fips != "", !str_detect(county_fips, ";")) %>%
  mutate(county_fips = str_pad(as.character(county_fips), 5, side = "left", pad = "0")) %>%
  filter(str_sub(county_fips, 3, 5) != "999") %>%
  group_by(county_fips) %>%
  summarise(
    n_projects        = n(),
    n_geocoded        = sum(geocoded, na.rm = T),
    total_spending    = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm = T)
  ) %>%
  mutate(pct_proj_geo     = n_geocoded / n_projects,
         pct_spending_geo = total_geo_spending / total_spending) %>%
  right_join(
    us_map(regions = "counties",
           exclude = "PR"),
    by = join_by(county_fips == fips)
  ) %>%
  st_as_sf()