# ==============================================================================
# This script contains helper functions for handling highway geometry objects, including CRS transforms, linear referencing, and route snapping.
# ==============================================================================
library(sf)
library(lwgeom)
library(geos)
library(dplyr)
library(stringr)

METRIC_CRS <- 5070 # CONUS Albers
MILES_TO_METERS <- 1609.344

miles_to_meters <- function(mi) {
  return(mi * MILES_TO_METERS)
}

meters_to_miles <- function(m) {
  return(m / MILES_TO_METERS)
}

to_metric_crs <- function(x) {
  # Transforms an sf/sfc object to the project's default metric CRS (CONUS Albers).
  #
  # Args:
  #   x: an `sf` or `sfc` object with a defined CRS.
  if (is.na(sf::st_crs(x))) {
    stop("to_metric_crs: input has no CRS defined")
  }
  return(sf::st_transform(x, METRIC_CRS))
}

# ---- linear referencing ----

position_along_route <- function(point, route) {
  # Projects a point onto the nearest distance along a route, and returns the distance (in miles) from the start of the route to the projected point.
  #
  # TODO: right now the 'start' of the route is arbitrarily based on however the linestring was constructed. we should define this so that it starts 0 at the south end for north-south routes and 0 at the west end for east-west routes. also caveat that the position along route is not necessarily the same as the actual mile marker.
  #
  # TODO: check if HPMS/NHPN linestrings are actually in traversal order.
  #
  # Transforms inputs to METRIC_CRS internally.
  #
  # Args:
  #   point: an sfc/sf POINT (length 1).
  #   route: an sfc/sf LINESTRING (length 1).

  point <- to_metric_crs(point)
  route <- to_metric_crs(route)

  if (sf::st_geometry_type(sf::st_geometry(route))[1] != "LINESTRING") {
    stop(
      "position_along_route: route must be a single LINESTRING, not ",
      sf::st_geometry_type(sf::st_geometry(route))[1]
    )
  }
  if (nrow(sf::st_coordinates(sf::st_geometry(route))) < 2) {
    stop("position_along_route: route has fewer than 2 vertices.")
  }

  dist_m <- geos::geos_project(
    geos::as_geos_geometry(route),
    geos::as_geos_geometry(point)
  ) # get distance of point 2 projected onto linestring 1 from the origin of linestring 1
  return(meters_to_miles(dist_m))
}

segment_position_along_route <- function(seg, route) {
  # Computes the milepost interval of `seg` relative to `route`, sorted ascending regardless of `seg`'s drawn direction.
  #
  # Args:
  #   seg: an sfc/sf LINESTRING (length 1), assumed to lie on or near `route`.
  #   route: an sfc/sf LINESTRING (length 1), the reference route.
  #
  # Returns:
  #   numeric length-2 `c(m_start, m_end)`, miles.
  seg <- to_metric_crs(seg)
  route <- to_metric_crs(route)
  p_start <- lwgeom::st_startpoint(seg)
  p_end <- lwgeom::st_endpoint(seg)
  m1 <- position_along_route(p_start, route)
  m2 <- position_along_route(p_end, route)
  return(sort(c(m1, m2)))
}

# ---- route snapping ----

