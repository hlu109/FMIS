state_proj_hist <- ggplot(data = plf_states, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                     bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of State-level Geocoding Rates",
       subtitle = "Share of interstate receipts successfully geocoded",
       x = "Share of receipts geocoded", y = "Percentage") +
  qje_theme()

state_spend_hist <- ggplot(data = plf_states, mapping = aes(x = pct_spending_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of State-level Geocoding Rates",
       subtitle = "Share of interstate spending successfully geocoded",
       x = "Share of spending geocoded", y = "Percentage") +
  qje_theme()

county_proj_hist <- ggplot(data = plf_counties, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of County-level Geocoding Rates",
       subtitle = "Share of interstate receipts successfully geocoded",
       x = "Share of receipts geocoded", y = "Percentage") +
  qje_theme()

county_spend_hist <- ggplot(data = plf_counties, mapping = aes(x = pct_spending_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of County-level Geocoding Rates",
       subtitle = "Share of interstate spending successfully geocoded",
       x = "Share of spending geocoded", y = "Percentage") +
  qje_theme()

proj_recpt_hist <- ggplot(data = plf_projects, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of Project-level Geocoding Rates",
       subtitle = "Share of interstate receipts successfully geocoded",
       x = "Share of receipts geocoded", y = "Percentage") +
  qje_theme()

proj_spend_hist <- ggplot(data = plf_projects, mapping = aes(x = pct_spending_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of Project-level Geocoding Rates",
       subtitle = "Share of interstate spending successfully geocoded",
       x = "Share of spending geocoded", y = "Percentage") +
  qje_theme()

print(state_proj_hist)
print(state_spend_hist)
print(county_proj_hist)
print(county_spend_hist)
print(proj_recpt_hist)
print(proj_spend_hist)

ggsave(file.path(output_dir, "hist_state_pct_recpt_geocoded.png"),
       state_proj_hist, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_state_pct_spending_geocoded.png"),
       state_spend_hist, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_county_pct_recpt_geocoded.png"),
       county_proj_hist, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_county_pct_spending_geocoded.png"),
       county_spend_hist, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_proj_pct_recpt_geocoded.png"),
       proj_recpt_hist, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_proj_pct_spending_geocoded.png"),
       proj_spend_hist, width = 8, height = 5)

state_proj_hist_oneyear <- ggplot(data = plf_states_oneyear, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of State-level Geocoding Rates",
       subtitle = "Share of interstate receipts successfully geocoded in counties with one year of PR511 data ever",
       x = "Share of receipts geocoded", y = "Percentage") +
  qje_theme()

state_spend_hist_oneyear <- ggplot(data = plf_states_oneyear, mapping = aes(x = pct_spending_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of State-level Geocoding Rates",
       subtitle = "Share of interstate spending successfully geocoded in counties with one year of PR511 data ever",
       x = "Share of spending geocoded", y = "Percentage") +
  qje_theme()

county_proj_hist_oneyear <- ggplot(data = plf_counties_oneyear, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of County-level Geocoding Rates",
       subtitle = "Share of interstate receipts successfully geocoded in counties with one year of PR511 data ever",
       x = "Share of receipts geocoded", y = "Percentage") +
  qje_theme()

county_spend_hist_oneyear <- ggplot(data = plf_counties_oneyear, mapping = aes(x = pct_spending_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of County-level Geocoding Rates",
       subtitle = "Share of interstate spending successfully geocoded in counties with one year of PR511 data ever",
       x = "Share of spending geocoded", y = "Percentage") +
  qje_theme()

proj_recpt_hist_oneyear <- ggplot(data = plf_projects_oneyear, mapping = aes(x = pct_proj_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of Project-level Geocoding Rates",
       subtitle = "Share of interstate receipts successfully geocoded in counties with one year of PR511 data ever",
       x = "Share of receipts geocoded", y = "Percentage") +
  qje_theme()

proj_spend_hist_oneyear <- ggplot(data = plf_projects_oneyear, mapping = aes(x = pct_spending_geo)) +
  geom_histogram(aes(y = after_stat(count) / sum(after_stat(count))),
                 bins = 25, fill = "#4292c6", color = "white", linewidth = 0.2) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  scale_y_continuous(labels = percent_format()) +
  labs(title = "Distribution of Project-level Geocoding Rates",
       subtitle = "Share of interstate spending successfully geocoded in counties with one year of PR511 data ever",
       x = "Share of spending geocoded", y = "Percentage") +
  qje_theme()

print(state_proj_hist_oneyear)
print(state_spend_hist_oneyear)
print(county_proj_hist_oneyear)
print(county_spend_hist_oneyear)
print(proj_recpt_hist_oneyear)
print(proj_spend_hist_oneyear)

ggsave(file.path(output_dir, "hist_state_pct_recpt_geocoded_oneyear.png"),
       state_proj_hist_oneyear, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_state_pct_spending_geocoded_oneyear.png"),
       state_spend_hist_oneyear, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_county_pct_recpt_geocoded_oneyear.png"),
       county_proj_hist_oneyear, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_county_pct_spending_geocoded_oneyear.png"),
       county_spend_hist_oneyear, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_proj_pct_recpt_geocoded_oneyear.png"),
       proj_recpt_hist_oneyear, width = 8, height = 5)
ggsave(file.path(output_dir, "hist_proj_pct_spending_geocoded_oneyear.png"),
       proj_spend_hist_oneyear, width = 8, height = 5)