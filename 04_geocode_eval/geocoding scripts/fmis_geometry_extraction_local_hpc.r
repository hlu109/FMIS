####Setup & Global Config####
  ##libraries needed
    .libPaths("~/Rlibs")
    suppressPackageStartupMessages({
      library(tidyverse)
      library(sf)
      library(stringdist)
      library(future.apply)
    })
  
  ##data & cache paths
    setwd('/home/egoecknerwald/fmis')    
    #setwd('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Code/ella-temp')
    tiger_data_year  <- 2025   # road/water/rail edges
    county_data_year <- 2013   # county/state polygons
    place_data_year  <- 2025   # incorporated places/CDPs/county subdivisions
    county_src      <- "zip"
    county_zip_stem <- "tl_2013_us_county"
    tiger_root       <- 'data/tiger_cb'
    cache_dir     <- 'data/tiger_cb/cache'
    endpoints_csv <- 'data/fmis_endpoints/interstate_new_constr_10k_v5_20260710_113650.csv'
    out_dir       <- 'data/extracted_geometry/by_state'
    
  ##clearing cache from prev run  
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(out_dir,   recursive = TRUE, showWarnings = FALSE)

  ##parallel configs
    N_WORKERS <- 25
    PARALLEL  <- TRUE

  ##matching parameters
    states_subset <- NULL
    drop_local_streets <- FALSE
    max_stringdist    <- 0.1
    state_route_rttyp <- c("S")
    anchor_types      <- c("city", "city_limits", "county", "county_line", "highway",
                           "railroad_crossing", "road", "state_line", "waterway")
    dir_anchor_types  <- c("county_line", "state_line", "city_limits")
    road_anchor_types <- c("highway", "road")

  ##fips/state name/state abbreviation lookup
    STATE_AB <- c(
      "01"="al","02"="ak","04"="az","05"="ar","06"="ca","08"="co","09"="ct","10"="de",
      "11"="dc","12"="fl","13"="ga","15"="hi","16"="id","17"="il","18"="in","19"="ia",
      "20"="ks","21"="ky","22"="la","23"="me","24"="md","25"="ma","26"="mi","27"="mn",
      "28"="ms","29"="mo","30"="mt","31"="ne","32"="nv","33"="nh","34"="nj","35"="nm",
      "36"="ny","37"="nc","38"="nd","39"="oh","40"="ok","41"="or","42"="pa","44"="ri",
      "45"="sc","46"="sd","47"="tn","48"="tx","49"="ut","50"="vt","51"="va","53"="wa",
      "54"="wv","55"="wi","56"="wy")
    
    STATE_NAME <- c(
      "01"="Alabama","02"="Alaska","04"="Arizona","05"="Arkansas","06"="California",
      "08"="Colorado","09"="Connecticut","10"="Delaware","11"="District of Columbia",
      "12"="Florida","13"="Georgia","15"="Hawaii","16"="Idaho","17"="Illinois",
      "18"="Indiana","19"="Iowa","20"="Kansas","21"="Kentucky","22"="Louisiana",
      "23"="Maine","24"="Maryland","25"="Massachusetts","26"="Michigan","27"="Minnesota",
      "28"="Mississippi","29"="Missouri","30"="Montana","31"="Nebraska","32"="Nevada",
      "33"="New Hampshire","34"="New Jersey","35"="New Mexico","36"="New York",
      "37"="North Carolina","38"="North Dakota","39"="Ohio","40"="Oklahoma","41"="Oregon",
      "42"="Pennsylvania","44"="Rhode Island","45"="South Carolina","46"="South Dakota",
      "47"="Tennessee","48"="Texas","49"="Utah","50"="Vermont","51"="Virginia",
      "53"="Washington","54"="West Virginia","55"="Wisconsin","56"="Wyoming")
  
  ##dividing large datasets by type to match
    road_mtfcc  <- c("S1100","S1200","S1400","S1500","S1630", "S1640", "S1710", 
                     "S1720", "S1730", "S1740", "S1750", "S1780", "S1820", "S1830")
    water_mtfcc <- c("H1100", "H2030", "H2040", "H2041", "H2051", "H2053", 
                     "H2060", "H2081", "H3010","H3020","H3013")
    rail_mtfcc  <- c("R1011","R1051","R1052")
    route_tiers <- list(primary = c("S1100"),
                        psr     = c("S1100","S1200"),
                        roads   = road_mtfcc)
    
    road_mtfcc_run <- if (drop_local_streets) setdiff(road_mtfcc, "S1400") else road_mtfcc
  
  ##suffix to match tigerline lookup
    tiger_suffix <- c(
      "(?i)\\bRiver$"="Riv", "(?i)\\bAvenue$"="Ave", "(?i)\\bStreet$"="St",
      "(?i)\\bRoad$"="Rd", "(?i)\\bCreek$"="Crk", "(?i)\\bBrook$"="Brk",
      "(?i)\\bLake$"="Lk", "(?i)\\bHighway$"="Hwy", "(?i)\\bDrive$"="Dr",
      "(?i)\\bBoulevard$"="Blvd", "(?i)\\bLane$"="Ln", "(?i)\\bCourt$"="Ct",
      "(?i)\\bPlace$"="Pl", "(?i)\\bNorth$"="N", "(?i)\\bSouth$"="S", 
      "(?i)\\bEast$"="E", "(?i)\\bWest$"="W", "(?i)\\bNorthwest$"="NW", 
      "(?i)\\bSouthwest$"="SW", "(?i)\\bNortheast$"="NE", 
      "(?i)\\bSoutheast$"="SE", "(?i)\\bParkway$"="Pkwy", 
      "(?i)\\bBayou$"="Byu")

