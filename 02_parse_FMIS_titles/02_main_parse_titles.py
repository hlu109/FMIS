from google import genai
import os
import sys
import time
from pathlib import Path
import pandas as pd

project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root))

import config
from helpers.gemini_utils import process_titles, write_log, write_run_boundary, log_config, RateLimitException
from utils.sample_utils import stratified_sample, stratified_sample_summary


def main():
    # --------------------------------------------------------------------------
    # Create output directories
    # --------------------------------------------------------------------------
    if config.REUSE_OLD_RESULTS and not config.RUN_DIR.exists():
        raise FileNotFoundError(
            f"REUSE_OLD_RESULTS is True but run directory does not exist: {config.RUN_DIR}"
        )

    os.makedirs(config.GEMINI_DIR, exist_ok=True)
    os.makedirs(config.LOG_DIR, exist_ok=True)
    os.makedirs(config.RUN_DIR, exist_ok=True)

    print(f"Using prompt: {config.PROMPT_TEXT_PATH}")
    print(f"Intermediate JSONs: {config.RUN_DIR}")
    print(f"Final CSV: {config.OUTPUT_PATH}")
    if config.REUSE_OLD_RESULTS:
        print(
            f"Resuming run '{config.RESUME_RUN_IDENTIFIER}': existing JSONs will be reused.")

    write_run_boundary(config.LOG_DIR, config.IDENTIFIER, "START")

    # --------------------------------------------------------------------------
    # Create Gemini client
    # --------------------------------------------------------------------------
    with open("secret/GEMINI_API_KEY.txt", "r", encoding="utf-8") as file:
        api_key = file.read().strip()
        print("Successfully loaded API key")

    client = genai.Client(api_key=api_key)
    print("Successfully loaded Gemini AI client with API key")

    # --------------------------------------------------------------------------
    # Read prompt and input data
    # --------------------------------------------------------------------------
    with open(config.PROMPT_TEXT_PATH, "r", encoding="utf-8") as file:
        task = file.read()

    df = pd.read_stata(str(config.INPUT_PATH), convert_categoricals=False)
    print(f"Loaded {len(df)} rows from {config.INPUT_PATH}")

    population_stratum_counts = None
    allocated_stratum_counts = None
    sample_stratum_counts = None

    if config.ROW_INDICES is not None:
        row_indices = config.ROW_INDICES
        auto_sample = False
    elif config.SAMPLE_N is not None:
        row_indices = stratified_sample(
            df, n=config.SAMPLE_N,
            stratify_by=config.SAMPLE_STRATIFY_BY,
            seed=config.RANDOM_SEED,
        ).index.tolist()
        summary = stratified_sample_summary(
            df, config.SAMPLE_N, config.SAMPLE_STRATIFY_BY, row_indices)
        auto_sample = True

        if summary:
            population_stratum_counts = summary["population"]
            allocated_stratum_counts = summary["allocated"]
            sample_stratum_counts = summary["sample"]
    else:
        row_indices = None
        auto_sample = False

    log_config(
        prompt_text_path=config.PROMPT_TEXT_PATH,
        gemini_model_id=config.GEMINI_MODEL_ID,
        identifier=config.IDENTIFIER,
        log_dir=config.LOG_DIR,
        input_path=config.INPUT_PATH,
        output_path=config.OUTPUT_PATH,
        run_dir=config.RUN_DIR,
        data_struct=config.page_schema,
        row_indices=row_indices,
        sample_n=config.SAMPLE_N if auto_sample else None,
        sample_stratify_by=config.SAMPLE_STRATIFY_BY if auto_sample else None,
        random_seed=config.RANDOM_SEED if auto_sample else None,
        reuse_old_results=config.REUSE_OLD_RESULTS,
        resume_run_identifier=config.RESUME_RUN_IDENTIFIER,
        population_stratum_counts=population_stratum_counts,
        allocated_stratum_counts=allocated_stratum_counts,
        sample_stratum_counts=sample_stratum_counts,
    )

    outpath = str(config.OUTPUT_PATH)

    # --------------------------------------------------------------------------
    # Run parsing
    # --------------------------------------------------------------------------
    start_time = time.time()
    try:
        process_titles(
            client,
            df=df,
            data_struct=config.page_schema,
            prompt_text=task,
            model_id=config.GEMINI_MODEL_ID,
            outfile_path=outpath,
            intermediate_dir=str(config.RUN_DIR),
            row_indices=row_indices,
            log_dir=config.LOG_DIR,
            identifier=config.IDENTIFIER,
            reuse_old_results=config.REUSE_OLD_RESULTS,
        )
        elapsed_hrs = (time.time() - start_time) / 3600
        write_log(f"PROCESS COMPLETE. Run time: {elapsed_hrs:.2f} hrs",
                  config.LOG_DIR, config.IDENTIFIER)
        print(f"\nParsing complete! Run time: {elapsed_hrs:.2f} hrs")
    except RateLimitException as e:
        write_log(f"RUN ABORTED: {e}", config.LOG_DIR, config.IDENTIFIER)
        print(f"\nRun aborted due to fatal rate limit: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        write_log("RUN ABORTED.", config.LOG_DIR, config.IDENTIFIER)
        sys.exit(1)
    finally:
        write_run_boundary(config.LOG_DIR, config.IDENTIFIER, "END")


if __name__ == "__main__":
    main()
