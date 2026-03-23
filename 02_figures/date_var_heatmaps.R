# ==============================================================================
# This script generates heatmaps to analyze date variables in FMIS. 
# ==============================================================================
# Setup 
library(haven)
library(dplyr)
library(readr)
library(tidyverse)
library(stringr)
library(ggplot2)
# ==============================================================================
user <- Sys.info()[["user"]]

if (user == "andersonkovesci") {
  project_root <- "/Users/andersonkovesci/Dropbox/FHWA cost data"
  output_dir <- file.path(project_root, "Output", "Andy")
  intermediate_data_dir <- file.path(project_root, "Data", "Intermediate")
} else if (user == "hl2266") {
  project_root <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
  output_dir <- file.path(project_root, "Output", "Hannah")
  intermediate_data_dir <- file.path(project_root, "Data", "Intermediate")
} else {
  stop("Set your user paths")
}

source(file.path(getwd(), "utils/fig_utils.R"))

# check that output folders exist and create them if not 
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(intermediate_data_dir, recursive = TRUE, showWarnings = FALSE)
# ==============================================================================
# figure helper functions
add_contrast_text_color <- function(data, value_col, threshold_frac = 0.6) {
  # Adds `label_color` = white/black depending on whether value is "high"
  v <- data[[value_col]]
  mx <- suppressWarnings(max(v, na.rm = TRUE))
  cutoff <- threshold_frac * mx
  data$label_color <- ifelse(is.na(v), "black", ifelse(v >= cutoff, "white", "black"))
  data
}

heatmap_base_size <- 16
heatmap_cell_text_size <- 4.2

heatmap_theme <- function() {
  theme_minimal(base_size = heatmap_base_size) +
    theme(
      plot.title = element_text(size = heatmap_base_size + 4),
      axis.title = element_text(size = heatmap_base_size + 2),
      # axis.text = element_text(size = heatmap_base_size),
      legend.title = element_text(size = heatmap_base_size + 1),
      legend.text = element_text(size = heatmap_base_size),
      panel.grid = element_blank(),
      panel.border = element_rect(color = "grey60", fill = NA, linewidth = 0.4)
    )
}

# ==============================================================================
# message("Loading data.")
datevars <- c("authsprdate", "authpedate", "authrowdate", "authconstdate", "authotherdate", "completedate", "latestpaymentdate", "finalvoucherdate", "transactiondate", "lastactiondate")
datevar_labels <- c(
  authsprdate   = "SPR auth. date",
  authpedate    = "PE auth. date",
  authrowdate   = "ROW auth. date",
  authconstdate = "Construction auth. date",
  authotherdate = "Other auth. date",
  completedate  = "Complete date",
  latestpaymentdate = "Latest payment date",
  finalvoucherdate = "Final voucher date",
  transactiondate = "Transaction date",
  lastactiondate = "Last action date"
)
datevar_levels <- unname(datevar_labels[datevars])

receipt_path <- file.path(intermediate_data_dir, "receipt_level_FMIS_lite.dta")
project_path <- file.path(intermediate_data_dir, "project_level_FMIS_lite.dta")

df_receipt <- haven::read_dta(receipt_path) %>%
  select(all_of(c(datevars, "total_cost_mills", "completion_year", "interstate_syscode", "detail_improvementtype"))) %>%
  mutate(detail_improvementtype = haven::as_factor(detail_improvementtype)) %>%
  rename(year = completion_year)

df_project <- haven::read_dta(project_path) %>%
  select(all_of(c(datevars, "total_cost_mills", "completion_year", "interstate_syscode"))) %>%
  rename(year = completion_year)

# merge in cpi and compute adjusted total cost
cpi_path <- file.path(intermediate_data_dir, "CPI_2025.dta")
cpi_df <- haven::read_dta(cpi_path)
df_receipt <- df_receipt %>%
  left_join(cpi_df, by = "year") %>%
  mutate(total_cost_mills_adj = total_cost_mills / cpi)
df_project <- df_project %>%
  left_join(cpi_df, by = "year") %>%
  mutate(total_cost_mills_adj = total_cost_mills / cpi)


# ==============================================================================
# Analysis/Figures 
# ==============================================================================