####Helpers & Readers####
  ##reading    
    gdb_dsn <- function(statefips, edges = FALSE, year = tiger_data_year) {
      ab <- STATE_AB[[statefips]]
      if (is.null(ab)) return(NA_character_)
      stem <- sprintf("tlgdb_%d_a_%s_%s%s.gdb", year, statefips, ab,
                      if (edges) "_edges" else "")
      zip  <- file.path(tiger_root, year, paste0(stem, ".zip"))
      if (!file.exists(zip)) return(NA_character_)
      file.path("/vsizip", normalizePath(zip), stem)
    }
    
    have_state <- function(statefips, year = tiger_data_year)
      !is.na(gdb_dsn(statefips, year = year))
    
    resolve_layer <- function(dsn, candidates) {
      have <- tryCatch(sf::st_layers(dsn)$name, error = function(e) character(0))
      hit  <- have[tolower(have) %in% tolower(candidates)]
      if (!length(hit))
        stop(sprintf("none of [%s] found in %s (has: %s)",
                     paste(candidates, collapse = ", "), dsn, paste(have, collapse = ", ")))
      hit[1]
    }
  
  ##removing words from places names that would prevent matching  
    strip_lsad <- function(x) {
      x |>
        str_remove(paste0("(?i)\\s+(City and Borough|Census Area|Metropolitan Government|",
                          "Municipality|Municipio|Borough|Parish|County|CCD|CDP|",
                          "township|village|town|city)$")) |>
        str_squish()
    }
  
  ##function to extract direction  
    norm_direction <- function(d) {
      if (is.null(d) || length(d) != 1 || is.na(d)) return(NA_character_)
      d <- tolower(str_squish(d))
      if (grepl("^(n|north|northbound|nb)$", d)) return("north")
      if (grepl("^(s|south|southbound|sb)$", d)) return("south")
      if (grepl("^(e|east|eastbound|eb)$",  d)) return("east")
      if (grepl("^(w|west|westbound|wb)$",  d)) return("west")
      NA_character_
    }
  
  ##cached layer comes back renamed; restore the name on every cache read
    fix_geom_name <- function(x) {
      g <- attr(x, "sf_column")
      if (!identical(g, "geometry")) {
        names(x)[names(x) == g] <- "geometry"
        st_geometry(x) <- "geometry"
      }
      x
    }  
    
  ##non-matching observation catch  
    empty_match <- function() {
      st_sf(matched_name = NA_character_, match_dist = NA_real_,
            geometry = st_sfc(st_point(), crs = 4326))
    }
  
  ##function to build counties as needed (inherited by workers)
    build_national_counties <- function(year = county_data_year, src = county_src) {
      f    <- file.path(cache_dir, sprintf("counties_%d_%s.gpkg", year, src))
      need <- c("STATEFP", "COUNTYFP", "GEOID", "NAMELSAD", "NAME")
      
      if (file.exists(f)) {
        cached <- read_sf(f)
        if (all(need %in% names(cached))) return(fix_geom_name(cached))
        message("cached counties missing [", paste(setdiff(need, names(cached)), collapse = ", "),
                "] - rebuilding"); unlink(f)
      }
      
      ##cb_ files carry NAME + LSAD but no NAMELSAD; tl_ and tlgdb carry NAMELSAD
      tidy <- function(d) {
        stopifnot("GEOID" %in% names(d))
        nmls <- if ("NAMELSAD" %in% names(d)) d$NAMELSAD else d$NAME
        tibble(STATEFP  = substr(d$GEOID, 1, 2),
               COUNTYFP = substr(d$GEOID, 3, 5),
               GEOID    = d$GEOID,
               NAMELSAD = nmls,
               NAME     = strip_lsad(nmls)) |>
          st_sf(geometry = st_geometry(d))
      }
      
      if (src == "zip") {
        ##single national shapefile zip
        zip <- file.path(tiger_root, year, paste0(county_zip_stem, ".zip"))
        if (!file.exists(zip))
          stop(sprintf("missing %s", zip))
        dsn  <- sprintf("/vsizip/%s/%s.shp", normalizePath(zip), county_zip_stem)
        out  <- tidy(read_sf(dsn) |> st_transform(4326))
        nsrc <- 1L
        
      } else {
        ##per-state tlgdb; presence check must test the COUNTY vintage, not tiger_data_year
        fips <- names(STATE_AB)[map_lgl(names(STATE_AB), have_state, year = year)]
        if (!length(fips))
          stop(sprintf("no %d county gdbs found under %s/%d - nothing to build",
                       year, tiger_root, year))
        if (length(fips) < 51)
          warning(sprintf("only %d of 51 state gdbs present for %d; county_line neighbors in the missing states are unmatchable",
                          length(fips), year))
        out <- map_dfr(fips, function(ss) {
          dsn <- gdb_dsn(ss, year = year)
          lyr <- resolve_layer(dsn, c("County", "COUNTY", "County_and_Equivalent",
                                      "COUNTY_AND_EQUIVALENT"))
          tidy(read_sf(dsn, layer = lyr) |> st_transform(4326))
        })
        nsrc <- length(fips)
      }
      st_geometry(out) <- "geometry"
      
      ##drop territories the national file includes but the panel never uses
      out <- out[out$STATEFP %in% names(STATE_AB), ]
      
      ##connecticut check
      ct <- out$COUNTYFP[out$STATEFP == "09"]
      if (length(ct) && any(as.integer(ct) > 15))
        warning(sprintf("CT has COUNTYFP %s - looks like planning regions, not %d counties",
                        paste(sort(unique(ct)), collapse = ", "), year))
      message(sprintf("counties: %d rows from %d source(s), vintage %d (%s)",
                      nrow(out), nsrc, year, src))
      
      write_sf(out, f, delete_dsn = TRUE)
      out
    }
    
  ##function to build states as needed (inherited by workers)
    build_national_states <- function(counties, year = county_data_year, src = county_src) {
      f    <- file.path(cache_dir, sprintf("states_%d_%s.gpkg", year, src))
      need <- c("STATEFP", "NAME")
      if (file.exists(f)) {
        cached <- read_sf(f)
        if (all(need %in% names(cached))) return(fix_geom_name(cached))
        message("cached states stale - rebuilding"); unlink(f)
      }
      out <- counties %>%
        group_by(STATEFP) %>% summarise(geometry = st_union(geometry), .groups = "drop") %>%
        mutate(NAME = unname(STATE_NAME[STATEFP]))
      st_geometry(out) <- "geometry"
      write_sf(out, f, delete_dsn = TRUE)
      out
    }
  
  ##deriving rttyp from names (does not exist in downloaded data, need to reconstruct)
    derive_rttyp <- function(fullname) {
      case_when(
        is.na(fullname)                                                        ~ NA_character_,
        str_detect(fullname, "(?i)^I-\\s*\\d")                                 ~ "I",
        str_detect(fullname, "(?i)^U\\.?S\\.?\\s*(Hwy|Highway|Rte|Route)?\\s*\\d") ~ "U",
        str_detect(fullname, "(?i)^State\\s*(Hwy|Highway|Rte|Route|Rd)\\s*\\d") ~ "S",
        str_detect(fullname, "(?i)^(SR|SH)\\s*-?\\s*\\d")                      ~ "S",
        str_detect(fullname, "(?i)^[A-Z]{2}\\s*-\\s*\\d+$")                    ~ "S",
        str_detect(fullname, "(?i)^(County|Co)\\s*(Road|Rd|Hwy|Highway)\\s*\\d") ~ "C",
        str_detect(fullname, "(?i)^CR\\s*-?\\s*\\d")                           ~ "C",
        TRUE                                                                   ~ "M")
    }
  
  ##reading edges layer
    read_edges <- function(statefips, mtfcc, add_rttyp = FALSE) {
    dsn <- gdb_dsn(statefips, edges = TRUE)
    if (is.na(dsn)) { warning(sprintf("no edges gdb for state %s", statefips)); return(NULL) }
    lyr <- resolve_layer(dsn, c("All_Lines", "ALL_LINES"))
    q   <- sprintf("SELECT TLID, FULLNAME, MTFCC FROM %s WHERE MTFCC IN (%s) AND FULLNAME IS NOT NULL",
                   lyr, paste0("'", mtfcc, "'", collapse = ","))
    out <- tryCatch(read_sf(dsn, query = q) %>% st_transform(4326),
                    error = function(e) { warning(e$message); NULL })
    if (is.null(out) || nrow(out) == 0) return(NULL)
    if (add_rttyp) out$RTTYP <- derive_rttyp(out$FULLNAME)
    out
  }
  
  ##building pools to find data in
    read_city_pool <- function(statefips, year = place_data_year) {
      dsn <- gdb_dsn(statefips, year = year)
      if (is.na(dsn)) return(NULL)
      grab <- function(cand) {
        lyr <- tryCatch(resolve_layer(dsn, cand), error = function(e) NA_character_)
        if (is.na(lyr)) return(NULL)
        d  <- read_sf(dsn, layer = lyr) |> st_transform(4326)
        nm <- if ("NAME" %in% names(d)) d$NAME
        else if ("NAMELSAD" %in% names(d)) strip_lsad(d$NAMELSAD)
        else stop("no NAME/NAMELSAD in ", lyr)
        out <- tibble(NAME = nm, SRC = lyr) |> st_sf(geometry = st_geometry(d))
        st_geometry(out) <- "geometry"; out
      }
      cp <- bind_rows(grab("Incorporated_Place"),
                      grab("Census_Designated_Place"),
                      grab("County_Subdivision"))
      if (is.null(cp) || nrow(cp) == 0) NULL else cp
    }
    
    build_state_pools <- function(ss, types, net) {
      pl <- list()
      if (any(types %in% c('county', 'county_line')))
        pl$counties_raw <- fix_geom_name(counties_raw_all)
      if ('state_line' %in% types)
        pl$states_raw   <- fix_geom_name(states_raw_all)
      if (any(types %in% c('city', 'city_limits')))   pl$city_pool    <- read_city_pool(ss)
      if ('waterway' %in% types)                      pl$water        <- read_edges(ss, water_mtfcc)
      if ('railroad_crossing' %in% types)             pl$rails        <- read_edges(ss, rail_mtfcc)
      if (any(types %in% road_anchor_types))          pl$network      <- net
      pl
    }
    
    # build_state_pools <- function(ss, types, net) {
    #   pl <- list()
    #   if (any(types %in% c('county', 'county_line'))) {
    #     cr <- counties_raw_all
    #     if (attr(cr, "sf_column") != "geometry") st_geometry(cr) <- "geometry"
    #     pl$counties_raw <- cr
    #   }
    #   if ('state_line' %in% types) {
    #     sr <- states_raw_all
    #     if (attr(sr, "sf_column") != "geometry") st_geometry(sr) <- "geometry"
    #     pl$states_raw <- sr
    #   }
    #   if (any(types %in% c('city', 'city_limits')))   pl$city_pool    <- read_city_pool(ss)
    #   if ('waterway' %in% types)                      pl$water        <- read_edges(ss, water_mtfcc)
    #   if ('railroad_crossing' %in% types)             pl$rails        <- read_edges(ss, rail_mtfcc)
    #   if (any(types %in% road_anchor_types))          pl$network      <- net
    #   pl
    # }

