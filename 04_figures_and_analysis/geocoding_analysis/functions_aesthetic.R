# Had Claude create these aesthetics; based off of QJE standards
qje_common <- function(base_size = 11) {
  theme(
    legend.title  = element_text(size = base_size, hjust = 0.5),
    legend.text   = element_text(size = base_size - 2),
    plot.title    = element_text(face = "bold", hjust = 0.5,
                                 size = base_size + 3,
                                 margin = margin(b = 4)),
    plot.subtitle = element_text(hjust = 0.5, color = "grey30",
                                 size = base_size - 1,
                                 margin = margin(b = 6)),
    plot.caption  = ggtext::element_textbox_simple(
                                 hjust = 0, halign = 0,
                                 size = base_size - 3, color = "grey40",
                                 lineheight = 1.15,
                                 width = grid::unit(1, "npc"),
                                 margin = margin(t = 10)),
    plot.margin   = margin(10, 10, 10, 10)
  )
}

# Map theme: theme_void strips coordinate axes (correct for choropleths) and
# puts a wide horizontal color bar at the bottom.
qje_theme_map <- function(base_size = 11) {
  theme_void(base_size = base_size) +
    qje_common(base_size) +
    theme(
      legend.position   = "bottom",
      legend.key.width  = unit(2.2, "cm"),
      legend.key.height = unit(0.35, "cm")
    )
}

# Chart theme: theme_classic KEEPS the x/y axes, ticks, and titles, so it works
# for histograms, bar charts, scatter/line plots, etc. Use this instead of the
# map theme for anything with real coordinate axes.
qje_theme <- function(base_size = 11) {
  theme_classic(base_size = base_size) +
    qje_common(base_size) +
    theme(
      axis.line   = element_line(color = "grey20", linewidth = 0.3),
      axis.ticks  = element_line(color = "grey20", linewidth = 0.3),
      axis.title  = element_text(size = base_size, color = "grey20"),
      axis.text   = element_text(size = base_size - 2, color = "grey20"),
      axis.title.x = element_text(margin = margin(t = 6)),
      axis.title.y = element_text(margin = margin(r = 6)),
      legend.position = "right",
      panel.grid.major.y = element_line(color = "grey90", linewidth = 0.3)
    )
}

# shared sequential fill scale (percent-formatted)
qje_fill <- function(legend_name) {
  scale_fill_distiller(
    palette   = "Blues",
    direction = 1,
    labels    = percent_format(accuracy = 1),
    limits    = c(0, 1),
    name      = legend_name,
    na.value  = "grey90",
    guide     = guide_colorbar(title.position = "top", title.hjust = 0.5,
                               ticks.colour = "grey30", frame.colour = "grey30")
  )
}

# Append "N = X units." to a caption, given a count and singular/plural labels.
append_n_to_caption <- function(caption, n_units, unit_singular, unit_plural) {
  unit_label <- if (n_units == 1) unit_singular else unit_plural
  paste0(caption, " N = ", format(n_units, big.mark = ","), " ", unit_label, ".")
}

# state choropleth
make_state_map <- function(data, fill_var, title, subtitle, legend_name, caption) {
  n_units <- sum(!is.na(dplyr::pull(data, {{ fill_var }})))
  ggplot(data) +
    geom_sf(aes(fill = {{ fill_var }}), color = "white", linewidth = 0.15) +
    qje_fill(legend_name) +
    coord_sf(datum = NA) +
    labs(title = title, subtitle = subtitle,
         caption = append_n_to_caption(caption, n_units, "state", "states")) +
    qje_theme_map()
}

make_state_map_decade <- function(data, states, fill_var, title, subtitle, legend_name, caption, time_var) {
  n_units <- sum(!is.na(dplyr::pull(data, {{ fill_var }})))
  ggplot() +
    geom_sf(data = states, fill = "grey90", color = NA) +                    
    geom_sf(data = data, aes(fill = {{ fill_var }}), color = NA) +           
    geom_sf(data = states, fill = NA, color = "white", linewidth = 0.2) +   
    qje_fill(legend_name) +
    coord_sf(datum = NA) +
    labs(title = title, subtitle = subtitle, caption = caption) +
    qje_theme_map() +
    facet_wrap(vars({{ time_var }}))
}

# county choropleth (county fill + state borders overlaid for legibility)
make_county_map <- function(data, states, fill_var, title, subtitle, legend_name, caption) {
  n_units <- sum(!is.na(dplyr::pull(data, {{ fill_var }})))
  ggplot() +
    geom_sf(data = data, aes(fill = {{ fill_var }}), color = NA) +
    geom_sf(data = states, fill = NA, color = "white", linewidth = 0.2) +
    qje_fill(legend_name) +
    coord_sf(datum = NA) +
    labs(title = title, subtitle = subtitle,
         caption = append_n_to_caption(caption, n_units, "county", "counties")) +
    qje_theme_map()
}