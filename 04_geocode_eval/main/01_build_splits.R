# ==============================================================================
# Build val/test/train split tables for every available ground-truth source and write the row IDs to CSV.
# TODO: @Hannah should reorder this since we are calling this before the title-parsing/geocoding step 
# ==============================================================================
# Setup 
library(dplyr)
library(haven)
library(tidyr)

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

# source(file.path(getwd(), "utils", "geo_utils.R"))
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

#######################

# merge pr511 val/test cell splits onto individual FMIS interstate new-construction projects
fmis_interstate_newconstr <- haven::read_dta(file.path(intermediate_dir, "geocoding", "inputs", "FMIS_interstate_newconstr_project_titles.dta"))

# county_fips is semicolon-delimited when a project spans multiple counties; explode to one row per county so a project matches if ANY of its counties falls in a pr511 split cell. merges on county and route
newconstr_exploded <- fmis_interstate_newconstr %>%
  mutate(pid = paste0(recipientid, "_", federal_project_number)) %>%
  tidyr::separate_rows(county_fips, sep = ";") %>%
  mutate(county_fips = as.numeric(trimws(county_fips)))

val_pids <- newconstr_exploded %>%
  inner_join(
    pr511_splits %>% filter(split == "val"),
    by = c("state_fips", "county_fips", "route_fpn" = "route")
  ) %>%
  pull(pid) %>%
  unique()

test_pids <- newconstr_exploded %>%
  inner_join(
    pr511_splits %>% filter(split == "test"),
    by = c("state_fips", "county_fips", "route_fpn" = "route")
  ) %>%
  pull(pid) %>%
  unique()

# because a FMIS project may span multiple counties, some projects match both val and test cells; drop them entirely for now 
overlap_pids <- intersect(val_pids, test_pids)
val_pids <- setdiff(val_pids, overlap_pids)
test_pids <- setdiff(test_pids, overlap_pids)

for (s in c("val", "test")) {
  matched_pids <- if (s == "val") val_pids else test_pids
  out <- fmis_interstate_newconstr %>% filter(paste0(recipientid, "_", federal_project_number) %in% matched_pids)
  haven::write_dta(out, file.path(splits_dir, paste0("pr511_", s, "_fmis_interstate_newconstr_project_titles.dta")))
}
message(
  "pr511 fmis interstate newconstr splits: ",
  length(val_pids), " val, ", length(test_pids), " test (",
  length(overlap_pids), " multi-county overlap projects dropped)."
)

stopifnot(length(val_pids) == 1287)
stopifnot(length(test_pids) == 1212)
stopifnot(length(overlap_pids) == 48)

message("Splits build complete. Output: ", splits_dir)

