####Setup####
  library(tidyverse)
  library(tigris)
  library(sf)
  library(ggplot2)
  library(stringdist)
  library(mapview)
  library(furrr)
  library(future)
  library(memoise)
  library(progressr)
  handlers("txtprogressbar")
  
  #unlink("~/.tigris_memoise", recursive = TRUE) <- run when changing years to clear cache
  tig_cache <- cache_filesystem("~/.tigris_memoise")
  
  # endpoints <- read.csv('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/Intermediate/geocoding/title_parsing_gemini_output/fmis_interstate_parsed_titles_new_constr_v3_20260522_165917.csv',
  #                       colClasses = "character", na.strings = "")
  
  endpoints <- read.csv('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/Intermediate/geocoding/title_parsing_gemini_output/interstate_new_constr_10k_v5_20260710_113650.csv',
                        colClasses = "character", na.strings = "") %>%
    filter(statewide == "False") %>%
    filter(various_locs_unspecified == "False") %>%
    filter(multi_locs_specified == "False") %>%
    filter(!grepl(";", county_name)) %>%
    rename(main_route_designation = main_alt_names)
  
  ##global parameters
    data_year <- 2021
    max_stringdist <- 0.35
    options(tigris_use_cache = TRUE)
    county_buffermiles <- 25

  ##memoised tigris readers
    counties_m     <- memoise(tigris::counties, cache = tig_cache)
    places_m       <- memoise(tigris::places, cache = tig_cache)
    psr_m          <- memoise(tigris::primary_secondary_roads, cache = tig_cache)
    subdiv_m       <- memoise(tigris::county_subdivisions, cache = tig_cache)
    roads_m        <- memoise(tigris::roads, cache = tig_cache)
    linear_water_m <- memoise(tigris::linear_water, cache = tig_cache)
    rails_m        <- memoise(tigris::rails, cache = tig_cache)
    states_m       <- memoise(tigris::states, cache = tig_cache)
    landmarks_m    <- memoise(tigris::landmarks, cache = tig_cache)
    
  ##query setup for county buffer
    get_target_counties <- memoise(function(statefips, countyfips,
                                            yr = data_year, buf = county_buffermiles) {
      ac <- counties_m(state = statefips, cb = TRUE, year = yr, progress_bar = FALSE) %>%
        st_transform(9311) %>%
        st_simplify(preserveTopology = TRUE, dTolerance = 2000) %>%
        st_transform(4326)
      tgt <- ac %>% filter(COUNTYFP == countyfips)
      if (nrow(tgt) == 0) return(countyfips)
      d <- st_distance(tgt, ac)
      v <- ac %>% filter(as.numeric(d) <= buf * 1609.34) %>% pull(COUNTYFP)
      sort(unique(if (length(v) == 0) countyfips else v))
    }, cache = tig_cache)

