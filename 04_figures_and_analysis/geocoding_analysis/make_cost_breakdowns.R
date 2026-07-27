maj_counties <- plf_counties %>%
  filter(pct_spending_geo >= 0.75) %>%
  pull(county_fips)

cost_types <- c("new_construction_cost", "reconstruction_cost", "rehabilitation_cost", "maintenance_cost", "pe_cost", "row_cost", "other_cost")

# clean up function for county strings
clean_counties <- function(cc) {
  cc <- str_trim(cc)
  cc <- cc[!is.na(cc) & cc != ""]
  cc <- str_pad(cc, 5, side = "left", pad = "0")
  cc[str_sub(cc, 3, 5) != "999"]
}

# two vars: only_maj (project counties are all majority geocoded) and any_maj (at least one county is 75%+ geocoded)
plf_maj_flags <- plf_join %>%
  mutate(
    county_list = map(str_split(as.character(county_fips), ";"), clean_counties),
    n_counties  = map_int(county_list, length),
    n_maj       = map_int(county_list, ~ sum(.x %in% maj_counties)),
    only_maj    = n_counties > 0 & n_maj == n_counties,
    any_maj     = n_maj > 0
  )

# make function of previous code
make_costs_breakdown <- function(df, subset_flag, subset_label) {
  df %>%
    mutate(maj_spending = ifelse({{ subset_flag }}, 1, 0)) %>%
    group_by(maj_spending) %>%
    summarise(across(c(total_cost_mills, new_construction_cost, reconstruction_cost, rehabilitation_cost, maintenance_cost, pe_cost, row_cost),
                     sum, na.rm = T), .groups = "drop") %>%
    mutate(other_cost = total_cost_mills - new_construction_cost - reconstruction_cost - rehabilitation_cost - maintenance_cost - pe_cost - row_cost) %>%
    pivot_longer(c(new_construction_cost, reconstruction_cost, rehabilitation_cost, maintenance_cost, pe_cost, row_cost, other_cost),
                 names_to = "cost_type", values_to = "cost") %>%
    mutate(pct = 100 * cost / total_cost_mills,
           maj_spending = factor(maj_spending, labels = c("All other projects", subset_label)),
           cost_type = factor(cost_type, levels = cost_types,
                              labels = c("New construction", "Reconstruction", "Rehabilitation", "Maintenance", "PE", "ROW", "Other")))
}

plf_counties_costs_only <- make_costs_breakdown(
  plf_maj_flags, only_maj, "Only in 75%+ geocoded counties")

plf_counties_costs_any <- make_costs_breakdown(
  plf_maj_flags, any_maj, "≥1 county 75%+ geocoded")

