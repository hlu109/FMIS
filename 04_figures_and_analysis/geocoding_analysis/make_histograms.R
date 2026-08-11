state_proj_hist <- ggplot(data = plf_states, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(
    aes(y = after_stat(count) / sum(after_stat(count))),
    bins = 20,
    fill = "#4292c6",
    color = "white",
    linewidth = 0.2
  ) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title = "Distribution of State-level Geocoding Rates",
    subtitle = "Share of interstate projects successfully geocoded",
    x = "Share of projects geocoded",
    y = "Percentage",
    caption = append_n_to_caption(
      "",
      sum(!is.na(plf_states$pct_proj_geo)),
      "state",
      "states"
    )
  ) +
  qje_theme()

state_spend_hist <- ggplot(
  data = plf_states,
  mapping = aes(x = pct_spending_geo)
) +
  geom_histogram(
    aes(y = after_stat(count) / sum(after_stat(count))),
    bins = 20,
    fill = "#4292c6",
    color = "white",
    linewidth = 0.2
  ) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title = "Distribution of State-level Geocoding Rates",
    subtitle = "Share of interstate spending successfully geocoded",
    x = "Share of spending geocoded",
    y = "Percentage",
    caption = append_n_to_caption(
      "",
      sum(!is.na(plf_states$pct_spending_geo)),
      "state",
      "states"
    )
  ) +
  qje_theme()

county_proj_hist <- ggplot(
  data = plf_counties,
  mapping = aes(x = pct_proj_geo)
) +
  geom_histogram(
    aes(y = after_stat(count) / sum(after_stat(count))),
    bins = 20,
    fill = "#4292c6",
    color = "white",
    linewidth = 0.2
  ) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title = "Distribution of County-level Geocoding Rates",
    subtitle = "Share of interstate projects successfully geocoded",
    x = "Share of projects geocoded",
    y = "Percentage",
    caption = append_n_to_caption(
      "",
      sum(!is.na(plf_counties$pct_proj_geo)),
      "county",
      "counties"
    )
  ) +
  qje_theme()

county_spend_hist <- ggplot(
  data = plf_counties,
  mapping = aes(x = pct_spending_geo)
) +
  geom_histogram(
    aes(y = after_stat(count) / sum(after_stat(count))),
    bins = 20,
    fill = "#4292c6",
    color = "white",
    linewidth = 0.2
  ) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(
    title = "Distribution of County-level Geocoding Rates",
    subtitle = "Share of interstate spending successfully geocoded",
    x = "Share of spending geocoded",
    y = "Percentage",
    caption = append_n_to_caption(
      "",
      sum(!is.na(plf_counties$pct_spending_geo)),
      "county",
      "counties"
    )
  ) +
  qje_theme()

#=================================
# By decade figures (similar to the state maps before)

plf_counties_decade <- plf_join %>%
  filter(
    !is.na(county_fips),
    county_fips != "",
    !str_detect(county_fips, ";")
  ) %>%
  mutate(
    county_fips = str_pad(
      as.character(county_fips),
      5,
      side = "left",
      pad = "0"
    ),
    decade = paste0((year %/% 10) * 10, "-", ((year %/% 10) * 10) + 9)
  ) %>%
  filter(str_sub(county_fips, 3, 5) != "999") %>%
  group_by(county_fips, decade) %>%
  summarise(
    n_projects = n(),
    n_geocoded = sum(geocoded, na.rm = T),
    total_spending = sum(total_cost_mills, na.rm = T),
    total_geo_spending = sum(total_cost_mills[geocoded == 1], na.rm = T),
    .groups = "drop"
  ) %>%
  mutate(
    pct_proj_geo = n_geocoded / n_projects,
    pct_spending_geo = total_geo_spending / total_spending
  )

make_county_hist_decade <- function(
  data,
  geo_var,
  title,
  subtitle,
  x_lab,
  time_var
) {
  n_units <- sum(!is.na(dplyr::pull(data, {{ geo_var }})))
  ggplot(data, aes(x = {{ geo_var }})) +
    geom_histogram(
      aes(y = after_stat(count) / sum(after_stat(count))),
      bins = 20,
      fill = "#4292c6",
      color = "white",
      linewidth = 0.2
    ) +
    scale_x_continuous(labels = percent_format(accuracy = 1)) +
    scale_y_continuous(labels = percent_format()) +
    labs(title = title, subtitle = subtitle, x = x_lab, y = "Percentage", ) +
    qje_theme() +
    facet_wrap(vars({{ time_var }}))
}

