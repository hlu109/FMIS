# ==============================================================================
# Build and cache ground-truth segments for the geocode-eval sources.
# ==============================================================================
library(sf)
library(dplyr)
library(haven)
library(purrr)
library(stringr)

# depends on utils/geo_utils.R (source via helpers/paths.R first)

write_gpkg <- function(x, out_path) {
  # Writes an sf object to a GeoPackage, working around SQLite commit failures on Windows-hosted mounts.
  #
  # In this container, `geocode_eval_dir` (under /workspace) can be a Windows-hosted (DrvFs/WSL) mount that doesn't reliably support SQLite's file-locking/commit semantics for a multi-thousand-row GeoPackage write — `st_write` intermittently fails with `GDAL Error 1: sqlite3_exec(COMMIT) failed: disk I/O error` directly against such a path. Writing to a local tempfile (on the container's native filesystem) first and then copying the finished file into place sidesteps this: the SQLite transaction runs entirely on a filesystem that supports it, and the final copy is a plain byte copy, not a live SQLite write.
  #
  # Args:
  #   x: sf object to write.
  #   out_path: final destination path (e.g. `geocode_eval_dir/ground_truth/fmis_gis.gpkg`).
  #
  # Returns:
  #   `out_path`, invisibly, after the file has been written and copied into place.
  tmp_path <- tempfile(fileext = ".gpkg")
  sf::st_write(x, tmp_path, delete_dsn = TRUE, quiet = TRUE)
  file.copy(tmp_path, out_path, overwrite = TRUE)
  file.remove(tmp_path)
  return(invisible(out_path))
}

build_ground_truth <- function(source = c("pr511", "fmis_gis"), nhpn,
                                fmis_gis_path = NULL,
                                pr511_singleopen_path = NULL,
                                out_dir) {
  # Builds and caches ground-truth segments for one source into out_dir/<source>.gpkg.
  #
  # Both sources reduce to the same shape — (route_id, m_start, m_end) snapped onto NHPN — so one builder dispatches to a per-source implementation; see 04_geocode_eval/README.md for the source definitions.
  #
  # fmis_gis (fully implemented): see `build_ground_truth_fmis_gis`.
  # pr511 (BLOCKED — stubbed): see `build_ground_truth_pr511` and TODO(pr511 route crosswalk) there.
  #
  # Args:
  #   source: one of "fmis_gis" or "pr511".
  #   nhpn: sf object of NHPN sub-segments (as loaded by main/00_build_ground_truth.R — already `to_metric_crs()`'d and with `ROUTE_ID` trimmed).
  #   fmis_gis_path: path to `project_level_FMIS_w_GIS.dta` (only used when `source == "fmis_gis"`).
  #   pr511_singleopen_path: path to `pr511_cty_rt_single_openyr_ever.dta` (only used when `source == "pr511"`).
  #   out_dir: directory to write `<source>.gpkg` into (normally `geocode_eval_dir/ground_truth`).
  #
  # Returns:
  #   The sf object written to `<out_dir>/<source>.gpkg` (via `st_write(..., delete_dsn = TRUE)`, geometry in METRIC_CRS). Returns `NULL` for the still-blocked pr511 branch instead of writing anything.
  #
  # Raises:
  #   Errors if `source` is not one of the two recognized values.
  source <- match.arg(source)
  if (source == "fmis_gis") {
    return(build_ground_truth_fmis_gis(nhpn, fmis_gis_path, out_dir))
  }
  return(build_ground_truth_pr511(nhpn, pr511_singleopen_path, out_dir))
}

snap_fmis_gis_row <- function(state_fips, route_id, begin_mp, end_mp, nhpn, route_cache) {
  # Snaps one FMIS-GIS project's mileposts onto its NHPN route, with route-level caching.
  #
  # Looks up `route_cache` (keyed by `"<state_fips>_<route_id>"`) before calling `build_route`, so each distinct route is only unioned/line-merged once across the whole fmis_gis pass. `route_cache` is an environment so the lookup mutates it in place for the caller — this is a pure performance optimization (there are far more project rows than distinct routes), not a design decision.
  #
  # Args:
  #   state_fips: two-digit character FIPS, e.g. "06".
  #   route_id: character NHPN `ROUTE_ID` (already stripped of the FMIS "i" flag).
  #   begin_mp: numeric, gis_beginpoint in miles.
  #   end_mp: numeric, gis_endpoint in miles.
  #   nhpn: sf object of NHPN sub-segments in METRIC_CRS (a single state's slice, for speed).
  #   route_cache: an environment used as a mutable route_id -> route sfc cache.
  #
  # Returns:
  #   length-1 sfc geometry (LINESTRING or POINT) in METRIC_CRS, or an empty LINESTRING sfc if the route wasn't found in NHPN (coverage miss).
  key <- paste(state_fips, route_id, sep = "_")
  route <- route_cache[[key]]
  if (is.null(route)) {
    route <- build_route(nhpn, route_id, state_fips = state_fips)
    route_cache[[key]] <- route
  }
  return(snap_segment(route, begin_mp, end_mp))
}

