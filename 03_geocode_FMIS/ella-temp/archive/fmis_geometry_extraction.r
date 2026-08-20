####Setup####
  library(tidyverse)
  library(tigris)
  library(sf)
  library(ggplot2)
  library(stringdist)
  library(mapview)
  library(memoise)
  library(progressr)
  #unlink("~/.tigris_memoise", recursive = TRUE) #<- run when changing years to clear cache!!
  tig_cache <- cache_filesystem("~/.tigris_memoise")
  handlers(global = TRUE)
  handlers("txtprogressbar")
  
  setwd('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Code/ella-temp/')

####Configuration####
  ##global parameters
    max_stringdist     <- 0.1
    county_buffermiles <- 25
    data_year          <- 2021
    path               <- paste0('data/tiger_raw/data/', data_year)
    
  ##when to fall back to a tigris roads pull after local matching fails (opt: all/named/none)
    roads_fallback_scope <- "all"
  
  ##RTTYP values accepted when looking for a state route. <- needs more specific investigation
    state_route_rttyp <- c("S")
  
  ##anchor type selection <- currently working on only these types
    anchor_types <- c("city", "city_limits", "county", "county_line", "highway",
                      "railroad_crossing", "road", "state_line", "waterway")
  
  ##endpoints
    endpoints <- read.csv('data/fmis_endpoints/interstate_new_constr_10k_v5_20260710_113650.csv',
                          colClasses = "character", na.strings = "") %>%
      filter(statewide == "False") %>%
      filter(various_locs_unspecified == "False") %>%
      filter(multi_locs_specified == "False") %>%
      filter(!grepl(";", county_name)) %>%
      filter(ep_a_n_refs == 1 & ep_b_n_refs == 1) %>%
      filter(ep_a_ref1_anchor_type %in% anchor_types & ep_b_ref1_anchor_type %in% anchor_types) %>%
      filter(!is.na(main_route_num_match_status)) %>%
      rename(main_route_designation = main_alt_names)
  
  ##memoised tigris readers
    roads_m        <- memoise(tigris::roads,        cache = tig_cache)
    places_m       <- memoise(tigris::places,       cache = tig_cache)
    landmarks_m    <- memoise(tigris::landmarks,    cache = tig_cache)
    linear_water_m <- memoise(tigris::linear_water, cache = tig_cache)

####Data Setup####
  ##cache
    net_cache <- new.env(parent = emptyenv())
    
    cached <- function(key, fn) {
      if (!exists(key, envir = net_cache, inherits = FALSE)) {
        assign(key, fn(), envir = net_cache)
      }
      get(key, envir = net_cache, inherits = FALSE)
    }

  ##local data
    ##path helper for the cb_ files (useful for switching states, years)
      cb_path <- function(layer) {
        paste0(path, '/cb_', data_year, '_us_', layer, '_500k/cb_',
               data_year, '_us_', layer, '_500k.shp')
      }

    ##national polygons, UNSIMPLIFIED [boundary geometry must be exact]
      counties_raw_all <- read_sf(cb_path("county")) %>%
        st_transform(4326) %>% select(STATEFP, COUNTYFP, NAME, geometry)
      
      states_raw_all <- read_sf(cb_path("state")) %>%
        st_transform(4326) %>% select(STATEFP, NAME, geometry)
      
      cousub_all <- read_sf(cb_path("cousub")) %>%
        st_transform(4326) %>% select(STATEFP, COUNTYFP, NAME, geometry)
      
      rails_all <- read_sf(paste0(path, '/tl_', data_year, '_us_rails/tl_',
                                  data_year, '_us_rails.shp')) %>%
        st_transform(4326) %>% select(any_of("FULLNAME"), geometry)

    ##simplified  counties for corridor geometry test
      counties_simp <- counties_raw_all %>%
        st_transform(9311) %>%
        st_simplify(preserveTopology = TRUE, dTolerance = 2000) %>%
        st_transform(4326)

    ##state outlines, from the local file
      state_geoms <- states_raw_all %>% select(STATEFP, geometry)

    ##national primary roads
      primary_net <- read_sf(paste0(path, '/tl_', data_year, '_us_primaryroads/tl_',
                                    data_year, '_us_primaryroads.shp')) %>%
        st_transform(4326) %>%
        select(any_of(c("FULLNAME", "RTTYP")), geometry)

    ##per-state primary/secondary
      psr_dir <- paste0(path, '/primary_secondary')

  ##not data: function for target county + everything within the buffer
    get_target_counties <- function(statefips, countyfips,
                                    buf = county_buffermiles) {
      cached(paste0("tc_", statefips, "_", countyfips), function() {
        ac  <- counties_simp %>% filter(STATEFP == statefips)
        tgt <- ac %>% filter(COUNTYFP == countyfips)
        if (nrow(tgt) == 0) return(countyfips)
        d <- st_distance(tgt, ac)
        v <- ac %>% filter(as.numeric(d) <= buf * 1609.34) %>% pull(COUNTYFP)
        sort(unique(if (length(v) == 0) countyfips else v))
      })
    }