cost_break_bar_only <- ggplot(data = plf_counties_costs_only,
                              aes(x = maj_spending, y = pct, fill = cost_type)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct)),
            position = position_stack(vjust = 0.5), size = 2.5) +
  labs(x = NULL, y = "% of total cost", fill = "Cost type",
       title = "Cost Composition: Projects Only in\n75%+ Geocoded Counties",
       caption = paste0(
         "Right hand column includes all projects in which every county had 75%+ of its
       spending geocoded. Left hand column includes all other projects. Other represents the difference
       between total costs and the cost types included in this analysis.",
         " ", nrow(plf_maj_flags), " total projects, ", 
         nrow(plf_maj_flags %>% filter(only_maj == F)), " LHS projects, ",
         nrow(plf_maj_flags %>% filter(only_maj == T)), " RHS projects")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

cost_break_bar_any <- ggplot(data = plf_counties_costs_any,
                             aes(x = maj_spending, y = pct, fill = cost_type)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct)),
            position = position_stack(vjust = 0.5), size = 2.5) +
  labs(x = NULL, y = "% of total cost", fill = "Cost type",
       title = "Cost Composition: Projects With\n≥1 County 75%+ Geocoded",
       caption = paste0(
         "Right hand column includes all projects in which at least one of its counties had 75%+ of its
       spending geocoded. Left hand column includes all other projects. Other represents the difference
       between total costs and the cost types included in this analysis.",
         " ", nrow(plf_maj_flags), " total projects, ", 
         nrow(plf_maj_flags %>% filter(any_maj == F)), " LHS projects, ",
         nrow(plf_maj_flags %>% filter(any_maj == T)), " RHS projects")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

# extra thing for zach - 75%+ county projects, ungeocoded spending 

make_costs_breakdown_adj <- function(df, subset_flag) {
  df %>%
    mutate(maj_spending = ifelse({{ subset_flag }}, 1, 0)) %>%
    group_by(maj_spending) %>%
    summarise(across(c(total_cost_mills, new_construction_cost, reconstruction_cost, rehabilitation_cost, maintenance_cost, pe_cost, row_cost),
                     sum, na.rm = T), .groups = "drop") %>%
    mutate(other_cost = total_cost_mills - new_construction_cost - reconstruction_cost - rehabilitation_cost - maintenance_cost - pe_cost - row_cost) %>%
    pivot_longer(c(new_construction_cost, reconstruction_cost, rehabilitation_cost, maintenance_cost, pe_cost, row_cost, other_cost),
                 names_to = "cost_type", values_to = "cost") %>%
    mutate(pct = 100 * cost / total_cost_mills,
           cost_type = factor(cost_type, levels = cost_types,
                              labels = c("New construction", "Reconstruction", "Rehabilitation", "Maintenance", "PE", "ROW", "Other")))
}

cost_break_ungeocoded_df <- make_costs_breakdown_adj(plf_maj_flags %>% 
  filter(geocoded == 0, any_maj == 1), any_maj)

cost_break_ungeocoded <- ggplot(data = cost_break_ungeocoded_df,
                             aes(x = factor(maj_spending), y = pct, fill = cost_type)) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct)),
            position = position_stack(vjust = 0.5), size = 2.5) +
  labs(x = NULL, y = "% of total cost", fill = "Cost type",
       title = "Cost Composition: Ungeocoded Projects With\n≥1 County 75%+ Geocoded",
       caption = paste0(
         "Sample is every project within a 75%+ geocoded county that was not geocoded itself, as well as being within
         a county that has only 1 year of PR511 data ever.",
         " ", nrow(plf_maj_flags %>% filter(geocoded == 0, any_maj == 1)), " total projects.")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

# how do geocoding rates vary across projects based on cost types

plf_geo <- plf_maj_flags %>%
  mutate(other_cost = total_cost_mills - new_construction_cost - reconstruction_cost - rehabilitation_cost - maintenance_cost - pe_cost - row_cost)

pct_geo <- function(df) sum(df$geocoded, na.rm = TRUE) / nrow(df)
n_geo   <- function(df) sum(!is.na(df$geocoded))
# share of spending (not projects) that is geocoded
spend_geo <- function(df) {
  sum(df$total_cost_mills[df$geocoded == 1], na.rm = TRUE) /
    sum(df$total_cost_mills, na.rm = TRUE)
}

create_by_type <- function(data) { map_dfr(cost_types, function(ct) {
  others <- setdiff(cost_types, ct)
  d <- data %>%
    mutate(
      has_this   = .data[[ct]] > 0,
      standalone = .data[[ct]] > 0 &
        rowSums(across(all_of(others)), na.rm = TRUE) == 0
    )
  subsets <- list(filter(d, !has_this), filter(d, has_this), filter(d, standalone))
  tibble(
    cost_type = ct,
    group = c("Cost type not present", "Cost type present", "Standalone cost type"),
    pct_geocoded = map_dbl(subsets, pct_geo),
    pct_spending_geocoded = map_dbl(subsets, spend_geo),
    n = map_int(subsets, n_geo)
  )
}) %>%
  # Wald 95% CI for a proportion: p +/- 1.96 * sqrt(p(1-p)/n)
  mutate(
    se = sqrt(pct_geocoded * (1 - pct_geocoded) / n),
    ci_lower = pmax(0, pct_geocoded - 1.96 * se),
    ci_upper = pmin(1, pct_geocoded + 1.96 * se),
    group = factor(group, levels = c("Cost type not present", "Cost type present", "Standalone cost type")),
    cost_type = factor(cost_type, levels = cost_types,
                       labels = c("New construction", "Reconstruction", "Rehabilitation", "Maintenance", "PE", "ROW", "Other")),
    pct_not_geocoded = 1 - pct_geocoded,
    pct_spending_not_geocoded = 1 - pct_spending_geocoded
  )
}

geo_by_type <- create_by_type(plf_geo)
geo_by_type_75any <- create_by_type(plf_geo %>% filter(any_maj == T))

geo_by_type_bar <- ggplot(geo_by_type,
                          aes(x = cost_type, y = pct_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  #geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
  #              position = position_dodge(width = 0.8), width = 0.2) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_geocoded), #y = ci_upper
                ),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Geocoded", fill = NULL,
       title = "Geocoding Rate by Receipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of projects geocoded by their cost composition: standalone
       projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.",
         nrow(plf_geo), "project", "projects")
       ) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

