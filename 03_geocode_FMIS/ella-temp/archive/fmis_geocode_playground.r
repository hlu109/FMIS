#setwd('/Users/egoecknerwald/Library/CloudStorage/Dropbox')

library(tidyverse)
library(tigris)
library(sf)
library(ggplot2)
library(osmdata)
library(mapview)
library(arrow)
library(jsonlite)
library(duckdb)


endpoints <- read.csv('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/ella-temp/fmis_interstate_parsed_titles_new_constr_v3_20260522_165917.csv',
                      colClasses = "character", na.strings = "")

##tigris sample
options(tigris_year = 2025)

wake_roads <- roads(state = "NC", county = "Wake")

us_primary_roads <- primary_roads()

ggplot(wake_roads) +
  geom_sf(color = "blue") +
  theme_void()


##sample of centroids
ca_places <- places(state = "CA", year = 2025)
ca_centroids <- st_as_sf(
  ca_places, 
  coords = c("INTPTLON", "INTPTLAT"), 
  crs = 4326
)

ca_centroids <- st_as_sf(
  st_drop_geometry(ca_places), 
  coords = c("INTPTLON", "INTPTLAT"), 
  crs = 4326 
)

mapview(ca_centroids, col.regions = "red", cex = 2)

##sample of OSM via overture
latest_release <- jsonlite::fromJSON("https://stac.overturemaps.org/catalog.json") $latest

s3_path <- paste0(
  "s3://overturemaps-us-west-2/release/", 
  latest_release, 
  "/theme=transportation/type=segment/"
)


##overture try 1 - works but slow
  overture_transport <- open_dataset(s3_path, format = "parquet")
  
  us_road_names <- overture_transport %>%
    select(id, subtype, names, context_id) %>%
    filter(context_id == "US") %>%
    collect()
  
  final_road_names_df <- us_road_names %>%
    mutate(
      formal_name    = names$primary,
      common_name    = names$common,
      official_name  = names$official,
      alternate_name = names$alternate
    ) %>%
    select(-names) %>%
    filter(!is.na(formal_name) | !is.na(common_name) | !is.na(official_name) | !is.na(alternate_name))
  
  head(final_road_names_df)


##overture try 2 with duckdb - works faster but doesn't have the correct osm name
  library(duckdb)
  
  con <- dbConnect(duckdb())
  
  dbExecute(con, "SET s3_endpoint = 's3.amazonaws.com';")
  dbExecute(con, "SET s3_access_key_id = '';")
  dbExecute(con, "SET s3_secret_access_key = '';")
  
  latest_release <- jsonlite::fromJSON("https://stac.overturemaps.org/catalog.json")$latest
  s3_path <- paste0(
    "s3://overturemaps-us-west-2/release/",
    latest_release,
    "/theme=transportation/type=segment/**/*.parquet"
  )
  
  query <- sprintf("
    SELECT
      id,
      names.primary                                    AS primary_name,
      names.rules                                      AS name_rules
    FROM read_parquet('%s', hive_partitioning = true)
    WHERE subtype = 'road'
      AND class   = 'motorway'
      AND bbox.xmin >= -125.0
      AND bbox.xmax <=  -66.9
      AND bbox.ymin >=   24.4
      AND bbox.ymax <=   49.4
  ", s3_path)
  
  us_primary_raw <- dbGetQuery(con, query)
  dbDisconnect(con)
  
  road_names <- us_primary_raw %>%
    mutate(
      alternate = map_chr(name_rules, ~ {
        rules <- .x
        if (is.null(rules) || nrow(rules) == 0) return(NA_character_)
        hit <- rules[rules$variant %in% c("alternate", "short", "official"), ]
        if (nrow(hit) == 0) return(NA_character_)
        hit$value[1]
      })
    ) %>%
    select(primary_name, alternate) %>%
    filter(!is.na(primary_name)) %>%
    distinct()

##names and informal names list
  test <- fromJSON('/Users/egoecknerwald/Desktop/us_highways_list.jsonl')



####STEP 2: 