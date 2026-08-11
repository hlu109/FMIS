# all projects
plf_lite <- read_dta(file.path(data_dir, "project_level_FMIS_lite.dta")) %>%
  mutate(
    projectid = paste0(recipientid, "_", federal_project_number),
    auth_year = year(authconstdate)
  )

# adjust for inflation
inflation <- read_dta(file.path(data_dir, "CPI_2025.dta")) %>%
  select(year, cpi)

plf_lite_cy <- plf_lite %>%
  left_join(inflation, by = join_by(completion_year == year)) %>%
  mutate(total_cost_mills = total_cost_mills / cpi)

plf_lite_ay <- plf_lite %>%
  left_join(inflation, by = join_by(auth_year == year)) %>%
  mutate(total_cost_mills = total_cost_mills / cpi)

# projects with gis
plf_only_gis <- read_dta(file.path(
  data_dir,
  "project_level_FMIS_w_GIS.dta"
)) %>%
  mutate(projectid = paste0(recipientid, "_", federal_project_number)) %>%
  select(projectid, gis_beginpoint, gis_endpoint, n_proj_per_routeid)

make_plf_gis <- function(
  plf_lite_adj,
  sample = c("completion", "authorization", "original")
) {
  sample <- match.arg(sample)
  out <- plf_lite_adj %>%
    left_join(plf_only_gis, by = "projectid") %>%
    mutate(
      has_gis = ifelse(!is.na(gis_beginpoint) & !is.na(gis_endpoint), 1, 0),
      has_pe = ifelse(str_detect(proj_improv_types, "15"), 1, 0),
      has_row = ifelse(str_detect(proj_improv_types, "16"), 1, 0),
      fp_ic = as.factor(fp_ic),
      urban_rural = as.factor(urban_rural)
    )

  out <- if (sample == "original") {
    out %>% filter(completion_year <= 2024) # original sample (only need completion year before 2024), preserve so previous analysis matches
  } else if (sample == "authorization") {
    out %>% filter(auth_year <= 2025) # requires only an authorization year
  } else if (sample == "completion") {
    out %>% filter(auth_year <= 2025, completion_year <= 2025) # both completion and auth exist, completion before 2025
  }

  out %>%
    mutate(
      num_detail_codes = str_count(proj_improv_types, ";") + 1,
      gis_length = gis_endpoint - gis_beginpoint,
      log_cost_mile = ifelse(
        gis_length == 0 | is.na(gis_length) | total_cost_mills == 0,
        NA,
        log(total_cost_mills / gis_length)
      )
    )
}

# analysis dfs differ by sample and cpi
plf_gis <- make_plf_gis(plf_lite_cy, "original")
plf_gis_cy <- make_plf_gis(plf_lite_cy, "completion")
plf_gis_ay <- make_plf_gis(plf_lite_ay, "authorization")
plf_gis_cy_1yr <- plf_gis_cy %>%
  filter(completedate - authconstdate <= 365)
plf_gis_cy_2yr <- plf_gis_cy %>%
  filter(completedate - authconstdate <= 730)

# look at projects with specific program codes
iija_codes <- c("NHPP", "STBG", "HSIP", "CMAQ", "NHFP", "PL")

plf_gis_cy_iijacodes <- make_plf_gis(
  plf_lite_cy %>% filter(detail_prefix %in% iija_codes),
  "completion"
)
plf_gis_ay_iijacodes <- make_plf_gis(
  plf_lite_ay %>% filter(detail_prefix %in% iija_codes),
  "authorization"
)
plf_gis_cy_1yr_iijacodes <- make_plf_gis(
  plf_lite_cy %>%
    filter(detail_prefix %in% iija_codes, completedate - authconstdate <= 365),
  "completion"
)
plf_gis_cy_2yr_iijacodes <- make_plf_gis(
  plf_lite_cy %>%
    filter(detail_prefix %in% iija_codes, completedate - authconstdate <= 730),
  "completion"
)

# the authorization-year sample should be strictly larger
# nrow(plf_gis)      # completion-year sample
# nrow(plf_gis_cy)
# nrow(plf_gis_ay)   # authorization-year sample

# plf_gis_sample <- plf_gis[1:1000, ] inspect