ngeo_by_type_bar <- ggplot(geo_by_type,
                          aes(x = cost_type, y = pct_not_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  #geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
  #              position = position_dodge(width = 0.8), width = 0.2) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_not_geocoded), #y = ci_upper
  ),
  position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Not Geocoded", fill = NULL,
       title = "Ungeocoded Rate by Receipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of projects geocoded by their cost composition: standalone
       projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.",
         nrow(plf_geo), "project", "projects")
  ) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

# same breakdown, but weighting by spending (share of dollars geocoded)
# rather than by project count
geo_spending_by_type_bar <- ggplot(geo_by_type,
                                   aes(x = cost_type, y = pct_spending_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_spending_geocoded)),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Spending Geocoded", fill = NULL,
       title = "Geocoded Spending Rate by\nReceipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of project spending geocoded by the project's
       cost composition: standalone projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.",
         nrow(plf_geo), "project", "projects")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

ngeo_spending_by_type_bar <- ggplot(geo_by_type,
                                   aes(x = cost_type, y = pct_spending_not_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_spending_not_geocoded)),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Spending Not Geocoded", fill = NULL,
       title = "Ungeocoded Spending Rate by\nReceipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of project spending geocoded by the project's
       cost composition: standalone projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.",
         nrow(plf_geo), "project", "projects")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

geo_by_type_bar_75any <- ggplot(geo_by_type_75any,
                          aes(x = cost_type, y = pct_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  #geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
  #              position = position_dodge(width = 0.8), width = 0.2) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_geocoded), #y = ci_upper
  ),
  position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Geocoded", fill = NULL,
       title = "Geocoding Rate by Receipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of projects geocoded by their cost composition: standalone
       projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.
         Sample is all projects in which at least one of its counties had 75%+ of its
       spending geocoded.",
         nrow(plf_geo %>% filter(any_maj == T)), "project", "projects")
  ) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

ngeo_by_type_bar_75any <- ggplot(geo_by_type_75any,
                           aes(x = cost_type, y = pct_not_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  #geom_errorbar(aes(ymin = ci_lower, ymax = ci_upper),
  #              position = position_dodge(width = 0.8), width = 0.2) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_not_geocoded), #y = ci_upper
  ),
  position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Not Geocoded", fill = NULL,
       title = "Ungeocoded Rate by Receipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of projects geocoded by their cost composition: standalone
       projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.
       Sample is all projects in which at least one of its counties had 75%+ of its
       spending geocoded.",
         nrow(plf_geo %>% filter(any_maj == T)), "project", "projects")
  ) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

# same breakdown, but weighting by spending (share of dollars geocoded)
# rather than by project count
geo_spending_by_type_bar_75any <- ggplot(geo_by_type_75any,
                                   aes(x = cost_type, y = pct_spending_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_spending_geocoded)),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Spending Geocoded", fill = NULL,
       title = "Geocoded Spending Rate by\nReceipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of project spending geocoded by the project's
       cost composition: standalone projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.
       Sample is all projects in which at least one of its counties had 75%+ of its
       spending geocoded.",
         nrow(plf_geo %>% filter(any_maj == T)), "project", "projects")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

