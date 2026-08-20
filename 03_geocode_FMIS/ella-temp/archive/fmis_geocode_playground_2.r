library(tidyverse)
library(tigris)
library(sf)
library(ggplot2)
library(stringdist)
library(mapview)
library(furrr)
library(future)
library(memoise)
tig_cache <- cache_filesystem("~/.tigris_memoise")

endpoints <- read.csv('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/ella-temp/fmis_interstate_parsed_titles_new_constr_v3_20260522_165917.csv',
                      colClasses = "character", na.strings = "")

####SETUP####
  ##collapsing endpoints a and b
    endpoints_unique <- endpoints %>%
      pivot_longer(cols = starts_with("ep_"), 
                   names_to = c("source", ".value"), 
                   names_pattern = "ep_(.)_(.*)") %>%
      relocate(project_title, source)

  ##collapsing references 1, 2, 3
    refs_unique <- endpoints_unique %>%
      pivot_longer(cols = starts_with("ref"),
                   names_to = c("ref_tier", ".value"),
                   names_pattern = "ref(\\d+)_(.*)") %>%
      relocate(project_title, source, ref_tier)
    
  ##matrix of possible reference mapping routes
    ref_map_matrix <- expand.grid(anchor_type   = unique(refs_unique$anchor_type), 
                            rel_type      = unique(refs_unique$rel_type), 
                            rel_direction = unique(refs_unique$rel_direction), 
                            rel_dist_unit = unique(refs_unique$rel_dist_unit), 
                            rel_qualifier = unique(refs_unique$rel_qualifier))
    
    ref_map_matrix_exist <- refs_unique %>%
      distinct(anchor_type, rel_type, rel_direction, rel_dist_unit, rel_qualifier)

