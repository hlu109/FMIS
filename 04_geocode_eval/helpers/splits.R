# ==============================================================================
# Assign ground-truth projects to val/test splits.
# ==============================================================================
library(dplyr)
library(digest)

# TODO: @Hannah needs testing
cluster_hash_frac <- function(cluster_key, seed_salt) {
  # Maps a cluster key to a stable pseudo-random fraction in [0, 1).
  #
  # Uses the first 7 hex chars of an md5 digest of a string constructed from the cluster key plus seed salt as a base-16 integer, scaled to [0, 1). 7 hex chars ensures the value stays under R's 32-bit signed integer max and `strtoi` doesn't overflow to NA. This is stable across runs/machines (unlike `sample()` with a seed, which is not guaranteed stable across R versions), so cluster assignments don't reshuffle when the eval scope or R version changes.
  #
  # Args:
  #   cluster_key: character vector of cluster ids.
  #   seed_salt: string mixed into the hash so different sources/splits don't share an assignment pattern.
  #
  # Returns:
  #   numeric vector, same length as `cluster_key`, in [0, 1).

  # vectorize the hash function to get one digest per item
  digests <- vapply(
    cluster_key,
    function(k) digest::digest(paste0(k, "_", seed_salt), algo = "md5"),
    character(1)
  )

  # scale to [0, 1)
  return(strtoi(substr(digests, 1, 7), base = 16L) / (16^7))
}

# TODO: extend to train val test
build_splits <- function(
  source,
  cluster_key_df,
  val_frac = 0.5,
  seed_salt = source,
  universe_projectids = NULL
) {
  # Assigns val/test splits to a ground-truth source's projects.
  #
  # Projects are clustered by desired key (e.g., county and route) to avoid leakage across val and test where multiple projects may describe the same segment. Clusters (not individual projects) are assigned to val or test. A cluster's split is decided once via `cluster_hash_frac(cluster_key, seed_salt)` compared to `val_frac`. This is frozen and reproducible: re-running with the same `cluster_key`/`seed_salt` always yields the same assignment, and the hashing makes it stable under scope changes (adding new clusters doesn't reshuffle existing ones, unlike `sample()`).
  #
  # TODO: @Hannah idk if we want this
  # `universe_projectids`, if supplied, is the full set of geocodable projectids the pipeline runs on. Any projectid in `universe_projectids` not covered by a val/test cluster is labeled "train". For pr511, a project's *entire* county x route cluster is excluded from train (not just the matched project), preventing leakage from sibling projects sharing the same true segment.
  #
  # Args:
  #   source: string, e.g. "fmis_gis" or "pr511" — used as the output filename stem and folded into the hash salt by default.
  #   cluster_key_df: data.frame with one row per ground-truth project, containing at least `projectid` and `cluster_key`, plus any strata columns to carry through (`state`, `completion_year`, `has_*` flags, etc.).
  #   val_frac: numeric in (0, 1), target share of clusters assigned to val (vs. test).
  #   seed_salt: character scalar mixed into the cluster hash.
  #   universe_projectids: optional character vector of every geocodable projectid.
  #
  # Returns:
  #   data.frame with columns `projectid`, `split` (val/test, plus train rows if `universe_projectids` was supplied), `cluster_key`, and any strata columns carried through from `cluster_key_df`.

  # verify input contains required columns
  stopifnot(all(c("projectid", "cluster_key") %in% names(cluster_key_df)))

  # assign one split per distinct cluster via hash
  clusters <- unique(cluster_key_df$cluster_key)
  cluster_split <- tibble(
    cluster_key = clusters,
    split = ifelse(
      cluster_hash_frac(clusters, seed_salt) < val_frac,
      "val",
      "test"
    )
  )

  # broadcast each cluster's split back out to every project row in that cluster
  labeled <- cluster_key_df %>%
    left_join(cluster_split, by = "cluster_key") %>%
    relocate(projectid, split, cluster_key) # reorder columns

  if (is.null(universe_projectids)) {
    return(labeled)
  }

  # handle non-val/test projects
  # TODO: needs review
  excluded <- unique(labeled$projectid) # include every project in ANY val/test cluster, not just matched ones
  train_ids <- setdiff(universe_projectids, excluded)
  train_rows <- tibble(
    projectid = train_ids,
    split = "train",
    cluster_key = NA_character_
  )
  return(bind_rows(labeled, train_rows))
}