build_ground_truth_fmis_gis <- function(nhpn, fmis_gis_path, out_dir) {
  # Builds the fmis_gis ground-truth source: FMIS gis_beginpoint/gis_endpoint mileposts snapped onto NHPN.
  #
  # Reads `project_level_FMIS_w_GIS.dta`, keeps rows with both mileposts present and `0 < gis_endpoint - gis_beginpoint < 10000`, strips lowercase "i" from `gis_routeid` (`gsub("i", "", ...)`, per the coworker's `get_gis_shape` convention), and snaps each row's mileposts onto its NHPN route via `build_route`/`snap_segment`. Scope is every valid-milepost project, not just interstate/new-construction, per the locked design decision. NHPN is pre-split by state (`split(nhpn, nhpn$STFIPS)`) so `build_route`'s per-row ROUTE_ID filter runs against a small state-level slice instead of the full ~626k-row table — without this the fmis_gis pass (111k rows x 42k distinct routes) does not finish in reasonable time.
  #
  # Args:
  #   nhpn: sf object of NHPN sub-segments in METRIC_CRS, `ROUTE_ID` trimmed.
  #   fmis_gis_path: path to `project_level_FMIS_w_GIS.dta`.
  #   out_dir: directory to write `fmis_gis.gpkg` into.
  #
  # Returns:
  #   sf object with one row per scoped FMIS-GIS project: `projectid`, route/milepost fields, covariates (state/county fips, completion year, cost, `has_*` flags), an `is_covered` flag (FALSE = route not found in NHPN), and `geometry` in METRIC_CRS. Also written to `out_dir/fmis_gis.gpkg`.
  plf_gis <- haven::read_dta(fmis_gis_path)

  scoped <- plf_gis %>%
    filter(
      !is.na(gis_beginpoint), !is.na(gis_endpoint),
      (gis_endpoint - gis_beginpoint) > 0,
      (gis_endpoint - gis_beginpoint) < 10000
    ) %>%
    mutate(
      projectid = paste0(recipientid, "_", federal_project_number),
      gis_routeid_clean = gsub("i", "", gis_routeid),
      state_fips_padded = sprintf("%02d", as.integer(state_fips))
    )

  nhpn_by_state <- split(nhpn, nhpn$STFIPS)
  route_cache <- new.env(parent = emptyenv())

  geoms <- pmap(
    list(scoped$state_fips_padded, scoped$gis_routeid_clean, scoped$gis_beginpoint, scoped$gis_endpoint),
    function(sf_state, rid, bmp, emp) {
      state_slice <- nhpn_by_state[[sf_state]]
      if (is.null(state_slice)) {
        return(sf::st_sfc(sf::st_linestring(), crs = METRIC_CRS))  # state not present in NHPN -> coverage miss
      }
      snap_fmis_gis_row(sf_state, rid, bmp, emp, state_slice, route_cache)
    }
  )

  scoped$geometry <- sf::st_sfc(do.call(c, geoms), crs = METRIC_CRS)
  result <- sf::st_as_sf(scoped) %>%
    select(
      projectid, gis_routeid, gis_routeid_clean, gis_beginpoint, gis_endpoint,
      state_fips, county_fips, county_name, completion_year, total_cost_mills,
      starts_with("has_"), fp_ic, interstate_syscode, interstate_functional,
      geometry
    ) %>%
    mutate(is_covered = !sf::st_is_empty(geometry))

  write_gpkg(result, file.path(out_dir, "fmis_gis.gpkg"))
  return(result)
}

build_ground_truth_pr511 <- function(nhpn, pr511_singleopen_path, out_dir) {
  # Builds the pr511 ground-truth source. BLOCKED — see TODO below.
  #
  # TODO(pr511 route crosswalk): FMIS's interstate projects carry no `route_fpn` column in project_level_FMIS_w_GIS.dta (checked directly), and no PR-511 geodata with route + milepost geometry was found anywhere under Data/Intermediate/PR_511 or elsewhere in this container's data mount — both are required before build_route/snap_segment can run for this source. Implementing the join here would mean guessing at an undocumented mapping, which the plan explicitly says not to do, so this stops after loading the county x route strata. Wire this up once both the crosswalk and PR-511 route geodata are available: join FMIS interstate projects to `cty_rt` on (state, route, county), pull each match's PR-511 route + milepost endpoints, then `build_route`/`snap_segment` exactly as in `build_ground_truth_fmis_gis`, plus attach the PR-511 opening date for `temporal_penalty`.
  #
  # Args:
  #   nhpn: sf object of NHPN sub-segments in METRIC_CRS (unused until the crosswalk lands; kept in the signature so callers don't need to branch).
  #   pr511_singleopen_path: path to `pr511_cty_rt_single_openyr_ever.dta`.
  #   out_dir: directory `<source>.gpkg` would be written into once implemented.
  #
  # Returns:
  #   `NULL` (writes nothing).
  cty_rt <- haven::read_dta(pr511_singleopen_path)  # 511 county x route strata; the unambiguous FMIS<->PR-511 match universe

  message(
    "build_ground_truth(pr511): blocked on the FMIS route_fpn <-> PR-511 route ",
    "crosswalk and PR-511 route geodata (neither found in this container). ",
    "Loaded ", nrow(cty_rt), " county x route strata from pr511_cty_rt_single_openyr_ever.dta ",
    "and stopping there. See TODO(pr511 route crosswalk) in build_ground_truth_pr511()."
  )
  return(NULL)
}
