options(scipen = 999)
if(!require('pacman')) {
  install.packages('pacman')
}
pacman::p_load(sf, dplyr, haven, purrr, stringr, tidyverse, here, mapview, knitr, 
               kableExtra)

i_am("Code/FMIS_finn/04_geocode_eval/misc/first_round_validation.R")
intermediate_dir <- here("Data", "Intermediate")
code_dir <- here("Code", "FMIS_finn", "04_geocode_eval")
out_dir <- here("Output", "Finn", "geocoding validation")

# aesthetic stuff
hist_fill   <- "#4575b4"   # muted steel blue
hist_border <- "white"

theme_validation <- theme_minimal(base_size = 12) +
  theme(
    plot.title          = element_text(face = "bold", size = 13),
    plot.subtitle       = element_text(colour = "grey30", margin = margin(b = 8)),
    plot.title.position = "plot",
    panel.grid.minor    = element_blank()
  )

hist_layers <- list(
  geom_histogram(bins = 30, fill = hist_fill, colour = hist_border, linewidth = 0.2),
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40"),
  scale_y_continuous(labels = scales::percent),
  theme_validation
)

# auxiliary validation datasets
fmis_gis_projectids <- read_dta(file.path(intermediate_dir, "project_level_FMIS_w_GIS.dta")) %>% 
  mutate(project_id = paste0(federal_project_number, "_", recipientid)) %>% 
  select(project_id, gis_routeid, gis_beginpoint, gis_endpoint, gis_length)

# share interstate new construction

nrow(read_dta(file.path(intermediate_dir, "project_level_FMIS_w_GIS.dta")) %>% 
       filter(fp_ic == 1,
              has_new_construction == 1)) / nrow(read_dta(file.path(intermediate_dir, "project_level_FMIS_w_GIS.dta")))

pr511_chains <- read_csv(file.path(intermediate_dir, "PR_511", "PR511_hubbardmazzeo_chained.csv")) %>%
  mutate(county_fips = paste0(st, sprintf("%03d", county))) %>%
  select(county_fips, open_year, chain_len, mp_start, mp_end, route)

pr511_cty_totals <- pr511_chains %>% 
  group_by(county_fips, route) %>% 
  summarise(len_pr511 = sum(chain_len))

pr511_single_county_route_year <- read_dta(file.path(intermediate_dir, "PR_511", "pr511_cty_rt_single_openyr_ever.dta")) %>% 
  mutate(county_fips = as.character(county_fips)) %>%
  select(county_fips) %>% mutate(has_single_county_route_year = 1)

pr511_single_county_year <- read_dta(file.path(intermediate_dir, "PR_511", "pr511_cty_single_openyr_ever.dta")) %>% 
  mutate(county_fips = as.character(county_fips)) %>% 
  select(county_fips) %>% mutate(has_single_county_year = 1)

# load ella's inputs/outputs
ella_dir <- here("Code/ella-temp")

input_interstate_newconst_path <- file.path(ella_dir, "data", "fmis_endpoints", "interstate_new_constr_10k_v5_20260710_113650.csv")
output_interstate_newconst_path <- file.path(ella_dir, "extracted_geometry", "main_routes_cropped", "route_cropped.gpkg")
 
input_pr511_cty_path <- file.path(ella_dir, "data", "fmis_endpoints", "VAL_interstate_newconstr_1yrPR511_ct_v5_20260807_103957.csv")
output_pr511_cty_path <- file.path(ella_dir, "extracted_geometry", "main_routes_cropped", 
                               "route_cropped_VAL_interstate_newconstr_1yrPR511_ct_v5_20260807_103957.gpkg")

input_pr511_cty_rt_path <- file.path(ella_dir, "data", "fmis_endpoints", "VAL_interstate_newconstr_1yrPR511_ct_rt_v5_20260807_103902.csv")
output_pr511_cty_rt_path <- file.path(ella_dir, "extracted_geometry", "main_routes_cropped",
                                      "route_cropped_VAL_interstate_newconstr_1yrPR511_ct_rt_v5_20260807_103902.gpkg")

