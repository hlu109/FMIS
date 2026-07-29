# ==============================================================================
# Entry point: score one geocoding run's predictions against cached ground truth and splits, writing flat CSVs.
# ==============================================================================
library(sf)
library(dplyr)

script_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
this_dir <- if (length(script_arg) > 0) dirname(sub("^--file=", "", script_arg)) else "."

source(file.path(this_dir, "..", "helpers", "paths.R"))
source(file.path(this_dir, "..", "helpers", "metrics.R"))
source(file.path(this_dir, "..", "helpers", "eval.R"))

# run_id identifies one geocoding pipeline run; its predictions live at
# geocode_eval_dir/predictions/<run_id>/predictions.gpkg (LINESTRINGs keyed by projectid)
run_id <- Sys.getenv("GEOCODE_EVAL_RUN_ID", unset = "")
if (run_id == "") stop("Set GEOCODE_EVAL_RUN_ID (env var) to the geocoding run to evaluate.")

predictions_path <- file.path(geocode_eval_dir, "predictions", run_id, "predictions.gpkg")
if (!file.exists(predictions_path)) stop("No predictions found at ", predictions_path)
predictions <- sf::st_read(predictions_path, quiet = TRUE)

sources <- c("fmis_gis", "pr511")
metrics_dir <- file.path(geocode_eval_dir, "metrics")

for (source in sources) {
  gt_path <- file.path(geocode_eval_dir, "ground_truth", paste0(source, ".gpkg"))
  splits_path <- file.path(geocode_eval_dir, "splits", paste0(source, "_splits.csv"))
  if (!file.exists(gt_path) || !file.exists(splits_path)) {
    message("Skipping ", source, ": missing ", gt_path, " or ", splits_path, ".")
    next
  }

  ground_truth <- sf::st_read(gt_path, quiet = TRUE)
  splits <- read.csv(splits_path, stringsAsFactors = FALSE)

  for (split_name in c("val", "test")) {
    split_ids <- splits$projectid[splits$bucket == split_name]
    gt_split <- ground_truth %>% filter(projectid %in% split_ids)
    preds_split <- predictions %>% filter(projectid %in% split_ids)

    result <- evaluate(preds_split, gt_split, routes = NULL, split_name = split_name)

    per_project_path <- file.path(metrics_dir, paste0(run_id, "__", source, "_", split_name, "__per_project.csv"))
    summary_path <- file.path(metrics_dir, paste0(run_id, "__", source, "_", split_name, "__summary.csv"))
    write.csv(sf::st_drop_geometry(result$per_project), per_project_path, row.names = FALSE)
    write.csv(result$summary$by_metric, summary_path, row.names = FALSE)

    message(
      source, "/", split_name, ": ", result$summary$coverage$n_matched, "/",
      result$summary$coverage$n_ground_truth, " matched (",
      round(result$summary$coverage$pct_geocoded, 1), "%). Wrote ", per_project_path
    )
  }
}

message("Eval run complete for run_id=", run_id, ". Output: ", metrics_dir)
