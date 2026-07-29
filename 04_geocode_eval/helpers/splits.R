# ==============================================================================
# Assign ground-truth projects to val/test buckets by geographic cluster, frozen via a stable hash.
# ==============================================================================
library(dplyr)
library(digest)

cluster_hash_frac <- function(cluster_key, seed_salt) {
  # Maps a cluster key to a stable pseudo-random fraction in [0, 1).
  #
  # Uses the first 7 hex chars of an md5 digest of `paste0(cluster_key, "_", seed_salt)` as a base-16 integer, scaled to [0, 1) (7 hex chars, not 8, so the value stays under R's 32-bit signed integer max and `strtoi` doesn't overflow to NA). This is stable across runs/machines (unlike `sample()` with a seed, which is not guaranteed stable across R versions), so cluster assignments don't reshuffle when the eval scope or R version changes.
  #
  # Args:
  #   cluster_key: character vector of cluster keys (e.g. route id, or "<county>_<route>").
  #   seed_salt: character scalar mixed into the hash so different sources/splits don't share an assignment pattern.
  #
  # Returns:
  #   numeric vector, same length as `cluster_key`, values in [0, 1).
  digests <- vapply(cluster_key, function(k) digest::digest(paste0(k, "_", seed_salt), algo = "md5"), character(1))
  return(strtoi(substr(digests, 1, 7), base = 16L) / (16^7))
}

build_splits <- function(source, cluster_key_df, val_frac = 0.5, seed_salt = source,
                          universe_projectids = NULL) {
  # Assigns val/test buckets to a ground-truth source's projects by geographic cluster, and writes the split table to CSV.
  #
  # Whole clusters (not individual projects) are assigned to val or test, so the same true segment never lands in both halves — a cluster's bucket is decided once via `cluster_hash_frac(cluster_key, seed_salt)` compared to `val_frac`, then every project sharing that cluster gets the same bucket. This is frozen and reproducible: re-running with the same `cluster_key`/`seed_salt` always yields the same assignment, and it's stable under scope changes (adding new clusters doesn't reshuffle existing ones, unlike `sample()`).
  #
  # `universe_projectids`, if supplied, is the full set of geocodable projectids the pipeline runs on (val/test projects must be geocoded too, since splits are a label overlay, not a physical partition — see README). Any projectid in `universe_projectids` not covered by a val/test cluster is labeled "train". For pr511, a project's *entire* county x route cluster is excluded from train (not just the matched project), preventing leakage from sibling projects sharing the same true segment. NOTE: no canonical "universe of all geocodable projectids" file exists in this container yet (see README's Open Items — the ad-hoc `Data/Intermediate/geocoding/inputs/` variants haven't been consolidated); if `universe_projectids` is NULL, this returns/writes only the val/test rows and leaves train undefined, rather than guessing a universe.
  #
  # Args:
  #   source: character scalar, e.g. "fmis_gis" or "pr511" — used as the output filename stem and folded into the hash salt by default.
  #   cluster_key_df: data.frame with one row per ground-truth project, containing at least `projectid` and `cluster_key` (county x route for pr511, route for fmis_gis), plus any strata columns to carry through (`state`, `completion_year`, `has_*` flags, etc.).
  #   val_frac: numeric in (0, 1), target share of clusters assigned to val (vs. test). Default 0.5.
  #   seed_salt: character scalar mixed into the cluster hash. Defaults to `source` so different sources don't share a hash pattern; pass explicitly to keep it stable if `source`'s name ever changes.
  #   universe_projectids: optional character vector of every geocodable projectid; see above.
  #
  # Returns:
  #   data.frame with columns `projectid`, `bucket` (val/test, plus train rows if `universe_projectids` was supplied), `cluster_key`, and any strata columns carried through from `cluster_key_df`. Also written to `geocode_eval_dir/splits/<source>_splits.csv` by the caller (this function does not do file I/O itself — see `main/01_build_splits.R`).
  stopifnot(all(c("projectid", "cluster_key") %in% names(cluster_key_df)))

  clusters <- unique(cluster_key_df$cluster_key)
  cluster_bucket <- tibble(
    cluster_key = clusters,
    bucket = ifelse(cluster_hash_frac(clusters, seed_salt) < val_frac, "val", "test")
  )

  labeled <- cluster_key_df %>%
    left_join(cluster_bucket, by = "cluster_key") %>%
    relocate(projectid, bucket, cluster_key)

  if (is.null(universe_projectids)) {
    return(labeled)
  }

  excluded <- unique(labeled$projectid)  # every project in ANY val/test cluster, not just matched ones
  train_ids <- setdiff(universe_projectids, excluded)
  train_rows <- tibble(projectid = train_ids, bucket = "train", cluster_key = NA_character_)
  return(bind_rows(labeled, train_rows))
}
