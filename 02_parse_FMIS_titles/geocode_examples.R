# ==============================================================================
# Test out proposed geocoding algorithm on some example cases. 
# ==============================================================================
# Setup 
library(sf)
library(dplyr)
library(tidyverse)
library(stringr)
library(ggplot2)
library(mapview)
library(webshot)

options(width = 300)

user <- Sys.info()[["user"]]
if (user == "andersonkovesci") {
  project_root <- "/Users/andersonkovesci/Dropbox/FHWA cost data"
  output_dir <- file.path(project_root, "Output", "Andy")
  data_dir <- file.path(project_root, "Data")
  raw_data_dir <- file.path(data_dir, "Raw")
  intermediate_data_dir <- file.path(data_dir, "Intermediate")

} else if (user == "hl2266") {
  project_root <- "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
  output_dir <- file.path(project_root, "Output", "Hannah")
  data_dir <- file.path(project_root, "Data")
  raw_data_dir <- file.path(data_dir, "Raw")
  intermediate_data_dir <- file.path(data_dir, "Intermediate")
} else {
  stop("Set your user paths")
}

# Load helper utility functions 
source(file.path(getwd(), "utils/fig_utils.R"))

# ==============================================================================
examples_out_dir <- file.path(output_dir, "geocode_examples")
if (!dir.exists(examples_out_dir)) {
  dir.create(examples_out_dir, recursive = TRUE)
}
# ==============================================================================
# Load TIGER/Line road data 

# Santa Clara County 
roads_santaclara <- st_read(file.path(paste0(data_dir, "/Hannah sandbox/TIGER roads/tl_2025_06085_roads/tl_2025_06085_roads.shp")))%>%
  mutate(FULLNAME = str_to_upper(FULLNAME))

# San Mateo County 
roads_sanmateo <- st_read(file.path(paste0(data_dir, "/Hannah sandbox/TIGER roads/tl_2025_06081_roads/tl_2025_06081_roads.shp"))) %>%
  mutate(FULLNAME = str_to_upper(FULLNAME))

roads_combined <- rbind(roads_santaclara, roads_sanmateo)

# ==============================================================================
# Example: 
# I-280,RAYMUNDO DR.TO EDGEWOOD RD, P.E.8 LANE FREEWAY GRADING
endp_a_street_name <- "RAYMUNDO"
endp_a_street_suffix <- "DR"
# we only have raymundo ave in the TIGER data 
endp_b_street_name <- "EDGEWOOD"
endp_b_street_suffix <- "RD"
# we only have edgewood dr, ln, and way in the TIGER data 
county_fips <- "06085"
state_fips <- "06"

# search for endpoint a and b in the roads_santaclara dataset
endp_a_road_options <- roads_sanmateo %>%
  filter(str_detect(FULLNAME, paste0("\\b", endp_a_street_name))) # use word boundary regex 
endp_b_road_options <- roads_sanmateo %>%
  filter(str_detect(FULLNAME, paste0("\\b", endp_b_street_name))) # use word boundary regex to avoid "wedgewood" and "ledgewood"

print(endp_a_road_options)
print(endp_b_road_options)

# plot in mapview 
m <- mapview(
    endp_a_road_options, zcol = "FULLNAME", label = endp_a_road_options$FULLNAME,
    color = "red"
  ) + mapview(
    endp_b_road_options, zcol = "FULLNAME", label = endp_b_road_options$FULLNAME,
    color = "blue")
mapshot(m, url = file.path(examples_out_dir, "raymundo_edgewood_santaclara.html"))

# get I-280 shapefile and plot to see if we can find intersections 



# ==============================================================================





# I 280,1.3 MI.NW OF CUPERTINO, GRADE,DRAIN,PCC PAVT.,STRS

# I 280,IN MILLBRAE AND SAN BRUNO, GRADE,DRAIN,PCC PAVT,STRS

# I 280,IN SOUTH SAN FRANCISCO AND DALY CITY, GRADE,DRAIN,PCC PAVT.,STRS.

# I-280,SR 1/280 INTERCHANGE, PAVING AND STRUCTURES

# I-280,1.1 MI S TO 0.5 MI N OF RTE 92, P.E.2 LANE DETOUR