####Layer loaders####
  ##LOCAL: national primary, clipped to state
    get_primary <- function(statefips) {
      cached(paste0("pri_", statefips), function() {
        g <- state_geoms %>% filter(STATEFP == statefips)
        if (nrow(g) == 0) return(NULL)
        primary_net %>% st_filter(g, .predicate = st_intersects)
      })
    }
  
  ##LOCAL: primary/secondary, by state
    get_psr <- function(statefips) {
      cached(paste0("psr_", statefips), function() {
        f <- file.path(psr_dir,
                       paste0('tl_', data_year, '_', statefips, '_prisecroads'),
                       paste0('tl_', data_year, '_', statefips, '_prisecroads.shp'))
        tryCatch(
          read_sf(f) %>% st_transform(4326) %>%
            select(any_of(c("FULLNAME", "RTTYP")), geometry),
          error = function(e) {
            warning(sprintf("PSR read failed (state %s): %s", statefips, e$message))
            NULL
          })
      })
    }
    
  ##LOCAL: rails, clipped to state
    get_rails <- function(statefips) {
      cached(paste0("rail_", statefips), function() {
        g <- state_geoms %>% filter(STATEFP == statefips)
        if (nrow(g) == 0) return(NULL)
        rails_all %>% st_filter(g, .predicate = st_intersects)
      })
    }

  ##TIGRIS: all roads, by county FALLBACK ONLY: reached when local matching fails.
    get_roads <- function(statefips, countyfips) {
      cached(paste0("rds_", statefips, "_", countyfips), function() {
        tryCatch({
          tcv <- get_target_counties(statefips, countyfips)
          roads_m(state = statefips, county = tcv,
                  year = data_year, progress_bar = FALSE) %>%
            st_transform(4326) %>%
            filter(!is.na(FULLNAME)) %>%
            select(any_of(c("FULLNAME", "RTTYP", "MTFCC")), geometry)
        }, error = function(e) {
          warning(sprintf("Roads pull failed (state %s, county %s): %s",
                          statefips, countyfips, e$message))
          NULL
        })
      })
    }

  ##TIGRIS: places, by state
    get_places <- function(statefips) {
      cached(paste0("plc_", statefips), function() {
        tryCatch(
          places_m(state = statefips, year = data_year, progress_bar = FALSE) %>%
            st_transform(4326) %>% select(NAME, geometry),
          error = function(e) {
            warning(sprintf("Places pull failed (state %s): %s", statefips, e$message))
            NULL
          })
      })
    }

  ##TIGRIS: water
    get_water <- function(statefips, countyfips) {
      cached(paste0("wtr_", statefips, "_", countyfips), function() {
        tryCatch({
          tcv <- get_target_counties(statefips, countyfips)
          linear_water_m(state = statefips, county = tcv,
                         year = data_year, progress_bar = FALSE) %>%
            st_transform(4326) %>% select(any_of(c("FULLNAME", "NAME")), geometry)
        }, error = function(e) {
          warning(sprintf("Water pull failed (state %s, county %s): %s",
                          statefips, countyfips, e$message))
          NULL
        })
      })
    }

  ##not data: crs error capture function
    empty_match <- function() {
      st_sf(matched_name = NA_character_,
            match_dist   = NA_real_,
            geometry     = st_sfc(st_point(), crs = st_crs(4326)))
    }

  ##direction cleaner
    norm_direction <- function(d) {
      if (is.null(d) || length(d) != 1 || is.na(d)) return(NA_character_)
      d <- tolower(str_squish(d))
      if (grepl("^(n|north|northbound|nb)$", d)) return("north")
      if (grepl("^(s|south|southbound|sb)$", d)) return("south")
      if (grepl("^(e|east|eastbound|eb)$",  d)) return("east")
      if (grepl("^(w|west|westbound|wb)$",  d)) return("west")
      NA_character_ 
    }

