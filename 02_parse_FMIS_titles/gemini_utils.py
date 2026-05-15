import os
import time
import json
import pandas as pd
from pydantic import BaseModel
from google.genai import errors
from datetime import datetime

from Project import Project, project_to_dataframe


# ==============================================================================
# Logging
# ==============================================================================

def write_log(message, log_dir, identifier):
    """Appends a timestamped message to a run-specific log file."""
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)
    file_path = os.path.join(log_dir, f"log_{identifier}.txt")
    with open(file_path, "a", encoding="utf-8") as file:
        timestamp = datetime.now().strftime("%H%M:%S")
        file.write(f"[{timestamp}] {message}\n\n")


def _log_and_print(message, log_dir=None, identifier=None):
    """Print a message and optionally write it to a log file."""
    print(message)
    if log_dir and identifier:
        write_log(message, log_dir, identifier)


def _format_stratum_counts(label, counts):
    if counts is None:
        return ""
    return f"{label}:\n{counts.to_string()}\n\n"


def log_config(prompt_text_path, gemini_model_id, identifier, log_dir,
               input_path=None, row_indices=None, sample_n=None,
               sample_stratify_by=None, random_seed=None,
               population_stratum_counts=None,
               allocated_stratum_counts=None,
               sample_stratum_counts=None):
    """Logs prompt text and configuration values for a Gemini run."""
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)

    with open(prompt_text_path, "r", encoding="utf-8") as file:
        prompt_text = file.read()
    with open(os.path.join(log_dir, f"prompt_text_{identifier}.txt"), "a",
              encoding="utf-8") as file:
        file.write(prompt_text)

    file_path = os.path.join(log_dir, f"log_{identifier}.txt")
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    with open(file_path, "a", encoding="utf-8") as file:
        file.write(f"[{timestamp}] \n\n")
        file.write(f"CONFIG PARAMETERS\n\n")
        file.write(f"Input file: {input_path}\n")
        file.write(f"Prompt text file: {prompt_text_path}\n")
        file.write(f"Gemini model: {gemini_model_id}\n\n")

        if sample_n is not None:
            file.write(f"Sample: n={sample_n}, seed={random_seed}\n")
            if sample_stratify_by is not None:
                file.write(f"Stratify variables: {sample_stratify_by}\n")
                file.write(_format_stratum_counts(
                    "Population counts by stratum", population_stratum_counts))
                file.write(_format_stratum_counts(
                    "Target allocation by stratum", allocated_stratum_counts))
                file.write(_format_stratum_counts(
                    "Realized sample counts by stratum", sample_stratum_counts))
            else:
                file.write("Stratify variables: none (simple random sample)\n")
            if row_indices:
                if len(row_indices) <= 20:
                    file.write(f"Row indices: {row_indices}\n")
                else:
                    file.write(f"Row indices: {len(row_indices)} rows, "
                               f"first 10: {row_indices[:10]}\n")
        elif row_indices:
            if len(row_indices) <= 20:
                file.write(f"Row indices filter: {row_indices}\n")
            else:
                file.write(f"Row indices filter: {len(row_indices)} rows, "
                           f"first 10: {row_indices[:10]}\n")
        else:
            file.write(f"Row indices filter: All rows\n")

        file.write("\n")


# ==============================================================================
# Gemini 
# ==============================================================================


class RateLimitException(Exception):
    """Raised when 429 retries are exhausted; signals the full run should stop."""

