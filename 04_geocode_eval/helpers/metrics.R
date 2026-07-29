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

length_error <- function(pred_seg, true_seg) {
  # Computes predicted vs. true segment length using three metrics. 
  #
  # Args:
  #   pred_seg: length-1 sfc/sf LINESTRING, in CONUS Albers.
  #   true_seg: length-1 sfc/sf LINESTRING, in CONUS Albers.
  #
  # Returns:
  #   list(signed, abs, ratio): signed = pred_length - true_length (miles; positive = overshoot); abs = abs(signed) (miles); ratio = pred_length / true_length (unitless, NA if true_length == 0).
  if (sf::st_crs(pred_seg) != sf::st_crs(5070)) {
    stop(sprintf("pred_seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(pred_seg))) "no CRS" else sf::st_crs(pred_seg)$input))
  }
  if (sf::st_crs(true_seg) != sf::st_crs(5070)) {
    stop(sprintf("true_seg must be in EPSG:5070, got %s", if (is.na(sf::st_crs(true_seg))) "no CRS" else sf::st_crs(true_seg)$input))
  }
  pred_len <- segment_length(pred_seg)
  true_len <- segment_length(true_seg)
  signed <- pred_len - true_len
  return(list(
    signed = signed,
    abs = abs(signed),
    ratio = if (true_len == 0) NA_real_ else pred_len / true_len
  ))
}

segment_iou <- function(pred_ext, true_ext) {
  # Computes Jaccard overlap (IOU) of two milepost intervals.
  #
  # Operates on milepost intervals (as returned by `segment_position_along_route`), not raw geometry — this makes it orientation- and route-topology-agnostic by construction (both intervals are already sorted ascending). Also computes `iou_penalty = 1/iou - 1`, a monotone-decreasing-in-overlap penalty that's 0 at iou==1 and Inf at iou==0 (useful for combining with other penalties without IOU's awkward "higher is better" direction). These intervals are only meaningful if derived via `segment_position_along_route()`, which returns miles; being plain numeric here, there is nothing to assert on directly.
  #
  # Args:
  #   pred_ext: numeric length-2 `c(m_start, m_end)`, miles, `m_start <= m_end`.
  #   true_ext: numeric length-2 `c(m_start, m_end)`, miles, `m_start <= m_end`.
  #
  # Returns:
  #   list(iou, iou_penalty): iou is numeric in [0, 1] — two zero-length (point) intervals score 1 if they coincide, 0 otherwise, and touching-but-not-overlapping intervals score 0 (overlap == 0); iou_penalty is `1 / iou - 1`, `Inf` when `iou == 0`.
  pred_zero <- pred_ext[1] == pred_ext[2]
  true_zero <- true_ext[1] == true_ext[2]

  if (pred_zero && true_zero) {
    iou <- if (pred_ext[1] == true_ext[1]) 1 else 0
  } else {
    overlap <- max(0, min(pred_ext[2], true_ext[2]) - max(pred_ext[1], true_ext[1]))
    union <- max(pred_ext[2], true_ext[2]) - min(pred_ext[1], true_ext[1])
    iou <- if (union == 0) 0 else overlap / union
  }

  return(list(iou = iou, iou_penalty = if (iou == 0) Inf else 1 / iou - 1))
}

temporal_penalty <- function(fmis_date, pr511_date, unit = "days") {
  # Returns the absolute difference between an FMIS completion date and a PR-511 opening date.
  #
  # Args:
  #   fmis_date: a Date (or coercible via as.Date).
  #   pr511_date: a Date (or coercible via as.Date).
  #   unit: passed to `difftime`; default "days".
  #
  # Returns:
  #   numeric scalar: absolute difference between the two dates, in `unit`.
  return(abs(as.numeric(difftime(as.Date(pr511_date), as.Date(fmis_date), units = unit))))
}

combined_penalty <- function(spatial, temporal, w_spatial = 0.5) {
  # Combines a spatial penalty and a temporal penalty into one score.
  #
  # Weighted geometric mean: `spatial^w_spatial * temporal^(1 - w_spatial)`. Spatial should dominate per the eval design memo, so `w_spatial` defaults to 0.5 and callers evaluating PR-511 (which has a temporal signal) should generally use w_spatial >= 0.5. Guards zero/NA inputs: a geometric mean is 0 if either component is exactly 0, and NA propagates if either input is NA (there is nothing sensible to substitute).
  #
  # Args:
  #   spatial: numeric scalar >= 0 (e.g. crow_flies_error or along_route_error, meters).
  #   temporal: numeric scalar >= 0 (e.g. temporal_penalty, days).
  #   w_spatial: numeric in [0, 1], weight on the spatial term. Default 0.5.
  #
  # Returns:
  #   numeric scalar >= 0, or NA if either input is NA.
  if (is.na(spatial) || is.na(temporal)) return(NA_real_)
  if (spatial < 0 || temporal < 0) stop("combined_penalty: inputs must be >= 0.")
  if (spatial == 0 || temporal == 0) return(0)
  return(spatial^w_spatial * temporal^(1 - w_spatial))
}