input_fmis_gis_path <- file.path(ella_dir, "data", "fmis_endpoints", "VAL_fmis_gis_5k_noninterstate_prompt_v6_20260812_123113_corrected.csv")
output_fmis_gis_path <- file.path(ella_dir, "extracted_geometry", "main_routes_cropped",
                                  "route_cropped_VAL_fmis_gis_5k_noninterstate_prompt_v6_20260812_123113_corrected.gpkg")

validate_outputs_with_pr511 <- function (input_path, output_path) {
  
  raw_input <- read_csv(input_path)
  
  # occasionally more than one project_id per title (increases ids in ellas sample from 757 to 770)
  # length(unique(title_projectid_xwalk$project_title))
  title_projectid_xwalk <- raw_input %>% 
    mutate(project_id = paste0(federal_project_number, "_", recipient_id)) %>% 
    select(project_title, project_id, completion_year, authconstyear, county_fips, route_num = route_fpn)
  
  ella_projects <- st_read(output_path) %>% 
    mutate(len_corr = (len_corr_m / 1000) * 0.621371) %>% 
    inner_join(title_projectid_xwalk, by = join_by(project_title == project_title)) %>% 
    left_join(fmis_gis_projectids, by = "project_id") %>% 
  
  return(ella_projects)
}

nrow(st_read(output_fmis_gis_path)) / nrow(read_csv(input_fmis_gis_path))

z <- st_read(output_fmis_gis_path)
read_csv(input_fmis_gis_path) %>% select(project_title) %>% 
  head(n = 10) %>% 
  kable(format = "latex", booktabs = T) %>% 
  save_kable(file = file.path(out_dir, "tab_fmis_gis_title_sample.tex"))

read_csv(input_interstate_newconst_path) %>% select(project_title) %>% 
  head(n = 10) %>% 
  kable(format = "latex", booktabs = T) %>% 
  save_kable(file = file.path(out_dir, "tab_interstate_newconst_title_sample.tex"))

ella_projects_fmis_gis <- validate_outputs_with_pr511(input_fmis_gis_path, output_fmis_gis_path) %>% 
  select(project_id, len_geocoded = len_corr, len_mile_markers = gis_length) %>%
  mutate(len_diff = len_geocoded - len_mile_markers) %>% 
  arrange(-len_diff) %>% 
  st_drop_geometry() %>% 
  kable(format = "latex", booktabs = T) %>% 
  save_kable(file = file.path(out_dir, "tab_fmis_gis_diffs.tex"))
  

ella_projects <- validate_outputs_with_pr511(input_interstate_newconst_path,
                                             output_interstate_newconst_path)

ella_projects_pr511_cty <- validate_outputs_with_pr511(input_pr511_cty_path,
                                                   output_pr511_cty_path)

ella_projects_pr511_cty_rt <- validate_outputs_with_pr511(input_pr511_cty_rt_path,
                                                       output_pr511_cty_rt_path)


nrow(read_csv(input_pr511_cty_path)) + nrow(read_csv(input_pr511_cty_rt_path))

# match length of ella projects with PR511 data

######### not super interested in this anymore, want the pr511 totals vs. ella's county level results

# ella_projects <- ella_projects %>% 
#   left_join(pr511_single_county_year, by = "county_fips")

# return_single_county_projects <- function(projects_df) {
#   ella_projects_onecounty <- projects_df %>% 
#     filter(has_single_county_year == 1) %>% 
#     group_by(county_fips) %>% st_drop_geometry() %>% 
#     summarise(
#       len_corr = sum(len_corr)
#     ) %>% 
#     left_join(pr511_cty_totals, by = "county_fips") %>% 
#     mutate(
#       diff = len_corr - chain_len
#     )
#   
#   return(ella_projects_onecounty)
# }
# 
# ella_projects_onecounty <- return_single_county_projects(ella_projects)