def extract_title_data(genai_client,
                       project_input: dict,
                       data_struct: BaseModel,
                       prompt_text: str,
                       model_id: str,
                       recipient_id=None,
                       federal_project_number=None,
                       log_dir=None,
                       identifier=None):
    """
    Extracts structured data from an FMIS project title using the Gemini API.

    Parameters:
        genai_client: Gemini API client.
        project_input (dict): Dict with project title and metadata fields
            (project_title, state_fips, state_name, county_fips, county_name, route_num).
        data_struct (BaseModel): Pydantic model for structured output.
        prompt_text (str): Prompt text in raw text form.
        model_id (str): Gemini model ID.
        recipient_id: Recipient ID for logging.
        federal_project_number: Federal project number for logging.
        log_dir (str, optional): Directory for writing Gemini error logs.
        identifier (str, optional): Run identifier for the log filename.

    Returns:
        Project or None: Parsed structured data if successful, otherwise None.
        # wait should we return dict instead of project?
    """
    # limit output size
    max_token_output = 80000 # TODO check what is appropriate for this 
    max_retries = 7
    base_wait = 3  # this is in seconds!
    project_input_json_str = json.dumps(project_input)

    for attempt in range(max_retries):
        print(f"      Attempt {attempt + 1} to extract data...")
        try:
            # Generate a structured response using the Gemini API
            response = genai_client.models.generate_content(
                model=model_id,
                contents=[prompt_text, project_input_json_str],
                config={
                    'response_mime_type': 'application/json',
                    'response_schema': data_struct,
                    'max_output_tokens': max_token_output
                })

            # Check for token limit issues
            if hasattr(response, 'candidates') and response.candidates:
                if response.candidates[0].finish_reason.name == 'MAX_TOKENS':
                    m = (
                        f"WARNING: Response truncated due to token limit. "
                        f"Token count: {response.usage_metadata.candidates_token_count}"
                    )
                    _log_and_print(
                        f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\nextract_attempt={attempt + 1} \t\n{m}",
                        log_dir, identifier)

            if not response or not response.parsed:
                m = "ERROR: The API did not return a valid parsed response."
                _log_and_print(
                    f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\nextract_attempt={attempt + 1} \t\n{m}",
                    log_dir, identifier)
                return None

            return response.parsed

        # handle errors using gemini error classes 
        except errors.ServerError as e:
            wait_time = base_wait * (2 ** attempt)
            m = f"Server error {e.code} on attempt {attempt + 1}. Retrying in {wait_time:.1f}s..."
            _log_and_print(
                f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\nextract_attempt={attempt + 1} \t\n{m}",
                log_dir, identifier)
            time.sleep(wait_time)
        except errors.ClientError as e:
            if e.code == 429: # rate limit error 
                # rate limits are per minute and per day. first try to wait a minute, if that doesn't work, then wait until the end of the day (compute how much time left).... or maybe we should kill it 

                if attempt == max_retries - 1: 
                    # kill the full run if we've retried several times and still have a rate limit (this likely means we hit the rate limit for the full day rather than per minute so we probably screwed up and should downgrade to a lower model)
                    m = "Max rate limit retries reached. Giving up on this row."
                    _log_and_print(
                        f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\n{m}",
                        log_dir, identifier)
                    raise RateLimitException("Max rate limit retries reached. Killing rest of the full run.")

                wait_time = 60 * (2 ** attempt)
                m = f"Rate limit (429 error) on attempt {attempt + 1}. Retrying in {wait_time:.1f}s..."
                _log_and_print(
                    f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\nextract_attempt={attempt + 1} \t\n{m}",
                    log_dir, identifier)
                time.sleep(wait_time)
            else:
                m = f"Other client-side error occurred, not retrying: {e}"
                _log_and_print(
                    f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\nextract_attempt={attempt + 1} \t\n{m}",
                    log_dir, identifier)
                return None
        except Exception as e:
            m = f"Other Exception occurred, not retrying: {e}"
            _log_and_print(
                f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\nextract_attempt={attempt + 1} \t\n{m}",
                log_dir, identifier)
            return None

    m = "Max error retries reached. Giving up on this row."
    _log_and_print(
        f"recipient_id={recipient_id} \t\nfpn={federal_project_number} \t\nmodel_id={model_id} \t\n{m}",
        log_dir, identifier)
    return None


# ==============================================================================
# Processing loop
# ==============================================================================

def _format_state_fips(value):
    """Format state FIPS as a 2-digit zero-padded string."""
    if pd.isna(value):
        return None
    return f"{int(value):02d}"