# assess missingness of data =====
message("Assessing missingness of data.")
# Count and percent non-missing for each date variable
date_tbl <- df_project %>%
  pivot_longer(all_of(datevars), names_to = "varname", values_to = "value") %>%
  mutate(varname = dplyr::recode(varname, !!!datevar_labels)) %>%
  mutate(varname = factor(varname, levels = datevar_levels)) %>%
  group_by(varname) %>%
  summarise(
    count_nonmissing = sum(!is.na(value)),
    pct_nonmissing = round(100 * sum(!is.na(value)) / n(), 2),
    pct_nonmissing_2025_dollar_wgt = round(
      100 * sum(total_cost_mills_adj[!is.na(value)], na.rm = TRUE) /
            sum(total_cost_mills_adj, na.rm = TRUE),
      2
    ),
    .groups = "drop"
  ) %>%
  rename(
    `Date Variable` = varname,
    `Count Non-Missing` = count_nonmissing,
    `Pct Non-Missing` = pct_nonmissing,
    `2025-Dollar Weighted Pct Non-Missing` = pct_nonmissing_2025_dollar_wgt
  ) %>%
  arrange(`Date Variable`)
write_csv(date_tbl, file.path(output_dir, "date_vars_nonmissing.csv"))


# same but only for interstate projects 
date_tbl_interstate <- df_project %>%
  filter(interstate_syscode == 1) %>%
  pivot_longer(all_of(datevars), names_to = "varname", values_to = "value") %>%
  mutate(varname = dplyr::recode(varname, !!!datevar_labels)) %>%
  mutate(varname = factor(varname, levels = datevar_levels)) %>%
  group_by(varname) %>%
  summarise(
    count_nonmissing = sum(!is.na(value)),
    pct_nonmissing = round(100 * sum(!is.na(value)) / n(), 2),
    pct_nonmissing_2025_dollar_wgt = round(
      100 * sum(total_cost_mills_adj[!is.na(value)], na.rm = TRUE) /
            sum(total_cost_mills_adj, na.rm = TRUE),
      2
    ),
    .groups = "drop"
  ) %>%
  rename(
    `Date Variable` = varname,
    `Count Non-Missing` = count_nonmissing,
    `Pct Non-Missing` = pct_nonmissing,
    `2025-Dollar Weighted Pct Non-Missing` = pct_nonmissing_2025_dollar_wgt
  ) %>%
  arrange(`Date Variable`)
write_csv(date_tbl_interstate, file.path(output_dir, "date_vars_nonmissing_interstate.csv"))

# ==============================================================================

# co-occurrence of date variables =====
message("Assessing co-occurrence of date variables.")
# Co-occurrence matrix: counts and pcts of projects with non-missing values for both date variables
nm_mat <- df_project %>%
  select(all_of(datevars)) %>%
  mutate(across(everything(), ~ !is.na(.x))) %>%
  as.matrix()

cooccur_counts <- crossprod(nm_mat) # (j,k) = sum_i 1[date_j present & date_k present]
colnames(cooccur_counts) <- unname(datevar_labels[datevars])
rownames(cooccur_counts) <- unname(datevar_labels[datevars])

write_csv(as.data.frame(cooccur_counts) %>% tibble::rownames_to_column("Date Variable"),
          file.path(output_dir, "datevars_cooccurrence_counts.csv"))

n_proj <- nrow(df_project)
cooccur_pct <- if (n_proj > 0) {
  round(100 * cooccur_counts / n_proj, 2)
} else {
  cooccur_counts * NA_real_
}
colnames(cooccur_pct) <- unname(datevar_labels[datevars])
rownames(cooccur_pct) <- unname(datevar_labels[datevars])

write_csv(as.data.frame(cooccur_pct) %>% tibble::rownames_to_column("Date Variable"),
          file.path(output_dir, "datevars_cooccurrence_pct.csv"))

# Plot heatmap (counts)
cooccur_long <- as.data.frame(as.table(cooccur_counts))
names(cooccur_long) <- c("date_x", "date_y", "count")
cooccur_long <- cooccur_long %>%
  mutate(label = format(count, big.mark = ",", scientific = FALSE))
cooccur_long <- add_contrast_text_color(cooccur_long, "count")

