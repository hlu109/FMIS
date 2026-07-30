# quick figure on per capita spending 

iija_apportion <- read_xlsx(file.path(data_dir, "fmis_mile_markers", "apportionments_2022_2026.xlsx"),
                            sheet = "FY 2021 & Est FY 2022-FY 2026",
                            range = "B15:E65",
                            col_names = c("state", "app_2021", "blank", "app_2022")) %>% select(-blank) %>% 
  mutate(iija_shock = (app_2022 - app_2021),
         iija_shock_pct = iija_shock / app_2021,
         abbr = state.abb[match(state, state.name)]) %>% 
  inner_join(
    state_pop <- read_csv(file.path(data_dir, "fmis_mile_markers", "state_pop_timeseries_fred.csv")) %>% 
      filter(year == 2021) %>% select(-year),
    by = join_by(abbr == state)
  ) %>% 
  mutate(iija_shock_pc = iija_shock / pop,
         app_2021_pc = app_2021 / pop)

capital_outlays_pc <- read.csv("C:/Users/fm557/YLS Dropbox/Finn Meffe/Funding Uncertainty/Data/Raw/gov_finance_state_data.csv") %>% 
  select(st_fips = FIPS_Code_State,
         year = Year4,
         total_highway_co = Total_Highways_Cap_Out,
         total_highway_exp = Total_Highways_Tot_Exp) %>% 
  filter(year == 2021) %>% inner_join(state_xwalk, by = join_by(st_fips == state_fips)) %>% select(-st_fips) %>% 
  inner_join(state_pop <- read_csv(file.path(data_dir, "fmis_mile_markers", "state_pop_timeseries_fred.csv")) %>% 
               filter(year == 2021) %>% select(-year),
             by = join_by(abbr == state)) %>% 
  mutate(highway_co_pc = total_highway_co*1000 / pop, highway_exp_pc = total_highway_exp*1000 / pop)

pc_figures_for_plot <- inner_join(
  iija_apportion, capital_outlays_pc, by = "abbr"
)

ggplot(data = iija_apportion, aes(x = abbr, y = app_2021_pc, label = abbr)) +
  geom_col(fill = "steelblue") +
  geom_text(vjust = -0.5, size = 3) + 
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Per Capita Federal Highway Apportionments, 2021",
       subtitle = "Federal Highway Association Data",
       x = "State", y = "2021 Apportionments per Capita") +
  qje_theme() +
  theme(
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank()
  )

ggplot(data = pc_figures_for_plot, aes(x = abbr, y = highway_exp_pc, label = abbr)) +
  geom_col(fill = "steelblue") +
  geom_text(vjust = -0.5, size = 3) + 
  scale_y_continuous(expand = expansion(mult = c(0, 0.05))) +
  labs(title = "Per Capita Highway Expenditure, 2019",
       subtitle = "Government Finance Census Data",
       x = "State", y = "2019 Highway Expenditure per Capita") +
  qje_theme() +
  theme(
    axis.text.x = element_blank(),
    axis.ticks.x = element_blank()
  )

ggplot(data = pc_figures_for_plot, aes(x = app_2021_pc, y = highway_exp_pc, label = abbr)) +
  geom_point() +
  geom_text(size = 2.4, color = "grey30", nudge_x = 15, nudge_y = 15) +
  geom_smooth(method = "lm", se = F, linetype = "dashed") +
  labs(title = "Federal Apportionments per Capita and Highway Expenditure per Capita in 2021",
       subtitle = "Sample From FHWA and US Census Data",
       x = "Federal Apportionments per Capita",
       y = "Highway Expenditure per Capita") +
  qje_theme()