def _format_county_fips(value):
    """Format county FIPS as a 5-digit zero-padded string."""
    if pd.isna(value):
        return None
    return f"{int(value):05d}"


def _save_partial_results(all_dataframes: list[pd.DataFrame], outfile_path, log_dir,
                        identifier, reason) -> pd.DataFrame | None:
    """Save accumulated rows to CSV; returns the DataFrame if any rows were saved.

    Parameters:
        all_dataframes: List of one-row DataFrames to concatenate and save.
    """
    if not all_dataframes:
        _log_and_print(
            f"{reason}: no partial results to save.",
            log_dir, identifier)
        return None

    partial_df = pd.concat(all_dataframes, ignore_index=True)

    # rearrange so raw_project_title is first column
    if "raw_project_title" in partial_df.columns:
        partial_df = partial_df[["raw_project_title"] + [
            col for col in partial_df.columns if col != "raw_project_title"
        ]]

    partial_df.to_csv(outfile_path, index=False)

    _log_and_print(
        f"{reason}: partial results saved to {outfile_path} "
        f"({partial_df.shape[0]} rows).",
        log_dir, identifier)
    return partial_df


def process_titles(genai_client,
                   df: pd.DataFrame,
                   data_struct: BaseModel,
                   prompt_text: str,
                   model_id: str,
                   outfile_path: str,
                   intermediate_dir: str,
                   row_indices: list = None,
                   log_dir=None,
                   identifier=None):
    """
    Extracts structured endpoint data from FMIS project titles and saves results.

    Parameters:
        genai_client: Gemini API client.
        df (pd.DataFrame): Input DataFrame with project titles and metadata.
        data_struct (BaseModel): Pydantic model for structured output.
        prompt_text (str): Prompt text for the API.
        model_id (str): Gemini model ID.
        outfile_path (str): Path to save final CSV.
        intermediate_dir (str): Folder for intermediate JSON outputs.
        row_indices (list, optional): Specific DataFrame indices to process.
            If None, processes all rows.
        log_dir (str, optional): Directory for writing Gemini error logs.
        identifier (str, optional): Run identifier for the log filename.

    Returns:
        pd.DataFrame: Aggregated structured data extracted from all titles.
    """
    if row_indices is not None:
        df_subset = df.loc[row_indices]
    else:
        df_subset = df

    total_rows = len(df_subset)
    all_dataframes: list[pd.DataFrame] = []
    start_time = time.time()

    # track issues in real time 
    error_count = 0

    try:
        for i, (idx, row) in enumerate(df_subset.iterrows()):
            recipient_id = row.get("recipientid", "")
            fpn = row.get("federal_project_number", "")
            proj_id = f"{recipient_id}_{fpn}"
            json_path = os.path.join(intermediate_dir, 
                                     f"parsed_title_{proj_id}.json")

            # Resume support: load intermediate JSON if it already exists
            # TODO: need to allow selection of past run timestamp/identifier 
            # if os.path.exists(json_path):
            #     print(f"  Row {idx} ({i + 1}/{total_rows}): intermediate JSON exists, skipping LLM.")
            #     with open(json_path, "r", encoding="utf-8") as f:
            #         result_json = json.load(f)
            #     # TODO: replace with a json_to_dataframe function 
            #     result = Project(**{k: v for k, v in result_json.items()
            #                        if k in Project.model_fields})
            #     row_df = project_to_dataframe(result)
            #     row_df["row_index"] = idx
            #     row_df["recipient_id"] = recipient_id
            #     row_df["federal_project_number"] = fpn
            #     row_df["model_id"] = result_json.get("model_id")
            #     row_df["raw_project_title"] = result_json.get("raw_project_title")
            #     all_dataframes.append(row_df)
            #     continue

            print(f"\nProcessing row {idx} ({i + 1}/{total_rows}): {recipient_id} / {fpn}")

            project_input = {
                "project_title": str(row.get("projecttitle", "")),
                "state_fips": _format_state_fips(row.get("state_fips")),
                "state_name": str(row.get("state_name", "")),
                "county_fips": _format_county_fips(row.get("county_fips")),
                "county_name": str(row.get("county_name", "")),
                "route_num": int(row["route_fpn"]) if pd.notna(row.get("route_fpn")) else None,
            }

            if project_input["project_title"] == "":
                # skip projects with no title; don't raise any error, there are too many of these in FMIS and this is a known issue. 
                continue 

            try:
                result = extract_title_data(
                    genai_client,
                    project_input=project_input,
                    data_struct=data_struct,
                    prompt_text=prompt_text,
                    model_id=model_id,
                    recipient_id=recipient_id,
                    federal_project_number=fpn,
                    log_dir=log_dir,
                    identifier=identifier
                )
            except RateLimitException as e:
                m = (
                    f"FATAL rate limit error on row {idx} ({i + 1}/{total_rows}): "
                    f"{recipient_id} / {fpn}. {e}"
                )
                _log_and_print(m, log_dir, identifier)
                _save_partial_results(
                    all_dataframes, outfile_path, log_dir, identifier,
                    "Fatal rate limit stop")
                raise

            if result:
                runtime_metadata = {
                    "row_index": idx,
                    "recipient_id": recipient_id,
                    "federal_project_number": fpn,
                    "model_id": model_id,
                    "raw_project_title": project_input["project_title"],
                }

                # add additional tracked information to the json 
                result_json = result.model_dump()
                result_json.update(runtime_metadata)

                # save intermediate data structure to json
                # (for the future - to handle unplanned termination and be able to resume from existing progress)
                with open(json_path, "w", encoding="utf-8") as f:
                    json.dump(result_json, f, indent=4, ensure_ascii=False)
                print(
                    f"  Saved intermediate JSON to {json_path}"
                )

                row_df = project_to_dataframe(result)

                # add metadata to final dataframe
                # TODO: this stuff is kind of redundant with update runtime metadata above but right now we have to do it separately since project_to_dataframe only works on Project objects. we should refactor so it works on dicts/jsons? 
                for key, value in runtime_metadata.items():
                    row_df[key] = value
            
                if row_df is not None:
                    all_dataframes.append(row_df)

            else:
                m = f"FAILURE - No data returned for {recipient_id} / {fpn}."
                _log_and_print(
                    f"recipient_id={recipient_id} \t\nfpn={fpn} \t\nmodel_id={model_id} \t\n{m}",
                    log_dir, identifier)
                error_count += 1

            total_time_elapsed = time.time() - start_time
            avg_time_per_project = total_time_elapsed / (i + 1)
            print(f"Total time elapsed: {total_time_elapsed / 3600:.2f} hrs")
            print(f"Average time per project so far: {avg_time_per_project:.2f} s")
            print(f"Projects with no Gemini output so far: {error_count}")

    except KeyboardInterrupt:
        row_info = (
            f"on row {idx} ({i + 1}/{total_rows}): {recipient_id} / {fpn}"
            if "idx" in locals() else "during processing"
        )
        _log_and_print(
            f"RUN INTERRUPTED by user {row_info}.",
            log_dir, identifier)
        _save_partial_results(
            all_dataframes, outfile_path, log_dir, identifier,
            "Keyboard interrupt")
        raise

    # log error counts to log file 
    _log_and_print(f"Total projects with no Gemini output: {error_count}", log_dir, identifier)

    if all_dataframes:
        final_df = pd.concat(all_dataframes, ignore_index=True)
        # rearrange so raw_project_title is first column
        final_df = final_df[["raw_project_title"] + [col for col in final_df.columns if col != "raw_project_title"]]

        print(f"\n Generated dataframe with {final_df.shape[0]} rows")
        final_df.to_csv(outfile_path, index=False)
        print(f"  Saved final output to {outfile_path}\n")
        return final_df
    else:
        return None
