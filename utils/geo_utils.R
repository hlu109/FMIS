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