p <- ggplot(cooccur_long, aes(x = date_x, y = date_y, fill = count)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = label, color = label_color), size = heatmap_cell_text_size, show.legend = FALSE) +
  scale_color_identity() +
  scale_fill_gradient(low = "white", high = "blue") +
  coord_equal() +
  labs(
    title = "Co-occurrence of Date Variables \n(Count of Projects)",
    x = "Date Variable",
    y = "Date Variable",
    fill = "Count"
  ) +
  heatmap_theme() +
  theme(
    axis.text = element_text(size = heatmap_base_size),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  )
ggsave(
  filename = file.path(output_dir, "datevars_cooccurrence_heatmap_counts.png"),
  plot = p,
  width = 10,
  height = 8,
  dpi = 300
)

# Plot heatmap (percent)
cooccur_pct_long <- as.data.frame(as.table(cooccur_pct))
names(cooccur_pct_long) <- c("date_x", "date_y", "percent")
cooccur_pct_long <- cooccur_pct_long %>%
  mutate(label = sprintf("%.1f", percent))
cooccur_pct_long <- add_contrast_text_color(cooccur_pct_long, "percent")

p <- ggplot(cooccur_pct_long, aes(x = date_x, y = date_y, fill = percent)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = label, color = label_color), size = heatmap_cell_text_size, show.legend = FALSE) +
  scale_color_identity() +
  scale_fill_gradient(low = "white", high = "blue") +
  coord_equal() +
  labs(
    title = "Co-occurrence of Date Variables \n(Percent of FMIS Projects)",
    x = "Date Variable",
    y = "Date Variable",
    fill = "Percent",
    caption = "Percent is calculated using all FMIS projects."
  ) +
  heatmap_theme() +
  theme(
    axis.text = element_text(size = heatmap_base_size),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  )

ggsave(
  filename = file.path(output_dir, "datevars_cooccurrence_heatmap_pct.png"),
  plot = p,
  width = 10,
  height = 8,
  dpi = 300
)

# Duplicate the percent co-occurrence heatmap for interstate only
df_inter <- df_project %>% filter(interstate_syscode == 1)
nm_mat_inter <- df_inter %>%
  select(all_of(datevars)) %>%
  mutate(across(everything(), ~ !is.na(.x))) %>%
  as.matrix()

cooccur_counts_inter <- crossprod(nm_mat_inter)
colnames(cooccur_counts_inter) <- unname(datevar_labels[datevars])
rownames(cooccur_counts_inter) <- unname(datevar_labels[datevars])

n_proj_inter <- nrow(df_inter)
cooccur_pct_inter <- if (n_proj_inter > 0) {
  round(100 * cooccur_counts_inter / n_proj_inter, 2)
} else {
  cooccur_counts_inter * NA_real_
}
colnames(cooccur_pct_inter) <- unname(datevar_labels[datevars])
rownames(cooccur_pct_inter) <- unname(datevar_labels[datevars])

write_csv(as.data.frame(cooccur_counts_inter) %>% tibble::rownames_to_column("Date Variable"),
          file.path(output_dir, "datevars_cooccurrence_counts_interstate.csv"))
write_csv(as.data.frame(cooccur_pct_inter) %>% tibble::rownames_to_column("Date Variable"),
          file.path(output_dir, "datevars_cooccurrence_pct_interstate.csv"))

cooccur_pct_long_inter <- as.data.frame(as.table(cooccur_pct_inter))
names(cooccur_pct_long_inter) <- c("date_x", "date_y", "percent")
cooccur_pct_long_inter <- cooccur_pct_long_inter %>%
  mutate(label = sprintf("%.1f", percent))
cooccur_pct_long_inter <- add_contrast_text_color(cooccur_pct_long_inter, "percent")

p <- ggplot(cooccur_pct_long_inter, aes(x = date_x, y = date_y, fill = percent)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = label, color = label_color), size = heatmap_cell_text_size, show.legend = FALSE) +
  scale_color_identity() +
  scale_fill_gradient(low = "white", high = "blue") +
  coord_equal() +
  labs(
    title = "Co-occurrence of Date Variables \n(Percent of Interstate FMIS Projects)",
    x = "Date Variable",
    y = "Date Variable",
    fill = "Percent",
    caption = wrap_figure_notes(
      c("Percent is calculated using interstate FMIS projects only.", 
      "Interstate projects are those that have at least one receipt with an interstate federal-aid system code."), 80)
  ) +
  heatmap_theme() +
  theme(
    axis.text = element_text(size = heatmap_base_size),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  )
