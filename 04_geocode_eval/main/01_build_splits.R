# ==============================================================================
# Entry point: build val/test/train split tables for every available ground-truth source and write them to CSV.
# ==============================================================================
library(sf)
library(dplyr)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
this_dir <- if (length(script_arg) > 0) dirname(sub("^--file=", "", script_arg)) else "."

source(file.path(this_dir, "..", "helpers", "paths.R"))
source(file.path(this_dir, "..", "helpers", "splits.R"))

gt_dir <- file.path(geocode_eval_dir, "ground_truth")
splits_dir <- file.path(geocode_eval_dir, "splits")

fmis_gis_gpkg <- file.path(gt_dir, "fmis_gis.gpkg")
if (file.exists(fmis_gis_gpkg)) {
  fmis_gis_gt <- sf::st_read(fmis_gis_gpkg, quiet = TRUE) %>% sf::st_drop_geometry()

  # cluster = route for fmis_gis, per the locked design decision (README "How we split the data")
  cluster_df <- fmis_gis_gt %>%
    filter(is_covered) %>%
    transmute(
      projectid, cluster_key = gis_routeid_clean,
      state_fips, completion_year, county_fips,
      across(starts_with("has_"))
    )

  fmis_gis_splits <- build_splits("fmis_gis", cluster_df, val_frac = 0.5)
  write.csv(fmis_gis_splits, file.path(splits_dir, "fmis_gis_splits.csv"), row.names = FALSE)
  message(
    "fmis_gis splits: ", nrow(fmis_gis_splits), " projects across ",
    length(unique(fmis_gis_splits$cluster_key)), " route clusters (",
    sum(fmis_gis_splits$bucket == "val"), " val, ",
    sum(fmis_gis_splits$bucket == "test"), " test)."
  )
} else {
  message("Skipping fmis_gis splits: ", fmis_gis_gpkg, " not found — run main/00_build_ground_truth.R first.")
}

# pr511 splits are blocked on the same crosswalk as pr511 ground truth (see helpers/ground_truth.R TODO)
pr511_gpkg <- file.path(gt_dir, "pr511.gpkg")
if (file.exists(pr511_gpkg)) {
  pr511_gt <- sf::st_read(pr511_gpkg, quiet = TRUE) %>% sf::st_drop_geometry()
  cluster_df <- pr511_gt %>% transmute(projectid, cluster_key = paste(county_fips, route, sep = "_"))
  pr511_splits <- build_splits("pr511", cluster_df, val_frac = 0.5)
  write.csv(pr511_splits, file.path(splits_dir, "pr511_splits.csv"), row.names = FALSE)
  message("pr511 splits: ", nrow(pr511_splits), " projects.")
} else {
  message("Skipping pr511 splits: ", pr511_gpkg, " not found (pr511 ground truth is stubbed — see TODO(pr511 route crosswalk)).")
}

message("Splits build complete. Output: ", splits_dir)