# hist_pr511_onecounty_matches <- ggplot(
#     ella_projects_onecounty,
#     aes(x = diff, y = after_stat(width * density))) +
#   hist_layers +
#   labs(x        = "Geocoded distance - PR511 segment length (miles)",
#        y        = "Share of counties",
#        title    = "Geocoded vs. PR511 segment length",
#        subtitle = "Single-county interstate projects")
# hist_pr511_onecounty_matches
# 
# hist_pr511_onecounty_matches_nozero <- ggplot(
#     ella_projects_onecounty %>% filter(len_corr > 0),
#     aes(x = diff, y = after_stat(width * density))) +
#   hist_layers +
#   labs(x        = "Geocoded distance - PR511 segment length (miles)",
#        y        = "Share of counties",
#        title    = "Geocoded vs. PR511 segment length",
#        subtitle = "Single-county interstate projects; counties with zero geocoded distance excluded")
# hist_pr511_onecounty_matches_nozero
# 
# ggsave(file.path(out_dir, "hist_pr511_onecounty_matches.png"), hist_pr511_onecounty_matches)
# ggsave(file.path(out_dir, "hist_pr511_onecounty_matches_nozero.png"), hist_pr511_onecounty_matches_nozero)

# see how ella's distances compare to total PR511 distances ever
county_totals <- inner_join(
  ella_projects %>% st_drop_geometry() %>%
    group_by(county_fips) %>%
    summarise(len_geocoded = sum(len_corr)),
  pr511_chains %>%
    group_by(county_fips) %>%
    summarise(len_pr511 = sum(chain_len)),
  by = "county_fips"
) %>%
  mutate(len_diff = len_geocoded - len_pr511)


county_totals_pr511_single_cty <- rbind(ella_projects_pr511_cty %>% mutate(type = "cty"), 
                                        ella_projects_pr511_cty_rt %>% mutate(type = "cty_rt")) %>% 
  st_drop_geometry() %>%
  group_by(county_fips, route_num) %>%
  summarise(len_geocoded = sum(len_corr),
            type = first(type)) %>%
  inner_join(pr511_cty_totals,
             by = join_by(county_fips == county_fips, route_num == route)) %>% mutate(len_diff = len_geocoded - len_pr511)

winsorize <- function(x, probs = c(0.10, 0.80)) {
  caps <- quantile(x, probs = probs, na.rm = TRUE)
  pmin(pmax(x, caps[1]), caps[2])
}

# original outputs (interstate new construction)