build_route <- function(nhpn, route_id, state_fips = NULL, county_fips = NULL) {
  # Merges all NHPN sub-segments matching `route_id` into one LINESTRING, in METRIC_CRS, tagged with a `"milepost_range"` attribute (miles) for `snap_segment`/`milepost_to_fraction`.
  #
  # If the matched sub-segments don't form one connected path, keeps only the longest connected part — mileposts on a shorter disconnected piece get clamped onto the kept part.
  #
  # Args:
  #   nhpn: sf object with `ROUTE_ID`, `STFIPS`, `CTFIPS`, `BEGIN_POIN`/`END_POINT` (miles).
  #   route_id: character, matched against trimmed `nhpn$ROUTE_ID`.
  #   state_fips: optional, disambiguates route ids that repeat across states.
  #   county_fips: optional; leave NULL when a route may span multiple counties within one project's mileposts, since filtering here would truncate the route before it can be cut.
  #
  # Returns:
  #   Length-1 sfc LINESTRING with `"milepost_range" = c(min_mi, max_mi)`, or an empty LINESTRING with `milepost_range = c(NA, NA)` if no sub-segments match.
  candidates <- nhpn %>%
    mutate(ROUTE_ID = str_trim(ROUTE_ID)) %>%
    filter(ROUTE_ID == str_trim(route_id))

  if (!is.null(state_fips)) {
    candidates <- candidates %>% filter(STFIPS == state_fips)
  }
  if (!is.null(county_fips)) {
    candidates <- candidates %>% filter(CTFIPS %in% as.integer(county_fips))
  }

  if (nrow(candidates) == 0) {
    empty <- sf::st_sfc(sf::st_linestring(), crs = METRIC_CRS)
    attr(empty, "milepost_range") <- c(NA_real_, NA_real_)
    return(empty)
  }

  mp_range_mi <- c(
    min(candidates$BEGIN_POIN, na.rm = TRUE),
    max(candidates$END_POINT, na.rm = TRUE)
  )

  merged <- candidates %>%
    to_metric_crs() %>%
    sf::st_geometry() %>%
    sf::st_union()
  # st_line_merge only accepts MULTILINESTRING input; a single matched sub-segment unions to a plain LINESTRING already
  if (sf::st_geometry_type(merged, by_geometry = FALSE) == "MULTILINESTRING") {
    merged <- sf::st_line_merge(merged)
  }

  # st_line_merge can leave a MULTILINESTRING when the matched sub-segments don't form one connected path (gaps, or a route_id reused for disjoint pieces); st_linesubstring requires a single LINESTRING, so keep only the longest part. This is a known limitation: mileposts falling on a shorter disconnected part will be clamped onto the kept part instead.
  if (sf::st_geometry_type(merged, by_geometry = FALSE) == "MULTILINESTRING") {
    parts <- sf::st_cast(merged, "LINESTRING", warn = FALSE)
    merged <- parts[[which.max(sf::st_length(parts))]]
    merged <- sf::st_sfc(merged, crs = METRIC_CRS)
  }

  attr(merged, "milepost_range") <- mp_range_mi
  return(merged)
}

milepost_to_fraction <- function(route, m) {
  # Converts an absolute milepost to a fraction of `route`'s length, clamped to [0, 1].
  #
  # Uses `route`'s `"milepost_range"` attribute if present (from `build_route`) so cuts line up even when mileposts don't start at 0; otherwise falls back to treating `m` as meters-from-route-start.
  #
  # Args:
  #   route: length-1 sfc LINESTRING in METRIC_CRS (as from `build_route`).
  #   m: numeric milepost, miles.
  #
  # Returns:
  #   numeric scalar in [0, 1].
  mp_range <- attr(route, "milepost_range")
  if (!is.null(mp_range) && !anyNA(mp_range) && diff(mp_range) > 0) {
    frac <- (m - mp_range[1]) / diff(mp_range)
  } else {
    route_len <- meters_to_miles(as.numeric(sf::st_length(route)))  # st_length is meters (METRIC_CRS); convert to miles to match `m`
    frac <- if (route_len > 0) m / route_len else 0
  }
  return(min(1, max(0, frac)))
}

snap_segment <- function(route, m_start, m_end) {
  # Cuts `route` between two mileposts, exactly (via `lwgeom::st_linesubstring`), returning a LINESTRING.
  #
  # Improves on the coworker's `get_gis_shape` (FMIS_finn/04_figures_and_analysis/fmis_gis/fmis_gis_tests.Rmd), which grabs whole NHPN sub-segments and so over/undershoots when a cut point lands mid-subsegment. `m_start == m_end` returns a POINT rather than erroring; an empty/absent `route` returns an empty LINESTRING so batch callers can record a coverage miss instead of stopping.
  #
  # Args:
  #   route: length-1 sfc LINESTRING in METRIC_CRS, normally from `build_route`.
  #   m_start: numeric milepost (miles).
  #   m_end: numeric milepost (miles); order doesn't matter, sorted internally.
  #
  # Returns:
  #   length-1 sfc geometry (LINESTRING, or POINT if `m_start == m_end`), METRIC_CRS.
  if (length(route) == 0 || sf::st_is_empty(route)[1]) {
    return(sf::st_sfc(sf::st_linestring(), crs = METRIC_CRS))
  }

  if (isTRUE(m_start == m_end)) {
    frac <- milepost_to_fraction(route, m_start)
    return(lwgeom::st_linesubstring(route, frac, frac))
  }

  fracs <- sort(c(
    milepost_to_fraction(route, m_start),
    milepost_to_fraction(route, m_end)
  ))
  return(lwgeom::st_linesubstring(route, fracs[1], fracs[2]))
}
