# ==============================================================================
# Unit tests for helpers/metrics.R, on hand-built toy geometries (no data files). Run with: Rscript 04_geocode_eval/tests/test_metrics.R
# ==============================================================================
library(testthat)
suppressMessages(library(sf))
suppressMessages(library(lwgeom))
sf::sf_use_s2(FALSE)

# resolve this script's own directory so it can be run via `Rscript` from any cwd
script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
this_dir <- if (length(script_arg) > 0) dirname(sub("^--file=", "", script_arg)) else "."
source(file.path(this_dir, "..", "..", "utils", "geo_utils.R"))
source(file.path(this_dir, "..", "helpers", "metrics.R"))

# a straight route along the x-axis, 0..1000m, for along_route_error tests
route <- st_sfc(st_linestring(matrix(c(0, 0, 1000, 0), ncol = 2, byrow = TRUE)), crs = METRIC_CRS)

line <- function(x1, y1, x2, y2) {
  return(st_sfc(st_linestring(matrix(c(x1, y1, x2, y2), ncol = 2, byrow = TRUE)), crs = METRIC_CRS))
}

test_that("crow_flies_error of identical segments is 0", {
  seg <- line(0, 0, 100, 0)
  expect_equal(crow_flies_error(seg, seg), 0)
})

test_that("crow_flies_error of parallel-offset segments is the known offset", {
  a <- line(0, 0, 100, 0)
  b <- line(0, 10, 100, 10)
  # each endpoint offset by 10m perpendicular -> sum of two endpoint dists = 20m, in miles
  expect_equal(crow_flies_error(a, b), meters_to_miles(20))
})

test_that("crow_flies_error is orientation-robust", {
  a <- line(0, 0, 100, 0)
  b <- line(0, 10, 100, 10)
  b_rev <- line(100, 10, 0, 10)
  expect_equal(crow_flies_error(a, b), crow_flies_error(a, b_rev))
})

test_that("along_route_error is orientation-robust and matches crow-flies on-route", {
  pred <- line(100, 0, 400, 0)
  truth <- line(150, 0, 450, 0)
  true_rev <- line(450, 0, 150, 0)
  err <- along_route_error(pred, truth, route)
  err_rev <- along_route_error(pred, true_rev, route)
  expect_equal(err, err_rev)
  # both endpoints off by 50m along a straight route -> 100m total, in miles
  expect_equal(err, meters_to_miles(100))
})

test_that("segment_iou: identical intervals = 1", {
  result <- segment_iou(c(0, 100), c(0, 100))
  expect_equal(result$iou, 1)
  expect_equal(result$iou_penalty, 0)
})

test_that("segment_iou: disjoint intervals = 0", {
  result <- segment_iou(c(0, 100), c(200, 300))
  expect_equal(result$iou, 0)
  expect_true(is.infinite(result$iou_penalty))
})

test_that("segment_iou: half-overlap gives the known fraction", {
  # [0,100] vs [50,150]: overlap = 50, union = 150 -> iou = 1/3
  result <- segment_iou(c(0, 100), c(50, 150))
  expect_equal(result$iou, 1 / 3)
})

test_that("segment_iou: adjacent (touching) intervals = 0", {
  result <- segment_iou(c(0, 100), c(100, 200))
  expect_equal(result$iou, 0)
})

test_that("segment_iou: two equal zero-length points = 1, unequal = 0", {
  expect_equal(segment_iou(c(50, 50), c(50, 50))$iou, 1)
  expect_equal(segment_iou(c(50, 50), c(60, 60))$iou, 0)
})

test_that("length_error: signed, abs, and ratio on a known pair", {
  pred <- line(0, 0, 150, 0)   # length 150
  truth <- line(0, 0, 100, 0)  # length 100
  result <- length_error(pred, truth)
  expect_equal(result$signed, meters_to_miles(50))
  expect_equal(result$abs, meters_to_miles(50))
  expect_equal(result$ratio, 1.5)
})

test_that("length_error: negative signed error when pred is shorter", {
  pred <- line(0, 0, 50, 0)
  truth <- line(0, 0, 100, 0)
  result <- length_error(pred, truth)
  expect_equal(result$signed, meters_to_miles(-50))
  expect_equal(result$abs, meters_to_miles(50))
  expect_equal(result$ratio, 0.5)
})

test_that("combined_penalty reduces to spatial when temporal == spatial", {
  expect_equal(combined_penalty(10, 10, w_spatial = 0.5), 10)
  expect_equal(combined_penalty(10, 10, w_spatial = 0.8), 10)
})

test_that("combined_penalty respects the weight when spatial != temporal", {
  # geometric mean with w_spatial=1 -> just spatial; w_spatial=0 -> just temporal
  expect_equal(combined_penalty(4, 9, w_spatial = 1), 4)
  expect_equal(combined_penalty(4, 9, w_spatial = 0), 9)
  expect_equal(combined_penalty(4, 9, w_spatial = 0.5), sqrt(4 * 9))
})

test_that("combined_penalty is 0 if either term is 0, NA if either is NA", {
  expect_equal(combined_penalty(0, 10), 0)
  expect_true(is.na(combined_penalty(NA, 10)))
})

test_that("segment_length matches known lengths", {
  # line is 300m in METRIC_CRS; segment_length returns miles
  expect_equal(segment_length(line(0, 0, 300, 0)), meters_to_miles(300))
})

test_that("temporal_penalty is the absolute day difference", {
  expect_equal(temporal_penalty(as.Date("2020-01-01"), as.Date("2020-01-11")), 10)
  # symmetric regardless of which date is earlier
  expect_equal(temporal_penalty(as.Date("2020-01-11"), as.Date("2020-01-01")), 10)
})