####Main Route Matching Function####
  ##main matching function
    match_route <- function(network, rttyp, route_num, name, is_named) {
      na_fallback <- empty_match()
      if (is.null(network) || nrow(network) == 0) return(na_fallback)
      
      matches <- NULL; matched_name <- NA_character_; md <- NA_real_
      
      ##1. EXACT: numbered route via RTTYP + trailing number
        if (!is_named && !is.na(route_num) && "RTTYP" %in% names(network)) {
          ok_rttyp <- if (rttyp == "S") state_route_rttyp else rttyp
          pat      <- paste0("(?<![0-9])", route_num, "\\s*$")
          hits <- network %>% filter(RTTYP %in% ok_rttyp, str_detect(FULLNAME, pat))
          if (nrow(hits) > 0) {
            matches      <- hits
            matched_name <- hits %>% st_drop_geometry() %>%
              count(FULLNAME, sort = TRUE) %>% slice(1) %>% pull(FULLNAME)
            md <- NA_real_
          }
        }
      
      ## 2. JW fallback: match the designation string against ALL roads
        if (is.null(matches)) {
          if (is.null(name) || is.na(name)) return(na_fallback)
          scored <- network %>%
            mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
          best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
          if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
          matches      <- scored %>% filter(FULLNAME == best$FULLNAME)
          matched_name <- best$FULLNAME
          md           <- best$match_dist
        }
      
      g <- st_union(matches) %>% st_transform(4326)
      st_sf(matched_name = matched_name, match_dist = md, geometry = g)
    }
      
  ##tiered fallback function --> if not found, look in wider roads network
    match_route_chain <- function(net, rttyp, route_num, name, is_named) {
    if (is.null(net)) { r <- empty_match(); r$pool_used <- NA_character_; return(r) }
    tiers <- if (!is_named && rttyp %in% c("I", "U")) route_tiers
    else route_tiers[c("psr", "roads")]
    for (nm in names(tiers)) {
      res <- match_route(net %>% filter(MTFCC %in% tiers[[nm]]), rttyp, route_num, name, is_named)
      if (!is.na(res$matched_name[1])) { res$pool_used <- nm; return(res) }
    }
    r <- empty_match(); r$pool_used <- NA_character_; r
  }
  
  ##validation on rttyp extraction (just needed to fix the code above)
    validate_rttyp <- function(statefips) {
    net <- read_edges(statefips, road_mtfcc_run, add_rttyp = TRUE)
    if (is.null(net)) return(invisible(NULL))
    net %>% st_drop_geometry() %>% filter(MTFCC %in% c("S1100", "S1200")) %>%
      count(MTFCC, RTTYP) %>% group_by(MTFCC) %>%
      mutate(share = round(n / sum(n), 3)) %>% arrange(MTFCC, desc(n)) %>% print(n = 30)
    net %>% st_drop_geometry() %>% filter(MTFCC == "S1200", RTTYP == "M") %>%
      count(FULLNAME, sort = TRUE) %>% print(n = 25)
  }

