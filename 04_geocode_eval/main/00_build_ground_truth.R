# ==============================================================================
# Entry point: load NHPN once, build and cache ground-truth segments for every available source.
# ==============================================================================
library(sf)
library(dplyr)

# resolve this script's own directory so `helpers/paths.R` can be sourced regardless of the caller's working directory
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
this_dir <- if (length(script_arg) > 0) dirname(sub("^--file=", "", script_arg)) else "."

source(file.path(this_dir, "..", "helpers", "paths.R"))
source(file.path(this_dir, "..", "helpers", "ground_truth.R"))

nhpn_path <- file.path(raw_data_dir, "NHPN", "NTAD_National_Highway_Planning_Network_5862765175788916660.geojson")
nhpn <- sf::st_read(nhpn_path, quiet = TRUE) %>%
  to_metric_crs() %>%
  dplyr::mutate(ROUTE_ID = stringr::str_trim(ROUTE_ID))

out_dir <- file.path(geocode_eval_dir, "ground_truth")

fmis_gis_path <- file.path(intermediate_dir, "project_level_FMIS_w_GIS.dta")
message("Building fmis_gis ground truth from ", fmis_gis_path)
fmis_gis_gt <- build_ground_truth("fmis_gis", nhpn, fmis_gis_path = fmis_gis_path, out_dir = out_dir)
message(
  "fmis_gis: ", nrow(fmis_gis_gt), " scoped projects, ",
  round(100 * mean(fmis_gis_gt$is_covered), 1), "% matched to an NHPN route."
)

pr511_path <- file.path(intermediate_dir, "PR_511", "pr511_cty_rt_single_openyr_ever.dta")
message("Attempting pr511 ground truth (expected to stub out; see TODO(pr511 route crosswalk))")
pr511_gt <- build_ground_truth("pr511", nhpn, pr511_singleopen_path = pr511_path, out_dir = out_dir)
if (is.null(pr511_gt)) {
  message("pr511 ground truth not built (blocked — see message above).")
}

message("Ground truth build complete. Output: ", out_dir)