county_proj_hist_decade <- make_county_hist_decade(
  plf_counties_decade,
  pct_proj_geo,
  title = "Distribution of County-level Geocoding Rates",
  subtitle = "Share of interstate projects successfully geocoded, by decade",
  x_lab = "Share of projects geocoded",
  time_var = decade
)

county_spend_hist_decade <- make_county_hist_decade(
  plf_counties_decade,
  pct_spending_geo,
  title = "Distribution of County-level Geocoding Rates",
  subtitle = "Share of interstate spending successfully geocoded, by decade",
  x_lab = "Share of spending geocoded",
  time_var = decade
)

print(county_proj_hist_decade)
print(county_spend_hist_decade)

ggsave(
  file.path(output_dir, "hist_county_pct_proj_geocoded_by_decade.png"),
  county_proj_hist_decade,
  width = 8,
  height = 5
)
ggsave(
  file.path(output_dir, "hist_county_pct_spending_geocoded_by_decade.png"),
  county_spend_hist_decade,
  width = 8,
  height = 5
)

# state_proj_hist_oneyear <- ggplot(data = plf_states_oneyear, mapping = aes(x = pct_proj_geo)) +
#   geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
#                  bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
#   scale_x_continuous(labels = percent_format(accuracy = 1)) +
#   scale_y_continuous(labels = percent_format()) +
#   labs(title = "Distribution of State-level Geocoding Rates",
#        subtitle = "Share of interstate projects successfully geocoded in counties with one year of PR511 data ever",
#        x = "Share of projects geocoded", y = "Percentage") +
#   qje_theme()
#
# state_spend_hist_oneyear <- ggplot(data = plf_states_oneyear, mapping = aes(x = pct_spending_geo)) +
#   geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
#                  bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
#   scale_x_continuous(labels = percent_format(accuracy = 1)) +
#   scale_y_continuous(labels = percent_format()) +
#   labs(title = "Distribution of State-level Geocoding Rates",
#        subtitle = "Share of interstate spending successfully geocoded in counties with one year of PR511 data ever",
#        x = "Share of spending geocoded", y = "Percentage") +
#   qje_theme()
#
# county_proj_hist_oneyear <- ggplot(data = plf_counties_oneyear, mapping = aes(x = pct_proj_geo)) +
#   geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
#                  bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
#   scale_x_continuous(labels = percent_format(accuracy = 1)) +
#   scale_y_continuous(labels = percent_format()) +
#   labs(title = "Distribution of County-level Geocoding Rates",
#        subtitle = "Share of interstate projects successfully geocoded in counties with one year of PR511 data ever",
#        x = "Share of projects geocoded", y = "Percentage") +
#   qje_theme()
#
# county_spend_hist_oneyear <- ggplot(data = plf_counties_oneyear, mapping = aes(x = pct_spending_geo)) +
#   geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
#                  bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
#   scale_x_continuous(labels = percent_format(accuracy = 1)) +
#   scale_y_continuous(labels = percent_format()) +
#   labs(title = "Distribution of County-level Geocoding Rates",
#        subtitle = "Share of interstate spending successfully geocoded in counties with one year of PR511 data ever",
#        x = "Share of spending geocoded", y = "Percentage") +
#   qje_theme()
#
#
# print(state_proj_hist_oneyear)
# print(state_spend_hist_oneyear)
# print(county_proj_hist_oneyear)
# print(county_spend_hist_oneyear)
#
# ggsave(file.path(output_dir, "hist_state_pct_proj_geocoded_oneyear.png"),
#        state_proj_hist_oneyear, width = 8, height = 5)
# ggsave(file.path(output_dir, "hist_state_pct_spending_geocoded_oneyear.png"),
#        state_spend_hist_oneyear, width = 8, height = 5)
# ggsave(file.path(output_dir, "hist_county_pct_proj_geocoded_oneyear.png"),
#        county_proj_hist_oneyear, width = 8, height = 5)
# ggsave(file.path(output_dir, "hist_county_pct_spending_geocoded_oneyear.png"),
#        county_spend_hist_oneyear, width = 8, height = 5)