####Reference Matching Function####
  ##function before clipping by direction (for anchor types where it applies)
    clip_by_direction <- function(geom_metric, direction) {
    lines <- tryCatch(st_cast(geom_metric, "MULTILINESTRING"), error = function(e) geom_metric)
    bb    <- st_bbox(geom_metric)
    ctr   <- st_coordinates(st_centroid(st_union(geom_metric)))
    cx <- ctr[1, "X"]; cy <- ctr[1, "Y"]
    d  <- max(bb$xmax - bb$xmin, bb$ymax - bb$ymin) * 2
    m <- switch(direction,
                "north" = matrix(c(cx-d, cy,   cx+d, cy,   cx+d, cy+d, cx-d, cy+d, cx-d, cy  ), ncol=2, byrow=TRUE),
                "south" = matrix(c(cx-d, cy-d, cx+d, cy-d, cx+d, cy,   cx-d, cy,   cx-d, cy-d), ncol=2, byrow=TRUE),
                "east"  = matrix(c(cx,   cy-d, cx+d, cy-d, cx+d, cy+d, cx,   cy+d, cx,   cy-d), ncol=2, byrow=TRUE),
                "west"  = matrix(c(cx-d, cy-d, cx,   cy-d, cx,   cy+d, cx-d, cy+d, cx-d, cy-d), ncol=2, byrow=TRUE),
                NULL)
    if (is.null(m)) return(NULL)
    st_intersection(lines, st_sfc(st_polygon(list(m)), crs = 9311)) %>% st_transform(4326)
  }
  
  ##boundary matching function (for county line, state line)    
    match_boundary <- function(target, neighbor_pool, name, direction, label) {
    na_fallback <- empty_match()
    if (nrow(target) == 0) return(na_fallback)
    
    clean_nb <- str_remove_all(tolower(name),
                               "(?i)\\s*(county|state)\\s*line|\\s*county|\\s*line") %>% str_trim()
    
    is_dir_only <- str_detect(clean_nb, "(?i)^(north|south|east|west)?$")
    nb <- if (nrow(neighbor_pool) == 0 || is_dir_only) neighbor_pool[0, ] else
      neighbor_pool %>%
      mutate(match_dist = stringdist(tolower(NAME), clean_nb, method = "jw")) %>%
      arrange(match_dist) %>% slice(1)
    
    tgt_m <- st_transform(target, 9311)
    
    ##Type 1: resolved neighbor -> shared border
    if (nrow(nb) > 0 && nb$match_dist <= max_stringdist) {
      shared <- st_intersection(st_buffer(tgt_m, 10), st_transform(nb, 9311))
      if (nrow(shared) > 0)
        return(shared %>% st_transform(4326) %>%
                 mutate(border_name = paste0(target$NAME, "-", nb$NAME, " ", label),
                        match_dist  = nb$match_dist) %>%
                 select(matched_name = border_name, match_dist, geometry))
    }
    
    ##Type 2: no neighbor, but a direction -> clip the outline
    dir <- norm_direction(direction)
    if (!is.na(dir) && !str_detect(tolower(target$NAME), dir)) {
      clipped <- clip_by_direction(tgt_m, dir)
      if (!is.null(clipped) && nrow(clipped) > 0)
        return(clipped %>%
                 mutate(border_name = paste0(target$NAME, " ", tools::toTitleCase(dir), " Boundary Line"),
                        match_dist  = NA_real_) %>%
                 select(matched_name = border_name, match_dist, geometry))
    }
    
    ##Type 3: whole outline
    target %>% st_cast("MULTILINESTRING") %>%
      mutate(border_name = paste0(NAME, " Boundary Line"), match_dist = NA_real_) %>%
      select(matched_name = border_name, match_dist, geometry)
  }
  
  ##main reference matching main function  
    match_ref <- function(pools, type, name, extracted_direction, statefips, countyfips) {
    na_fallback <- empty_match()
    if (is.null(type) || length(type) == 0 || is.na(type)) return(na_fallback)
    
    tryCatch({
      
      if (type %in% c('city', 'city_limits')) {
        if (is.null(pools$city_pool) || nrow(pools$city_pool) == 0) return(na_fallback)
        hit <- pools$city_pool %>%
          mutate(match_dist = stringdist(tolower(NAME), tolower(name), method = "jw")) %>%
          arrange(match_dist) %>% slice(1)
        if (nrow(hit) == 0 || hit$match_dist > max_stringdist) return(na_fallback)
        
        centroid_res <- hit %>% st_centroid() %>% select(matched_name = NAME, match_dist, geometry)
        if (type == 'city') return(centroid_res)
        
        dir <- norm_direction(extracted_direction)
        if (is.na(dir) || str_detect(tolower(hit$NAME), paste0("^", dir))) return(centroid_res)
        clipped <- clip_by_direction(st_transform(hit, 9311), dir)
        if (is.null(clipped) || nrow(clipped) == 0) return(centroid_res)
        return(clipped %>%
                 mutate(border_name = paste0(hit$NAME, " ", tools::toTitleCase(dir), " City Limit Line"),
                        match_dist  = hit$match_dist) %>%
                 select(matched_name = border_name, match_dist, geometry))
      }
      
      if (type == 'county') {
        if (is.null(pools$counties_raw)) return(na_fallback)
        hit <- pools$counties_raw %>% filter(STATEFP == statefips, COUNTYFP == countyfips)
        if (nrow(hit) == 0) return(na_fallback)
        return(hit %>% st_centroid() %>% mutate(match_dist = NA_real_) %>%
                 select(matched_name = NAME, match_dist, geometry))
      }
      
      if (type == 'county_line') {
        if (is.null(pools$counties_raw)) return(na_fallback)
        idx <- which(pools$counties_raw$STATEFP == statefips &
                       pools$counties_raw$COUNTYFP == countyfips)
        if (length(idx) == 0) return(na_fallback)
        return(match_boundary(pools$counties_raw[idx[1], ],
                              pools$counties_raw[county_adj[[idx[1]]], ],
                              name, extracted_direction, "County Line"))
      }
      
      if (type == 'state_line') {
        if (is.null(pools$states_raw)) return(na_fallback)
        idx <- which(pools$states_raw$STATEFP == statefips)
        if (length(idx) == 0) return(na_fallback)
        return(match_boundary(pools$states_raw[idx[1], ],
                              pools$states_raw[state_adj[[idx[1]]], ],
                              name, extracted_direction, "State Line"))
      }
      
      pool <- switch(type,
                     highway = pools$network, road = pools$network,
                     waterway = pools$water, railroad_crossing = pools$rails, NULL)
      if (is.null(pool) || nrow(pool) == 0) return(na_fallback)
      if (type == 'railroad_crossing')
        pool <- pool %>% filter(!str_detect(FULLNAME, "(?i)^\\s*railroad\\s*$"),
                                str_length(FULLNAME) >= 5)
      
      scored <- pool %>%
        mutate(match_dist = stringdist(tolower(FULLNAME), tolower(name), method = "jw"))
      best <- scored %>% st_drop_geometry() %>% slice_min(match_dist, n = 1, with_ties = FALSE)
      if (nrow(best) == 0 || best$match_dist > max_stringdist) return(na_fallback)
      g <- scored %>% filter(FULLNAME == best$FULLNAME) %>% st_union() %>% st_transform(4326)
      st_sf(matched_name = best$FULLNAME, match_dist = best$match_dist, geometry = g)
      
    }, error = function(e) {
      msg <- conditionMessage(e); p <- e$parent
      while (!is.null(p)) { msg <- paste(msg, conditionMessage(p), sep = " | "); p <- p$parent }
      message(sprintf("Match error %s (%s/%s): %s", type, statefips, countyfips, msg))
      na_fallback
    })
  }