####Main Route Geometry Extraction####
  ##mutating route names for better matching: using route names only when absolutely necessary
    main_route <- endpoints %>%
      mutate(
        rttyp = case_when(
          main_route_type == "interstate"  ~ "I",
          main_route_type == "us_route"    ~ "U",
          main_route_type == "state_route" ~ "S",
          main_route_type == "local_road"  ~ "M",
          TRUE                             ~ "O" 
        ),
        main_route_designation_clean = case_when(
          rttyp == "I" & !is.na(main_route_num) ~ paste0("I- ",        main_route_num),
          rttyp == "U" & !is.na(main_route_num) ~ paste0("US Hwy ",    main_route_num),
          rttyp == "S" & !is.na(main_route_num) ~ paste0("State Hwy ", main_route_num),
          TRUE                                   ~ str_squish(main_route_designation)
        ),
        is_named = rttyp %in% c("M", "O") | is.na(main_route_num)
      ) %>%
      select(project_title, state_fips, county_fips, main_route_designation,
             main_route_designation_clean, rttyp, main_route_num, is_named)
  
  ##selecting for unique queries
    main_route_matrix <- main_route %>%
      mutate(county = substr(county_fips, 3, 5),
             state = state_fips) %>%
      distinct(state, county, rttyp, main_route_num, .keep_all = TRUE) %>%
      select(project_title, state, county, rttyp, main_route_num, main_route_designation,
             main_route_designation_clean, is_named) %>%
      filter(!(is.na(main_route_num) & is.na(main_route_designation)))
    
  ##split the work: numbered routes -> psr (statewide), named roads -> roads (county)
    main_route_numbered <- main_route_matrix %>% filter(!is_named)
    main_route_named    <- main_route_matrix %>% filter(is_named)
  
  ##functions (three parts: pure matcher, shared group-runner, two workers)
    ##route matcher 
      match_route <- function(network, rttyp, route_num, name, is_named,
                              statefips, countyfips) {
        
        na_fallback <- tibble(
          matched_name = NA_character_,
          match_dist   = NA_real_,
          geometry = st_sfc(st_point(), crs = 4326)
        )
        
        if (is.null(rttyp) || is.na(rttyp)) return(na_fallback)
        if (!is_named && (is.null(route_num) || is.na(route_num))) return(na_fallback)
        if (is_named  && (is.null(name)      || is.na(name)))      return(na_fallback)
        if (!"FULLNAME" %in% colnames(network)) return(na_fallback)
        
        ##using fuzzy matching for named 
          if (is_named) {
            scored <- network %>% filter(!is.na(FULLNAME)) %>%
              mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
            best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
            if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
            matches      <- scored %>% filter(FULLNAME == best$FULLNAME)
            matched_name <- best$FULLNAME
            md           <- best$match_dist
          } 
        
        ##using route matching (direct) for numbered
          else {
            num_pattern <- paste0("(?<![0-9])", route_num, "\\s*$")
            matches <- network %>% filter(RTTYP == rttyp, !is.na(FULLNAME), str_detect(FULLNAME, num_pattern))
            if (nrow(matches) == 0) return(na_fallback)
            matched_name <- matches %>% st_drop_geometry() %>% count(FULLNAME, sort = TRUE) %>% slice(1) %>% pull(FULLNAME)
            md           <- NA_real_
          }
        
        st_sf(matched_name = matched_name, match_dist = md, geometry = st_union(matches))
      }
    
    ##shared group-runner: given a pulled network, match every row in the group
      match_group <- function(group_rows, network, statefips, countyfips) {
        na_fallback_row <- function() tibble(
          matched_name = NA_character_,
          geometry = st_sfc(st_point(), crs = 4326)
        )
        group_rows %>%
          mutate(pulled_data = pmap(
            list(rttyp, main_route_num, main_route_designation_clean, is_named),
            function(rttyp, route_num, name, is_named) {
              if (is.null(network)) return(na_fallback_row())
              match_route(network, rttyp, route_num, name, is_named,
                          statefips, countyfips)
            }
          ))
      }
    
    ##per-STATE worker for NUMBERED routes (psr, pulled once per state, no corridor)
      pull_state_group <- function(group_rows) {
        statefips <- group_rows$state[1]
        
        network <- tryCatch({
          psr_m(state = statefips, year = data_year, progress_bar = FALSE) %>%
            st_transform(4326) %>%
            select(any_of(c("FULLNAME", "RTTYP")), geometry)
        }, error = function(e) {
          message(paste0("PSR pull failed (State: ", statefips, "): ", e$message))
          NULL
        })
        
        match_group(group_rows, network, statefips, group_rows$county[1])
      }
    
    ##per-COUNTY worker for NAMED roads (roads, corridor-scoped — needs S1400 locals)
      pull_county_group <- function(group_rows) {
        statefips  <- group_rows$state[1]
        countyfips <- group_rows$county[1]
        
        network <- tryCatch({
          tcv <- get_target_counties(statefips, countyfips)
          roads_m(state = statefips, county = tcv,
                  year = data_year, progress_bar = FALSE) %>%
            st_transform(4326) %>%
            select(any_of(c("FULLNAME", "RTTYP")), geometry)
        }, error = function(e) {
          message(paste0("Roads pull failed (State: ", statefips,
                         ", County: ", countyfips, "): ", e$message))
          NULL
        })
        
        match_group(group_rows, network, statefips, countyfips)
      }
    
    
    ##applying function (two parallel passes, then recombine)
      plan(multisession, workers = 6)
      
      run_time <- system.time({
        
        ##numbered routes
          numbered_geo <- if (nrow(main_route_numbered) > 0) {
            main_route_numbered %>%
              group_split(state) %>%
              future_map(pull_state_group,
                         .progress = TRUE,
                         .options = furrr_options(
                           seed    = TRUE,
                           globals = c("match_route", "match_group", "pull_state_group",
                                       "psr_m", "tig_cache", "data_year", "max_stringdist"),
                           packages = c("tigris", "sf", "dplyr", "stringr", "stringdist",
                                        "tidyr", "purrr", "memoise")
                         )) %>%
              bind_rows()
          } else NULL
        
        ##named routes
          named_geo <- if (nrow(main_route_named) > 0) {
            main_route_named %>%
              group_split(state, county) %>%
              future_map(pull_county_group,
                         .progress = TRUE,
                         .options = furrr_options(
                           seed    = TRUE,
                           globals = c("match_route", "match_group", "pull_county_group",
                                       "get_target_counties", "counties_m", "roads_m",
                                       "tig_cache", "data_year", "max_stringdist",
                                       "county_buffermiles"),
                           packages = c("tigris", "sf", "dplyr", "stringr", "stringdist",
                                        "tidyr", "purrr", "memoise")
                         )) %>%
              bind_rows()
          } else NULL
        
        ##recombining named and numbered
          main_routes_geo <- bind_rows(numbered_geo, named_geo) %>%
            unnest(pulled_data, keep_empty = TRUE) %>%
            st_as_sf() %>%
            select(project_title, state, county, rttyp, is_named, main_route_num,
                   main_route_designation, main_route_designation_clean,
                   matched_name, match_dist, geometry)
      })
      
      plan(sequential)
      rm(numbered_geo, named_geo)
      gc()
      
    ##catch
      if (nrow(main_routes_geo) == 0) stop("no routes matched — check inputs")
      
    ##matching rates
      n_counties <- main_route_matrix %>% distinct(state, county) %>% nrow()
      n_states   <- main_route_numbered %>% distinct(state) %>% nrow()
      n_matched  <- sum(!is.na(main_routes_geo$matched_name))
      message(sprintf("Done: %d routes (%d numbered / %d named), %d/%d matched, %.1f min elapsed",
                      nrow(main_routes_geo),
                      nrow(main_route_numbered), nrow(main_route_named),
                      n_matched, nrow(main_routes_geo),
                      run_time["elapsed"] / 60))

  ##creating relevant intermediate dataframe
    main_routes_intermediate <- main_route %>%
      mutate(
        state  = state_fips,
        county = substr(county_fips, 3, 5)
      ) %>%
      select(project_title, state, county, main_route_designation, rttyp, main_route_num) %>%
      left_join(
        (main_routes_geo %>% 
          mutate(is_geom_empty = st_is_empty(geometry)) %>% 
          select(state, county, main_route_designation, rttyp, 
                 main_route_num, matched_name, geometry, is_geom_empty)),
        by = c("state", "county", "main_route_designation", "rttyp", "main_route_num")
      ) %>%
      st_as_sf()
    
  ##plotting string distance to match
    main_routes_geo %>% st_drop_geometry() %>%
      filter(!is.na(match_dist)) %>%
      ggplot(aes(match_dist)) + geom_histogram(bins = 30, fill = "steelblue", color = "white") +
      theme_minimal(base_size = 14) + labs(x = "J-W String Distance (named routes)", y = "Count")
    
  ##saving data
    st_write(main_routes_intermediate, "/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/ella-temp/main_routes_intermediate/main_routes_intermediate.gpkg", delete_layer = TRUE)    
    
  ##clearing memory
    rm(main_route, main_route_matrix, main_route_named, main_route_numbered, 
       main_routes_geo, main_routes_intermediate)
    gc()
    
