from google import genai
import os
import sys
import pandas as pd

import config
from gemini_utils import process_titles, write_log, log_config, RateLimitException


def main():
    # --------------------------------------------------------------------------
    # Create output directories
    # --------------------------------------------------------------------------
    os.makedirs(config.gemini_dir, exist_ok=True)
    os.makedirs(config.log_dir, exist_ok=True)
    os.makedirs(config.results_dir, exist_ok=True)
    os.makedirs(config.temp_dir, exist_ok=True)

    # --------------------------------------------------------------------------
    # Log parameters
    # --------------------------------------------------------------------------
    log_config(
        prompt_text_path=config.prompt_text_path,
        gemini_model_id=config.gemini_model_id,
        identifier=config.identifier,
        log_dir=config.log_dir,
        input_path=config.INPUT_PATH,
        row_indices=config.row_indices,
    )

    print(f"Using prompt: {config.prompt_text_path}")
    print(f"Saving output in: {config.results_dir}")

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

    outpath = os.path.join(config.results_dir, config.OUTPUT_FILE_NAME)
    print(f"Output path: {outpath}")

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
            intermediate_dir=config.temp_dir,
            row_indices=config.row_indices,
            log_dir=config.log_dir,
            identifier=config.identifier,
        )
        write_log("PROCESS COMPLETE", config.log_dir, config.identifier)
        print("\nParsing complete!")
    except RateLimitException as e:
        write_log(f"RUN ABORTED: {e}", config.log_dir, config.identifier)
        print(f"\nRun aborted due to fatal rate limit: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