####Load & Clean Endpoints####
  ##opening and filtering    
    endpoints <- read.csv(endpoints_csv, colClasses = "character", na.strings = "") %>%
      mutate(state_fips  = str_pad(state_fips,  2, "left", "0"),
             county_fips = str_pad(county_fips, 5, "left", "0")) %>%
      filter(statewide == "False",
             various_locs_unspecified == "False",
             multi_locs_specified == "False",
             !grepl(";", county_name),
             ep_a_n_refs == 1 & ep_b_n_refs == 1,
             ep_a_ref1_anchor_type %in% anchor_types & ep_b_ref1_anchor_type %in% anchor_types,
             !is.na(main_route_num_match_status)) %>%
      rename(main_route_designation = main_alt_names)
  
    stopifnot(all(substr(endpoints$county_fips, 1, 2) == endpoints$state_fips))
    if (!is.null(states_subset))
      endpoints <- endpoints %>% filter(state_fips %in% states_subset)
  
  ##creating main route df and normalizing to fit tigerline  
    main_route <- endpoints %>%
      mutate(
        rttyp = case_when(
          main_route_type == "interstate"  ~ "I",
          main_route_type == "us_route"    ~ "U",
          main_route_type == "state_route" ~ "S",
          main_route_type == "local_road"  ~ "M",
          TRUE                             ~ "O"),
        main_route_designation_clean = case_when(
          rttyp == "I" & !is.na(main_route_num) ~ paste0("I- ",        main_route_num),
          rttyp == "U" & !is.na(main_route_num) ~ paste0("US Hwy ",    main_route_num),
          rttyp == "S" & !is.na(main_route_num) ~ paste0("State Hwy ", main_route_num),
          TRUE                                  ~ str_squish(main_route_designation)),
        is_named = rttyp %in% c("M", "O") | is.na(main_route_num)) %>%
      select(project_title, state_fips, county_fips, main_route_designation,
             main_route_designation_clean, rttyp, main_route_num, is_named)
  
  ##creating reference df (renaming to old names bc don't want to redo code)  
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
        precision           = .data[[paste0("ep_", ep, "_ref1_precision")]])
  }
  
    refs_unique <- bind_rows(build_refs("a"), build_refs("b")) %>%
      as_tibble() %>%
      mutate(feature_name = str_squish(old_feature_name)) %>%
      filter(!is.na(anchor_type), !is.na(feature_name))
    
    refs_unique <- refs_unique %>%
      mutate(county_name = case_when(
        str_detect(county_name, "(?i)\\s*County") ~
          str_replace(county_name, "(?i)(.*?)\\s*County", "\\1"),
        TRUE ~ county_name))
  
  ##paired boundary cleaner for between county/state borders
    clean_paired <- function(fn, state_name, county_name) {
    if (is.na(fn)) return(NA_character_)
    if (!str_detect(fn, "(?i)(State|County|Town)\\s*Line") ||
        !str_detect(fn, "\\w+\\s*-\\s*\\w+")) return(NA_character_)
    cp <- str_remove_all(fn, "(?i)\\s*(State|County|Town)\\s*Line")
    parts <- str_split(str_squish(cp), "\\s*-\\s*")[[1]] %>% str_squish()
    parts <- parts[parts != ""]
    if (length(parts) == 0) return(NA_character_)
    home <- c(str_to_lower(state_name), str_to_lower(county_name))
    neighbor <- parts[!str_to_lower(parts) %in% home]
    if (length(neighbor) == 0) neighbor <- parts[1]
    str_squish(neighbor[1])
  }
  
  ##normailizing feature names in refs df to match better with tigerline  
    refs_unique <- refs_unique %>%
      mutate(
        extracted_direction = if_else(
          anchor_type %in% dir_anchor_types,
          coalesce(tolower(str_extract(feature_name,
                                       "(?i)(?<![A-Za-z])(North|South|East|West)(?![A-Za-z])")),
                   extracted_direction),
          NA_character_),
        
        paired_clean = pmap_chr(list(feature_name, state_name, county_name), clean_paired),
        
        feature_name = case_when(
          anchor_type %in% dir_anchor_types & !is.na(paired_clean) ~ paired_clean,
          
          anchor_type == "county_line" & str_detect(feature_name, "(?i)\\s*County\\s*Line") ~
            str_squish(str_remove_all(
              str_remove(feature_name, regex(county_name, ignore_case = TRUE)),
              "(?i)\\s*County\\s*Line|\\s*County|-")),
          
          anchor_type == "state_line" & str_detect(feature_name, "(?i)State\\s*Line") ~
            str_squish(str_remove_all(feature_name, "(?i)\\s*State\\s*Line|-")),
          
          anchor_type %in% c("city", "city_limits") &
            str_detect(feature_name, "(?i)City\\s*Limit|Town\\s*Line") ~
            str_squish(str_remove_all(feature_name,
                                      "(?i)\\s*City\\s*Limits?\\s*|\\s*Town\\s*Lines?\\s*|\\s*Limits?\\s*|-")),
          
          anchor_type == "county" & str_detect(feature_name, "(?i)\\bCounty\\b") ~
            str_squish(str_remove_all(feature_name, "(?i)\\s*County\\b")),
          
          str_detect(feature_name, "(?i)Rail\\s*road|Railway|\\bRR\\b|\\bRwy\\b") ~
            str_squish(str_replace_all(
              str_replace_all(feature_name, "(?i)\\s*Rail\\s*road", " RR"),
              "(?i)\\s*Railway", " Rlwy")),
          
          str_detect(feature_name, "(?i)^Interstate\\s+\\S+") ~
            str_replace(feature_name, "(?i)^Interstate\\s+(\\S+)", "I- \\1"),
          str_detect(feature_name, "(?i)^US\\s+Route\\s+\\S+") ~
            str_replace(feature_name, "(?i)^US\\s+Route\\s+(\\S+)", "US Hwy \\1"),
          str_detect(feature_name, "(?i)^State\\s+Route\\s+\\S+") ~
            str_replace(feature_name, "(?i)^State\\s+Route\\s+(\\S+)", "State Rte \\1"),
          str_detect(feature_name, "(?i)^State\\s+Highway\\s+\\S+") ~
            str_replace(feature_name, "(?i)^State\\s+Highway\\s+(\\S+)", "State Hwy \\1"),
          
          TRUE ~ feature_name)) %>%
      select(-paired_clean) %>%
      mutate(feature_name = str_replace_all(feature_name, tiger_suffix) %>% str_squish())

