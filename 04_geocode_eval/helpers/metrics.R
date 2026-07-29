# ==============================================================================
# This script defines a set of evaluation metrics for highway geocoding quality.
# ==============================================================================
library(sf)
library(lwgeom)

crow_flies_error <- function(pred_seg, true_seg) {
  # Sums endpoint distances between two segments using as-the-crow-flies distance.
  #
  # Robust to orientation of segments. (Takes the smaller of the two endpoint pairings.) Does not account for road curvature. 
  #
  # Args:
  #   pred_seg: length-1 sfc/sf LINESTRING, in CONUS Albers
  #   true_seg: length-1 sfc/sf LINESTRING, in CONUS Albers
  #
  # Returns:
  #   numeric (in miles): min endpoint distance error.

  # Assert that the inputs are in the correct CRS
  if (sf::st_crs(pred_seg) != sf::st_crs(5070)) {
    stop(sprintf("pred_seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(pred_seg))) "no CRS" else sf::st_crs(pred_seg)$input))
  }
  if (sf::st_crs(true_seg) != sf::st_crs(5070)) {
    stop(sprintf("true_seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(true_seg))) "no CRS" else sf::st_crs(true_seg)$input))
  }

  p1 <- lwgeom::st_startpoint(pred_seg)
  p2 <- lwgeom::st_endpoint(pred_seg)
  t1 <- lwgeom::st_startpoint(true_seg)
  t2 <- lwgeom::st_endpoint(true_seg)

  same <- as.numeric(sf::st_distance(p1, t1)) + as.numeric(sf::st_distance(p2, t2))
  swapped <- as.numeric(sf::st_distance(p1, t2)) + as.numeric(sf::st_distance(p2, t1))
  return(meters_to_miles(min(same, swapped)))
}

along_route_error <- function(pred_seg, true_seg, route) {
  # Sums endpoint distances between two segments, measured along the route.
  #
  # Robust to orientation of segments. (Takes the smaller of the two endpoint pairings.) Distances are measured by moving along a linestring's geometry rather than as-the-crow-flies distance.
  #
  # Args:
  #   pred_seg: length-1 sfc/sf LINESTRING, in CONUS Albers.
  #   true_seg: length-1 sfc/sf LINESTRING, in CONUS Albers.
  #   route: length-1 sfc/sf LINESTRING, in CONUS Albers.
  #
  # Returns:
  #   numeric (in miles): min endpoint distance error.

  # Assert that the inputs are in the correct CRS
  if (sf::st_crs(pred_seg) != sf::st_crs(5070)) {
    stop(sprintf("pred_seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(pred_seg))) "no CRS" else sf::st_crs(pred_seg)$input))
  }
  if (sf::st_crs(true_seg) != sf::st_crs(5070)) {
    stop(sprintf("true_seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(true_seg))) "no CRS" else sf::st_crs(true_seg)$input))
  }
  if (sf::st_crs(route) != sf::st_crs(5070)) {
    stop(sprintf("route must be in EPSG:5070, got %s", if (is.na(sf::st_crs(route))) "no CRS" else sf::st_crs(route)$input))
  }

  pred_ext <- segment_position_along_route(pred_seg, route) # start and end position points (miles) along route 
  true_ext <- segment_position_along_route(true_seg, route) # start and end position points (miles) along route 

  same <- abs(pred_ext[1] - true_ext[1]) + abs(pred_ext[2] - true_ext[2])
  swapped <- abs(pred_ext[1] - true_ext[2]) + abs(pred_ext[2] - true_ext[1])
  return(min(same, swapped))
}

segment_length <- function(seg) {
  # Computes the length of a segment.
  #
  # Args:
  #   seg: length-1 sfc/sf LINESTRING (or POINT), in CONUS Albers.
  #
  # Returns:
  #   numeric scalar, miles. 0 for a POINT (degenerate segment).
  if (sf::st_crs(seg) != sf::st_crs(5070)) {
    stop(sprintf("seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(seg))) "no CRS" else sf::st_crs(seg)$input))
  }
  return(meters_to_miles(as.numeric(sf::st_length(seg))))
}