####Matching: Main Route Geometry####
  ##mutating route names for better matching (using route names only when absolutely necessary tho)
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
          TRUE                                  ~ str_squish(main_route_designation)
        ),
        is_named = rttyp %in% c("M", "O") | is.na(main_route_num)
      ) %>%
      select(project_title, state_fips, county_fips, main_route_designation,
             main_route_designation_clean, rttyp, main_route_num, is_named)
  
  ##selecting for unique queries for processing
    main_route_matrix <- main_route %>%
      mutate(county = substr(county_fips, 3, 5),
             state  = state_fips) %>%
      distinct(state, county, rttyp, main_route_num, main_route_designation_clean,
               .keep_all = TRUE) %>%
      select(project_title, state, county, rttyp, main_route_num, main_route_designation,
             main_route_designation_clean, is_named) %>%
      filter(!(is.na(main_route_num) & is.na(main_route_designation)))
  
  ##route matcher function
    match_route <- function(network, rttyp, route_num, name, is_named,
                            statefips, countyfips) {
      
      na_fallback <- empty_match()
      
      if (is.null(network) || nrow(network) == 0)                return(na_fallback)
      if (is.null(rttyp) || is.na(rttyp))                        return(na_fallback)
      if (!is_named && (is.null(route_num) || is.na(route_num))) return(na_fallback)
      if (is_named  && (is.null(name)      || is.na(name)))      return(na_fallback)
      if (!"FULLNAME" %in% colnames(network))                    return(na_fallback)
      
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
        if (!"RTTYP" %in% colnames(network)) return(na_fallback)
        ok_rttyp    <- if (rttyp == "S") state_route_rttyp else rttyp
        num_pattern <- paste0("(?<![0-9])", route_num, "\\s*$")
        matches <- network %>% filter(RTTYP %in% ok_rttyp, !is.na(FULLNAME),
                                      str_detect(FULLNAME, num_pattern))
        if (nrow(matches) == 0) return(na_fallback)
        matched_name <- matches %>% st_drop_geometry() %>%
          count(FULLNAME, sort = TRUE) %>% slice(1) %>% pull(FULLNAME)
        md <- NA_real_
      }
      
      ##taking union of matches (roads generally in segments)
        g <- st_union(matches)
        st_crs(g) <- st_crs(4326)
        st_sf(matched_name = matched_name, match_dist = md, geometry = g)
    }
  
  ##pool chain: local first, tigris roads only as last resort
    route_pool_chain <- function(statefips, countyfips, rttyp, is_named) {
    chain <- list()
    if (!is_named && rttyp %in% c("I", "U")) {
      chain$primary <- function() get_primary(statefips)
    }
    chain$psr <- function() get_psr(statefips)
    
    use_fallback <- switch(roads_fallback_scope,
                           all   = TRUE,
                           named = is_named,
                           none  = FALSE,
                           FALSE)
    if (use_fallback) chain$roads <- function() get_roads(statefips, countyfips)
    chain
  }
  
  ##try each pool in order, stop at the first hit
    match_route_chain <- function(statefips, countyfips, rttyp, route_num, name, is_named) {
    chain <- route_pool_chain(statefips, countyfips, rttyp, is_named)
    for (nm in names(chain)) {
      res <- match_route(chain[[nm]](), rttyp, route_num, name, is_named,
                         statefips, countyfips)
      if (!is.na(res$matched_name[1])) {
        res$pool_used <- nm
        return(res)
      }
    }
    res <- empty_match()
    res$pool_used <- NA_character_
    res
  }
  
  ##applying route matching: one sequential pass, grouped by state
    group_list <- main_route_matrix %>% arrange(state) %>% group_split(state)
    
    run_time_routes <- system.time({
      with_progress({
        prog <- progressor(steps = length(group_list))
        
        main_routes_geo <- group_list %>%
          map(function(group_rows) {
            statefips <- group_rows$state[1]
            out <- group_rows %>%
              mutate(pulled_data = pmap(
                list(rttyp, main_route_num, main_route_designation_clean, is_named, county),
                function(rttyp, route_num, name, is_named, countyfips) {
                  match_route_chain(statefips, countyfips, rttyp, route_num, name, is_named)
                }
              ))
            prog(sprintf("state %s", statefips))
            out
          }) %>%
          bind_rows() %>%
          unnest(pulled_data, keep_empty = TRUE) %>%
          st_as_sf() %>%
          select(project_title, state, county, rttyp, is_named, main_route_num,
                 main_route_designation, main_route_designation_clean,
                 matched_name, match_dist, pool_used, geometry)
      })
    })
  
    if (nrow(main_routes_geo) == 0) stop("!!something went wrong no matches!!")
  
  ##matching rates & stats 4 fun
    message(sprintf("Routes: %d (%d numbered / %d named), %d matched, %.1f min",
                    nrow(main_routes_geo),
                    sum(!main_route_matrix$is_named), sum(main_route_matrix$is_named),
                    sum(!is.na(main_routes_geo$matched_name)),
                    run_time_routes["elapsed"] / 60))
  
  ##check for roads: which pool actually resolved each route
    main_routes_geo %>% st_drop_geometry() %>%
      count(is_named, pool_used) %>% print(n = 20)
    
    main_routes_geo %>% st_drop_geometry() %>%
      count(state, matched = !is.na(matched_name)) %>%
      pivot_wider(names_from = matched, values_from = n, values_fill = 0) %>%
      print(n = 60)
  
  ##creating relevant intermediate dataframe
    main_routes_intermediate <- main_route %>%
      mutate(state  = state_fips,
             county = substr(county_fips, 3, 5)) %>%
      select(project_title, state, county, main_route_designation, rttyp, main_route_num) %>%
      left_join(
        (main_routes_geo %>%
           mutate(is_geom_empty = st_is_empty(geometry)) %>%
           select(state, county, main_route_designation, rttyp,
                  main_route_num, matched_name, geometry, is_geom_empty)),
        by = c("state", "county", "main_route_designation", "rttyp", "main_route_num")
      ) %>%
      st_as_sf()
    
  ##summary figures: main route matching success
    main_routes_intermediate %>%
      st_drop_geometry() %>%
      mutate(matched = !is_geom_empty, route_class = case_when(
        is.na(main_route_designation) | main_route_designation == "" ~ "No main route",
        rttyp == "I" ~ "Interstate",
        rttyp == "U" ~ "US Route",
        rttyp == "S" ~ "State Route",
        rttyp == "M" ~ "Named/Local",
        rttyp == "O" ~ "Other",
        TRUE         ~ "Unknown")) %>%
      count(route_class, matched) %>%
      ggplot(aes(x = reorder(route_class, -n), y = n, fill = matched)) +
      geom_col() +
      scale_fill_manual(values = c(`TRUE` = "#4a7c59", `FALSE` = "#c04a4a"),
                        labels = c(`TRUE` = "Matched", `FALSE` = "No match"),
                        name = NULL) +
      labs(x = NULL, y = "Routes", title = "Main-route match rate by route type") +
      theme_minimal(base_size = 13) +
      theme(axis.text.x = element_text(angle = 30, hjust = 1), legend.position = "top")
  
  ##saving data for manipulation
    st_write(main_routes_intermediate,
             "data/extracted_geometry/main_routes_intermediate/main_routes_intermediate.gpkg",
             delete_layer = TRUE)
    
  ##closing out  
    rm(main_routes_intermediate); gc()

