# ==============================================================================
# Generic runner: score predicted segments against cached ground truth for one split.
# ==============================================================================
library(sf)
library(dplyr)
library(purrr)
library(tidyr)

# depends on utils/geo_utils.R and helpers/metrics.R (source via helpers/paths.R + helpers/metrics.R first)

default_metrics <- c("crow_flies_error", "along_route_error", "length_error", "segment_iou")
default_strata <- c("state_fips", "completion_year_bin")

`%||%` <- function(a, b) return(if (is.null(a)) b else a)  # $ on a missing column returns NULL, so this picks the fallback route-id column

sample_size_for_moe <- function(pilot_sd, E, Z = 1.96) {
  # Computes the required val/test sample size for a target margin of error.
  #
  # From the eval design memo's margin-of-error formula: `n = (Z * pilot_sd / E)^2`.
  #
  # Args:
  #   pilot_sd: numeric scalar, standard deviation of the metric from a pilot sample (same units as `E`).
  #   E: numeric scalar, target margin of error (same units as `pilot_sd`).
  #   Z: numeric scalar, z-score for the desired confidence level. Default 1.96 (95% CI).
  #
  # Returns:
  #   numeric scalar, required sample size (not rounded — caller should `ceiling()` as needed).
  return((Z * pilot_sd / E)^2)
}

score_one_project <- function(pred_seg, true_seg, route) {
  # Computes every per-project metric for one predicted/ground-truth segment pair.
  #
  # Computes `segment_position_along_route` for both segments once and reuses it for `along_route_error` and `segment_iou`, per the plan (avoids projecting the same endpoints onto `route` twice). Assumes all three geometries are already in METRIC_CRS (the caller, `evaluate()`, transforms once up front).
  #
  # Args:
  #   pred_seg: length-1 sfc/sf LINESTRING, in METRIC_CRS.
  #   true_seg: length-1 sfc/sf LINESTRING, in METRIC_CRS.
  #   route: length-1 sfc/sf LINESTRING, in METRIC_CRS — reference route for along-route/IOU metrics.
  #
  # Returns:
  #   named list: crow_flies_error, along_route_error, length_error_signed/abs/ratio, iou, iou_penalty.
  pred_ext <- segment_position_along_route(pred_seg, route)
  true_ext <- segment_position_along_route(true_seg, route)
  len_err <- length_error(pred_seg, true_seg)
  iou_result <- segment_iou(pred_ext, true_ext)

  return(list(
    crow_flies_error = crow_flies_error(pred_seg, true_seg),
    along_route_error = along_route_error(pred_seg, true_seg, route),
    length_error_signed = len_err$signed,
    length_error_abs = len_err$abs,
    length_error_ratio = len_err$ratio,
    iou = iou_result$iou,
    iou_penalty = iou_result$iou_penalty
  ))
}

