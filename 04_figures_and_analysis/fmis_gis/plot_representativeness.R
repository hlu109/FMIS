sample_2015 <- plf_gis %>% filter(completion_year >= 2015)

state_xwalk <- usmap::us_map() %>%
  sf::st_drop_geometry() %>%
  dplyr::distinct(fips, abbr) %>%
  mutate(state_fips = as.numeric(fips))

# =============================================================
# State representativeness

rep_state <- sample_2015 %>%
  group_by(state_fips) %>%
  summarise(
    n_full    = n(),
    n_gis     = sum(has_gis),
    cost_full = sum(total_cost_mills),
    cost_gis  = sum(total_cost_mills[has_gis == 1]),
    .groups   = "drop"
  ) %>%
  mutate(
    share_proj_full = n_full    / sum(n_full),
    share_proj_gis  = n_gis     / sum(n_gis),
    share_cost_full = cost_full / sum(cost_full),
    share_cost_gis  = cost_gis  / sum(cost_gis)
  ) %>%
  inner_join(state_xwalk, by = "state_fips")

# scatter plot for sample share vs full share
state_rep_scatter <- function(data, x, y, title, subtitle, axis_unit, label, caption) {
  lim <- c(0, max(dplyr::pull(data, {{ x }}), dplyr::pull(data, {{ y }}), na.rm = TRUE))
  ggplot(data, aes({{ x }}, {{ y }})) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
    geom_point() +
    ggrepel::geom_text_repel(aes(label = {{label}}), size = 2.4, color = "grey30",
                             max.overlaps = 15,
                             segment.size = 0.2) +
    scale_x_continuous(labels = percent_format(accuracy = 1), limits = lim) +
    scale_y_continuous(labels = percent_format(accuracy = 1), limits = lim) +
    coord_equal() +
    labs(title = title, subtitle = subtitle,
         x = paste0("Share of all ", axis_unit, " in full sample"),
         y = paste0("Share of ", axis_unit, " in subsample with milemarkers"),
         caption = caption) +
    qje_theme()
}

state_rep_proj_scatter <- state_rep_scatter(
  rep_state, share_proj_full, share_proj_gis,
  title    = "State Representativeness of the Mile Markers GIS Subsample (# Projects)",
  subtitle = "FMIS Projects Completed 2015-2024",
  axis_unit = "projects",
  label = abbr,
  caption  = 
    "Each point is a state, with axis representing that state's share of projects
  in the respective full (all 2015-2024 FMIS data) or limited (has mile markers) sample. 
  Observations above the line are overrepresented
  in the \"has milemarker\" subsample; observations under the line are underrepresented." 
)

state_rep_spend_scatter <- state_rep_scatter(
  rep_state, share_cost_full, share_cost_gis,
  title    = "State Representativeness of the GIS Subsample (Spending)",
  subtitle = "FMIS Projects Completed 2015-2024",
  axis_unit = "spending",
  label = abbr,
  caption  = "Each point is a state, with axis representing that state's share of spending
  in the respective full (all 2015-2024 FMIS data) or limited (has mile markers) sample. 
  Observations above the line are overrepresented
  in the \"has milemarker\" subsample; observations under the line are underrepresented." 
)

# look at correlation between num. detail codes and % geocoded by state

