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

# ---- Shared figure styling --------------------------------------------------
# One look-and-feel so every validation histogram reads as part of the same set.
hist_fill   <- "#4575b4"   # muted steel blue
hist_border <- "white"

theme_validation <- theme_minimal(base_size = 12) +
  theme(
    plot.title          = element_text(face = "bold", size = 13),
    plot.subtitle       = element_text(colour = "grey30", margin = margin(b = 8)),
    plot.title.position = "plot",
    panel.grid.minor    = element_blank()
  )

# Reusable layers: bin height as a share of observations, plus a zero reference.
hist_layers <- list(
  geom_histogram(bins = 30, fill = hist_fill, colour = hist_border, linewidth = 0.2),
  geom_vline(xintercept = 0, linetype = "dashed", colour = "grey40"),
  scale_y_continuous(labels = scales::percent),
  theme_validation
)

# load ella's inputs/outputs
ella_dir <- here("Code/ella-temp")
ella_raw_input <- read_csv(file.path(ella_dir, "data", "fmis_endpoints", "interstate_new_constr_10k_v5_20260710_113650.csv"))
ella_projects <- st_read(file.path(ella_dir, "extracted_geometry", "main_routes_cropped", "route_cropped.gpkg")) %>% 
  mutate(len_corr = (len_corr_m / 1000) * 0.621371)

title_projectid_xwalk <- ella_raw_input %>% 
  mutate(project_id = paste0(federal_project_number, "_", recipient_id)) %>% 
  select(project_title, project_id, completion_year, authconstyear, county_fips)

# occasionally more than one project_id per title (increases ids in ellas sample from 757 to 770)
# length(unique(title_projectid_xwalk$project_title))

ella_projects <- ella_projects %>% 
  inner_join(title_projectid_xwalk, by = join_by(project_title == project_title))

# load comparison samples (FMIS mile markers and PR511)
fmis_gis_projectids <- read_dta(file.path(intermediate_dir, "project_level_FMIS_w_GIS.dta")) %>% 
  mutate(project_id = paste0(federal_project_number, "_", recipientid)) %>% 
  select(project_id, gis_routeid, gis_beginpoint, gis_endpoint, gis_length)

pr511_single_county <- read_dta(file.path(intermediate_dir, "one_chain_counties.dta")) %>% 
  mutate(county = sprintf("%03d", county), county_fips = paste0(st, county)) %>% 
  select(county_fips) %>% mutate(has_single_county = 1)
pr511_single_county_year <- read_dta(file.path(intermediate_dir, "one_year_counties.dta")) %>% 
  mutate(county = sprintf("%03d", county), county_fips = paste0(st, county)) %>% 
  select(county_fips) %>% mutate(has_single_county_year = 1)

ella_projects <- ella_projects %>% 
  left_join(fmis_gis_projectids, by = "project_id") %>% 
  left_join(pr511_single_county, by = "county_fips") %>% 
  left_join(pr511_single_county_year, by = "county_fips")

nrow(ella_projects %>% filter(!is.na(gis_length)))
nrow(ella_projects %>% filter(!is.na(has_single_county)))
nrow(ella_projects %>% filter(!is.na(has_single_county_year)))

# match length of ella projects with PR511 data

pr511_chains <- read_csv(file.path(intermediate_dir, "PR_511", "PR511_hubbardmazzeo_chained.csv")) %>%
  mutate(county_fips = paste0(st, sprintf("%03d", county))) %>%
  select(county_fips, open_year, chain_len, mp_start, mp_end)

ella_projects_onecounty <- ella_projects %>% 
  filter(has_single_county == 1) %>% 
  left_join(pr511_chains, by = "county_fips") %>% 
  select(project_title, len_corr, chain_len, completion_year, open_year, county_fips) %>% 
  group_by(county_fips) %>% st_drop_geometry() %>% 
  summarise(
    len_corr = sum(len_corr),
    chain_len = first(chain_len),
    diff = len_corr - chain_len
  )

# aside - test if there are any PR511 "single counties" for which there is more than one interstate route in the FMIS sample
# n = 20 here, which is worrying ~ 20/103 matched PR511 counties
t <- inner_join(ella_raw_input, pr511_single_county, by = "county_fips") %>% 
  group_by(county_fips) %>% 
  summarise(n = n_distinct(main_route_num)) %>% 
  filter(n > 1) %>% print()

hist_pr511_onecounty_matches <- ggplot(
    ella_projects_onecounty,
    aes(x = diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Geocoded distance - PR511 segment length (miles)",
       y        = "Share of counties",
       title    = "Geocoded vs. PR511 segment length",
       subtitle = "Single-county interstate projects")
hist_pr511_onecounty_matches

hist_pr511_onecounty_matches_nozero <- ggplot(
    ella_projects_onecounty %>% filter(len_corr > 0),
    aes(x = diff, y = after_stat(width * density))) +
  hist_layers +
  labs(x        = "Geocoded distance - PR511 segment length (miles)",
       y        = "Share of counties",
       title    = "Geocoded vs. PR511 segment length",
       subtitle = "Single-county interstate projects; counties with zero geocoded distance excluded")
hist_pr511_onecounty_matches_nozero

ggsave(file.path(out_dir, "hist_pr511_onecounty_matches.png"), hist_pr511_onecounty_matches)
ggsave(file.path(out_dir, "hist_pr511_onecounty_matches_nozero.png"), hist_pr511_onecounty_matches_nozero)

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

winsorize <- function(x, probs = c(0.10, 0.80)) {
  caps <- quantile(x, probs = probs, na.rm = TRUE)
  pmin(pmax(x, caps[1]), caps[2])
}

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

fmis_10k_num_routes_county <- ella_raw_input %>%
  inner_join(pr511_single_county,
             by = "county_fips") %>%
  filter(!is.na(main_route_num)) %>% 
  group_by(county_fips) %>% 
  summarise(distinct_routes = n_distinct(main_route_num))

fmis_10k_num_fpn_county <- ella_raw_input %>%
  inner_join(pr511_single_county,
             by = "county_fips") %>%
  filter(!is.na(main_route_num)) %>% 
  group_by(county_fips) %>% 
  summarise(distinct_routes = n_distinct(route_fpn))

x <- ella_raw_input %>% filter(
  county_fips %in% c("17133", "17147", "51510", "26121")
) %>% arrange(county_fips) %>% 
  select(project_title, main_route_num, county_fips, completion_year) %>% 
  kable(format = "latex") %>% 
  save_kable(file.path(out_dir, "multi_interstate_counties.tex"))


y <- read_csv(file.path(intermediate_dir, "PR_511", "PR511_hubbardmazzeo_chained.csv")) %>%
  mutate(county_fips = paste0(st, sprintf("%03d", county))) %>%
  filter(
  county_fips %in% c("17133", "17147", "51510", "26121"))
  

1- (nrow(ella_raw_input %>% filter(main_route_type == "interstate")) / 10000)

z <- inner_join(largest_diffs_spot_check,
                ella_raw_input,
                by = "project_title") %>% 
  filter(main_route_type == "interstate") 

