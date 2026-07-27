# load main FMIS datasets
project_level_fmis <- read_dta(file.path(data_dir, "project_level_FMIS_lite.dta")) %>% 
  mutate(project_id = paste0(
    sprintf("%02d", recipientid),
    sep = "_",
    federal_project_number
  ))

receipt_level_fmis <- read_dta(file.path(data_dir, "receipt_level_FMIS_lite.dta")) %>% 
  mutate(project_id = paste0(
    sprintf("%02d", recipientid),
    sep = "_",
    federal_project_number
  )) %>% 
  haven::zap_labels()

# load subset of geocoded data

old_subset <- "interstate_new_constr_10k_v5_20260710_113650.csv" # previous iterations

oneyear_counties_subset <- "interstate_oneyearPR511_v5_20260716_120910.csv" # new df with only one year of PR511 data counties

project_level_fmis_geo <- fread(file.path(data_dir, "geocoding", "title_parsing_gemini_output", oneyear_counties_subset)) %>% 
  select(recipient_id,
         federal_project_number,
         ep_a_max_precision,
         ep_b_max_precision) %>% 
  mutate(
    num_ep = rowSums(!is.na(pick(ep_a_max_precision:ep_b_max_precision))),
    ep_a_max_precision = ifelse(is.na(ep_a_max_precision), 0, ep_a_max_precision),
    ep_b_max_precision = ifelse(is.na(ep_b_max_precision), 0, ep_b_max_precision),
    geocoded = ifelse(
      num_ep >= 2 & pmax(ep_a_max_precision, ep_b_max_precision) >= 3,
      1,
      0
    ),
    project_id = paste0(
      sprintf("%02d", recipient_id), 
      sep = "_", 
      federal_project_number)) %>% 
  select(-recipient_id, -federal_project_number)

#==============================================
# join datasets, adjust for inflation

plf_join <- project_level_fmis_geo %>%
  inner_join(receipt_level_fmis, by = "project_id") %>% 
  filter(funding_program == "Interstate Construction",
         completion_year >= 1950 & completion_year <= 2000,
         detail_improvementtype != 5 | detail_improvementtype != 59) %>% 
  mutate(
    new_construction_cost = if_else(new_construction == 1, total_cost_mills, NA_real_),
    reconstruction_cost   = if_else(reconstruction == 1, total_cost_mills, NA_real_),
    rehabilitation_cost   = if_else(rehabilitation == 1, total_cost_mills, NA_real_),
    maintenance_cost      = if_else(maintenance == 1, total_cost_mills, NA_real_),
    row_cost              = if_else(detail_improvementtype == 16, total_cost_mills, NA_real_),
    pe_cost               = if_else(detail_improvementtype == 15, total_cost_mills, NA_real_),
    road_cost             = if_else(road == 1, total_cost_mills, NA_real_),
    bridge_cost           = if_else(bridge == 1, total_cost_mills, NA_real_),
    tunnel_cost           = if_else(tunnel == 1, total_cost_mills, NA_real_)
  ) %>%
  group_by(project_id) %>% 
  summarise(
    total_cost_mills = sum(total_cost_mills, na.rm=T),
    new_construction_cost = sum(new_construction_cost, na.rm=T),
    reconstruction_cost = sum(reconstruction_cost, na.rm=T),
    rehabilitation_cost = sum(rehabilitation_cost, na.rm=T),
    maintenance_cost = sum(maintenance_cost, na.rm=T),
    row_cost = sum(row_cost, na.rm=T),
    pe_cost = sum(pe_cost, na.rm=T),
    road_cost = sum(road_cost, na.rm=T),
    bridge_cost = sum(bridge_cost, na.rm=T),
    tunnel_cost = sum(tunnel_cost, na.rm=T),
    state_fips = first(state_fips),
    county_fips = paste(unique(county_fips), collapse = ";"),
    federal_project_number = first(federal_project_number),
    geocoded = first(geocoded),
    year = first(completion_year)
  )

# adjust for inflation

inf <- read_dta(file.path(data_dir, "CPI_2025.dta")) %>% 
  select(year, cpi)

plf_join <- plf_join %>% 
  left_join(inf, by = "year") %>% 
  mutate(
    total_cost_mills = total_cost_mills / cpi,
    new_construction_cost = new_construction_cost / cpi,
    reconstruction_cost = reconstruction_cost / cpi,
    rehabilitation_cost = rehabilitation_cost / cpi,
    maintenance_cost = maintenance_cost / cpi,
    row_cost = row_cost / cpi,
    pe_cost = pe_cost / cpi,
    road_cost = road_cost / cpi,
    bridge_cost = bridge_cost / cpi,
    tunnel_cost = tunnel_cost / cpi
  )

write.csv(plf_join, file = file.path(data_dir, "geocoding/project_level_FMIS_geocoded.csv"), row.names = F)