####Reference Geometry Extraction####
  ##finding unique geometries
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
    
  ##cleaning strings for input
    ##mutating county name
      refs_unique <- refs_unique %>% 
        mutate(county_name = case_when(
          str_detect(county_name, "(?i)\\s*County") ~ 
            str_replace(county_name, "(?i)(.*?)\\s*County", "\\1"),
          TRUE ~ county_name))  
        
    ##paired-boundary cleaner — row-wise (unchanged, defined before the mutate)
      clean_paired <- function(fn, state_name, county_name) {
        if (is.na(fn)) return(NA_character_)
        if (!str_detect(fn, "(?i)(State|County|Town)\\s*Line") ||
            !str_detect(fn, "\\w+\\s*-\\s*\\w+")) return(NA_character_)
        cp <- str_remove_all(fn, "(?i)\\s*(State|County|Town)\\s*Line")
        cp <- str_remove_all(cp, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")
        parts <- str_split(str_squish(cp), "\\s*-\\s*")[[1]] %>% str_squish()
        parts <- parts[parts != ""]
        if (length(parts) == 0) return(NA_character_)
        home <- c(str_to_lower(state_name), str_to_lower(county_name))
        neighbor <- parts[!str_to_lower(parts) %in% home]
        if (length(neighbor) == 0) neighbor <- parts[1]
        str_squish(neighbor[1])
      }
      
    ##TIGER suffix abbreviations (anchored to end-of-string)
      tiger_suffix <- c(
        "(?i)\\bRiver$"     = "Riv",
        "(?i)\\bAvenue$"    = "Ave",
        "(?i)\\bStreet$"    = "St",
        "(?i)\\bRoad$"      = "Rd",
        "(?i)\\bCreek$"     = "Crk",
        "(?i)\\bBrook$"     = "Brk",
        "(?i)\\bLake$"      = "Lk",
        "(?i)\\bHighway$"   = "Hwy",
        "(?i)\\bDrive$"     = "Dr",
        "(?i)\\bBoulevard$" = "Blvd",
        "(?i)\\bLane$"      = "Ln",
        "(?i)\\bCourt$"     = "Ct",
        "(?i)\\bPlace$"     = "Pl"
      )
      
    ##mutating feature names
      refs_unique <- refs_unique %>%
        mutate(
          old_feature_name = feature_name,
          extracted_direction = case_when(
            str_detect(feature_name, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])") ~
              str_extract(feature_name, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])") %>% tolower(),
            TRUE ~ NA_character_
          ),
          ##paired-boundary result, computed row-wise first
          paired_clean = pmap_chr(list(feature_name, state_name, county_name), clean_paired),
          feature_name = case_when(
            ##paired boundary (Alabama-Georgia State Line -> Georgia)
            !is.na(paired_clean) ~ paired_clean,
            
            ##county line, single neighbor
            str_detect(feature_name, "(?i)\\s*County\\s*Line") ~ {
              clean_step1 <- str_remove(feature_name, regex(county_name, ignore_case = TRUE))
              clean_step2 <- str_remove_all(clean_step1, "(?i)\\s*County\\s*Line|\\s*County")
              clean_step3 <- str_remove_all(clean_step2, "-")
              str_squish(clean_step3)
            },
            
            ##state line, single neighbor
            str_detect(feature_name, "(?i)State\\s*Line") ~ {
              clean_sl <- str_remove_all(feature_name, "(?i)\\s*State\\s*Line")
              clean_sl <- str_remove_all(clean_sl, "-")
              clean_sl <- str_remove_all(clean_sl, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")
              str_squish(clean_sl)
            },
            
            ##city / town limit, single place
            str_detect(feature_name, "(?i)City\\s*Limit|Town\\s*Line") ~ {
              clean_city <- str_remove_all(feature_name, "(?i)\\s*City\\s*Limits?\\s*|\\s*Town\\s*Lines?\\s*|\\s*Limits?\\s*")
              clean_city <- str_remove_all(clean_city, "-")
              clean_city <- str_remove_all(clean_city, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")
              str_squish(clean_city)
            },
            
            ##county — drop "County"
            str_detect(feature_name, "(?i)\\bCounty\\b") ~
              str_squish(str_remove_all(feature_name, "(?i)\\s*County\\b")),
            
            ##railroad
            str_detect(feature_name, "(?i)Rail\\s*road|Railway|\\bRR\\b|\\bRwy\\b") ~ {
              clean_rr <- str_replace_all(feature_name, "(?i)\\s*Rail\\s*road", " RR")
              clean_rr <- str_replace_all(clean_rr, "(?i)\\s*Railway", " Rlwy")
              str_squish(clean_rr)
            },
            
            ##routes — prefix-based (State Highway 181 -> State Hwy 181, etc.)
            str_detect(feature_name, "(?i)^Interstate\\s+\\S+") ~
              str_replace(feature_name, "(?i)^Interstate\\s+(\\S+)", "I- \\1"),
            str_detect(feature_name, "(?i)^US\\s+Route\\s+\\S+") ~
              str_replace(feature_name, "(?i)^US\\s+Route\\s+(\\S+)", "US Hwy \\1"),
            str_detect(feature_name, "(?i)^State\\s+Route\\s+\\S+") ~
              str_replace(feature_name, "(?i)^State\\s+Route\\s+(\\S+)", "State Rte \\1"),
            str_detect(feature_name, "(?i)^State\\s+Highway\\s+\\S+") ~
              str_replace(feature_name, "(?i)^State\\s+Highway\\s+(\\S+)", "State Hwy \\1"),
            
            TRUE ~ feature_name
          )
        ) %>%
        select(-paired_clean) %>%
        mutate(feature_name = str_replace_all(feature_name, tiger_suffix) %>% str_squish())
        
    ##matching TIGER fips format
      refs_unique <- refs_unique %>%
        mutate(state  = state_fips,
               county = substr(county_fips, 3, 5))
      
  ##reference endpoint functions
    ##pure matcher: reads from pre-loaded `pools`, no I/O
      match_ref <- function(pools, type, name, extracted_direction,
                            statefips, countyfips) {
        
        na_fallback <- tibble(
          matched_name = NA_character_,
          match_dist   = NA_real_,
          geometry = st_sfc(st_point(), crs = 4326)
        )
        
        if (is.null(type) || length(type) == 0 || is.na(type)) return(na_fallback)
        
        tryCatch({
          
          # --- 1. CITY CENTROID ---
          if (type == 'city') {
            if (is.null(pools$city_pool)) return(na_fallback)
            match_row <- pools$city_pool %>%
              mutate(match_dist = stringdist(tolower(NAME), tolower(name), method = "jw")) %>%
              arrange(match_dist) %>% slice(1)
            if (nrow(match_row) == 0 || match_row$match_dist > max_stringdist) return(na_fallback)
            return(match_row %>% st_centroid() %>%
                     mutate(match_dist = match_row$match_dist) %>%
                     select(matched_name = NAME, match_dist, geometry))
          }
          
          # --- 2. CITY LIMITS POLYGON ---
          if (type == 'city_limits') {
            if (is.null(pools$city_pool)) return(na_fallback)
            match_row <- pools$city_pool %>%
              mutate(match_dist = stringdist(tolower(NAME), tolower(name), method = "jw")) %>%
              arrange(match_dist) %>% slice(1)
            if (nrow(match_row) == 0 || match_row$match_dist > max_stringdist) return(na_fallback)
            
            result_sf <- match_row %>% st_centroid() %>%
              mutate(match_dist = match_row$match_dist) %>%
              select(matched_name = NAME, match_dist, geometry)
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
              cx <- centroid[1, "X"]; cy <- centroid[1, "Y"]
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
                mutate(border_name = paste0(match_row$NAME, " ", tools::toTitleCase(detected_direction), " City Limit Line"),
                       match_dist  = match_row$match_dist) %>%
                select(matched_name = border_name, match_dist, geometry)
            }
            return(result_sf)
          }
          
          # --- 3. COUNTY CENTROID ---
          if (type == 'county') {
            if (is.null(pools$counties_raw)) return(na_fallback)
            match_row <- pools$counties_raw %>% filter(COUNTYFP == countyfips)
            if (nrow(match_row) == 0) return(na_fallback)
            return(match_row %>% st_centroid() %>% st_transform(4326) %>%
                     mutate(match_dist = NA_real_) %>%
                     select(matched_name = NAME, match_dist, geometry))
          }
          
          # --- 4. COUNTY LINE ---
          if (type == 'county_line') {
            if (is.null(pools$counties_raw)) return(na_fallback)
            all_counties <- pools$counties_raw %>% st_transform(4326)
            target_county <- all_counties %>% filter(COUNTYFP == countyfips)
            if (nrow(target_county) == 0) return(na_fallback)
            
            clean_neighbor_name <- stringr::str_remove_all(tolower(name), "(?i)\\s*county\\s*line|\\s*county") %>%
              stringr::str_trim()
            neighbor_county <- all_counties %>%
              mutate(match_dist = stringdist(tolower(NAME), clean_neighbor_name, method = "jw")) %>%
              arrange(match_dist) %>% slice(1)
            
            result_sf <- NULL
            if (nrow(neighbor_county) == 0 || neighbor_county$match_dist > max_stringdist) {
              result_sf <- target_county %>%
                st_transform(4326) %>% st_cast("MULTILINESTRING") %>%
                mutate(border_name = paste0(NAME, " County Boundary Line"),
                       match_dist  = NA_real_) %>%
                select(matched_name = border_name, match_dist, geometry)
            } else {
              target_metric   <- st_transform(target_county, 9311)
              neighbor_metric <- st_transform(neighbor_county, 9311)
              target_buffered_metric <- st_buffer(target_metric, 10)
              shared_border_metric <- st_intersection(target_buffered_metric, neighbor_metric)
              if (nrow(shared_border_metric) == 0) {
                result_sf <- target_county %>%
                  st_cast("MULTILINESTRING") %>%
                  mutate(border_name = paste0(NAME, " County Boundary Line"),
                         match_dist  = NA_real_) %>%
                  select(matched_name = border_name, match_dist, geometry)
              } else {
                result_sf <- shared_border_metric %>%
                  st_transform(4326) %>%
                  mutate(border_name = paste0(target_county$NAME, "-", neighbor_county$NAME, " County Line"),
                         match_dist  = neighbor_county$match_dist) %>%
                  select(matched_name = border_name, match_dist, geometry)
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
              cx <- centroid[1, "X"]; cy <- centroid[1, "Y"]
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
                mutate(border_name = paste0(target_county$NAME, " ", tools::toTitleCase(detected_direction), " Boundary Line"),
                       match_dist  = NA_real_) %>%
                select(matched_name = border_name, match_dist, geometry)
            }
            return(result_sf)
          }
          
          # --- 5. HIGHWAY/ROAD LINES ---
          if (type %in% c('highway', 'road')) {
            if (is.null(pools$network)) return(na_fallback)
            scored <- pools$network %>%
              filter(!is.na(FULLNAME)) %>%
              mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
            best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
            if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
            road_union <- scored %>% filter(FULLNAME == best$FULLNAME) %>% st_union()
            return(st_sf(matched_name = best$FULLNAME, match_dist = best$match_dist, geometry = road_union))
          }
          
          # --- 6. WATERWAY (name match on linear water) ---
          if (type == 'waterway') {
            if (is.null(pools$water)) return(na_fallback)
            scored <- pools$water %>%
              filter(!is.na(FULLNAME)) %>%
              mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
            best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
            if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
            water_union <- scored %>% filter(FULLNAME == best$FULLNAME) %>% st_union()
            return(st_sf(matched_name = best$FULLNAME, match_dist = best$match_dist, geometry = water_union))
          }
          
          # --- 7. RAILROAD CROSSING (name match on rails) ---
          if (type == 'railroad_crossing') {
            if (is.null(pools$rails)) return(na_fallback)
            scored <- pools$rails %>%
              filter(!is.na(FULLNAME),
                     !str_detect(FULLNAME, "(?i)^\\s*railroad\\s*$"),   # drop bare "Railroad"
                     str_length(FULLNAME) >= 5) %>%                      # drop too-short generics
              mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
            best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
            if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
            rail_union <- scored %>% filter(FULLNAME == best$FULLNAME) %>% st_union()
            return(st_sf(matched_name = best$FULLNAME, match_dist = best$match_dist, geometry = rail_union))
          }
          
          # --- 8. STATE LINE (same logic as county_line, on states) ---
          if (type == 'state_line') {
            if (is.null(pools$states_raw)) return(na_fallback)
            all_states <- pools$states_raw %>% st_transform(4326)
            target_state <- all_states %>% filter(STATEFP == statefips)
            if (nrow(target_state) == 0) return(na_fallback)
            
            clean_neighbor_name <- stringr::str_remove_all(tolower(name), "(?i)\\s*state\\s*line|\\s*line") %>%
              stringr::str_trim()
            neighbor_state <- all_states %>%
              mutate(match_dist = stringdist(tolower(NAME), clean_neighbor_name, method = "jw")) %>%
              arrange(match_dist) %>% slice(1)
            
            result_sf <- NULL
            if (nrow(neighbor_state) == 0 || neighbor_state$match_dist > max_stringdist) {
              result_sf <- target_state %>%
                st_transform(4326) %>% st_cast("MULTILINESTRING") %>%
                mutate(border_name = paste0(NAME, " State Boundary Line"),
                       match_dist  = NA_real_) %>%
                select(matched_name = border_name, match_dist, geometry)
            } else {
              target_metric   <- st_transform(target_state, 9311)
              neighbor_metric <- st_transform(neighbor_state, 9311)
              target_buffered_metric <- st_buffer(target_metric, 10)
              shared_border_metric <- st_intersection(target_buffered_metric, neighbor_metric)
              if (nrow(shared_border_metric) == 0) {
                result_sf <- target_state %>%
                  st_cast("MULTILINESTRING") %>%
                  mutate(border_name = paste0(NAME, " State Boundary Line"),
                         match_dist  = NA_real_) %>%
                  select(matched_name = border_name, match_dist, geometry)
              } else {
                result_sf <- shared_border_metric %>%
                  st_transform(4326) %>%
                  mutate(border_name = paste0(target_state$NAME, "-", neighbor_state$NAME, " State Line"),
                         match_dist  = neighbor_state$match_dist) %>%
                  select(matched_name = border_name, match_dist, geometry)
              }
            }
            
            detected_direction <- case_when(
              str_detect(name, "(?i)\\bnorth\\b") ~ "north",
              str_detect(name, "(?i)\\bsouth\\b") ~ "south",
              str_detect(name, "(?i)\\beast\\b")  ~ "east",
              str_detect(name, "(?i)\\bwest\\b")  ~ "west",
              TRUE ~ NA_character_
            )
            is_part_of_state_name <- !is.na(detected_direction) &&
              str_detect(tolower(target_state$NAME), detected_direction)
            
            if (!is.na(detected_direction) && !is_part_of_state_name &&
                str_detect(result_sf$matched_name[1], "(?i)Boundary Line")) {
              target_metric <- st_transform(target_state, 9311)
              boundary_lines <- st_cast(target_metric, "MULTILINESTRING")
              bbox <- st_bbox(target_metric)
              centroid <- st_coordinates(st_centroid(st_union(target_metric)))
              cx <- centroid[1, "X"]; cy <- centroid[1, "Y"]
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
                mutate(border_name = paste0(target_state$NAME, " ", tools::toTitleCase(detected_direction), " Boundary Line"),
                       match_dist  = NA_real_) %>%
                select(matched_name = border_name, match_dist, geometry)
            }
            return(result_sf)
          }
          
          # --- 9. OTHER LANDMARK (TIGER landmarks, jw on FULLNAME) ---
          if (type == 'other_landmark') {
            if (is.null(pools$landmarks) || nrow(pools$landmarks) == 0) return(na_fallback)
            scored <- pools$landmarks %>%
              filter(!is.na(FULLNAME), FULLNAME != "") %>%
              mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
            best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
            if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
            lm_geom <- scored %>% filter(FULLNAME == best$FULLNAME) %>% st_union()
            return(st_sf(matched_name = best$FULLNAME, match_dist = best$match_dist, geometry = lm_geom))
          }
          
          return(na_fallback)
          
        }, error = function(e) {
          message(paste0("Match error for ", type, " (State: ", statefips,
                         ", County: ", countyfips, "): ", e$message))
          return(na_fallback)
        })
      }
      
    ##per-county worker: pull each NEEDED layer once, match all refs in the county
      pull_ref_county_group <- function(group_rows) {
        statefips  <- group_rows$state[1]
        countyfips <- group_rows$county[1]
        types      <- unique(group_rows$anchor_type)
        
        pools <- tryCatch({
          p <- list()
          
          # counties: needed by county/county_line directly; cheap, statewide (memoised per state)
          if (any(types %in% c('county', 'county_line'))) {
            p$counties_raw <- counties_m(state = statefips, cb = TRUE,
                                         year = data_year, progress_bar = FALSE)
          }
          
          # corridor vector only if a corridor-scoped layer is needed
          tcv <- if (any(types %in% c('city', 'city_limits', 'highway', 'road', 'waterway'))) {
            get_target_counties(statefips, countyfips)
          } else countyfips
          
          # city pool: subdivisions (corridor) + places (statewide), built once
          if (any(types %in% c('city', 'city_limits'))) {
            subdiv <- subdiv_m(state = statefips, county = tcv,
                               year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(NAME, geometry)
            places <- places_m(state = statefips, year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(NAME, geometry)
            p$city_pool <- bind_rows(subdiv, places)
          }
          
          # waterways: linear_water is corridor-scoped (state + county), like roads
          if ('waterway' %in% types) {
            p$water <- linear_water_m(state = statefips, county = tcv,
                                      year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
          }
          
          # railroads: rails is statewide (no county arg), memoised per state
          if ('railroad_crossing' %in% types) {
            p$rails <- rails_m(year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
          }
          
          # states: single national pull, needed for state_line
          if ('state_line' %in% types) {
            p$states_raw <- states_m(cb = TRUE, year = data_year, progress_bar = FALSE)
          }
          
          # landmarks: point + area, statewide (memoised per state)
          if ('other_landmark' %in% types) {
            lm_pt <- tryCatch(
              landmarks_m(state = statefips, type = "point", year = data_year, progress_bar = FALSE) %>%
                st_transform(4326) %>% select(any_of(c("FULLNAME")), geometry),
              error = function(e) NULL
            )
            lm_ar <- tryCatch(
              landmarks_m(state = statefips, type = "area", year = data_year, progress_bar = FALSE) %>%
                st_transform(4326) %>% select(any_of(c("FULLNAME")), geometry),
              error = function(e) NULL
            )
            p$landmarks <- bind_rows(lm_pt, lm_ar)
          }
          
          # road network: roads (corridor) + psr (statewide), combined once
          if (any(types %in% c('highway', 'road'))) {
            local_roads <- roads_m(state = statefips, county = tcv,
                                   year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
            major <- psr_m(state = statefips, year = data_year, progress_bar = FALSE) %>%
              st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
            net <- bind_rows(local_roads, major)
            if (!"FULLNAME" %in% colnames(net) && "NAME" %in% colnames(net)) {
              net <- net %>% rename(FULLNAME = NAME)
            }
            p$network <- net
          }
          p
        }, error = function(e) {
          message(paste0("Pull failed (State: ", statefips, ", County: ", countyfips, "): ", e$message))
          list()  # empty pools -> every ref in this county falls back
        })
        
        out <- group_rows %>%
          mutate(pulled_data = pmap(
            list(anchor_type, feature_name, extracted_direction),
            function(anchor_type, feature_name, extracted_direction) {
              match_ref(pools, anchor_type, feature_name, extracted_direction,
                        statefips, countyfips)
            }
          ))
        
        rm(pools); gc()
        out
      }
    
  ##pre-loading counties, places, psr
    walk(unique(refs_unique$state), ~{
      counties_m(state = .x, cb = TRUE, year = data_year, progress_bar = FALSE)
      places_m(state = .x, year = data_year, progress_bar = FALSE)
      psr_m(state = .x, year = data_year, progress_bar = FALSE)
    })
    
  ##applying function
    ##applying function
    plan(multisession, workers = 2)
    
    # the fields that actually determine geometry — NOT project_title / source / ref_tier
    match_keys <- c("state", "county", "anchor_type", "feature_name", "extracted_direction")
    
    # dedup to ONE row per distinct feature BEFORE matching
    refs_to_match <- refs_unique %>%
      filter(anchor_type %in% c('road', 'highway', 'county',
                                'city', 'county_line', 'city_limits',
                                'waterway', 'railroad_crossing', 'state_line',
                                'other_landmark')) %>%
      distinct(across(all_of(match_keys)), .keep_all = TRUE)
    
    group_list <- refs_to_match %>%
      group_split(state, county)
    
    run_time <- system.time({
      with_progress({
        p <- progressor(steps = length(group_list))
        
        refs_geo <- group_list %>%
          future_map(function(g) {
            t0  <- Sys.time()
            res <- pull_ref_county_group(g)
            p(sprintf("%s/%s done in %.0fs", g$state[1], g$county[1],
                      as.numeric(difftime(Sys.time(), t0, units = "secs"))))
            res
          },
          .options = furrr_options(
            seed    = TRUE,
            globals = c("p", "match_ref", "pull_ref_county_group", "get_target_counties",
                        "counties_m", "places_m", "psr_m", "subdiv_m", "roads_m",
                        "linear_water_m", "rails_m", "states_m", "landmarks_m",
                        "tig_cache", "data_year", "max_stringdist", "county_buffermiles"),
            packages = c("tigris", "sf", "dplyr", "stringr", "stringdist",
                         "tidyr", "purrr", "memoise")
          )) %>%
          bind_rows() %>%
          unnest(pulled_data, keep_empty = TRUE) %>%
          st_as_sf() %>%
          select(state, county, state_name, county_name, anchor_type,
                 old_feature_name, feature_name, extracted_direction,
                 matched_name, match_dist, geometry) %>%
          unique()
      })
    })
    
    plan(sequential)
    
    n_counties <- refs_unique %>%
      filter(anchor_type %in% c('city', 'city_limits', 'county', 'county_line',
                                'highway', 'road', 'waterway', 'railroad_crossing', 
                                'state_line', 'other_landmark')) %>%
      distinct(state, county) %>% nrow()
    n_matched  <- sum(!is.na(refs_geo$matched_name))
    message(sprintf("Done: %d refs, %d/%d matched, %d counties, %.1f min elapsed",
                    nrow(refs_geo), n_matched, nrow(refs_geo), n_counties,
                    run_time["elapsed"] / 60))
    
    refs_geo %>% st_drop_geometry() %>%
      group_by(anchor_type) %>%
      summarise(q50 = median(match_dist, na.rm = TRUE),
                q90 = quantile(match_dist, 0.9, na.rm = TRUE),
                n_na = sum(is.na(match_dist)))
    
    refs_geo_check <- refs_geo %>% 
      mutate(geom_empty = st_is_empty(geometry)) %>%
      st_drop_geometry() %>%
      relocate(matched_name, .after = old_feature_name)
    
    refs_geo_check %>% 
      ggplot(aes(x = match_dist)) +
      geom_histogram(bins = 30, fill = "steelblue", color = "white") + 
      theme_minimal(base_size = 14) + 
      labs(x = "J-W String Distance",y = "Count")
    
    table(refs_geo_check$geom_empty)
    
  ##merging with refs
    references_intermediate <- refs_unique %>%
      left_join(
        refs_geo %>%
          select(all_of(match_keys), matched_name, match_dist, geometry) %>%
          mutate(geom_empty = st_is_empty(geometry)),
        by = match_keys
      ) %>%
      st_as_sf(sf_column_name = "geometry")
  
  ##saving data
    st_write(references_intermediate, "/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/ella-temp/references_intermediate/references_intermediate.gpkg", delete_layer = TRUE)    
    
    