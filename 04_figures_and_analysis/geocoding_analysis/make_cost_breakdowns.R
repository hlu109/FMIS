maj_counties <- plf_counties %>%
  filter(pct_spending_geo >= 0.75) %>% 
  pull(county_fips)

plf_counties_costs <- plf_join %>%
  mutate(maj_spending = ifelse(
    sprintf("%05d", as.numeric(county_fips)) %in% maj_counties, 1, 0
  )) %>% 
  group_by(maj_spending) %>% 
  summarise(across(c(total_cost_mills, new_construction_cost, pe_cost, row_cost), sum, na.rm=T)) %>% 
  mutate(other_cost = total_cost_mills - new_construction_cost - pe_cost - row_cost) %>%
  pivot_longer(c(new_construction_cost, pe_cost, row_cost, other_cost),
               names_to = "cost_type", values_to = "cost") %>%
  mutate(pct = 100 * cost / total_cost_mills,
         maj_spending = factor(maj_spending, labels = c("All other counties", "75%+ Spending Geocoded")))

plf_counties_costs_oneyear <- plf_join %>%
  filter(sprintf("%05d", as.numeric(county_fips)) %in% one_pr511_year_counties) %>% 
  mutate(maj_spending = ifelse(
    sprintf("%05d", as.numeric(county_fips)) %in% maj_counties, 1, 0
  )) %>% 
  group_by(maj_spending) %>% 
  summarise(across(c(total_cost_mills, new_construction_cost, pe_cost, row_cost), sum, na.rm=T)) %>% 
  mutate(other_cost = total_cost_mills - new_construction_cost - pe_cost - row_cost) %>%
  pivot_longer(c(new_construction_cost, pe_cost, row_cost, other_cost),
               names_to = "cost_type", values_to = "cost") %>%
  mutate(pct = 100 * cost / total_cost_mills,
         maj_spending = factor(maj_spending, labels = c("All other counties", "75%+ Spending Geocoded")))

cost_break_bar <- ggplot(data = plf_counties_costs, aes(x = maj_spending, y = pct, fill = cost_type)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct)),
            position = position_stack(vjust = 0.5), size = 3) +
  labs(x = NULL, y = "% of total cost", fill = "Cost type") +
  qje_theme()


cost_break_bar_oneyear <- ggplot(data = plf_counties_costs_oneyear, aes(x = maj_spending, y = pct, fill = cost_type)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct)),
            position = position_stack(vjust = 0.5), size = 3) +
  labs(x = NULL, y = "% of total cost", fill = "Cost type") +
  qje_theme()

print(cost_break_bar)
print(cost_break_bar_oneyear)