ggsave(
  filename = file.path(output_dir, "datevars_cooccurrence_heatmap_pct_interstate.png"),
  plot = p,
  width = 10,
  height = 8,
  dpi = 300
)

# ==============================================================================

# look into existence of dates by project type ====
message("Assessing existence of dates by project type.")
projtype_long <- df_receipt %>%
  select(all_of(c("detail_improvementtype", datevars))) %>%
  pivot_longer(all_of(datevars), names_to = "datevar", values_to = "value") %>%
  mutate(present = !is.na(value))

# Counts per (improvement type, datevar)
projtype_date_counts_long <- projtype_long %>%
  group_by(detail_improvementtype, datevar) %>%
  summarise(count = sum(present), .groups = "drop") %>%
  mutate(datevar = dplyr::recode(datevar, !!!datevar_labels)) %>%
  rename(`Improvement Type` = detail_improvementtype)
projtype_date_counts_long <- projtype_date_counts_long %>%
  mutate(datevar = factor(datevar, levels = datevar_levels))

projtype_type_totals <- df_receipt %>%
  count(detail_improvementtype, name = "n_receipts") %>%
  rename(`Improvement Type` = detail_improvementtype, `Total projects` = n_receipts)

projtype_date_counts_wide <- projtype_date_counts_long %>%
  tidyr::pivot_wider(names_from = datevar, values_from = count, values_fill = 0) %>%
  left_join(projtype_type_totals, by = "Improvement Type")

  write_csv(
    projtype_date_counts_wide,
    file.path(output_dir, "datevars_improvementtype_cooccurrence_counts.csv")
  )

# Percent within improvement type per (improvement type, datevar)
projtype_date_pct_long <- projtype_date_counts_long %>%
  left_join(projtype_type_totals %>% select(`Improvement Type`, n_receipts = `Total projects`), by = "Improvement Type") %>%
  mutate(percent = round(100 * count / n_receipts, 2)) %>%
  select(-n_receipts)

projtype_date_pct_wide <- projtype_date_pct_long %>%
  select(`Improvement Type`, datevar, percent) %>%
  tidyr::pivot_wider(names_from = datevar, values_from = percent, values_fill = 0)

write_csv(
  projtype_date_pct_wide,
  file.path(output_dir, "datevars_improvementtype_cooccurrence_pct.csv")
)

# Heatmap (counts)
projtype_date_counts_long <- projtype_date_counts_long %>%
  mutate(label = format(count, big.mark = ",", scientific = FALSE))
projtype_date_counts_long <- add_contrast_text_color(projtype_date_counts_long, "count")

p <- ggplot(projtype_date_counts_long, aes(x = datevar, y = `Improvement Type`, fill = count)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = label, color = label_color), size = heatmap_cell_text_size, show.legend = FALSE) +
    scale_color_identity() +
    scale_fill_gradient(low = "white", high = "blue") +
  scale_x_discrete(limits = datevar_levels) +
  scale_y_discrete(limits = function(x) rev(x)) +
  labs(
    title = "Occurrence of Date Variables by Improvement Type \n(Count of Receipts)",
    x = "Date Variable",
    y = "Improvement Type",
    fill = "Count"
  ) +
  heatmap_theme() +
  theme(
    plot.title.position = "plot",
    plot.title = element_text(hjust = 0),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  )

ggsave(
  filename = file.path(output_dir, "datevars_improvementtype_cooccurrence_counts_heatmap.png"),
  plot = p,
  width = 10,
  height = 16,
  dpi = 300
)

# Heatmap (percent)
projtype_date_pct_long <- projtype_date_pct_long %>%
  mutate(label = sprintf("%.0f", percent))
projtype_date_pct_long <- add_contrast_text_color(projtype_date_pct_long, "percent")

p <- ggplot(projtype_date_pct_long, aes(x = datevar, y = `Improvement Type`, fill = percent)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = label, color = label_color), size = heatmap_cell_text_size, show.legend = FALSE) +
    scale_color_identity() +
    scale_fill_gradient(low = "white", high = "blue") +
  scale_x_discrete(limits = datevar_levels) +
  scale_y_discrete(limits = function(x) rev(x)) +
  labs(
    title = "Occurrence of Date Variables by Improvement Type \n(Percent of Receipts)",
    x = "Date Variable",
    y = "Improvement Type",
    fill = "Percent",
    caption = "Percent is calculated out of the receipts within each improvement type."
  ) +
  heatmap_theme() +
  theme(
    plot.title.position = "plot",
    plot.title = element_text(hjust = 0),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  )