evaluate <- function(predictions, ground_truth, routes = NULL, split_name,
                      metrics = default_metrics, strata = default_strata,
                      threshold_mi = 0.5) {
  # Scores `predictions` against `ground_truth` for one split, returning per-project and summary results.
  #
  # Inner-joins `predictions` and `ground_truth` on `projectid`; coverage (n matched, % of the split geocoded, n dropped) is recorded on the summary. Both inputs are transformed to METRIC_CRS once up front (not inside the per-project loop). `routes`, if supplied, maps each ground-truth row to its reference route (by `route_id`/`gis_routeid_clean`, matching however `ground_truth` was built) for `along_route_error`/`segment_iou`; if NULL, `true_seg` is used as its own reference route, which degrades along-route metrics to crow-flies-equivalent (fine for a smoke test, not for the real run). The `metrics` and `strata` arguments select which columns end up in the per-project/summary output but don't change what's computed by `score_one_project` — trimming down to fewer columns downstream is cheap and keeps this function usable for both val and test without duplicating logic (only the split table and ground-truth file passed in differ).
  #
  # Args:
  #   predictions: sf object with `projectid` and a LINESTRING geometry column — the geocoder's predicted segments.
  #   ground_truth: sf object with `projectid` and a LINESTRING geometry column, as written by `build_ground_truth`.
  #   routes: optional sf object with a route id column and LINESTRING geometry, used as the along-route reference; see above.
  #   split_name: character scalar, e.g. "val" or "test" — attached to every output row and used in the coverage message.
  #   metrics: character vector of metric names to retain in the output (informational; all metrics are always computed — see above).
  #   strata: character vector of column names in `ground_truth` to carry through and group the summary by.
  #   threshold_mi: numeric, miles — distance threshold `E` for the "% within threshold" summary stat.
  #
  # Returns:
  #   list(per_project, summary): `per_project` is a data.frame with one row per matched projectid (all metrics + strata columns + `split_name`); `summary` is a data.frame with one row per metric x stratum-group (plus one "overall" group), giving mean/median/p25/p75/p90 and `pct_within_<threshold_mi>mi`, alongside a `coverage` data.frame reporting n matched / % geocoded / n dropped.
  predictions <- to_metric_crs(predictions)
  ground_truth <- to_metric_crs(ground_truth)

  matched <- inner_join(
    sf::st_drop_geometry(ground_truth) %>% mutate(true_geom = sf::st_geometry(ground_truth)),
    sf::st_drop_geometry(predictions) %>% mutate(pred_geom = sf::st_geometry(predictions)),
    by = "projectid"
  )

  n_true <- nrow(ground_truth)
  n_matched <- nrow(matched)
  coverage <- tibble(
    split = split_name,
    n_ground_truth = n_true,
    n_matched = n_matched,
    pct_geocoded = if (n_true > 0) 100 * n_matched / n_true else NA_real_,
    n_dropped = n_true - n_matched
  )

  if (n_matched == 0) {
    return(list(per_project = matched, summary = list(coverage = coverage, by_metric = tibble())))
  }

  # reference route per row: joined `routes` if supplied, else the true segment itself (see above)
  route_geoms <- if (!is.null(routes)) {
    routes <- to_metric_crs(routes)
    route_lookup <- setNames(sf::st_geometry(routes), routes$route_id)
    matched_route_ids <- matched$gis_routeid_clean %||% matched$route_id
    route_lookup[matched_route_ids]
  } else {
    matched$true_geom
  }

  per_row_metrics <- pmap_dfr(
    list(matched$pred_geom, matched$true_geom, route_geoms),
    function(pred_seg, true_seg, route) {
      as_tibble(score_one_project(sf::st_sfc(pred_seg, crs = METRIC_CRS), sf::st_sfc(true_seg, crs = METRIC_CRS), sf::st_sfc(route, crs = METRIC_CRS)))
    }
  )

  strata_present <- intersect(strata, names(matched))
  per_project <- bind_cols(
    matched %>% select(projectid, all_of(strata_present)),
    per_row_metrics
  ) %>%
    mutate(split = split_name)

  summary <- summarize_metrics(per_project, metrics = intersect(names(per_row_metrics), c(metrics, "crow_flies_error", "along_route_error", "length_error_abs", "iou")), strata = strata_present, threshold_mi = threshold_mi)

  return(list(per_project = per_project, summary = list(coverage = coverage, by_metric = summary)))
}

summarize_metrics <- function(per_project, metrics, strata, threshold_mi) {
  # Aggregates per-project metrics into summary stats, overall and by stratum.
  #
  # Args:
  #   per_project: data.frame as returned by `evaluate()$per_project`.
  #   metrics: character vector of numeric column names in `per_project` to summarize.
  #   strata: character vector of column names in `per_project` to group by, in addition to an implicit "overall" group.
  #   threshold_mi: numeric, miles — used for the `pct_within_<threshold_mi>mi` stat on distance-like metrics (crow_flies_error, along_route_error).
  #
  # Returns:
  #   data.frame with one row per (group, metric): `group` ("overall" or "<stratum>=<value>"), `metric`, `n`, `mean`, `median`, `p25`, `p75`, `p90`, and `pct_within_threshold` (NA for metrics the threshold doesn't apply to, e.g. iou/length_error_ratio).
  distance_metrics <- intersect(metrics, c("crow_flies_error", "along_route_error"))

  summarize_group <- function(df, group_label) {
    return(map_dfr(metrics, function(m) {
      x <- df[[m]]
      x <- x[is.finite(x)]
      tibble(
        group = group_label,
        metric = m,
        n = length(x),
        mean = mean(x, na.rm = TRUE),
        median = median(x, na.rm = TRUE),
        p25 = quantile(x, 0.25, na.rm = TRUE, names = FALSE),
        p75 = quantile(x, 0.75, na.rm = TRUE, names = FALSE),
        p90 = quantile(x, 0.90, na.rm = TRUE, names = FALSE),
        pct_within_threshold = if (m %in% distance_metrics) 100 * mean(x <= threshold_mi, na.rm = TRUE) else NA_real_
      )
    }))
  }

  overall <- summarize_group(per_project, "overall")

  by_stratum <- map_dfr(strata, function(s) {
    per_project %>%
      filter(!is.na(.data[[s]])) %>%
      group_split(.data[[s]]) %>%
      map_dfr(function(g) summarize_group(g, paste0(s, "=", g[[s]][1])))
  })

  return(bind_rows(overall, by_stratum))
}