####Run & Combine####
  ##partitioning by state
    main_route_matrix <- main_route %>%
      mutate(state = state_fips) %>%
      distinct(state, rttyp, main_route_num, main_route_designation_clean, .keep_all = TRUE) %>%
      select(project_title, state, rttyp, main_route_num, main_route_designation,
             main_route_designation_clean, is_named) %>%
      filter(!(is.na(main_route_num) & is.na(main_route_designation)))
    
    match_keys <- c("state", "county", "anchor_type", "feature_name", "extracted_direction")
    refs_to_match <- refs_unique %>%
      filter(anchor_type %in% anchor_types) %>%
      distinct(across(all_of(match_keys)), .keep_all = TRUE)
    
    routes_by_state <- split(main_route_matrix, main_route_matrix$state)
    refs_by_state   <- split(refs_to_match,     refs_to_match$state)
    states_to_run   <- sort(union(names(routes_by_state), names(refs_by_state)))
  
  ##per state run
    run_state <- function(ss) {
    routes_ss <- routes_by_state[[ss]]
    refs_ss   <- refs_by_state[[ss]]
    t0  <- Sys.time()
    net <- read_edges(ss, road_mtfcc, add_rttyp = TRUE)
    
    if (!is.null(routes_ss) && nrow(routes_ss) > 0) {
      routes_out <- routes_ss %>%
        mutate(pulled_data = pmap(
          list(rttyp, main_route_num, main_route_designation_clean, is_named),
          function(rttyp, route_num, name, is_named)
            match_route_chain(net, rttyp, route_num, name, is_named))) %>%
        unnest(pulled_data, keep_empty = TRUE) %>% st_as_sf() %>%
        select(project_title, state, rttyp, is_named, main_route_num,
               main_route_designation, main_route_designation_clean,
               matched_name, match_dist, pool_used, geometry)
      write_sf(routes_out, file.path(out_dir, sprintf("routes_%s.gpkg", ss)), delete_dsn = TRUE)
    }
    
    if (!is.null(refs_ss) && nrow(refs_ss) > 0) {
      types <- unique(refs_ss$anchor_type)
      pools <- build_state_pools(ss, types, net)
      refs_out <- refs_ss %>%
        mutate(pulled_data = pmap(
          list(anchor_type, feature_name, extracted_direction, county),
          function(anchor_type, feature_name, extracted_direction, countyfips)
            match_ref(pools, anchor_type, feature_name, extracted_direction, ss, countyfips)),
          used_fallback = FALSE) %>%
        unnest(pulled_data, keep_empty = TRUE) %>% st_as_sf() %>%
        select(state, county, state_name, county_name, anchor_type,
               old_feature_name, feature_name, extracted_direction,
               matched_name, match_dist, used_fallback, geometry)
      write_sf(refs_out, file.path(out_dir, sprintf("refs_%s.gpkg", ss)), delete_dsn = TRUE)
    }
    
    rm(net); gc()
    as.numeric(difftime(Sys.time(), t0, units = "secs"))
    }
    
  ##combining
    combine_outputs <- function() {
    rf <- list.files(out_dir, "^refs_.*\\.gpkg$",   full.names = TRUE)
    rt <- list.files(out_dir, "^routes_.*\\.gpkg$", full.names = TRUE)
    message(sprintf("combining %d ref files, %d route files", length(rf), length(rt)))
    
    got  <- sub("^refs_(\\d+)\\.gpkg$", "\\1", basename(rf))
    want <- refs_to_match %>% distinct(state) %>% pull(state)
    gaps <- setdiff(want, got)
    if (length(gaps)) warning("no refs output for states: ", paste(gaps, collapse = ", "))
    
    if (length(rf)) {
      refs_geo <- do.call(rbind, lapply(rf, read_sf))
      st_geometry(refs_geo) <- "geometry"
      references_intermediate <- refs_unique %>%
        left_join(refs_geo %>%
                    select(all_of(match_keys), matched_name, match_dist, geometry) %>%
                    mutate(geom_empty = st_is_empty(geometry)),
                  by = match_keys) %>%
        st_as_sf(sf_column_name = "geometry")
      dir.create("data/extracted_geometry/references_intermediate", recursive = TRUE, showWarnings = FALSE)
      write_sf(references_intermediate,
               "data/extracted_geometry/references_intermediate/references_intermediate.gpkg",
               delete_layer = TRUE)
      message("wrote references_intermediate.gpkg (", nrow(references_intermediate), " rows)")
      
      refs_geo %>% st_drop_geometry() %>%
        group_by(anchor_type) %>%
        summarise(n = n(), nomatch = sum(is.na(matched_name)),
                  q50 = median(match_dist, na.rm = TRUE),
                  q90 = quantile(match_dist, 0.9, na.rm = TRUE), .groups = "drop") %>% print()
      refs_geo %>% mutate(geom_empty = st_is_empty(geometry)) %>% st_drop_geometry() %>%
        { table(.$anchor_type, .$geom_empty) } %>% print()
    }
    
    if (length(rt)) {
      routes_geo <- do.call(rbind, lapply(rt, read_sf))
      st_geometry(routes_geo) <- "geometry"
      main_routes_intermediate <- main_route %>%
        mutate(state = state_fips) %>%
        select(project_title, state, main_route_designation,
               main_route_designation_clean, rttyp, main_route_num) %>%
        left_join(routes_geo %>%
                    mutate(is_geom_empty = st_is_empty(geometry)) %>%
                    select(state, main_route_designation_clean, rttyp, main_route_num,
                           matched_name, geometry, is_geom_empty),
                  by = c("state", "main_route_designation_clean", "rttyp", "main_route_num")) %>%
        st_as_sf()
      dir.create("data/extracted_geometry/main_routes_intermediate", recursive = TRUE, showWarnings = FALSE)
      write_sf(main_routes_intermediate,
               "data/extracted_geometry/main_routes_intermediate/main_routes_intermediate.gpkg",
               delete_layer = TRUE)
      message("wrote main_routes_intermediate.gpkg (", nrow(main_routes_intermediate), " rows)")
    }
  }