build_splits_stratified <- function(
  source,
  cluster_key_df,
  strata_cols,
  val_frac = 0.5,
  seed_salt = source,
  universe_projectids = NULL
) {
  # Assigns val/test splits to a ground-truth source's projects using stratified random sampling and clustering projects to prevent leakage across multiple projects describing the same segment.
  #
  # Each cluster is reduced to one stratum via its first row in `cluster_key_df` (arbitrary but deterministic — a cluster can carry rows with different strata values, e.g. a route with several project types, so this is an approximation, not an exact per-row stratification). Results across strata are combined, then train rows (if any) are computed once over the full combined set.
  #
  # Args:
  #   source: string, e.g. "fmis_gis" or "pr511" — used as the output filename stem and folded into the hash salt by default.
  #   cluster_key_df: data.frame with one row per ground-truth project, containing at least `projectid` and `cluster_key`, plus every column named in `strata_cols`.
  #   strata_cols: character vector of column names in `cluster_key_df` to stratify by.
  #   val_frac: numeric in (0, 1), target share of clusters assigned to val (vs. test) within each stratum.
  #   seed_salt: character scalar mixed into the cluster hash (along with the stratum).
  #   universe_projectids: optional character vector of every geocodable projectid the pipeline runs on. Any projectid not covered by a val/test cluster, in any stratum, is labeled "train" once all strata have been combined.
  #
  # Returns:
  #   data.frame with columns `projectid`, `split` (val/test, plus train rows if `universe_projectids` was supplied), `cluster_key`, and any strata columns carried through from `cluster_key_df`.

  # verify input contains required columns
  stopifnot(all(c("projectid", "cluster_key") %in% names(cluster_key_df)))
  stopifnot(all(strata_cols %in% names(cluster_key_df)))

  # keep one row per cluster (first row wins)
  cluster_reps <- cluster_key_df %>% distinct(cluster_key, .keep_all = TRUE)
  # collapse multiple strata columns into a single "|"-joined stratum label per cluster
  cluster_reps$stratum <- Reduce(
    function(a, b) paste(a, b, sep = "|"),
    lapply(strata_cols, function(col) as.character(cluster_reps[[col]])) # convert each strata column to string type
  )
  print(head(cluster_reps))

  # run build_splits() once per stratum, on just that stratum's clusters, so val_frac is hit within each stratum rather than only in aggregate
  # (seed_salt is stratum-specific so strata don't share a hash pattern)
  strata <- unique(cluster_reps$stratum)
  print(strata)
  per_stratum <- lapply(strata, function(s) {
    keys_in_stratum <- cluster_reps$cluster_key[cluster_reps$stratum == s]
    build_splits(
      source,
      cluster_key_df %>% filter(cluster_key %in% keys_in_stratum),
      val_frac = val_frac,
      seed_salt = paste(seed_salt, s, sep = "_")
    )
  })
  labeled <- bind_rows(per_stratum)

  if (is.null(universe_projectids)) {
    return(labeled)
  }

  # handle non-val/test projects
  # TODO: needs review
  # same train-labeling as the single-stratum path: whatever wasn't claimed by any stratum's val/test clusters is train
  excluded <- unique(labeled$projectid)
  train_ids <- setdiff(universe_projectids, excluded)
  train_rows <- tibble(
    projectid = train_ids,
    split = "train",
    cluster_key = NA_character_
  )
  return(bind_rows(labeled, train_rows))
}
