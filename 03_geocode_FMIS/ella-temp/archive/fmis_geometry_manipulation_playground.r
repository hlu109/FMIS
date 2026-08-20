####Setup####
  library(tidyverse)
  library(sf)
  library(ggplot2)
  library(mapview)
  library(lwgeom)

  ##loading intermediate files
    main_routes_intermediate <- read_sf('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/ella-temp/main_routes_intermediate/main_routes_intermediate.gpkg')
    references_intermediate <- read_sf('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Data/ella-temp/references_intermediate/references_intermediate.gpkg')
    
  ##self check of possible geometry changes
    ref_map_matrix <- expand.grid(
      rel_type      = unique(na.omit(references_intermediate$rel_type)), 
      rel_direction = unique(na.omit(references_intermediate$rel_direction)), 
      rel_dist_unit = unique(na.omit(references_intermediate$rel_dist_unit)), 
      rel_qualifier = unique(na.omit(references_intermediate$rel_qualifier)))
    
    ref_map_matrix_exist <- references_intermediate %>%
      distinct(rel_type, rel_direction, rel_dist_unit, rel_qualifier)
    
######Summary Stats####
  ##reference matching
    ##setup
      references_intermediate_stat <- references_intermediate %>%
        mutate(has_geom = !st_is_empty(geom), 
               geom_correct = case_when(!has_geom ~ FALSE,
                                        is.na(match_dist) ~ TRUE,
                                        match_dist <= 0.025 ~ TRUE,
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
      
      references_intermediate_stat %>% 
        with(table(anchor_type, geom_correct, useNA = "ifany"))
      
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
      
  ##main routes matching
    ##plotting match success rate
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
    
    ##specific issue: counties--need to investigate
      references_intermediate_county <- references_intermediate %>% 
        filter(anchor_type == 'county') %>%
        select(old_feature_name, matched_name, match_dist, geom)
    
  ##TEMP: filtering for single reference point, offset, existing geometries, both endpoints
    references_intermediate <- references_intermediate %>% 
      filter(n_refs == 1) %>%
      filter(geom_empty == FALSE) %>%
      add_count(project_title, name = "title_occurrences") %>%
      filter(n_refs == 1) %>%
      filter(title_occurrences == 2) %>%
      select(-title_occurrences) %>%
      filter(match_dist <= 0.05)
    
    
####Reference Offset Manipulation####
  ##parameters
    ##distance buffer
      dist_buffer_m <- 500  
      
    ##direction vectors
      dir_vec <- list(N  = c(0, 1), S  = c(0, -1), E  = c(1, 0), W  = c(-1, 0),
                      NE = c(1, 1)/sqrt(2), NW = c(-1, 1)/sqrt(2), 
                      SE = c(1, -1)/sqrt(2), SW = c(-1, -1)/sqrt(2))
    
  ##reference offset function 
    apply_rel <- function(geom, rel_type, rel_direction, rel_dist, rel_dist_unit) { 
      if (is.na(rel_type) || is.null(geom) || length(geom) == 0 || st_is_empty(geom)) return(geom)
      
      rel_dist <- as.numeric(rel_dist)
      
      d_m <- dplyr::case_when(rel_dist_unit == "ft" ~ rel_dist * 0.3048,
                              rel_dist_unit == "mi" ~ rel_dist * 1609.34,
                              TRUE                  ~ NA_real_)
      
      geom_m <- st_transform(st_sfc(geom, crs = 4326), 9311)
      
      out_m <- switch(rel_type,
                      "at"      = st_buffer(geom_m, dist_buffer_m),                 
                      "offset"  = {                         
                        v <- dir_vec[[rel_direction]]
                        if (is.null(v) || is.na(d_m)) geom_m 
                        else geom_m + c(v[1]*d_m, v[2]*d_m)
                        },
                      "near"    = st_buffer(geom_m, dist_buffer_m),
                      "side_of" = st_buffer(geom_m, dist_buffer_m),
                      geom_m)
      st_transform(st_sfc(out_m, crs = 9311), 4326)[[1]]
    }
  
  ##applying function
    references_adjusted <- references_intermediate %>%
      mutate(geometry_adj = purrr::pmap(list(geom, rel_type, rel_direction, 
                                             rel_dist, rel_dist_unit),
                                        apply_rel) %>% 
               st_sfc(crs = 4326)) %>%
      st_set_geometry("geometry_adj")
    
  ##check
    mapview(references_adjusted$geom[24], color = "green") +
      mapview(references_adjusted$geometry_adj[24], color = "red")
    
    mapview(references_adjusted$geom[64], color = "green") +
      mapview(references_adjusted$geometry_adj[64], color = "red")
    
####Intersection with Interstate####
  ##joining interstate geometry
    resolved <- references_adjusted %>%
      st_drop_geometry() %>% 
      mutate(ref_geom = references_adjusted$geometry_adj) %>% 
      left_join(main_routes_intermediate %>%
                  select(project_title, geom) %>%
                  st_drop_geometry() %>%
                  mutate(int_geom = st_geometry(main_routes_intermediate)),
                by = "project_title")
    
  ##function
    resolve_one <- function(ref_geom, int_geom) {
      empty_pt <- st_point()                                   # bare sfg, not sfc
      if (is.null(ref_geom) || is.null(int_geom)) return(empty_pt)
      if (st_is_empty(ref_geom) || st_is_empty(int_geom)) return(empty_pt)
      
      ref_m <- st_transform(st_sfc(ref_geom, crs = 4326), 9311)
      int_m <- st_transform(st_sfc(int_geom, crs = 4326), 9311)
      
      gtype <- as.character(st_geometry_type(ref_m))
      
      result_m <- if (gtype %in% c("POINT", "MULTIPOINT")) {
        np  <- st_nearest_points(ref_m, int_m)
        pts <- st_cast(np, "POINT")
        pts[2]                                                 # sfc, length 1
      } else {
        inter <- st_intersection(ref_m, int_m)
        if (length(inter) == 0 || all(st_is_empty(inter))) st_sfc(st_point(), crs = 9311) else inter
      }
      
      # ensure single geometry, back to 4326, extract bare sfg
      result_4326 <- st_transform(st_sfc(result_m, crs = 9311), 4326)
      if (length(result_4326) == 0 || all(st_is_empty(result_4326))) return(empty_pt)
      result_4326[[1]]                             
    }
    
  ##applying function
    resolved <- resolved %>%
      mutate(
        resolved_geom = purrr::map2(ref_geom, int_geom, resolve_one) %>%
          st_sfc(crs = 4326)
      ) %>%
      st_set_geometry("resolved_geom")
    
    
  ##check
    mapview(resolved$ref_geom[5], color = "green") +
      mapview(resolved$int_geom[5], color = "red") +
      mapview(resolved$resolved_geom[5], color = 'black') +
      mapview(resolved$ref_geom[6], color = "green") +
      mapview(resolved$int_geom[6], color = "red") +
      mapview(resolved$resolved_geom[6], color = 'black')
    
  ##check
    resolved %>%
      st_drop_geometry() %>%
      mutate(
        is_resolved = !st_is_empty(resolved$resolved_geom),
        int_present = !st_is_empty(resolved$int_geom)
      ) %>%
      group_by(project_title) %>%
      summarise(
        n_resolved  = sum(is_resolved),
        int_present = any(int_present),
        n_endpoints = n(),
        .groups = "drop"
      ) %>%
      count(
        both_resolved   = (n_resolved == 2 & n_endpoints == 2),
        interstate_ok   = int_present
      )
  
####Cropping Interstate####
  ##function
    crop_interstate <- function(int_geom, pt_a, pt_b) {
      empty_line <- st_linestring()
      bad <- function(g) is.null(g) || length(g) == 0 || st_is_empty(g)
      if (bad(int_geom) || bad(pt_a) || bad(pt_b)) return(empty_line)
      
      int_m <- st_transform(st_sfc(int_geom, crs = 4326), 9311)
      a_m   <- st_transform(st_sfc(pt_a,     crs = 4326), 9311)
      b_m   <- st_transform(st_sfc(pt_b,     crs = 4326), 9311)
      
      # reduce MULTIPOINT endpoints to a single POINT
      if (as.character(st_geometry_type(a_m)) != "POINT") a_m <- st_point_on_surface(a_m)
      if (as.character(st_geometry_type(b_m)) != "POINT") b_m <- st_point_on_surface(b_m)
      
      # merge the interstate to a single LINESTRING
      int_line <- tryCatch(st_line_merge(st_cast(int_m, "MULTILINESTRING")),
                           error = function(e) int_m)
      if (as.character(st_geometry_type(int_line)) != "LINESTRING") return(empty_line)
      
      fa <- st_line_locate_point(int_line, a_m)
      fb <- st_line_locate_point(int_line, b_m)
      if (is.na(fa) || is.na(fb)) return(empty_line)
      
      seg <- st_line_substring(int_line, min(fa, fb), max(fa, fb))
      st_transform(st_sfc(seg, crs = 9311), 4326)[[1]]
    }
    
  ##mutating df for one row per project
    crop_input <- resolved %>%
      st_drop_geometry() %>%
      mutate(resolved_geom = resolved$resolved_geom,
             int_geom      = resolved$int_geom) %>%
      # keep only viable projects (both endpoints resolved + interstate present)
      group_by(project_title) %>%
      filter(sum(!st_is_empty(resolved_geom)) == 2 & n() == 2 &
               any(!sapply(int_geom, function(g) is.null(g) || st_is_empty(g)))) %>%
      # order the two endpoints so 'source' a/b (or first/second) is deterministic
      arrange(project_title, source) %>%
      summarise(
        int_geom = int_geom[1],
        pt_a     = resolved_geom[1],
        pt_b     = resolved_geom[2],
        .groups  = "drop"
      )
    
  ##applying function
    cropped_interstates <- crop_input %>%
      mutate(
        cropped_geom = purrr::pmap(list(int_geom, pt_a, pt_b), crop_interstate) %>%
          st_sfc(crs = 4326)
      ) %>%
      st_sf()
    
  ##check
    bnd <- resolved %>%
      filter(anchor_type %in% c("county_line", "state_line"))
    
    gap_m <- mapply(function(ig, rg) {
      if (is.null(ig) || is.null(rg) || st_is_empty(st_sfc(ig)) || st_is_empty(st_sfc(rg))) return(NA_real_)
      as.numeric(st_distance(
        st_transform(st_sfc(ig, crs = 4326), 9311),
        st_transform(st_sfc(rg, crs = 4326), 9311)
      ))
    }, bnd$int_geom, bnd$resolved_geom)
    
    summary(gap_m)
    quantile(gap_m, c(0.5, 0.9), na.rm = TRUE)
    max(gap_m, na.rm = TRUE)
    
    
####Cropping Interstate####
    ##parameters
    snap_tol_m    <- 50      # tolerance (m) for snapping segment endpoints before merge
    locate_n      <- 2000    # samples along line for locating point fractions
    
    ##function
    crop_interstate <- function(int_geom, pt_a, pt_b) {
      empty_line <- st_linestring()                          # bare sfg fallback
      
      # viability guard — all three must be present and non-empty
      bad <- function(g) is.null(g) || length(g) == 0 || st_is_empty(g)
      if (bad(int_geom) || bad(pt_a) || bad(pt_b)) return(empty_line)
      
      # project to metric
      int_m <- st_transform(st_sfc(int_geom, crs = 4326), 9311)
      a_m   <- st_transform(st_sfc(pt_a,     crs = 4326), 9311)
      b_m   <- st_transform(st_sfc(pt_b,     crs = 4326), 9311)
      
      # reduce MULTIPOINT endpoints to a single POINT on the geometry
      if (as.character(st_geometry_type(a_m)) != "POINT") a_m <- st_point_on_surface(a_m)
      if (as.character(st_geometry_type(b_m)) != "POINT") b_m <- st_point_on_surface(b_m)
      
      # close small digitization gaps, then merge to ONE continuous linestring
      int_snapped <- st_snap(int_m, int_m, tolerance = snap_tol_m)
      int_line <- tryCatch(
        st_line_merge(st_cast(int_snapped, "MULTILINESTRING")),
        error = function(e) int_m
      )
      # if it still isn't a single LINESTRING, the interstate is genuinely gappy — bail
      if (as.character(st_geometry_type(int_line)) != "LINESTRING") return(empty_line)
      
      # locate a point's fraction (0-1) along the line by sampling evenly and
      # taking the nearest sample — uses only sf (no lwgeom locate function needed)
      locate <- function(line, point, n = locate_n) {
        samp <- st_cast(st_sfc(st_line_sample(line, n = n), crs = st_crs(line)), "POINT")
        (which.min(st_distance(point, samp)) - 1) / (n - 1)
      }
      
      fa <- locate(int_line, a_m)
      fb <- locate(int_line, b_m)
      if (length(fa) == 0 || length(fb) == 0 || is.na(fa) || is.na(fb)) return(empty_line)
      
      # extract the sub-line between the two fractions (order-independent)
      seg <- lwgeom::st_linesubstring(int_line, min(fa, fb), max(fa, fb))
      
      st_transform(st_sfc(seg, crs = 9311), 4326)[[1]]       # bare sfg in 4326
    }
    
    ##mutating df for one row per project
    crop_input <- resolved %>%
      st_drop_geometry() %>%
      mutate(resolved_geom = resolved$resolved_geom,
             int_geom      = resolved$int_geom) %>%
      # keep only viable projects (both endpoints resolved + interstate present)
      group_by(project_title) %>%
      filter(sum(!st_is_empty(resolved_geom)) == 2 & n() == 2 &
               any(!sapply(int_geom, function(g) is.null(g) || st_is_empty(g)))) %>%
      # order the two endpoints so 'source' a/b (or first/second) is deterministic
      arrange(project_title, source) %>%
      summarise(
        int_geom = int_geom[1],
        pt_a     = resolved_geom[1],
        pt_b     = resolved_geom[2],
        .groups  = "drop"
      )
    
    ##applying function
    cropped_interstates <- crop_input %>%
      mutate(
        cropped_geom = purrr::pmap(list(int_geom, pt_a, pt_b), crop_interstate) %>%
          st_sfc(crs = 4326)
      ) %>%
      st_sf()
    
    ##check — how many crops succeeded?
    cropped_interstates %>%
      mutate(empty = st_is_empty(cropped_geom)) %>%
      st_drop_geometry() %>%
      count(empty)
    
    
    
  ##check
    mapview(cropped_interstates$cropped_geom[41], color = 'red') +
      mapview(cropped_interstates$int_geom[41], color = 'blue') +
      mapview(cropped_interstates$pt_a[41], color = 'black') +
      mapview(cropped_interstates$pt_b[41], color = 'black')
    
    mapview(cropped_interstates$cropped_geom[42], color = 'red') +
      mapview(cropped_interstates$int_geom[42], color = 'blue') +
      mapview(cropped_interstates$pt_a[42], color = 'black') +
      mapview(cropped_interstates$pt_b[42], color = 'black')
    
    
    
    
    