####Run everything####
  ##building inheritable state & county polygons
    counties_raw_all <- build_national_counties()
    states_raw_all   <- build_national_states(counties_raw_all)
    county_adj <- st_touches(counties_raw_all)
    state_adj  <- st_touches(states_raw_all)
  
  ##sorting states largest first
    sz             <- map_int(states_to_run, ~ nrow(refs_by_state[[.x]] %||% data.frame()))
    states_ordered <- states_to_run[order(-sz)]
    
  ##running
    run_time <- system.time({
      if (PARALLEL && length(states_ordered) > 1) {
        plan(multicore, workers = min(N_WORKERS, length(states_ordered)))
        secs <- future_lapply(states_ordered, function(ss)
          tryCatch(run_state(ss),
                   error = function(e) { message(sprintf("state %s FAILED: %s", ss, conditionMessage(e))); NA_real_ }),
          future.seed = TRUE)
        plan(sequential)
      } else {
        secs <- lapply(states_ordered, function(ss)
          tryCatch(run_state(ss),
                   error = function(e) { message(sprintf("state %s FAILED: %s", ss, conditionMessage(e))); NA_real_ }))
      }
    })
  
    tibble(state = states_ordered, secs = unlist(secs)) %>% arrange(desc(secs)) %>% print(n = 60)
    message(sprintf("all states done in %.1f min", run_time["elapsed"] / 60))
    
    combine_outputs()
