# make state level maps

state_proj_map <- make_state_map(
  plf_states, pct_proj_geo,
  title      = "Share of Interstate Project Receipts Successfully Geocoded",
  subtitle   = "By state",
  legend_name = "Share of receipts geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects."
)

state_spend_map <- make_state_map(
  plf_states, pct_spending_geo,
  title      = "Share of Interstate Spending Successfully Geocoded",
  subtitle   = "By state",
  legend_name = "Share of spending geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects."
)

print(state_proj_map)
print(state_spend_map)

ggsave(file.path(output_dir, "map_state_pct_recpt_geocoded.png"),
       state_proj_map, width = 8, height = 5)
ggsave(file.path(output_dir, "map_state_pct_spending_geocoded.png"),
       state_spend_map, width = 8, height = 5)

# make county level maps

county_proj_map <- make_county_map(
  plf_counties, plf_state_borders, pct_proj_geo,
  title      = "Share of Interstate Receipts Successfully Geocoded",
  subtitle   = "By county",
  legend_name = "Share of receipts geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects; multi-county and unspecified-county projects excluded."
)

county_spend_map <- make_county_map(
  plf_counties, plf_state_borders, pct_spending_geo,
  title      = "Share of Interstate Spending Successfully Geocoded",
  subtitle   = "By county",
  legend_name = "Share of spending geocoded",
  caption = "Source: FMIS receipt-level data, interstate construction between 1950 and 2000. Grey = no projects; multi-county and unspecified-county projects excluded."
)

print(county_proj_map)
print(county_spend_map)

ggsave(file.path(output_dir, "map_county_pct_recpt_geocoded.png"),
       county_proj_map, width = 8, height = 5)
ggsave(file.path(output_dir, "map_county_pct_spending_geo.png"),
       county_spend_map, width = 8, height = 5)