ggsave(
  filename = file.path(output_dir, "datevars_improvementtype_cooccurrence_pct_heatmap.png"),
  plot = p,
  width = 10,
  height = 16,
  dpi = 300
)


# ==============================================================================

# look into date timelines =====

# For each pair of date variables, compute:
# count of projects where y_date > x_date (strictly greater).
# and leave the diagonal empty (NA).
message("Computing y_date > x_date matrix.")

as_numeric_date <- function(x) {
  if (inherits(x, "Date")) return(as.numeric(x))
  if (is.numeric(x)) return(as.numeric(x))
  if (is.factor(x)) x <- as.character(x)
  if (is.character(x)) return(as.numeric(lubridate::mdy(x, quiet = TRUE)))
  as.numeric(x)
}

date_num <- lapply(datevars, function(v) as_numeric_date(df_project[[v]]))
n_vars <- length(datevars)

counts_gt <- matrix(NA_real_, nrow = n_vars, ncol = n_vars,
                     dimnames = list(datevar_levels, datevar_levels))
signed_counts <- counts_gt

for (iy in seq_len(n_vars)) {
  yval <- date_num[[iy]]
  for (ix in seq_len(n_vars)) {
    if (iy == ix) next
    xval <- date_num[[ix]]
    keep <- !is.na(yval) & !is.na(xval) & (yval > xval)
    c_val <- sum(keep)
    counts_gt[iy, ix] <- c_val
    # positive (blue) should correspond to the "upper" triangle
    signed_counts[iy, ix] <- if (iy < ix) c_val else -c_val
  }
}

write_csv(
  as.data.frame(counts_gt) %>% tibble::rownames_to_column("date_y"),
  file.path(output_dir, "datevars_seq_counts.csv")
)

order_long <- as.data.frame(as.table(signed_counts))
names(order_long) <- c("date_y", "date_x", "signed_count")

max_pos <- suppressWarnings(max(order_long$signed_count, na.rm = TRUE))
max_neg_abs <- suppressWarnings(max(abs(order_long$signed_count[order_long$signed_count < 0]), na.rm = TRUE))

order_long <- order_long %>%
  mutate(
    count = ifelse(is.na(signed_count), NA_real_, abs(signed_count)),
    # Asymmetric scaling: negatives and positives each use their own max.
    scaled_fill = dplyr::case_when(
      is.na(signed_count) ~ NA_real_,
      signed_count > 0 & max_pos > 0 ~ signed_count / max_pos,
      signed_count < 0 & max_neg_abs > 0 ~ signed_count / max_neg_abs,
      TRUE ~ 0
    ),
    label = ifelse(is.na(count), NA_character_,
                    format(round(count / 1000, 2), nsmall = 2, trim = TRUE)),
    label_color = ifelse(
      is.na(count),
      "black",
      ifelse(abs(scaled_fill) >= 0.6, "white", "black")
    ),
    date_x = factor(date_x, levels = datevar_levels),
    date_y = factor(date_y, levels = datevar_levels)
  )

p_order <- ggplot(
  order_long, aes(x = date_x, y = date_y, fill = scaled_fill)) +
  geom_tile(color = "white", linewidth = 0.2) +
  geom_text(aes(label = label, color = label_color), size = heatmap_cell_text_size, angle = 45, show.legend = FALSE) +
  scale_color_identity() +
  scale_fill_gradient2(
    low = "blue",
    mid = "white",
    high = "red",
    midpoint = 0,
    limits = c(-1, 1),
    na.value = "white"
  ) +
  coord_equal() +
  guides(fill = "none") +
  labs(
    title = "Projects with Y-date later than X-date \n(thousands of projects)",
    x = "X-date variable",
    y = "Y-date variable",
    # fill = "Y-date > X-date"
  ) +
  heatmap_theme() +
  theme(
    axis.text = element_text(size = heatmap_base_size),
    axis.text.x = element_text(angle = 45, hjust = 1, vjust = 1)
  )

ggsave(
  filename = file.path(output_dir, "datevars_seq_heatmap.png"),
  plot = p_order,
  width = 10,
  height = 8,
  dpi = 300
)

message("**********\nScript complete.\n**********")