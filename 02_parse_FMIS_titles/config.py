import os
import getpass
from pathlib import Path
from datetime import datetime

from Project import Project


# ------------------------------------------------------------------------------
# SET PARAMETERS ---------------------------------------------------------------
# ------------------------------------------------------------------------------

# Set API Parameters -------------------------------------------
gemini_model_id = "gemini-2.5-flash"
# gemini_model_id = "gemini-2.5-pro"
# gemini_model_id = "gemini-3.1-pro"
# gemini_model_id = "gemini-3.5-flash"

# Set File Paths -------------------------------------------
username = getpass.getuser()
if username == "hl2266":
    PROJECT_ROOT = Path("C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data")
    DATA_ROOT = PROJECT_ROOT / "Data"
    RAW_DATA_DIR = DATA_ROOT / "Raw"
    INTERMEDIATE_DATA_DIR = DATA_ROOT / "Intermediate"
    GEOCODING_DIR = INTERMEDIATE_DATA_DIR / "geocoding"
    CODE_ROOT = PROJECT_ROOT / "Code" / "FMIS_hannah"
elif username == "andersonkovesci":
    PROJECT_ROOT = Path("/Users/andersonkovesci/Dropbox/FHWA cost data")
    DATA_ROOT = PROJECT_ROOT / "Data"
    RAW_DATA_DIR = DATA_ROOT / "Raw"
    INTERMEDIATE_DATA_DIR = DATA_ROOT / "Intermediate"
    GEOCODING_DIR = INTERMEDIATE_DATA_DIR / "geocoding"
    CODE_ROOT = PROJECT_ROOT / "Code" / "FMIS_andy"
else:
    raise ValueError("Update config with machine-specific paths.")


INPUT_PATH = GEOCODING_DIR / "FMIS_interstate_newconstr_project_titles.dta"

# SET OUTPUT PATHS -------------------------------------------------------------
gemini_dir = GEOCODING_DIR / "title_parsing_gemini_output"
log_dir = GEOCODING_DIR / "title_parsing_gemini_logs"

# SET GEMINI PROMPT ------------------------------------------------------------
prompt_text_path = CODE_ROOT / "02_parse_FMIS_titles" / "prompt v3.md"

# Set Schema -----------------------------------
page_schema = Project

# Project filtering (optional)
row_indices = None 
# row_indices = [27, 28, 29, 30]          # manual override; if set, skip auto sample
sample_n = 100                # if set (and row_indices is None), sample this many rows
sample_stratify_by = ["state_fips", "post_1970_auth", "below_median_cost"]
random_seed = 42

# ------------------------------------------------------------------------------
# END OF SET PARAMETERS --------------------------------------------------------
# ------------------------------------------------------------------------------

timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
identifier = "new_constr_v3_" + timestamp
RUN_PREFIX = "fmis_interstate_parsed_titles"
run_name = f"{RUN_PREFIX}_{identifier}"
OUTPUT_FILE_NAME = f"{run_name}.csv"
run_dir = gemini_dir / run_name
OUTPUT_PATH = gemini_dir / OUTPUT_FILE_NAME