####Reference endpoint assembly####
  ##one unique!! row per endpoint (a, b), ref1 only [endpoints is already filtered to n_refs == 1 currently]
    build_refs <- function(ep) {
      endpoints %>%
        transmute(
          project_title, state_name, county_name,
          state    = state_fips,
          county   = substr(county_fips, 3, 5),
          endpoint = ep,
          anchor_type         = .data[[paste0("ep_", ep, "_ref1_anchor_type")]],
          old_feature_name    = .data[[paste0("ep_", ep, "_ref1_feature_name")]],
          extracted_direction = .data[[paste0("ep_", ep, "_ref1_rel_direction")]],
          rel_type            = .data[[paste0("ep_", ep, "_ref1_rel_type")]],
          rel_direction       = .data[[paste0("ep_", ep, "_ref1_rel_direction")]],
          rel_dist            = .data[[paste0("ep_", ep, "_ref1_rel_dist")]],
          rel_dist_unit       = .data[[paste0("ep_", ep, "_ref1_rel_dist_unit")]],
          rel_qualifier       = .data[[paste0("ep_", ep, "_ref1_rel_qualifier")]],
          mile_num            = .data[[paste0("ep_", ep, "_ref1_mile_num")]],
          exit_num            = .data[[paste0("ep_", ep, "_ref1_exit_num")]],
          precision           = .data[[paste0("ep_", ep, "_ref1_precision")]]
        )
    }

    refs_unique <- bind_rows(build_refs("a"), build_refs("b")) %>%
      as_tibble() %>%
      mutate(feature_name = str_squish(old_feature_name)) %>%
      filter(!is.na(anchor_type), !is.na(feature_name))

