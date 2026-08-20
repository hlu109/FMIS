# ==============================================================================
# Shared path resolution for the geocode-eval module — source this first from any main/ entry script.
# TODO: probably significant modifications needed here 
# ==============================================================================
library(sf)
sf::sf_use_s2(FALSE)

user <- Sys.info()[["user"]]

if (user %in% c("hl2266")) {
  data_dir <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data/Data"
} else if (user %in% c("fm557")) {
  data_dir <- "C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data/Data"
} else if (user %in% c("andersonkovesci")) {
  data_dir <- "/Users/andersonkovesci/Dropbox/FHWA cost data/Data"
} else if (user %in% c("coder", "root")) {
  # container environment: writable stub tree + read-only full-data mount
  data_dir <- "/workspace/Data"
  raw_data_dir_external <- "/workspace/external/FHWA cost data/Data/Raw"
  intermediate_dir_external <- "/workspace/external/FHWA cost data/Data/Intermediate"
} else {
  stop("Set your user paths.")
}

raw_data_dir <- if (exists("raw_data_dir_external")) raw_data_dir_external else file.path(data_dir, "Raw")
intermediate_dir <- if (exists("intermediate_dir_external")) intermediate_dir_external else file.path(data_dir, "Intermediate")

geocode_eval_dir <- file.path(data_dir, "Intermediate", "geocode_eval")
dir.create(file.path(geocode_eval_dir, "ground_truth"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(geocode_eval_dir, "splits"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(geocode_eval_dir, "predictions"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(geocode_eval_dir, "metrics"), recursive = TRUE, showWarnings = FALSE)

# code_dir = .../Code/FMIS_container. Derived from data_dir (both live under the same "FHWA cost data" root) rather than from this file's own location, since paths.R is `source()`d (its own path isn't reliably recoverable).
code_dir <- if (user %in% c("coder", "root")) {
  "/workspace/Code/FMIS_container"
} else {
  file.path(dirname(data_dir), "Code", "FMIS_container")
}

source(file.path(code_dir, "utils", "geo_utils.R"))