corr_ncodes_gis_share <- ggplot(data = make_state_df(sample_2015), aes(x = avg_detail_codes, y = pct_gis, label = abbr)) + 
  geom_point() +
  ggrepel::geom_text_repel(size = 2.4, color = "grey30",
                           max.overlaps = 15,
                           segment.size = 0.2) +
  geom_smooth(method = "lm", se = F, linetype = "dashed", colour = "black") +
  labs(title = "Number of Detail Codes and\nShare of Projects Geocoded (State-level)",
       subtitle = "FMIS Projects Completed 2015-2024",
       x = "Mean Number of FHWA Improvement Type Codes",
       y = "Share of Projects with Mile Markers",
       caption = "Each point is a state, using summarized FMIS data from 2015 to 2024. The
      x-axis gives the average number of improvement type costs for all projects within a state;
       the y-axis gives the share of projects at the state-level that have mile marker data.") +
  qje_theme()

# =============================================================
# Construction-type representativeness

rep_type <- purrr::map_dfr(work_types, function(wt) {
  flag     <- sample_2015[[wt]] %in% 1          
  gis      <- sample_2015$has_gis == 1
  cost     <- sample_2015$total_cost_mills
  tibble(
    work_type       = wt,
    share_proj_full = mean(flag),
    share_proj_gis  = mean(flag[gis]),
    share_cost_full = sum(cost[flag])        / sum(cost),
    share_cost_gis  = sum(cost[flag & gis])  / sum(cost[gis])
  )
})

type_rep_bar <- function(data, full_col, gis_col, title, subtitle, y_lab, caption) {
  long <- data %>%
    select(work_type, full = {{ full_col }}, gis = {{ gis_col }}) %>%
    pivot_longer(c(full, gis), names_to = "sample", values_to = "share") %>%
    mutate(
      work_type = factor(work_type, levels = work_types, labels = work_type_labels),
      sample    = factor(sample, levels = c("full", "gis"),
                         labels = c("Full 2015-24 sample", "GIS subsample"))
    )
  ggplot(long, aes(x = work_type, y = share, fill = sample)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.65) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    scale_fill_manual(values = c("Full 2015-24 sample" = "grey65",
                                 "GIS subsample" = "#2c7fb8"), name = NULL) +
    labs(title = title, subtitle = subtitle, x = NULL, y = y_lab, caption = caption) +
    qje_theme() +
    theme(axis.text.x = element_text(angle = 30, hjust = 1))
}

type_rep_proj_bar <- type_rep_bar(
  rep_type, share_proj_full, share_proj_gis,
  title    = "Construction-Type Representativeness of the Mile Markers Subsample (Projects)",
  subtitle = "FMIS Projects Completed 2015-2024",
  y_lab    = "Share of projects flagged with type",
  caption  = paste(
    "Each pair of bars compares the share of projects flagged with a given work type in the",
    "full 2015-2024 FMIS sample versus the GIS subsample. Work types are not mutually exclusive, so",
    "shares do not sum to one."
  )
)

type_rep_spend_bar <- type_rep_bar(
  rep_type, share_cost_full, share_cost_gis,
  title    = "Construction-Type Representativeness of the Mile Markers Subsample (Spending)",
  subtitle = "FMIS Projects Completed 2015-2024",
  y_lab    = "Share of spending flagged with type",
  caption  = paste(
    "Each pair of bars compares the share of spending on projects flagged with a given work",
    "type in the full 2015-2024 FMIS sample versus the mile markers subsample. Work types are not mutually",
    "exclusive, so shares do not sum to one."
  )
)

# =============================================================
# full improvement labels

improvement_labels <- c(
  "0"  = "N/A",
  "1"  = "New Construction Roadway",
  "2"  = "4R - Reconstruction (Obsolete)",
  "3"  = "4R - Added Capacity",
  "4"  = "4R - No Added Capacity",
  "5"  = "4R - Maintenance Resurfacing",
  "6"  = "4R - Restoration & Rehabilitation",
  "7"  = "4R - Maintenance Relocation",
  "8"  = "Bridge New Construction",
  "9"  = "Bridge Replacement (Obsolete)",
  "10" = "Bridge Replacement - Added Capacity",
  "11" = "Bridge Replacement - No Added Capacity",
  "12" = "Bridge Rehabilitation (Obsolete)",
  "13" = "Bridge Rehabilitation - Added Capacity",
  "14" = "Bridge Rehabilitation - No Added Capacity",
  "15" = "Preliminary Engineering",
  "16" = "Right of Way",
  "17" = "Construction Engineering",
  "18" = "Planning",
  "19" = "Research",
  "20" = "Environmental Only",
  "21" = "Safety",
  "22" = "Rail/Hwy Crossing",
  "23" = "Transit",
  "24" = "Traffic Management/Engineering - HOV",
  "25" = "Vehicle Weight Enforcement Program",
  "26" = "Ferry Boats",
  "27" = "Administration",
  "28" = "Facilities for Pedestrians and Bicycles",
  "29" = "Acquisition of Scenic Easements and Scenic/Historic Sites",
  "30" = "Scenic or Historic Highway Programs",
  "31" = "Landscaping and Other Scenic Beautification",
  "32" = "Historic Preservation",
  "33" = "Rehabilitation/Operation of Historic Transportation Buildings etc.",
  "34" = "Preservation of Abandoned Railway Corridors",
  "35" = "Control and Removal of Outdoor Advertising",
  "36" = "Archaeological Planning & Research",
  "37" = "Mitigation of Water Pollution due to Highway Runoff",
  "38" = "Safety and Education for Peds/Bicyclists",
  "39" = "Establishment of Transportation Museums",
  "40" = "Special Bridge",
  "41" = "Youth Conservation Service",
  "42" = "Training",
  "43" = "Utilities",
  "44" = "Other",
  "45" = "Debt Service",
  "46" = "Design-Build Contract (Obsolete)",
  "47" = "Bridge Preventive Maintenance",
  "48" = "Bridge Protection",
  "49" = "Bridge Inspection and Bridge Related Training",
  "50" = "New Tunnel",
  "51" = "Tunnel Replacement",
  "52" = "Tunnel Rehabilitation",
  "53" = "Tunnel Preventive Maintenance",
  "54" = "Tunnel Protection",
  "55" = "Tunnel Inspection and Tunnel Related Training",
  "56" = "Other Asset Inspection",
  "57" = "Safety - Non Infrastructure",
  "58" = "Freight",
  "59" = "Bridge Resurfacing",
  "60" = "Highway Infrastructure Preventive Maintenance",
  "61" = "Routine Maintenance",
  "62" = "Operations",
  "63" = "Electric Vehicle & Charging Infrastructure",
  "64" = "Other Alternative Fuel Vehicles & Infrastructure",
  "65" = "Resilience Planning",
  "66" = "Resilience Improvement - Highway Project",
  "67" = "Resilience Improvement - Transit or Port Projects",
  "68" = "Resilience Improvement - Natural Infrastructure",
  "69" = "Community Resilience and Evacuation Routes",
  "70" = "At-Risk Coastal Infrastructure - Highway Project",
  "71" = "At-Risk Coastal Infrastructure - Transit or Port Projects",
  "72" = "At-Risk Coastal Infrastructure - Natural Infrastructure"
)

# denominators for the full sample and the GIS subsample
n_proj_full  <- nrow(sample_2015)
n_proj_gis   <- sum(sample_2015$has_gis == 1)
cost_all_full <- sum(sample_2015$total_cost_mills)
cost_all_gis  <- sum(sample_2015$total_cost_mills[sample_2015$has_gis == 1])

# one row per (project, improvement code)
code_long <- sample_2015 %>%
  mutate(.rid = row_number()) %>%
  select(.rid, has_gis, total_cost_mills, proj_improv_types) %>%
  mutate(code = str_split(proj_improv_types, ";")) %>%
  tidyr::unnest(code) %>%
  mutate(code = str_trim(code)) %>%
  filter(!code %in% c("", ".", "NA"), !is.na(code)) %>%
  distinct(.rid, code, .keep_all = TRUE)

# replicate above but with 70 codes
rep_code <- code_long %>%
  group_by(code) %>%
  summarise(
    n_full    = n(),
    n_gis     = sum(has_gis == 1),
    cost_full = sum(total_cost_mills),
    cost_gis  = sum(total_cost_mills[has_gis == 1]),
    .groups   = "drop"
  ) %>%
  mutate(
    share_proj_full = n_full    / n_proj_full,
    share_proj_gis  = n_gis     / n_proj_gis,
    share_cost_full = cost_full / cost_all_full,
    share_cost_gis  = cost_gis  / cost_all_gis,
    label           = dplyr::recode(code, !!!improvement_labels, .default = "Unknown code"),
    code_label      = paste0(code, " - ", label)
  ) %>%
  arrange(desc(n_full))

# bar for top-N improvement codes, ordered by `order_col`
code_rep_bar <- function(data, full_col, gis_col, order_col, n_top,
                         title, subtitle, y_lab, caption) {
  top <- data %>% slice_max({{ order_col }}, n = n_top, with_ties = FALSE)
  lvls <- top %>% arrange(desc({{ order_col }})) %>% pull(code_label)
  long <- top %>%
    select(code_label, full = {{ full_col }}, gis = {{ gis_col }}) %>%
    pivot_longer(c(full, gis), names_to = "sample", values_to = "share") %>%
    mutate(
      code_label = factor(str_wrap(code_label, 24), levels = str_wrap(lvls, 24)),
      sample     = factor(sample, levels = c("full", "gis"),
                          labels = c("Full 2015-24 sample", "GIS subsample"))
    )
  ggplot(long, aes(x = code_label, y = share, fill = sample)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.65) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    scale_fill_manual(values = c("Full 2015-24 sample" = "grey65",
                                 "GIS subsample" = "#2c7fb8"), name = NULL) +
    labs(title = title, subtitle = subtitle, x = NULL, y = y_lab, caption = caption) +
    qje_theme() +
    theme(axis.text.x = element_text(angle = 40, hjust = 1, size = 7))
}

code_rep_proj_bar <- code_rep_bar(
  rep_code, share_proj_full, share_proj_gis, order_col = n_full, n_top = 20,
  title    = "Improvement-Code Representativeness of the Mile Markers Subsample (Projects)",
  subtitle = "Top 20 improvement codes by project count, FMIS Projects Completed 2015-2024",
  y_lab    = "Share of projects flagged with code",
  caption  = paste(
    "The 10 improvement codes carried by the most projects in the full 2015-2024 sample.",
    "Each pair of bars compares the share of projects flagged with that code in the full sample",
    "versus the mile markers subsample. proj_improv_types lists every code a project carries, so codes are",
    "not mutually exclusive and shares do not sum to one."
  )
)

code_rep_proj_bar_50 <- code_rep_bar(
  rep_code, share_proj_full, share_proj_gis, order_col = n_full, n_top = 50,
  title    = "Improvement-Code Representativeness of the Mile Markers Subsample (Projects)",
  subtitle = "Top 10 improvement codes by project count, FMIS Projects Completed 2015-2024",
  y_lab    = "Share of projects flagged with code",
  caption  = paste(
    "The 10 improvement codes carried by the most projects in the full 2015-2024 sample.",
    "Each pair of bars compares the share of projects flagged with that code in the full sample",
    "versus the mile markers subsample. proj_improv_types lists every code a project carries, so codes are",
    "not mutually exclusive and shares do not sum to one."
  )
)

code_rep_spend_bar <- code_rep_bar(
  rep_code, share_cost_full, share_cost_gis, order_col = cost_full, n_top = 20,
  title    = "Improvement-Code Representativeness of the Mile Markers Subsample (Spending)",
  subtitle = "Top 20 improvement codes by spending, FMIS Projects Completed 2015-2024",
  y_lab    = "Share of spending flagged with code",
  caption  = paste(
    "The 10 improvement codes accounting for the most spending in the full 2015-2024 sample.",
    "Project cost is attributed to every code the project carries. Each pair of bars compares the",
    "share of spending flagged with that code in the full sample versus the mile markers subsample. Codes",
    "are not mutually exclusive, so shares do not sum to one."
  )
)

# scatter plot for codes in the style of states

code_rep_proj_scatter <- state_rep_scatter(
  rep_code, share_proj_full, share_proj_gis,
  title    = "Representativeness by Code of the Mile Markers GIS Subsample (# Projects)",
  subtitle = "FMIS Projects Completed 2015-2024",
  axis_unit = "projects",
  label = code,
  caption  = 
    "Each point is a FHWA improvement type code, with axis representing that state's share of projects
  in the respective full (all 2015-2024 FMIS data) or limited (has mile markers) sample. 
  Observations above the line are overrepresented
  in the \"has milemarker\" subsample; observations under the line are underrepresented." 
)

code_rep_spend_scatter <- state_rep_scatter(
  rep_code, share_cost_full, share_cost_gis,
  title    = "Representativeness by Code of the Mile Markers GIS Subsample (Spending)",
  subtitle = "FMIS Projects Completed 2015-2024",
  axis_unit = "projects",
  label = code,
  caption  = 
    "Each point is a FHWA improvement type code, with axis representing that state's share of projects
  in the respective full (all 2015-2024 FMIS data) or limited (has mile markers) sample. 
  Observations above the line are overrepresented
  in the \"has milemarker\" subsample; observations under the line are underrepresented." 
)