####Reference name cleaning####
  ##mutating county name for matching tiger
    refs_unique <- refs_unique %>%
      mutate(county_name = case_when(
        str_detect(county_name, "(?i)\\s*County") ~
          str_replace(county_name, "(?i)(.*?)\\s*County", "\\1"),
        TRUE ~ county_name))

  ##paired-boundary cleaner for county, state lines
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

  ##tiger suffix abbrv lookup
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

  ##mutating feature names [based on anchor type to match tigerline formats]
    refs_unique <- refs_unique %>%
      mutate(
        ##parsed direction wins; CSV rel_direction fills the gaps
          extracted_direction = coalesce(
            str_extract(feature_name,
                        "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])") %>% 
              tolower(), extracted_direction),
        
        ##paired-boundary result, computed row-wise first
          paired_clean = pmap_chr(list(feature_name, state_name, county_name), clean_paired),
          
          feature_name = case_when(
          
            ##paired boundary
              anchor_type %in% c("county_line", "state_line", "city_limits") &
                !is.na(paired_clean) ~ paired_clean,
            
            ##county line, single neighbor
              anchor_type == "county_line" &
                str_detect(feature_name, "(?i)\\s*County\\s*Line") ~ {
                  clean_step1 <- str_remove(feature_name, regex(county_name, ignore_case = TRUE))
                  clean_step2 <- str_remove_all(clean_step1, "(?i)\\s*County\\s*Line|\\s*County")
                  clean_step3 <- str_remove_all(clean_step2, "-")
                  str_squish(clean_step3)
                },
            
            ##state line, single neighbor
              anchor_type == "state_line" &
                str_detect(feature_name, "(?i)State\\s*Line") ~ {
                  clean_sl <- str_remove_all(feature_name, "(?i)\\s*State\\s*Line")
                  clean_sl <- str_remove_all(clean_sl, "-")
                  clean_sl <- str_remove_all(clean_sl, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")
                  str_squish(clean_sl)
                },
            
            ##city limit, single place
              anchor_type %in% c("city", "city_limits") &
                str_detect(feature_name, "(?i)City\\s*Limit|Town\\s*Line") ~ {
                  clean_city <- str_remove_all(feature_name, "(?i)\\s*City\\s*Limits?\\s*|\\s*Town\\s*Lines?\\s*|\\s*Limits?\\s*")
                  clean_city <- str_remove_all(clean_city, "-")
                  clean_city <- str_remove_all(clean_city, "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")
                  str_squish(clean_city)
                },
            
            ##county: drop "County"
              anchor_type == "county" &
                str_detect(feature_name, "(?i)\\bCounty\\b") ~
                str_squish(str_remove_all(feature_name, "(?i)\\s*County\\b")),
              
            ##railroad: ungated
              str_detect(feature_name, "(?i)Rail\\s*road|Railway|\\bRR\\b|\\bRwy\\b") ~ {
                clean_rr <- str_replace_all(feature_name, "(?i)\\s*Rail\\s*road", " RR")
                clean_rr <- str_replace_all(clean_rr, "(?i)\\s*Railway", " Rlwy")
                str_squish(clean_rr)
              },
              
            ##routes: prefix-based, ungated
              str_detect(feature_name, "(?i)^Interstate\\s+\\S+") ~
                str_replace(feature_name, "(?i)^Interstate\\s+(\\S+)", "I- \\1"),
              str_detect(feature_name, "(?i)^US\\s+Route\\s+\\S+") ~
                str_replace(feature_name, "(?i)^US\\s+Route\\s+(\\S+)", "US Hwy \\1"),
              str_detect(feature_name, "(?i)^State\\s+Route\\s+\\S+") ~
                str_replace(feature_name, "(?i)^State\\s+Route\\s+(\\S+)", "State Rte \\1"),
              str_detect(feature_name, "(?i)^State\\s+Highway\\s+\\S+") ~
                str_replace(feature_name, "(?i)^State\\s+Highway\\s+(\\S+)", "State Hwy \\1"),
              
            ##backup default  
              TRUE ~ feature_name
        )
      ) %>%
      select(-paired_clean) %>%
      mutate(feature_name = str_replace_all(feature_name, tiger_suffix) %>% str_squish())
    
  ##sanity check before matching
    setdiff(c("rel_type", "rel_direction", "rel_dist", "rel_dist_unit", "rel_qualifier"),
            names(refs_unique))  
    
    refs_unique %>%
      filter(anchor_type %in% c("highway", "road"), old_feature_name != feature_name) %>%
      count(old_feature_name, feature_name, sort = TRUE) %>%
      print(n = 40)

####Matching: Reference Endpoints####
  ##match ref function
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
          
          detected_direction <- norm_direction(extracted_direction)
          
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
            
            ##ADDED: unrecognized direction -> keep the centroid instead of erroring
            if (is.null(clipper_coords)) return(result_sf)
            
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
  
  ##anchor types whose geometry comes from the road network
    road_anchor_types <- c("highway", "road", "named_bridge")
  
  ##build pools from LOCAL layers only
    get_pools <- function(statefips, countyfips, types) {
    pl <- list()
    
    if (any(types %in% c('county', 'county_line')))
      pl$counties_raw <- counties_raw_all %>% filter(STATEFP == statefips)
    
    if ('state_line' %in% types)
      pl$states_raw <- states_raw_all
    
    if (any(types %in% c('city', 'city_limits'))) {
      tcv    <- get_target_counties(statefips, countyfips)
      subdiv <- cousub_all %>%
        filter(STATEFP == statefips, COUNTYFP %in% tcv) %>%
        select(NAME, geometry)
      pl$city_pool <- bind_rows(subdiv, get_places(statefips))
    }
    
    if ('waterway' %in% types)          pl$water <- get_water(statefips, countyfips)
    if ('railroad_crossing' %in% types) pl$rails <- get_rails(statefips)
    
    if (any(types %in% road_anchor_types)) {
      net <- get_psr(statefips)
      if (!is.null(net) && !"FULLNAME" %in% colnames(net) && "NAME" %in% colnames(net)) {
        net <- net %>% rename(FULLNAME = NAME)
      }
      pl$network <- net
      if ('named_bridge' %in% types) {
        pl$bridges <- bind_rows(net, get_landmarks(statefips))
      }
    }
    pl
  }
  
  ##add the tigris road network to an existing pool set [retry]
    augment_pools_with_roads <- function(pools, statefips, countyfips) {
    rds <- get_roads(statefips, countyfips)
    if (is.null(rds)) return(pools)
    pools$network <- bind_rows(rds, pools$network)
    if (!is.null(pools$bridges)) {
      pools$bridges <- bind_rows(rds, pools$bridges)
    }
    pools
  }
  
  ##per-county worker: local pass, then a roads retry for whatever missed
    pull_ref_county_group <- function(group_rows) {
    statefips  <- group_rows$state[1]
    countyfips <- group_rows$county[1]
    types      <- unique(group_rows$anchor_type)
    
    pools <- tryCatch(
      get_pools(statefips, countyfips, types),
      error = function(e) {
        warning(sprintf("Pool build failed (state %s, county %s): %s",
                        statefips, countyfips, e$message))
        list()
      })
    
    run_rows <- function(rows, pl) {
      pmap(list(rows$anchor_type, rows$feature_name, rows$extracted_direction),
           function(anchor_type, feature_name, extracted_direction) {
             match_ref(pl, anchor_type, feature_name, extracted_direction,
                       statefips, countyfips)
           })
    }
    
    out <- group_rows %>%
      mutate(pulled_data  = run_rows(., pools),
             used_fallback = FALSE)
    
    ##retry the road-based misses against a tigris pull
    if (roads_fallback_scope != "none") {
      miss <- map_lgl(out$pulled_data, ~ is.na(.x$matched_name[1])) &
        out$anchor_type %in% road_anchor_types
      if (any(miss)) {
        pools2 <- tryCatch(
          augment_pools_with_roads(pools, statefips, countyfips),
          error = function(e) pools)
        out$pulled_data[miss]  <- run_rows(out[miss, ], pools2)
        out$used_fallback[miss] <- TRUE
      }
    }
    out
  }
  
  ##applying: sequential, ordered by state so statewide caches stay warm
    match_keys <- c("state", "county", "anchor_type", "feature_name", "extracted_direction")
    
    refs_to_match <- refs_unique %>%
      filter(anchor_type %in% anchor_types) %>%
      distinct(across(all_of(match_keys)), .keep_all = TRUE)
    
    ref_group_list <- refs_to_match %>%
      arrange(state, county) %>%
      group_split(state, county)
    
    run_time_refs <- system.time({
      with_progress({
        prog <- progressor(steps = length(ref_group_list))
        
        refs_geo <- ref_group_list %>%
          map(function(g) {
            t0  <- Sys.time()
            res <- pull_ref_county_group(g)
            prog(sprintf("%s/%s in %.0fs", g$state[1], g$county[1],
                         as.numeric(difftime(Sys.time(), t0, units = "secs"))))
            res
          }) %>%
          bind_rows() %>%
          unnest(pulled_data, keep_empty = TRUE) %>%
          st_as_sf() %>%
          select(state, county, state_name, county_name, anchor_type,
                 old_feature_name, feature_name, extracted_direction,
                 matched_name, match_dist, used_fallback, geometry) %>%
          unique()
      })
    })

  ##diagnostics & sanity check on references
    message(sprintf("Refs: %d, %d matched, %d counties, %.1f min",
                    nrow(refs_geo), sum(!is.na(refs_geo$matched_name)),
                    refs_to_match %>% distinct(state, county) %>% nrow(),
                    run_time_refs["elapsed"] / 60))
    
    refs_geo %>% st_drop_geometry() %>%
      group_by(anchor_type) %>%
      summarise(n         = n(),
                nomatch   = sum(is.na(matched_name)),
                fallback  = sum(used_fallback),
                saved     = sum(used_fallback & !is.na(matched_name)),
                q50       = median(match_dist, na.rm = TRUE),
                q90       = quantile(match_dist, 0.9, na.rm = TRUE),
                .groups   = "drop")
    
    refs_geo_check <- refs_geo %>%
      mutate(geom_empty = st_is_empty(geometry)) %>%
      st_drop_geometry() %>%
      relocate(matched_name, .after = old_feature_name)
    
    table(refs_geo_check$anchor_type, refs_geo_check$geom_empty)
    
  ##summary figures: matching success, reference points
    ##setup
      references_intermediate_stat <- refs_geo %>%
        mutate(has_geom = !st_is_empty(geometry), 
               geom_correct = case_when(!has_geom ~ FALSE,
                                        is.na(match_dist) ~ TRUE,
                                        match_dist <= 0.1 ~ TRUE,
                                        TRUE ~ FALSE))
      
      
      osm_types <- c('other_landmark', 'named_bridge', 'other_terrain', 'exit_number', 'tunnel')
      
    ##plotting match correctness by anchor type
      references_intermediate_stat %>%
        filter(!is.na(anchor_type)) %>%
        st_drop_geometry() %>%
        mutate(status = case_when(anchor_type %in% osm_types ~ "Needs OSM",
                                  geom_correct               ~ "Correct",
                                  TRUE                       ~ "Incorrect")) %>%
        count(anchor_type, status) %>%
        ggplot(aes(x = reorder(anchor_type, -n), y = n, fill = status)) +
        geom_col() +
        scale_fill_manual(values = c("Correct" = "#4a7c59",
                                     "Incorrect" = "#c04a4a",
                                     "Needs OSM" = "#9e9e9e"),
                          name = NULL) +
        labs(x = NULL, y = "References", title = "Match correctness by anchor type") +
        theme_minimal(base_size = 13) +
        theme(axis.text.x = element_text(angle = 40, hjust = 1),
              legend.position = "top")
    
    ##plotting match correctness by anchor type, standardized bars
      references_intermediate_stat %>%
        filter(!is.na(anchor_type)) %>%
        st_drop_geometry() %>%
        count(anchor_type, geom_correct) %>%
        ggplot(aes(x = anchor_type, y = n, fill = geom_correct)) +
        geom_col(position = "fill") +
        scale_y_continuous(labels = scales::percent) +
        scale_fill_manual(values = c("TRUE" = "#4a7c59", "FALSE" = "#c04a4a"),
                          labels = c("TRUE" = "Correct", "FALSE" = "Incorrect"), name = NULL) +
        labs(x = NULL, y = "Share of references", title = "Match correctness rate by anchor type") +
        theme_minimal(base_size = 13) +
        theme(axis.text.x = element_text(angle = 40, hjust = 1), legend.position = "top")
      
    
    ##plotting cumulative jaro-winkler score dist
      references_intermediate_stat %>%
        st_drop_geometry() %>%
        filter(!is.na(match_dist)) %>%
        ggplot(aes(x = match_dist)) +
        geom_density(fill = "#4a7c59", alpha = 0.5, color = "#2f5038") +
        geom_vline(xintercept = 0.025, linetype = "dashed", color = "#c04a4a") +
        labs(x = "Jaro-Winkler distance", y = "Density",
             title = "Distribution of fuzzy-match distances",
             subtitle = "Dashed line = correctness threshold (0.025)") +
        theme_minimal(base_size = 13)
    
    ##plotting jaro-winkler score dist by type
      references_intermediate_stat %>%
        st_drop_geometry() %>%
        filter(!is.na(match_dist)) %>%
        filter(anchor_type != 'other_landmark') %>%
        ggplot(aes(x = match_dist, fill = anchor_type, color = anchor_type)) +
        geom_density(position = "stack", alpha = 0.5, aes(y = after_stat(count))) +
        geom_vline(xintercept = 0.025, linetype = "dashed", color = "black") +
        geom_vline(xintercept = 0.05, linetype = "dashed", color = "grey") +
        labs(x = "Jaro-Winkler distance", y = "Density", fill = NULL, color = NULL,
             title = "Match-distance distribution by anchor type") +
        theme_minimal(base_size = 13)

  ##saving data for manipulation file
    references_intermediate <- refs_unique %>%
      left_join(
        refs_geo %>%
          select(all_of(match_keys), matched_name, match_dist, geometry) %>%
          mutate(geom_empty = st_is_empty(geometry)),
        by = match_keys
      ) %>%
      st_as_sf(sf_column_name = "geometry")
    
    st_write(references_intermediate,
             "data/extracted_geometry/references_intermediate/references_intermediate.gpkg",
             delete_layer = TRUE)

  ##closing out 
    rm(list = ls(envir = net_cache), envir = net_cache)
    rm(main_route, main_route_matrix, main_routes_geo, primary_net, counties_simp)
    gc()
  
  