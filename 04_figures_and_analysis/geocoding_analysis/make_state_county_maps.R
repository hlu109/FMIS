# make state level maps

state_proj_map <- make_state_map(
  plf_states, pct_proj_geo,
  title      = "Share of Interstate Project Receipts Geocoded",
  subtitle   = "By state",
  legend_name = "Share of receipts geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects."
)

state_spend_map <- make_state_map(
  plf_states, pct_spending_geo,
  title      = "Share of Interstate Spending Geocoded",
  subtitle   = "By state",
  legend_name = "Share of spending geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects."
)

state_proj_map_decade <- make_state_map_decade(
  plf_states_decade, plf_state_borders, pct_proj_geo,
  title      = "Share of Interstate Project Receipts Geocoded",
  subtitle   = "By state",
  legend_name = "Share of receipts geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects.",
  time_var = decade
)

state_spend_map_decade <- make_state_map_decade(
  plf_states_decade, plf_state_borders, pct_spending_geo,
  title      = "Share of Interstate Spending Geocoded",
  subtitle   = "By state",
  legend_name = "Share of spending geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects.",
  time_var = decade
)

# make county level maps

county_proj_map <- make_county_map(
  plf_counties, plf_state_borders, pct_proj_geo,
  title      = "Share of Interstate Receipts Geocoded",
  subtitle   = "By county",
  legend_name = "Share of receipts geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects; multi-county and unspecified-county projects excluded."
)

county_spend_map <- make_county_map(
  plf_counties, plf_state_borders, pct_spending_geo,
  title      = "Share of Interstate Spending Geocoded",
  subtitle   = "By county",
  legend_name = "Share of spending geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects; multi-county and unspecified-county projects excluded."
)

county_spend_map_75_only <- make_county_map(
  plf_counties %>%
    mutate(pct_spending_geo = ifelse(pct_spending_geo >= 0.75,
                                     pct_spending_geo,
                                     NA)),
  plf_state_borders, pct_spending_geo,
  title      = "Share of Interstate Spending Geocoded",
  subtitle   = "By county; only counties with 75%+ of spending geocoded",
  legend_name = "Share of spending geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects or below 0.75 threshold;
  multi-county and unspecified-county projects excluded."
) + guides(fill = "none")

# county_proj_map_oneyear <- make_county_map(
#   plf_counties_oneyear, plf_state_borders, pct_proj_geo,
#   title      = "Share of Interstate Receipts Successfully Geocoded",
#   subtitle   = "By county; counties with only one year of PR511 data ever",
#   legend_name = "Share of receipts geocoded",
#   caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects; multi-county and unspecified-county projects excluded."
# )
# 
# county_spend_map_oneyear <- make_county_map(
#   plf_counties_oneyear, plf_state_borders, pct_spending_geo,
#   title      = "Share of Interstate Spending Successfully Geocoded",
#   subtitle   = "By county; counties with only one year of PR511 data ever",
#   legend_name = "Share of spending geocoded",
#   caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects; multi-county and unspecified-county projects excluded."
# )
# 
# county_spend_map_75_only_oneyear <- make_county_map(
#   plf_counties_oneyear %>% 
#     mutate(pct_spending_geo = ifelse(pct_spending_geo >= 0.75,
#                                      pct_spending_geo,
#                                      NA)), 
#   plf_state_borders, pct_spending_geo,
#   title      = "Share of Interstate Spending Successfully Geocoded",
#   subtitle   = "By county; only counties with 75%+ of spending geocoded and only one year of PR511 data ever",
#   legend_name = "Share of spending geocoded",
#   caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects or below 0.75 threshold; 
#   multi-county and unspecified-county projects excluded."
# ) + guides(fill = "none")

# print(county_proj_map_oneyear)
# print(county_spend_map_oneyear)
# print(county_spend_map_75_only_oneyear)

# ggsave(file.path(output_dir, "map_county_pct_recpt_geocoded_oneyear.png"),
#        county_proj_map_oneyear, width = 8, height = 5)
# ggsave(file.path(output_dir, "map_county_pct_spending_geo_oneyear.png"),
#        county_spend_map_oneyear, width = 8, height = 5)
# ggsave(file.path(output_dir, "map_county_pct_spending_geo_75_only_oneyear.png"),
#        county_spend_map_75_only_oneyear, width = 8, height = 5)