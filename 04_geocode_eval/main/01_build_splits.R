# ==============================================================================
# Build val/test/train split tables for every available ground-truth source and write the row IDs to CSV.
# ==============================================================================
# Setup 
library(dplyr)
library(haven)

user <- Sys.info()[["user"]]
if (user == "hl2266") {
  # # hannah - handle docker vs dropbox paths 
  # if (grepl("docker", getwd(), ignore.case = TRUE)) {
  #   project_root <- "C:/Users/hl2266/project_dockers/fmis"
  # } else {
  #   project_root <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
  # }
  project_root <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
  data_dir <- file.path(project_root, "Data")
  raw_data_dir <- file.path(data_dir, "Raw")
  intermediate_dir <- file.path(data_dir, "Intermediate")
} else {
  stop("Set your user paths.")
}

source(file.path(getwd(), "utils", "geo_utils.R"))
source(file.path(getwd(), "04_geocode_eval", "helpers", "splits.R"))
# ==============================================================================

geocode_eval_dir <- file.path(data_dir, "Intermediate", "geocode_eval")
gt_dir <- file.path(geocode_eval_dir, "ground_truth")
splits_dir <- file.path(geocode_eval_dir, "splits")
dir.create(gt_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(splits_dir, recursive = TRUE, showWarnings = FALSE)


# ==============================================================================
# PR511 with one open year per county x route cell
# ==============================================================================
pr511_intermediate <- file.path(intermediate_dir, "PR_511")
pr511_cty_rt_path <- file.path(pr511_intermediate, "pr511_cty_rt_single_openyr_ever.dta")
pr511_chained_path <- file.path(pr511_intermediate, "PR511_hubbardmazzeo_chained.dta")

pr511_cty_rt <- haven::read_dta(pr511_cty_rt_path)

# assert sample size is stable  
stopifnot(nrow(pr511_cty_rt) == 511)

# merge back to the unfiltered PR-511 data to recover open_year for stratification
pr511_chained <- haven::read_dta(pr511_chained_path) %>%
  select(st, county_fips, route, open_year) %>%
  distinct(st, county_fips, route, .keep_all = TRUE)  # single_openyr_ever guarantees one distinct year per cell

pr511_cluster_df <- pr511_cty_rt %>%
  left_join(pr511_chained, by = c("st", "county_fips", "route")) %>%
  mutate(
    projectid = paste(county_fips, route, sep = "_"),
    cluster_key = projectid,
    state_fips = st,
    open_year_decade = (open_year %/% 10) * 10
  )

# assert sample size is stable  
stopifnot(nrow(pr511_cluster_df) == 511)

pr511_splits <- build_splits_stratified(
  "pr511", pr511_cluster_df, strata_cols = c("state_fips"), val_frac = 0.5
) # don't intentionally stratify by open_year_decade because it makes the state stratification too lumpy – but the results split pretty well along decade anyway

# merge back with PR-511 data to get original state/route/county variables 
pr511_splits <- pr511_splits %>%
  select(projectid, split) %>%
  left_join(pr511_cluster_df, by = "projectid") %>%
  select("state_fips", "county_fips", "route", "split", "open_year_decade", "open_year")

write.csv(pr511_splits, file.path(splits_dir, "pr511_splits.csv"), row.names = FALSE)
message("pr511 splits: ", nrow(pr511_splits), " county x route cells.")

message("Splits build complete. Output: ", splits_dir)

