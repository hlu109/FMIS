####Setup####
  library(tidyverse)
  library(sf)
  library(ggplot2)
  library(mapview)
  library(lwgeom)

  setwd('/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data/Code/ella-temp/extracted_geometry/')

  ##version control
    version <- "VAL_fmis_gis_5k_noninterstate_prompt_v6_20260812_123113_corrected"
  
  ##loading intermediate files
    main_routes_intermediate <- read_sf(paste0('main_routes_intermediate/main_routes_intermediate_', version, '.gpkg'))
    references_intermediate  <- read_sf(paste0('references_intermediate/references_intermediate_', version, '.gpkg'))
  
    ##import for stitched test--temp
      #main_routes_intermediate <- read_sf('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Code/ella-temp/extracted_geometry/main_routes_intermediate/main_routes_intermediate_stitched.gpkg')
      #references_intermediate <- read_sf('/Users/egoecknerwald/Library/CloudStorage/Dropbox/FHWA cost data/Code/ella-temp/extracted_geometry/references_intermediate/references_intermediate_stitched.gpkg')
      #mapview(references_intermediate$geom[6,], color = 'red') + mapview(references_intermediate_stitched$geom[6,])

####Reference Offset Manipulation####
  ##parameters
    ##distance buffer (meters)
      dist_buffer_m <- 100  
    
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
                    "at"      = geom_m,                 
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
    # offset <- which(references_adjusted$rel_type == "offset" & references_adjusted$geom_empty == FALSE & references_adjusted$anchor_type == 'highway')
    # 
    # mapview(references_adjusted$geom[24], color = "green") +
    #   mapview(references_adjusted$geometry_adj[24], color = "red")
    # 
    # mapview(references_adjusted$geom[64], color = "green") +
    #   mapview(references_adjusted$geometry_adj[64], color = "red")
    # 
    # mapview(references_adjusted$geom[offset[25]], color = "green") +
    #   mapview(references_adjusted$geometry_adj[offset[25]], color = "red")

