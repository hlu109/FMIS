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

geocode_eval_dir <- file.path(data_dir, "Intermediate", "geocoding", "evaluation")
gt_dir <- file.path(geocode_eval_dir, "ground_truth")
splits_dir <- file.path(geocode_eval_dir, "splits")
dir.create(gt_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(splits_dir, recursive = TRUE, showWarnings = FALSE)


# ==============================================================================
# pr511_cty: one open year per county only (no route)
# ==============================================================================
pr511_intermediate <- file.path(intermediate_dir, "PR_511")
pr511_cty_path <- file.path(
  pr511_intermediate,
  "pr511_cty_single_openyr_ever.dta"
)
pr511_chained_path <- file.path(
  pr511_intermediate,
  "PR511_hubbardmazzeo_chained.dta"
)

pr511_cty <- haven::read_dta(pr511_cty_path)

# assert sample size is stable
stopifnot(nrow(pr511_cty) == 263)

# merge back to the unfiltered PR-511 data to recover open_year in case we want it for stratification (though we aren't actually using it rn)
pr511_chained_cty <- haven::read_dta(pr511_chained_path) %>%
  select(st, county_fips, open_year) %>%
  distinct(st, county_fips, .keep_all = TRUE) # single_openyr_ever guarantees one distinct year per county

pr511_cty_cluster_df <- pr511_cty %>%
  left_join(pr511_chained_cty, by = c("st", "county_fips")) %>%
  mutate(
    projectid = as.character(county_fips),
    cluster_key = projectid,
    state_fips = st,
    open_year_decade = (open_year %/% 10) * 10
  )

# assert sample size is stable
stopifnot(nrow(pr511_cty_cluster_df) == 263)

pr511_cty_splits <- build_splits_stratified(
  "pr511_cty",
  pr511_cty_cluster_df,
  strata_cols = c("state_fips"),
  val_frac = 0.5,
  seed_salt = "pr511_cty_1"
)
# don't intentionally stratify by open_year_decade for now because it makes the state stratification too lumpy – but the results split pretty well along decade anyway

# merge back with PR-511 data to get original state/county variables
pr511_cty_splits <- pr511_cty_splits %>%
  select(projectid, split) %>%
  left_join(pr511_cty_cluster_df, by = "projectid") %>%
  select("state_fips", "county_fips", "split", "open_year_decade", "open_year")

write.csv(
  pr511_cty_splits,
  file.path(splits_dir, "pr511_cty_splits.csv"),
  row.names = FALSE
)
message("pr511_cty splits: ", nrow(pr511_cty_splits), " counties.")

# ==============================================================================
# pr511_cty_rt: one open year per county x route cell, EXCLUDING any county already covered by pr511_cty above
# ==============================================================================
pr511_cty_rt_path <- file.path(
  pr511_intermediate,
  "pr511_cty_rt_single_openyr_ever.dta"
)
pr511_cty_rt_raw <- haven::read_dta(pr511_cty_rt_path)

# drop all the counties that are already in pr511_cty above since they are a subset of pr511_cty_rt and we don't want leakage across val/test assignments
pr511_cty_rt <- pr511_cty_rt_raw %>%
  anti_join(pr511_cty, by = c("st", "county_fips"))

# assert sample size is stable (511 raw cells, 263 dropped for counties already in pr511_cty, 248 remain)
stopifnot(nrow(pr511_cty_rt_raw) == 511)
stopifnot(nrow(pr511_cty_rt) == (511 - 263))

# merge back to the unfiltered PR-511 data to recover open_year in case we want it for stratification (though we aren't actually using it rn)
pr511_chained_cty_rt <- haven::read_dta(pr511_chained_path) %>%
  select(st, county_fips, route, open_year) %>%
  distinct(st, county_fips, route, .keep_all = TRUE) # single_openyr_ever guarantees one distinct year per cell

pr511_cty_rt_cluster_df <- pr511_cty_rt %>%
  left_join(pr511_chained_cty_rt, by = c("st", "county_fips", "route")) %>%
  mutate(
    projectid = paste(county_fips, route, sep = "_"),
    cluster_key = projectid,
    state_fips = st,
    open_year_decade = (open_year %/% 10) * 10
  )

# assert sample size is stable
stopifnot(nrow(pr511_cty_rt_cluster_df) == (511 - 263))

pr511_cty_rt_splits <- build_splits_stratified(
  "pr511_cty_rt",
  pr511_cty_rt_cluster_df,
  strata_cols = c("state_fips"),
  val_frac = 0.5,
  seed_salt = "pr511_cty_rt_1"
)
# don't intentionally stratify by open_year_decade because it makes the state stratification too lumpy – but the results split pretty well along decade anyway

# merge back with PR-511 data to get original state/route/county variables
pr511_cty_rt_splits <- pr511_cty_rt_splits %>%
  select(projectid, split) %>%
  left_join(pr511_cty_rt_cluster_df, by = "projectid") %>%
  select(
    "state_fips",
    "county_fips",
    "route",
    "split",
    "open_year_decade",
    "open_year"
  )

write.csv(
  pr511_cty_rt_splits,
  file.path(splits_dir, "pr511_cty_rt_splits.csv"),
  row.names = FALSE
)
message(
  "pr511_cty_rt splits: ",
  nrow(pr511_cty_rt_splits),
  " county x route cells."
)

#######################

# merge pr511 val/test cell splits onto individual FMIS interstate new-construction projects
fmis_interstate_newconstr <- haven::read_dta(file.path(
  intermediate_dir,
  "geocoding",
  "inputs",
  "FMIS_interstate_newconstr_project_titles.dta"
))

# county_fips is semicolon-delimited when a project spans multiple counties; explode to one row per county so a project matches if ANY of its counties falls in a pr511 split cell
newconstr_exploded <- fmis_interstate_newconstr %>%
  mutate(pid = paste0(recipientid, "_", federal_project_number)) %>%
  tidyr::separate_rows(county_fips, sep = ";") %>%
  mutate(county_fips = as.numeric(trimws(county_fips)))

# handle pr511_cty
# merges on county_fips only
val_pids_cty <- newconstr_exploded %>%
  inner_join(
    pr511_cty_splits %>% filter(split == "val"),
    by = "county_fips"
  ) %>%
  pull(pid) %>%
  unique()

test_pids_cty <- newconstr_exploded %>%
  inner_join(
    pr511_cty_splits %>% filter(split == "test"),
    by = "county_fips"
  ) %>%
  pull(pid) %>%
  unique()

# because a FMIS project may span multiple counties, some projects match both val and test counties; drop them entirely for now
overlap_pids_cty <- intersect(val_pids_cty, test_pids_cty)
val_pids_cty <- setdiff(val_pids_cty, overlap_pids_cty)
test_pids_cty <- setdiff(test_pids_cty, overlap_pids_cty)

# export
for (s in c("val", "test")) {
  matched_pids <- if (s == "val") val_pids_cty else test_pids_cty
  out <- fmis_interstate_newconstr %>%
    filter(
      paste0(recipientid, "_", federal_project_number) %in% matched_pids
    )
  haven::write_dta(
    out,
    file.path(
      splits_dir,
      paste0(
        toupper(s),
        "_pr511_cty_fmis_interstate_newconstr_project_titles.dta"
      )
    )
  )
}
message(
  "pr511_cty fmis interstate newconstr splits: ",
  length(val_pids_cty),
  " val, ",
  length(test_pids_cty),
  " test (",
  length(overlap_pids_cty),
  " multi-county overlap projects dropped)."
)
stopifnot(length(val_pids_cty) == 706)
stopifnot(length(test_pids_cty) == 811)
stopifnot(length(overlap_pids_cty) == 26)


# merges on state_fips x county_fips x route, treating FMIS's inferred route_fpn as equivalent to PR-511's route
val_pids_cty_rt <- newconstr_exploded %>%
  inner_join(
    pr511_cty_rt_splits %>% filter(split == "val"),
    by = c("state_fips", "county_fips", "route_fpn" = "route")
  ) %>%
  pull(pid) %>%
  unique()

test_pids_cty_rt <- newconstr_exploded %>%
  inner_join(
    pr511_cty_rt_splits %>% filter(split == "test"),
    by = c("state_fips", "county_fips", "route_fpn" = "route")
  ) %>%
  pull(pid) %>%
  unique()

# because a FMIS project may span multiple counties, some projects match both val and test cells; drop them entirely for now
overlap_pids_cty_rt <- intersect(val_pids_cty_rt, test_pids_cty_rt)
val_pids_cty_rt <- setdiff(val_pids_cty_rt, overlap_pids_cty_rt)
test_pids_cty_rt <- setdiff(test_pids_cty_rt, overlap_pids_cty_rt)

for (s in c("val", "test")) {
  matched_pids <- if (s == "val") val_pids_cty_rt else test_pids_cty_rt
  out <- fmis_interstate_newconstr %>%
    filter(
      paste0(recipientid, "_", federal_project_number) %in% matched_pids
    )
  haven::write_dta(
    out,
    file.path(
      splits_dir,
      paste0(
        toupper(s),
        "_pr511_cty_rt_fmis_interstate_newconstr_project_titles.dta"
      )
    )
  )
}
message(
  "pr511_cty_rt fmis interstate newconstr splits: ",
  length(val_pids_cty_rt),
  " val, ",
  length(test_pids_cty_rt),
  " test (",
  length(overlap_pids_cty_rt),
  " multi-county overlap projects dropped)."
)

stopifnot(length(val_pids_cty_rt) == 553)
stopifnot(length(test_pids_cty_rt) == 530)
stopifnot(length(overlap_pids_cty_rt) == 14)


# ==============================================================================
# FMIS GIS data
# ==============================================================================
fmis_gis_path <- file.path(intermediate_dir, "project_level_FMIS_w_GIS.dta")
fmis_gis_clean <- haven::read_dta(fmis_gis_path)

# assert sample size is stable
stopifnot(nrow(fmis_gis_clean) == 135041)

# cluster = projecttitle x county_fips
# the leakage concern here is duplicate/near-duplicate titles that refer to the same physical road segment. projecttitle alone is too coarse (e.g. 174 projects all titled "bridge replacement", differentiated only by projectdescription), but projecttitle x projectdescription is too fine and can split apart projects that share an identical (and sometimes location-specific) title with differing descriptions. county_fips narrows the generic "bridge replacement"-style titles without introducing the description-level leakage risk.
fmis_gis_cluster_df <- fmis_gis_clean %>%
  transmute(
    projectid = paste0(recipientid, "_", federal_project_number),
    cluster_key = paste(projecttitle, county_fips, sep = "_"),
    state_fips
  )

# stratify by state only
fmis_gis_splits <- build_splits_stratified(
  "fmis_gis",
  fmis_gis_cluster_df,
  strata_cols = "state_fips",
  val_frac = 0.5,
  seed_salt = "fmis_gis"
)

write.csv(
  fmis_gis_splits,
  file.path(splits_dir, "fmis_gis_splits.csv"),
  row.names = FALSE
)
message(
  "fmis_gis splits: ",
  nrow(fmis_gis_splits),
  " projects across ",
  length(unique(fmis_gis_splits$cluster_key)),
  " title x county clusters (",
  sum(fmis_gis_splits$split == "val"),
  " val, ",
  sum(fmis_gis_splits$split == "test"),
  " test)."
)


#######################

# retrieve the original FMIS project data for these splits and save the subsamples for geocoding
for (s in c("val", "test")) {
  matched_pids <- fmis_gis_splits %>%
    filter(split == s) %>%
    pull(projectid) %>%
    unique()
  out <- fmis_gis_clean %>%
    filter(paste0(recipientid, "_", federal_project_number) %in% matched_pids)
  haven::write_dta(
    out,
    file.path(splits_dir, paste0(toupper(s), "_fmis_gis_project_titles.dta"))
  )
}
stopifnot(sum(fmis_gis_splits$split == "val") == 67479)
stopifnot(sum(fmis_gis_splits$split == "test") == 67562)

message("*********************\nScript complete.\n*********************")