####Finding main route geometry####
    
    
####Finding Reference Geometry####
    ##parameters
      data_year <- 2024
      max_stringdist <- 0.15
      options(tigris_use_cache = TRUE)
      
    ##memoised tigris readers
      counties_m <- memoise(tigris::counties,                cache = tig_cache)
      places_m   <- memoise(tigris::places,                  cache = tig_cache)
      psr_m      <- memoise(tigris::primary_secondary_roads, cache = tig_cache)
      subdiv_m   <- memoise(tigris::county_subdivisions,     cache = tig_cache)
      roads_m    <- memoise(tigris::roads,                   cache = tig_cache)
      
      get_target_counties <- memoise(function(statefips, countyfips) {
        ac <- counties_m(state = statefips, cb = TRUE, year = data_year, progress_bar = FALSE) %>%
          st_transform(9311) %>%
          st_simplify(preserveTopology = TRUE, dTolerance = 2000) %>%
          st_transform(4326)
        tgt <- ac %>% filter(COUNTYFP == countyfips)
        d <- st_distance(tgt, ac)
        v <- ac %>% filter(as.numeric(d) <= 50 * 1609.34) %>% pull(COUNTYFP)
        sort(unique(if (length(v) == 0) countyfips else v))
      }, cache = tig_cache)
      
    ##mutating county name
      refs_unique <- refs_unique %>% 
        mutate(county_name = case_when(
          str_detect(county_name, "(?i)\\s*County") ~ 
            str_replace(county_name, "(?i)(.*?)\\s*County", "\\1"),
          TRUE ~ county_name))  
      
    ##mutating feature names
      refs_unique <- refs_unique %>%
        mutate(
          old_feature_name = feature_name,
          extracted_direction = case_when(
            str_detect(feature_name, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])") ~
              str_extract(feature_name, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])") %>% tolower(),
            TRUE ~ NA_character_
          ),
          
          ##county line
          feature_name = case_when(
            str_detect(feature_name, "(?i)\\s*County\\s*Line") ~ {
              clean_step1 <- str_remove(feature_name, regex(county_name, ignore_case = TRUE))
              clean_step2 <- str_remove_all(clean_step1, "(?i)\\s*County\\s*Line|\\s*County")
              clean_step3 <- str_remove_all(clean_step2, "-")
              str_squish(clean_step3)
            },
            
            ##city line
            str_detect(feature_name, "(?i)City\\s*Limit|Town\\s*Line") ~ {
              clean_city <- str_remove_all(feature_name, "(?i)\\s*City\\s*Limits?\\s*|\\s*Town\\s*Lines?\\s*|\\s*Limits?\\s*")
              clean_city <- str_remove_all(clean_city, "-")
              clean_city <- str_remove_all(clean_city, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")
              str_squish(clean_city)
            },
            
            ##routes
            str_detect(feature_name, "(?i)^Interstate\\s+\\d+") ~
              str_replace(feature_name, "(?i)^Interstate\\s+(\\d+)", "I- \\1"),
            str_detect(feature_name, "(?i)^US\\s+Route\\s+\\d+") ~
              str_replace(feature_name, "(?i)^US\\s+Route\\s+(\\d+)", "US Hwy \\1"),
            str_detect(feature_name, "(?i)^State\\s+Route\\s+\\d+") ~
              str_replace(feature_name, "(?i)^State\\s+Route\\s+(\\d+)", "State Rte \\1"),
            
            TRUE ~ feature_name
          )
        )
      
    ##reference endpoint function
      ref_pull <- function(type, name, countyfips, statefips, extracted_direction = NA_character_) {
        
        na_fallback <- tibble(
          matched_name = NA_character_, 
          geometry = st_sfc(st_point(), crs = 4326)
        )
        
        if (is.null(type) || length(type) == 0 || is.na(type)) {
          return(na_fallback)
        }
        
        tryCatch({
          
          # if (type %in% c('city_limits', 'city', 'highway', 'road')) {
          #   all_counties <- counties(state = statefips, cb = TRUE, year = data_year, progress_bar = FALSE)
          #   
          #   all_counties_simplified <- all_counties %>%
          #     st_transform(9311) %>%
          #     st_simplify(preserveTopology = TRUE, dTolerance = 2000) %>%
          #     st_transform(4326)
          #   
          #   target_county <- all_counties_simplified %>% filter(COUNTYFP == countyfips)
          #   
          #   search_radius_meters <- 50 * 1609.34
          #   distances <- st_distance(target_county, all_counties_simplified)
          #   
          #   target_counties_vector <- all_counties_simplified %>%
          #     filter(as.numeric(distances) <= search_radius_meters) %>%
          #     pull(COUNTYFP)
          #   
          #   if (length(target_counties_vector) == 0) target_counties_vector <- countyfips
          # }
          
          if (type %in% c('city_limits', 'city', 'highway', 'road')) {
            target_counties_vector <- get_target_counties(statefips, countyfips)
          }
          
          # --- 1. CITY CENTROID ---
          if (type == 'city') {
            
            subdivisions_pool <- county_subdivisions(
              state = statefips,
              county = target_counties_vector,
              year = data_year,
              progress_bar = FALSE
            ) %>%
              st_transform(4326) %>%
              select(NAME, geometry)
            
            places_pool <- places(
              state = statefips,
              year = data_year,
              progress_bar = FALSE
            ) %>%
              st_transform(4326) %>%
              select(NAME, geometry)
            
            match_row <- bind_rows(subdivisions_pool, places_pool) %>%
              mutate(match_dist = stringdist(tolower(NAME), tolower(name), method = "jw")) %>%
              arrange(match_dist) %>%
              slice(1)
            
            if (nrow(match_row) == 0 || match_row$match_dist > max_stringdist) return(na_fallback)
            
            return(match_row %>% st_centroid() %>% select(matched_name = NAME, geometry))
          }
          
          # --- 2. CITY LIMITS POLYGON ---
          if (type == 'city_limits') {
            
            subdivisions_pool <- county_subdivisions(
              state = statefips,
              county = target_counties_vector,
              year = data_year,
              progress_bar = FALSE
            ) %>%
              st_transform(4326) %>%
              select(NAME, geometry)
            
            places_pool <- places(
              state = statefips,
              year = data_year,
              progress_bar = FALSE
            ) %>%
              st_transform(4326) %>%
              select(NAME, geometry)
            
            match_row <- bind_rows(subdivisions_pool, places_pool) %>%
              mutate(match_dist = stringdist(tolower(NAME), tolower(name), method = "jw")) %>%
              arrange(match_dist) %>%
              slice(1)
            
            if (nrow(match_row) == 0 || match_row$match_dist > max_stringdist) return(na_fallback)
            
            result_sf <- match_row %>% select(matched_name = NAME, geometry)
            
            detected_direction <- extracted_direction
            
            is_part_of_city_name <- !is.na(detected_direction) &&
              str_detect(tolower(match_row$NAME), paste0("^", detected_direction))
            
            if (!is.na(detected_direction) && !is_part_of_city_name) {
              
              target_metric <- st_transform(match_row, 9311)
              geom_types <- as.character(st_geometry_type(target_metric, by_geometry = FALSE))
              
              if (any(c("POLYGON", "MULTIPOLYGON") %in% geom_types)) {
                boundary_lines <- st_cast(target_metric, "MULTILINESTRING")
              } else if ("GEOMETRYCOLLECTION" %in% geom_types) {
                boundary_lines <- st_collection_extract(target_metric, "LINESTRING") %>%
                  st_cast("MULTILINESTRING")
              } else {
                boundary_lines <- target_metric
              }
              
              bbox <- st_bbox(target_metric)
              centroid <- st_coordinates(st_centroid(st_union(target_metric)))
              cx <- centroid[1, "X"]
              cy <- centroid[1, "Y"]
              
              clip_dist <- max(bbox$xmax - bbox$xmin, bbox$ymax - bbox$ymin) * 2
              
              clipper_coords <- switch(
                detected_direction,
                "north" = matrix(c(cx - clip_dist, cy,             cx + clip_dist, cy,             cx + clip_dist, cy + clip_dist, cx - clip_dist, cy + clip_dist, cx - clip_dist, cy),             ncol = 2, byrow = TRUE),
                "south" = matrix(c(cx - clip_dist, cy - clip_dist, cx + clip_dist, cy - clip_dist, cx + clip_dist, cy,             cx - clip_dist, cy,             cx - clip_dist, cy - clip_dist), ncol = 2, byrow = TRUE),
                "east"  = matrix(c(cx,             cy - clip_dist, cx + clip_dist, cy - clip_dist, cx + clip_dist, cy + clip_dist, cx,             cy + clip_dist, cx,             cy - clip_dist), ncol = 2, byrow = TRUE),
                "west"  = matrix(c(cx - clip_dist, cy - clip_dist, cx,             cy - clip_dist, cx,             cy + clip_dist, cx - clip_dist, cy + clip_dist, cx - clip_dist, cy - clip_dist), ncol = 2, byrow = TRUE)
              )
              
              clipper_poly <- st_polygon(list(clipper_coords)) %>% st_sfc(crs = 9311)
              
              result_sf <- st_intersection(boundary_lines, clipper_poly) %>%
                st_transform(4326) %>%
                mutate(border_name = paste0(match_row$NAME, " ", tools::toTitleCase(detected_direction), " City Limit Line")) %>%
                select(matched_name = border_name, geometry)
            }
            
            return(result_sf)
          }
          
          # --- 3. COUNTY CENTROID ---
          if (type == 'county') {
            match_row <- counties(state = statefips, cb = TRUE, year = data_year, progress_bar = FALSE) %>%
              filter(COUNTYFP == countyfips)
            
            if (nrow(match_row) == 0) return(na_fallback)
            return(match_row %>% st_centroid() %>% st_transform(4326) %>% select(matched_name = NAME, geometry))
          }
          
          # --- 4. COUNTY LINE ---
          if (type == 'county_line') {
            all_counties <- counties(state = statefips, cb = TRUE, year = data_year, progress_bar = FALSE) %>%
              st_transform(4326)
            
            target_county <- all_counties %>% filter(COUNTYFP == countyfips)
            if (nrow(target_county) == 0) return(na_fallback)
            
            clean_neighbor_name <- stringr::str_remove_all(tolower(name), "(?i)\\s*county\\s*line|\\s*county") %>%
              stringr::str_trim()
            
            neighbor_county <- all_counties %>%
              mutate(match_dist = stringdist(tolower(NAME), clean_neighbor_name, method = "jw")) %>%
              arrange(match_dist) %>%
              slice(1)
            
            result_sf <- NULL
            
            if (nrow(neighbor_county) == 0 || neighbor_county$match_dist > max_stringdist) {
              result_sf <- target_county %>%
                st_transform(4326) %>%
                st_cast("MULTILINESTRING") %>%
                mutate(border_name = paste0(NAME, " County Boundary Line")) %>%
                select(matched_name = border_name, geometry)
              
            } else {
              target_metric   <- st_transform(target_county, 9311)
              neighbor_metric <- st_transform(neighbor_county, 9311)
              target_buffered_metric <- st_buffer(target_metric, 10)
              shared_border_metric <- st_intersection(target_buffered_metric, neighbor_metric)
              
              if (nrow(shared_border_metric) == 0) {
                result_sf <- target_county %>%
                  st_cast("MULTILINESTRING") %>%
                  mutate(border_name = paste0(NAME, " County Boundary Line")) %>%
                  select(matched_name = border_name, geometry)
              } else {
                result_sf <- shared_border_metric %>%
                  st_transform(4326) %>%
                  mutate(border_name = paste0(target_county$NAME, "-", neighbor_county$NAME, " County Line")) %>%
                  select(matched_name = border_name, geometry)
              }
            }
            
            detected_direction <- case_when(
              str_detect(name, "(?i)\\bnorth\\b") ~ "north",
              str_detect(name, "(?i)\\bsouth\\b") ~ "south",
              str_detect(name, "(?i)\\beast\\b")  ~ "east",
              str_detect(name, "(?i)\\bwest\\b")  ~ "west",
              TRUE ~ NA_character_
            )
            
            is_part_of_county_name <- !is.na(detected_direction) &&
              str_detect(tolower(target_county$NAME), detected_direction)
            
            if (!is.na(detected_direction) && !is_part_of_county_name &&
                str_detect(result_sf$matched_name[1], "(?i)Boundary Line")) {
              
              target_metric <- st_transform(target_county, 9311)
              boundary_lines <- st_cast(target_metric, "MULTILINESTRING")
              
              bbox <- st_bbox(target_metric)
              centroid <- st_coordinates(st_centroid(st_union(target_metric)))
              cx <- centroid[1, "X"]
              cy <- centroid[1, "Y"]
              
              clip_dist <- max(bbox$xmax - bbox$xmin, bbox$ymax - bbox$ymin) * 2
              
              clipper_coords <- switch(
                detected_direction,
                "north" = matrix(c(cx - clip_dist, cy,             cx + clip_dist, cy,             cx + clip_dist, cy + clip_dist, cx - clip_dist, cy + clip_dist, cx - clip_dist, cy),             ncol = 2, byrow = TRUE),
                "south" = matrix(c(cx - clip_dist, cy - clip_dist, cx + clip_dist, cy - clip_dist, cx + clip_dist, cy,             cx - clip_dist, cy,             cx - clip_dist, cy - clip_dist), ncol = 2, byrow = TRUE),
                "east"  = matrix(c(cx,             cy - clip_dist, cx + clip_dist, cy - clip_dist, cx + clip_dist, cy + clip_dist, cx,             cy + clip_dist, cx,             cy - clip_dist), ncol = 2, byrow = TRUE),
                "west"  = matrix(c(cx - clip_dist, cy - clip_dist, cx,             cy - clip_dist, cx,             cy + clip_dist, cx - clip_dist, cy + clip_dist, cx - clip_dist, cy - clip_dist), ncol = 2, byrow = TRUE)
              )
              
              clipper_poly <- st_polygon(list(clipper_coords)) %>% st_sfc(crs = 9311)
              
              result_sf <- st_intersection(boundary_lines, clipper_poly) %>%
                st_transform(4326) %>%
                mutate(border_name = paste0(target_county$NAME, " ", tools::toTitleCase(detected_direction), " Boundary Line")) %>%
                select(matched_name = border_name, geometry)
            }
            
            return(result_sf)
          }
          
          # --- 5. HIGHWAY/ROAD LINES ---
          if (type %in% c('highway', 'road')) {
            local_roads <- roads(state = statefips, county = target_counties_vector,
                                 year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
            
            major_highways <- primary_secondary_roads(state = statefips, year = data_year,
                                                      progress_bar = FALSE) %>%
              st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
            
            combined_network <- bind_rows(local_roads, major_highways)
            if (!"FULLNAME" %in% colnames(combined_network) && "NAME" %in% colnames(combined_network)) {
              combined_network <- combined_network %>% rename(FULLNAME = NAME)
            }
            
            scored <- combined_network %>%
              filter(!is.na(FULLNAME)) %>%
              mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
            
            best <- scored %>% slice_min(match_dist, n = 1, with_ties = FALSE)
            if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
            
            road_union <- scored %>% filter(FULLNAME == best$FULLNAME) %>% st_union()
            
            return(st_sf(matched_name = best$FULLNAME, geometry = road_union))
          }
          
          return(NULL)
          
        }, error = function(e) {
          message(paste0("Error for ", type, " (State: ", statefips, ", County: ", countyfips, "): ", e$message))
          return(na_fallback)
        })
      }
      
    ##test
      county_test <- refs_unique[which(refs_unique$anchor_type %in% c("county_line")),] %>%
        rowwise() %>%
        mutate(pulled_data = list(ref_pull(type = anchor_type,
                                           name = feature_name,
                                           countyfips = substr(county_fips, 3, 5),
                                           statefips = state_fips,
                                           extracted_direction = extracted_direction))) %>%
        ungroup() %>%
        unnest(pulled_data, keep_empty = TRUE) %>%
        st_as_sf() %>%
        select(project_title, state_name, county_name, anchor_type, old_feature_name,
               feature_name, extracted_direction, matched_name, geometry) %>%
        unique()

      all_test <- refs_unique %>%
        filter(anchor_type %in% c('road', 'highway', 'county', 'city', 'county_line', 'city_limits')) %>%
        group_by(anchor_type) %>%
        slice_head(n = 20) %>%
        ungroup() %>% 
        rowwise() %>%
        mutate(pulled_data = 
                 list(ref_pull(type = anchor_type,
                               name = feature_name,
                               countyfips = substr(county_fips, 3, 5),
                               statefips = state_fips,
                               extracted_direction = extracted_direction))) %>%
        ungroup() %>%
        unnest(pulled_data, keep_empty = TRUE) %>%
        st_as_sf() %>%
        select(project_title, state_name, county_name, anchor_type, old_feature_name,
               feature_name, extracted_direction, matched_name, geometry) %>%
        unique()
      
      
    ##test in parallel
      walk(unique(refs_unique$state_fips), ~{
        counties_m(state = .x, cb = TRUE, year = data_year, progress_bar = FALSE)
        places_m(state = .x, year = data_year, progress_bar = FALSE)
        psr_m(state = .x, year = data_year, progress_bar = FALSE)
      })
      
      plan(multisession, workers = 6)
      
      roads_test <- refs_unique %>%
        #filter(anchor_type %in% c('road', 'highway', 'county', 'city', 'county_line', 'city_limits')) %>%
        filter(anchor_type %in% c('road', 'highway')) %>%
        filter(n_refs == 1) %>%
        group_by(anchor_type) %>%
        #slice_head(n = 100) %>%
        ungroup() %>% 
        mutate(
          pulled_data = future_pmap(list(
            type = anchor_type,
            name = feature_name,
            countyfips = substr(county_fips, 3, 5),
            statefips = state_fips,
            extracted_direction = extracted_direction
          ), function(type, name, countyfips, statefips, extracted_direction) {
            ref_pull(
              type = type,
              name = name,
              countyfips = countyfips,
              statefips = statefips,
              extracted_direction = extracted_direction
            )
          }, 
          .options = furrr_options(
            seed = TRUE,
            globals = c("ref_pull", "get_target_counties",
                        "counties_m", "places_m", "psr_m", "subdiv_m", "roads_m",
                        "tig_cache", "data_year", "max_stringdist"),
            packages = c("tigris", "sf", "dplyr", "stringr", "stringdist", "tidyr", "memoise")
          ))
        ) %>%
        unnest(pulled_data, keep_empty = TRUE) %>%
        st_as_sf() %>%
        select(
          project_title, state_name, county_name, anchor_type, old_feature_name,
          feature_name, extracted_direction, matched_name, geometry
        )
      
      plan(sequential)
      
    ##plotting tests
      mapview(county_test[81,] %>% 
                st_transform(4326), 
              layer.name = "Reference Point",
              color = "red", 
              lwd = 3)
      
      mapview(all_test[59,] %>% 
                st_transform(4326), 
              layer.name = "Reference Point",
              color = "red", 
              lwd = 3)

####Computing offset geometry####
  
      
      
####Mapping reference geometry to interstate####
  ##re-merging with unique references
    refs_geometry <- refs_unique %>% left_join(unique(roads_test)) %>%
        filter(!is.na(matched_name))
      
  ##sorting for usable geometries  
    interstate_test_filtered <- refs_geometry %>%
      add_count(project_title, name = "title_occurrences") %>%
      filter(n_refs == 1) %>%
      filter(title_occurrences == 2) %>%
      select(-title_occurrences) %>%
      filter(!is.na(main_route_num))
    
  ##
    
      
####Tests####
  interstate_test <- refs_geometry %>% filter(n_refs == 1)
    
  interstate_test_filtered <- refs_geometry %>%
    add_count(project_title, name = "title_occurrences") %>%
    filter(n_refs == 1) %>%
    filter(title_occurrences == 2) %>%
    select(-title_occurrences) %>%
    filter(!is.na(main_route_num))
      
  ##I-65
  interstate_map <- primary_secondary_roads(state = 'Alabama') %>%
    filter(FULLNAME == "I- 65") %>%
    st_union() %>%
    st_intersection(counties(state = 'Alabama') %>%
                      filter(NAME == 'Mobile') %>%
                      st_transform(st_crs(primary_secondary_roads(state = 'Alabama'))))
  
  mapview(interstate_map, color = "blue", layer.name = "I-65 Mobile") + 
    mapview(
      interstate_test_filtered[interstate_test_filtered$project_title == "I-65,US-90 TO US-45 MOBILE, ACCELERATION LANES" & interstate_test_filtered$source == "a", ], 
      color = 'red', 
      layer.name = "Source A (Red)"
    ) +
    mapview(
      interstate_test_filtered[interstate_test_filtered$project_title == "I-65,US-90 TO US-45 MOBILE, ACCELERATION LANES" & interstate_test_filtered$source == "b", ], 
      color = 'green', 
      layer.name = "Source B (Green)"
    )
  
  
  intersection_a <- interstate_map %>% st_intersection(interstate_test_filtered %>%
                                                         slice(10) %>% 
                                                         st_transform(st_crs(interstate_map)))
  
  intersection_b <- interstate_map %>% st_intersection(interstate_test_filtered %>%
                                                         slice(11) %>% 
                                                         st_transform(st_crs(interstate_map)))
      
  
  mapview(interstate_map, color = "blue", layer.name = "I-65 Mobile") + 
    mapview(
      interstate_test_filtered[interstate_test_filtered$project_title == "I-65,US-90 TO US-45 MOBILE, ACCELERATION LANES" & interstate_test_filtered$source == "a", ], 
      color = 'red', 
      layer.name = "US-90"
    ) +
    mapview(
      interstate_test_filtered[interstate_test_filtered$project_title == "I-65,US-90 TO US-45 MOBILE, ACCELERATION LANES" & interstate_test_filtered$source == "b", ], 
      color = 'green', 
      layer.name = "US-45"
    ) +
    mapview(intersection_a, color = 'black') +
    mapview(intersection_b, color = 'black')
   
  ##I-85
  interstate_map <- primary_secondary_roads(state = 'Alabama') %>%
    filter(FULLNAME == "I- 85") %>%
    st_union() %>%
    st_intersection(counties(state = 'Alabama') %>%
                      filter(NAME == 'Lee') %>%
                      st_transform(st_crs(primary_secondary_roads(state = 'Alabama'))))
  
  
  mapview(interstate_map, color = "blue", layer.name = "I-65 Mobile") + 
    mapview(
      interstate_test_filtered[interstate_test_filtered$project_title == "I-85,US-29 SW OF AUBURN NE TO PT SW OPELIKA , PE,ROW,GR,DR,BRS FOR 4-LANE HWY" & interstate_test_filtered$source == "a", ], 
      color = 'red', 
      layer.name = "Source A (Red)"
    ) +
    mapview(
      interstate_test_filtered[interstate_test_filtered$project_title == "I-85,US-29 SW OF AUBURN NE TO PT SW OPELIKA , PE,ROW,GR,DR,BRS FOR 4-LANE HWY" & interstate_test_filtered$source == "b", ], 
      color = 'green', 
      layer.name = "Source B (Green)"
    ) + 
    mapview(intersection_a, color = 'black') +
    mapview(intersection_b, color = 'black')

  intersection_b <- st_cast(st_nearest_points(interstate_test_filtered %>%
                                                slice(4) %>% 
                                                st_transform(st_crs(interstate_map)), interstate_map), "POINT")[2] %>%
    st_transform(4326)
  
  intersection_a <- st_cast(st_nearest_points(interstate_test_filtered %>%
                                                slice(3) %>% 
                                                st_transform(st_crs(interstate_map)), interstate_map), "POINT")[2] %>%
    st_transform(4326)
  
  intersection_b
      
####Bridge test####
  bb <- getbb("Allegheny County, Pennsylvania")
  
  osm_bridge_query <- opq(bbox = bb) %>%
    add_osm_feature(key = "bridge") 
  
  osm_bridges_raw <- osmdata_sf(osm_bridge_query)
  
  bridge_lines <- osm_bridges_raw$osm_lines
  bridge_polys <- osm_bridges_raw$osm_polygons
  
  duquesne_lines <- osm_bridges_raw$osm_lines %>% 
    filter(grepl("Duquesne", name, ignore.case = TRUE))
  
  duquesne_unified_geom <- st_union(duquesne_lines)
  
  duquesne_sf <- st_sf(Bridge_Name = "Fort Duquesne Bridge", 
                       geometry = st_sfc(duquesne_unified_geom),
                       crs = st_crs(duquesne_lines))
  
  mapview(duquesne_sf, color = "red", lwd = 5,  layer.name = "Unified Bridge")
  