hist_county_totals <- ggplot(
    county_totals,
    aes(x = len_diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Total geocoded distance - total PR511 distance (miles)",
       y        = "Share of counties",
       title    = "Geocoded vs. PR511 total length, by county",
       subtitle = "All counties present in both PR511 and the geocoded output")
hist_county_totals

hist_county_totals_trim <- ggplot(
    county_totals %>% filter(abs(len_diff) <= 20),
    aes(x = len_diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Total geocoded distance - total PR511 distance (miles)",
       y        = "Share of counties",
       title    = "Geocoded vs. PR511 total length, by county",
       subtitle = "Dropping highest and lowest 10% of observations")
hist_county_totals_trim

county_totals_positive <- county_totals %>%
  filter(len_diff > 0) #%>%
  #mutate(len_diff_wins = winsorize(len_diff))

print(nrow(county_totals_positive) / nrow(county_totals))

hist_county_totals_positive <- ggplot(
    county_totals_positive,
    aes(x = len_diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Total geocoded distance - total PR511 distance (miles)",
       y        = "Share of counties",
       title    = "Geocoded vs. PR511 total length, by county",
       subtitle = "Positive differences only")
hist_county_totals_positive

print(nrow(county_totals_positive) / nrow(county_totals))

ggsave(file.path(out_dir, "hist_county_totals.png"), hist_county_totals)
ggsave(file.path(out_dir, "hist_county_totals_trim.png"), hist_county_totals_trim)
ggsave(file.path(out_dir, "hist_county_totals_positive.png"), hist_county_totals_positive)

# pr-511 filtered outputs

hist_county_totals_pr511_single_cty <- ggplot(
  county_totals_pr511_single_cty,
  aes(x = len_diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Total geocoded distance - total PR511 distance (miles)",
       y        = "Share of route x counties",
       title    = "Geocoded vs. PR511 total length, by route x county",
       subtitle = "PR-511 Single Route x Year Counties")
hist_county_totals_pr511_single_cty

hist_county_totals_trim_pr511_single_cty <- ggplot(
  county_totals_pr511_single_cty %>% filter(abs(len_diff) <= 20),
  aes(x = len_diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Total geocoded distance - total PR511 distance (miles)",
       y        = "Share of route x counties",
       title    = "Geocoded vs. PR511 total length, by route x county",
       subtitle = "PR-511 Single Route x Year Counties, <= 20 mile differences") +
  theme_minimal()
hist_county_totals_trim_pr511_single_cty


county_totals_positive_pr511_single_cty <- county_totals_pr511_single_cty %>%
  filter(len_diff > 0) #%>%
#mutate(len_diff_wins = winsorize(len_diff))

print(nrow(county_totals_positive_pr511_single_cty) / nrow(county_totals_pr511_single_cty))

county_totals_positive_pr511_single_cty %>%
  arrange(-len_diff) %>% select(-type) %>% 
  kable(format = "latex", booktabs = TRUE) %>%
  save_kable(file = file.path(out_dir, "tab_county_totals_positive_pr511_single_cty.tex"))

hist_county_totals_positive_pr511_single_cty <- ggplot(
  county_totals_positive_pr511_single_cty,
  aes(x = len_diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Total geocoded distance - total PR511 distance (miles)",
       y        = "Share of route x counties",
       title    = "Geocoded vs. PR511 total length, by county",
       subtitle = "PR-511 Single Route x Year Counties, positive differences only")
hist_county_totals_positive_pr511_single_cty

ggsave(file.path(out_dir, "hist_county_totals_pr511_single_cty.png"), hist_county_totals_pr511_single_cty)
ggsave(file.path(out_dir, "hist_county_totals_trim_pr511_single_cty.png"), hist_county_totals_trim_pr511_single_cty)
ggsave(file.path(out_dir, "hist_county_totals_positive_pr511_single_cty.png"), hist_county_totals_positive_pr511_single_cty)

# spot check largest positive observations (csv construction)

largest_diffs_spot_check <- ella_projects %>% 
  inner_join(
    county_totals %>% select(county_fips, len_pr511),
    by = "county_fips"
  ) %>% 
  mutate(diff = len_corr - len_pr511) %>% 
  select(project_title, county_fips, diff, len_corr, len_pr511) %>% 
  st_drop_geometry() %>% 
  arrange(-diff)


# how many interstate numbers do PR511 counties typically have?

fmis_10k_num_routes_county <- st_read(input_interstate_newconst_path) %>%
  inner_join(pr511_single_county_year,
             by = "county_fips") %>%
  filter(!is.na(main_route_num)) %>% 
  group_by(county_fips) %>% 
  summarise(distinct_routes = n_distinct(main_route_num))

fmis_10k_num_fpn_county <- st_read(input_interstate_newconst_path) %>%
  inner_join(pr511_single_county_year,
             by = "county_fips") %>%
  filter(!is.na(main_route_num)) %>% 
  group_by(county_fips) %>% 
  summarise(distinct_routes = n_distinct(route_fpn))

x <- st_read(input_interstate_newconst_path) %>% filter(
  county_fips %in% c("17133", "17147", "51510", "26121")
) %>% arrange(county_fips) %>% 
  select(project_title, main_route_num, county_fips, completion_year) %>% 
  kable(format = "latex") %>% 
  save_kable(file.path(out_dir, "tab_multi_interstate_counties.tex"))


y <- read_csv(file.path(intermediate_dir, "PR_511", "PR511_hubbardmazzeo_chained.csv")) %>%
  mutate(county_fips = paste0(st, sprintf("%03d", county))) %>%
  filter(
  county_fips %in% c("17133", "17147", "51510", "26121"))
  

1- (nrow(ella_raw_input %>% filter(main_route_type == "interstate")) / 10000)

# z <- inner_join(largest_diffs_spot_check,
#                 ella_raw_input,
#                 by = "project_title") %>% 
#   filter(main_route_type == "interstate") 

