from google import genai
import os
import sys
from pathlib import Path
import pandas as pd

project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root))

import config
from gemini_utils import process_titles, write_log, log_config, RateLimitException
from utils.sample_utils import stratified_sample, stratified_sample_summary


def main():
    # --------------------------------------------------------------------------
    # Create output directories
    # --------------------------------------------------------------------------
    os.makedirs(config.gemini_dir, exist_ok=True)
    os.makedirs(config.log_dir, exist_ok=True)
    os.makedirs(config.run_dir, exist_ok=True)

    print(f"Using prompt: {config.prompt_text_path}")
    print(f"Intermediate JSONs: {config.run_dir}")
    print(f"Final CSV: {config.OUTPUT_PATH}")

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
    with open(config.prompt_text_path, "r", encoding="utf-8") as file:
        task = file.read()

    df = pd.read_stata(str(config.INPUT_PATH), convert_categoricals=False)
    print(f"Loaded {len(df)} rows from {config.INPUT_PATH}")

    population_stratum_counts = None
    allocated_stratum_counts = None
    sample_stratum_counts = None

    if config.row_indices is not None:
        row_indices = config.row_indices
        auto_sample = False
    elif config.sample_n is not None:
        row_indices = stratified_sample(
            df, n=config.sample_n,
            stratify_by=config.sample_stratify_by,
            seed=config.random_seed,
        ).index.tolist()
        summary = stratified_sample_summary(
            df, config.sample_n, config.sample_stratify_by, row_indices)
        auto_sample = True

        if summary:
            population_stratum_counts = summary["population"]
            allocated_stratum_counts = summary["allocated"]
            sample_stratum_counts = summary["sample"]
    else:
        row_indices = None
        auto_sample = False


    log_config(
        prompt_text_path=config.prompt_text_path,
        gemini_model_id=config.gemini_model_id,
        identifier=config.identifier,
        log_dir=config.log_dir,
        input_path=config.INPUT_PATH,
        row_indices=row_indices,
        sample_n=config.sample_n if auto_sample else None,
        sample_stratify_by=config.sample_stratify_by if auto_sample else None,
        random_seed=config.random_seed if auto_sample else None,
        population_stratum_counts=population_stratum_counts,
        allocated_stratum_counts=allocated_stratum_counts,
        sample_stratum_counts=sample_stratum_counts,
    )

    outpath = str(config.OUTPUT_PATH)

    # --------------------------------------------------------------------------
    # Run parsing
    # --------------------------------------------------------------------------
    try:
        process_titles(
            client,
            df=df,
            data_struct=config.page_schema,
            prompt_text=task,
            model_id=config.gemini_model_id,
            outfile_path=outpath,
            intermediate_dir=str(config.run_dir),
            row_indices=row_indices,
            log_dir=config.log_dir,
            identifier=config.identifier,
        )
        write_log("PROCESS COMPLETE", config.log_dir, config.identifier)
        print("\nParsing complete!")
    except RateLimitException as e:
        write_log(f"RUN ABORTED: {e}", config.log_dir, config.identifier)
        print(f"\nRun aborted due to fatal rate limit: {e}")
        sys.exit(1)
    except KeyboardInterrupt:
        write_log("RUN ABORTED.", config.log_dir, config.identifier)
        sys.exit(1)


if __name__ == "__main__":
    main()