####Checking####
  ##creating df for viewing stats
    references_intermediate_stat <- references_intermediate %>%
      mutate(has_geom = !st_is_empty(geom),
             geom_correct = case_when(!has_geom ~ FALSE,
                                      is.na(match_dist) ~ TRUE,
                                      match_dist <= 0.1 ~ TRUE,
                                      TRUE ~ FALSE)) 
    
  ##plotting reference success (by j-w matching < 0.1)
    osm_types <- c('other_landmark', 'named_bridge', 'other_terrain', 'exit_number', 'tunnel')
    references_intermediate_stat %>%
      filter(!is.na(anchor_type)) %>% st_drop_geometry() %>%
      mutate(status = case_when(anchor_type %in% osm_types ~ "Needs OSM",
                                geom_correct               ~ "Correct",
                                TRUE                       ~ "Incorrect")) %>%
      count(anchor_type, status) %>%
      ggplot(aes(reorder(anchor_type, -n), n, fill = status)) +
      geom_col() +
      scale_fill_manual(values = c(Correct = "#4a7c59", Incorrect = "#c04a4a", `Needs OSM` = "#9e9e9e"),
                        name = NULL) +
      labs(x = NULL, y = "References", title = "Match correctness by anchor type") +
      theme_minimal(base_size = 13) +
      theme(axis.text.x = element_text(angle = 40, hjust = 1), legend.position = "top")
    
  ##plotting main route success
    main_routes_intermediate %>%
      st_drop_geometry() %>%
      mutate(matched = !is_geom_empty, route_class = case_when(
        is.na(main_route_designation_clean) | main_route_designation_clean == "" ~ "No main route/Missing",
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
    
  ##view specific df subset
    View(references_intermediate_stat[which(references_intermediate_stat$anchor_type == "city"),])
  
    
####Joining dfs by project####
    ref_wide <- references_adjusted %>%
      mutate(geometry_adj = st_geometry(references_adjusted)) %>%
      as_tibble() %>%
      select(project_title, endpoint, geometry_adj) %>%
      group_by(project_title, endpoint) %>%
      summarise(
        geometry_adj = {
          g <- st_sfc(geometry_adj, crs = st_crs(references_adjusted))
          g <- g[!st_is_empty(g)]
          g <- st_make_valid(g)
          if (length(g) == 0)
            st_sfc(st_point(), crs = st_crs(references_adjusted))
          else
            st_sfc(st_union(g), crs = st_crs(references_adjusted))
        },
        .groups = "drop"
      ) %>%
      pivot_wider(names_from = endpoint, values_from = geometry_adj,
                  names_glue = "endpoint_{endpoint}_geom")
    ref_wide <- as_tibble(ref_wide)  
    
    projects_geom <- main_routes_intermediate %>%
      select(project_title, state, geom) %>%
      filter(!duplicated(project_title)) %>%
      rename(main_route_geom = geom) %>%
      left_join(ref_wide, by = "project_title")
    
    is_bad <- function(g) {
      vapply(g, function(x) is.null(x) || length(x) == 0 || st_is_empty(st_sfc(x)), logical(1))
    }
    
    projects_geom_clean <- projects_geom %>%
      filter(!is_bad(main_route_geom),
             !is_bad(endpoint_a_geom),
             !is_bad(endpoint_b_geom))
    
    ##test
      # testrow <- 22
      # 
      # r  <- projects_geom_clean[testrow,]
      # cr <- st_crs(main_routes_intermediate)
      # 
      # route <- st_sf(what = "route",      geometry = st_sfc(r$main_route_geom[[1]], crs = cr))
      # epa   <- st_sf(what = "endpoint_a", geometry = st_sfc(r$endpoint_a_geom[[1]], crs = cr))
      # epb   <- st_sf(what = "endpoint_b", geometry = st_sfc(r$endpoint_b_geom[[1]], crs = cr))
      # 
      # mapview(route, color = "black", lwd = 4) +
      #   mapview(epa, col.regions = "red",  cex = 20) +
      #   mapview(epb, col.regions = "blue", cex = 20)
      # 
      # print(projects_geom_clean$project_title[testrow])
      
  ##checking geometry types
    table(st_geometry_type(projects_geom_clean$main_route_geom))
    table(st_geometry_type(projects_geom_clean$endpoint_a_geom))
    table(st_geometry_type(projects_geom_clean$endpoint_b_geom))
      
    
####Cropping: Setup####
  ##global parameters
    SRC          <- quote(projects_geom_clean)
    WORK_CRS      <- 5070    ##CRS for calculations (NAD83)
    OVERLAP_RULE  <- "inner"  ##cut rule when an endpoint geom overlaps a stretch (options: mid/inner/outer)
    PART_MAX_M    <- 25000    ##a route component farther than this from BOTH endpoints gets removed (large, can filter later)
    KEEP_BOTH     <- TRUE    ##whether to keep both carriageways
    VERBOSE_EVERY <- 200     ##progress print interval

####Cropping: Main Functions####
  ##vertices + cumulative along-line distance for a length-1 LINESTRING sfc
    line_xyd <- function(line) {
      xy <- st_coordinates(line)[, 1:2, drop = FALSE]
      list(xy = xy, d = c(0, cumsum(sqrt(rowSums(diff(xy)^2)))))
    }
    
  ##position (0-1) along the line of a point lying on or near it
    frac_along <- function(L, p) {
      xy <- L$xy; d <- L$d; n <- nrow(xy)
      if (n < 2 || d[n] == 0) return(NA_real_)
      seg <- xy[-1, , drop = FALSE] - xy[-n, , drop = FALSE]
      ll  <- rowSums(seg^2)
      w   <- cbind(p[1] - xy[-n, 1], p[2] - xy[-n, 2])
      t   <- ifelse(ll > 0, pmin(1, pmax(0, rowSums(w * seg) / ll)), 0)
      i   <- which.min((xy[-n, 1] + t * seg[, 1] - p[1])^2 +
                         (xy[-n, 2] + t * seg[, 2] - p[2])^2)
      (d[i] + t[i] * sqrt(ll[i])) / d[n]
    }
    
  ##function: fraction range on the line covered by one endpoint geometry [src = "intersect" else fallback "nearest"]
    ep_frac <- function(line, L, ep) {
      na <- list(lo = NA_real_, hi = NA_real_, dist = NA_real_, src = NA_character_)
      if (length(ep) == 0 || st_is_empty(line) || st_is_empty(ep)) return(na)
      
      hit <- suppressWarnings(st_intersection(line, ep))
      if (length(hit) && !all(st_is_empty(hit))) {
        xy  <- st_coordinates(hit)[, 1:2, drop = FALSE]
        src <- "intersect"; dd <- 0
      } else {
        xy  <- st_coordinates(st_nearest_points(line, ep))[1, 1:2, drop = FALSE]
        src <- "nearest";   dd <- as.numeric(st_distance(line, ep))
      }
      f <- vapply(seq_len(nrow(xy)), function(k) frac_along(L, xy[k, ]), 0)
      f <- f[is.finite(f)]
      if (!length(f)) return(na)
      list(lo = min(f), hi = max(f), dist = dd, src = src)
    }
    
  ##function: crop a LINESTRING between two fractions; empty geometry on failure
    line_sub <- function(line, L, from, to) {
      xy <- L$xy; d <- L$d; tot <- d[length(d)]
      if (!is.finite(from) || !is.finite(to) || tot == 0 || nrow(xy) < 2)
        return(st_sfc(st_linestring(), crs = st_crs(line)))
      ft <- sort(pmin(1, pmax(0, c(from, to))))
      d1 <- ft[1] * tot; d2 <- ft[2] * tot
      at <- function(dd) {
        i <- max(1, min(findInterval(dd, d, rightmost.closed = TRUE), nrow(xy) - 1))
        r <- if (d[i + 1] > d[i]) (dd - d[i]) / (d[i + 1] - d[i]) else 0
        xy[i, ] + r * (xy[i + 1, ] - xy[i, ])
      }
      st_sfc(st_linestring(rbind(at(d1), xy[d > d1 & d < d2, , drop = FALSE], at(d2))),
             crs = st_crs(line))
    }
    
  ##function: crop one project
    crop_one <- function(line0, ea, eb) {
      empty <- st_sfc(st_multilinestring(), crs = st_crs(line0))
      bad <- list(geom = empty, n_all = NA_integer_, n_kept = 0L, d_part = NA_real_,
                  from = NA_real_, to = NA_real_, dist_a = NA_real_, dist_b = NA_real_,
                  src_a = NA_character_, src_b = NA_character_)
      
      if (st_is_empty(line0) || st_is_empty(ea) || st_is_empty(eb)) return(bad)
      if (st_crs(ea) != st_crs(line0)) ea <- st_transform(ea, st_crs(line0))
      if (st_crs(eb) != st_crs(line0)) eb <- st_transform(eb, st_crs(line0))
      
      parts <- st_cast(st_line_merge(st_cast(line0, "MULTILINESTRING")), "LINESTRING")
      parts <- parts[as.numeric(st_length(parts)) > 0]
      if (!length(parts)) return(bad)
      bad$n_all <- length(parts)
      
      d <- pmax(as.numeric(st_distance(parts, ea)), as.numeric(st_distance(parts, eb)))
      bad$d_part <- min(d)
      keep <- which(d <= PART_MAX_M)
      if (!length(keep)) return(bad)
      if (!KEEP_BOTH) keep <- keep[which.min(d[keep])]
      
      out <- lapply(keep, function(k) {
        line <- parts[k]
        L <- line_xyd(line)
        a <- ep_frac(line, L, ea); b <- ep_frac(line, L, eb)
        if (is.na(a$lo) || is.na(b$lo)) return(NULL)
        
        swap <- (a$lo + a$hi) > (b$lo + b$hi)
        A <- if (swap) b else a
        B <- if (swap) a else b
        fr <- switch(OVERLAP_RULE,
                     inner = c(A$hi, B$lo),
                     outer = c(A$lo, B$hi),
                     mid   = c(mean(c(A$lo, A$hi)), mean(c(B$lo, B$hi))),
                     stop("OVERLAP_RULE must be inner, outer or mid"))
        if (fr[1] > fr[2]) fr <- rep(mean(fr), 2)      # ranges overlap -> collapse
        
        g <- line_sub(line, L, fr[1], fr[2])
        if (st_is_empty(g)) return(NULL)
        list(g = g, fr = fr, dist_a = a$dist, dist_b = b$dist,
             src_a = a$src, src_b = b$src)
      })
      out <- Filter(Negate(is.null), out)
      if (!length(out)) return(bad)
      
      list(geom   = st_cast(st_combine(do.call(c, lapply(out, `[[`, "g"))),
                            "MULTILINESTRING"),
           n_all  = length(parts),
           n_kept = length(out),
           d_part = min(d),
           from   = out[[1]]$fr[1],
           to     = out[[1]]$fr[2],
           dist_a = out[[1]]$dist_a,
           dist_b = out[[1]]$dist_b,
           src_a  = out[[1]]$src_a,
           src_b  = out[[1]]$src_b)
    }
    
####Cropping: Running####
  ##running functions
    src <- eval(SRC)
    
    stopifnot(st_crs(src$main_route_geom) == st_crs(src$endpoint_a_geom),
              st_crs(src$main_route_geom) == st_crs(src$endpoint_b_geom))
    
    out_crs <- st_crs(src$main_route_geom)
    RT <- st_transform(src$main_route_geom,  WORK_CRS)
    EA <- st_transform(src$endpoint_a_geom,  WORK_CRS)
    EB <- st_transform(src$endpoint_b_geom,  WORK_CRS)
    
    res <- lapply(seq_along(RT), function(i) {
      if (VERBOSE_EVERY > 0 && i %% VERBOSE_EVERY == 0)
        message(sprintf("  %d / %d", i, length(RT)))
      crop_one(RT[i], EA[i], EB[i])
    })
    
    geo <- do.call(c, lapply(res, `[[`, "geom"))  
    num <- function(nm) vapply(res, function(r) as.numeric(r[[nm]]),   0)
    chr <- function(nm) vapply(res, function(r) as.character(r[[nm]]), "")
    int <- function(nm) vapply(res, function(r) as.integer(r[[nm]]),   0L)
    
  ##making cropped df w shapefiles and stats
    projects_geom_cropped <- src |> mutate(
      route_cropped = st_transform(geo, out_crs),
      n_parts_all   = int("n_all"), ##number of disjoint components in the source route
      n_parts_kept  = int("n_kept"), ##number of components retained (0 = crop failed)
      part_dist_m   = num("d_part"), ##best max-distance from a component to the endpoints
      crop_from     = num("from"),  
      crop_to       = num("to"),
      snap_dist_a_m = num("dist_a"),
      snap_dist_b_m = num("dist_b"),
      cut_src_a     = chr("src_a"),
      cut_src_b     = chr("src_b"),
      len_crop_m    = as.numeric(st_length(st_transform(geo, WORK_CRS))),
      len_corr_m    = len_crop_m / pmax(n_parts_kept, 1)  ##divide out double-counted carriageways for any length-based measure
    )
    
    
####Cropping: Diagnostics [Claude gen, test version--will be changed and edited]####
    qa <- projects_geom_cropped |> st_drop_geometry() |> summarise(
      n            = n(),
      failed       = mean(n_parts_kept == 0),
      kept_2plus   = mean(n_parts_kept >= 2),
      both_touch   = mean(cut_src_a == "intersect" & cut_src_b == "intersect", na.rm = TRUE),
      med_corr_km  = median(len_corr_m[n_parts_kept > 0]) / 1000,
      frac_full    = mean(crop_from < 1e-6 & crop_to > 1 - 1e-6, na.rm = TRUE)
    )
    print(qa)
    print(table(kept = projects_geom_cropped$n_parts_kept))
    print(summary(projects_geom_cropped$part_dist_m))
    
    # failed rows: no component within PART_MAX_M of both endpoints. raising the
    # threshold will not fix corridors genuinely split across disjoint TIGER
    # segments -- those need the qualifying parts stitched before cropping.
    failed_rows <- which(projects_geom_cropped$n_parts_kept == 0)
    message(sprintf("failed: %d rows", length(failed_rows)))
    
    
    # ---- inspection --------------------------------------------------------------
    # per-component breakdown for one row: near-equal lengths at near-equal endpoint
    # distances = dual carriageway; long component far from both = wrong corridor
    inspect_parts <- function(i) {
      parts <- st_cast(st_line_merge(st_cast(RT[i], "MULTILINESTRING")), "LINESTRING")
      data.frame(part  = seq_along(parts),
                 len_m = as.numeric(st_length(parts)),
                 d_a   = as.numeric(st_distance(parts, EA[i])),
                 d_b   = as.numeric(st_distance(parts, EB[i])))
    }
    
    # self-test: line_sub on known fractions must return ~60% of the input length
    local({
      l <- st_sfc(st_linestring(cbind(c(0, 10, 20), c(0, 0, 10))), crs = WORK_CRS)
      s <- line_sub(l, line_xyd(l), 0.2, 0.8)
      stopifnot(abs(as.numeric(st_length(s)) / as.numeric(st_length(l)) - 0.6) < 1e-9)
      message("line_sub self-test passed")
    })
    
####Cropping: Mapping & Plots####
  ##creating subset of more confidence
    projects_geom_cropped_subset <- projects_geom_cropped %>% 
      filter(!st_is_empty(route_cropped)) %>%
      filter(snap_dist_a_m <= 10000 & snap_dist_b_m <= 10000)
      #filter(cut_src_a == "intersect" | cut_src_b == "intersect")
    
  ##mapping random test w/ project title print
    testrow <- sample(1:nrow(projects_geom_cropped_subset), 1)

    r  <- projects_geom_cropped_subset[testrow,]
    cr <- st_crs(main_routes_intermediate)

    route <- st_sf(what = "route",      geometry = st_sfc(r$main_route_geom[[1]], crs = cr))
    epa   <- st_sf(what = "endpoint_a", geometry = st_sfc(r$endpoint_a_geom[[1]], crs = cr))
    epb   <- st_sf(what = "endpoint_b", geometry = st_sfc(r$endpoint_b_geom[[1]], crs = cr))
    crop  <- st_sf(what = "crop",       geometry = st_sfc(r$route_cropped[[1]], crs = cr))

    mapview(route, color = "black",  lwd = 2) +
      mapview(epa, col.regions = "red",  color = "red",  cex = 2, alpha.regions = 0.4) +
      mapview(epb, col.regions = "blue", color = "blue", cex = 2, alpha.regions = 0.4) +
      mapview(crop, color = "green", lwd = 6)

    print(projects_geom_cropped_subset$project_title[testrow])
    
  ##other stats & viewing
    table(projects_geom_cropped$cut_src_a, projects_geom_cropped$cut_src_b)
    summary(projects_geom_cropped$len_crop_m / projects_geom_cropped$len_full_m)
    
    sum(!st_is_empty(projects_geom_cropped$route_cropped))
    
    projects_geom_cropped_view <- projects_geom_cropped %>%
      st_drop_geometry() %>%
      select(-c("endpoint_a_geom", "endpoint_b_geom", "route_cropped")) 
    
    hist(projects_geom_cropped_view$snap_dist_a_m)
    hist(projects_geom_cropped_view$snap_dist_b_m)
    
####Saving: Crop attempt####
  ##saving as separate files for different shapes -- need to be remerged
    projects_geom_cropped_subset %>%
      st_drop_geometry() %>% 
      st_set_geometry("endpoint_a_geom") %>% 
      st_write(paste0("main_routes_cropped/endpoint_a_", version, ".gpkg"), delete_layer = TRUE)
    
    projects_geom_cropped_subset %>%
      st_drop_geometry() %>% 
      st_set_geometry("endpoint_b_geom") %>% 
      st_write(paste0("main_routes_cropped/endpoint_b_", version, ".gpkg"), delete_layer = TRUE)
    
    projects_geom_cropped_subset %>%
      st_drop_geometry() %>% 
      st_set_geometry("route_cropped") %>% 
      st_write(paste0("main_routes_cropped/route_cropped_", version, ".gpkg"), delete_layer = TRUE)
    
    
    