ngeo_spending_by_type_bar_75any <- ggplot(geo_by_type_75any,
                                    aes(x = cost_type, y = pct_spending_not_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f", 100 * pct_spending_not_geocoded)),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_discrete(guide = guide_axis(n.dodge = 2)) +
  labs(x = NULL, y = "% Spending Not Geocoded", fill = NULL,
       title = "Ungeocoded Spending Rate by\nReceipt Cost Composition",
       caption = append_n_to_caption(
         "Columns represent the share of project spending geocoded by the project's
       cost composition: standalone projects have only that cost type, whereas present simply denotes existence.
       Other represents the difference between total costs and the cost types included in this analysis.
       Sample is all projects in which at least one of its counties had 75%+ of its
       spending geocoded.",
         nrow(plf_geo %>% filter(any_maj == T)), "project", "projects")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

#=============================================================
# Structure-type breakdowns (road / bridge / tunnel)

structure_types  <- c("road_cost", "bridge_cost", "tunnel_cost")
structure_labels <- c("Road", "Bridge", "Tunnel")

create_by_structure <- function(data) {
  map_dfr(structure_types, function(ct) {
    others <- setdiff(structure_types, ct)
    d <- data %>%
      mutate(
        has_this   = .data[[ct]] > 0,
        standalone = .data[[ct]] > 0 &
          rowSums(across(all_of(others)), na.rm = TRUE) == 0
      )
    subsets <- list(filter(d, has_this), filter(d, standalone))
    tibble(
      structure_type = ct,
      group = c("Structure type is\npresent in project", "Structure type is\n the only type found\n in project"),
      pct_geocoded = map_dbl(subsets, pct_geo),
      pct_spending_geocoded = map_dbl(subsets, spend_geo),
      n = map_int(subsets, n_geo)
    )
  }) %>%
    mutate(
      group = factor(group, levels = c("Structure type is\npresent in project", "Structure type is\n the only type found\n in project")),
      structure_type = factor(structure_type, levels = structure_types,
                              labels = structure_labels)
    )
}

structure_geo <- create_by_structure(plf_geo)

# share of projects geocoded, by structure type
structure_geo_by_type_bar <- ggplot(structure_geo,
                          aes(x = structure_type, y = pct_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_geocoded)),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = NULL, y = "% Geocoded", fill = NULL,
       title = "Geocoding Rate by Structure Type",
       caption = paste0(
         "Columns represent the share of projects geocoded by the structure type found in the project.
         The sample is all projects in which the project county has a single year of PR511 data ever. ",
         nrow(plf_geo %>% filter(road_cost > 0 | bridge_cost > 0 | tunnel_cost > 0)), " total projects. ",
         nrow(plf_geo %>% filter(road_cost > 0)), " projects with roadway construction, ",
         nrow(plf_geo %>% filter(bridge_cost > 0)), " projects with bridge construction, ",
         nrow(plf_geo %>% filter(tunnel_cost > 0)), " projects with tunnel construction.")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()

# share of spending geocoded, by structure type
structure_geo_spending_by_type_bar <- ggplot(structure_geo,
                          aes(x = structure_type, y = pct_spending_geocoded, fill = group)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * pct_spending_geocoded)),
            position = position_dodge(width = 0.8), vjust = -0.5, size = 2.5) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = NULL, y = "% Spending Geocoded", fill = NULL,
       title = "Geocoded Spending Rate by Structure Type",
       caption = paste0(
         "Columns represent the share of spending geocoded by the structure type found in the project.
         The sample is all projects in which the project county has a single year of PR511 data ever. ",
         nrow(plf_geo %>% filter(road_cost > 0 | bridge_cost > 0 | tunnel_cost > 0)), " total projects. ",
         nrow(plf_geo %>% filter(road_cost > 0)), " projects with roadway construction, ",
         nrow(plf_geo %>% filter(bridge_cost > 0)), " projects with bridge construction, ",
         nrow(plf_geo %>% filter(tunnel_cost > 0)), " projects with tunnel construction.")) +
  scale_fill_brewer(palette = "Blues") +
  qje_theme()
