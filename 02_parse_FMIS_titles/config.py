import os
import sys
import getpass
from pathlib import Path
from datetime import datetime

project_root = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(project_root))

from helpers.Project import Project

# Set File Paths -------------------------------------------
username = getpass.getuser()
print(f"Running as user: {username}")

if username == "hl2266":  # username is the same between local machine and server, hence need further handling
    if os.getcwd().startswith("C:"):  # local machine
        PROJECT_ROOT = Path(
            "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data")
    elif "pi_zdl3" in os.getcwd():  # Yale HPC
        PROJECT_ROOT = Path("/nfs/roberts/project/pi_zdl3/shared/FMIS project")
    CODE_ROOT = PROJECT_ROOT / "Code" / "FMIS_hannah"
elif username == "andersonkovesci":
    PROJECT_ROOT = Path("/Users/andersonkovesci/Dropbox/FHWA cost data")
    CODE_ROOT = PROJECT_ROOT / "Code" / "FMIS_andy"
else:
    raise ValueError("Update config with machine-specific paths.")

DATA_ROOT = PROJECT_ROOT / "Data"
RAW_DATA_DIR = DATA_ROOT / "Raw"
INTERMEDIATE_DATA_DIR = DATA_ROOT / "Intermediate"
GEOCODING_DIR = INTERMEDIATE_DATA_DIR / "geocoding"

print(f"PROJECT_ROOT: {PROJECT_ROOT}")

# ------------------------------------------------------------------------------
# SET PARAMETERS
# ------------------------------------------------------------------------------

# Optional note to log purpose of the run (default set to None)
NOTE = "Testing new Gemini prompt to work on non-interstates without route_FPN metadata."

# Set API Parameters
GEMINI_MODEL_ID = "gemini-2.5-flash"
# GEMINI_MODEL_ID = "gemini-2.5-pro"
# GEMINI_MODEL_ID = "gemini-3.1-pro"
# GEMINI_MODEL_ID = "gemini-3.5-flash"

# SET GEMINI PROMPT
prompt_version = 6

# SET FILE IDENTIFIERS
RUN_PREFIX = f"VAL_fmis_gis_200_test_noninterstate_prompt_v{prompt_version}"

# SET RESUME PARAMETERS
REUSE_OLD_RESULTS = False
RESUME_RUN_IDENTIFIER = None

# SET FILE PATHS
INPUT_PATH = INTERMEDIATE_DATA_DIR / "geocode_eval" / "splits" / "VAL_fmis_gis_project_titles.dta"

# SET SCHEMA
page_schema = Project

# SET SAMPLING PARAMETERS
ROW_INDICES = None
# ROW_INDICES = [27, 28, 29, 30]          # manual override; if set, skip auto sample
# if set (and ROW_INDICES is None), sample this many rows
SAMPLE_N = 200
# SAMPLE_N = None # use full dataset
# SAMPLE_STRATIFY_BY = ["state_fips", "post_1970_auth", "below_median_cost"]
RANDOM_SEED = 42

# ------------------------------------------------------------------------------
# AUTO SET REMAINING FILE PATHS
if REUSE_OLD_RESULTS:
    if not RESUME_RUN_IDENTIFIER:
        raise ValueError(
            "REUSE_OLD_RESULTS is True but RESUME_RUN_IDENTIFIER is not set.")
    # reuse the prior run's identifier so intermediate JSONs, the output CSV, and the log file all resolve to the same paths as the run being resumed
    IDENTIFIER = RESUME_RUN_IDENTIFIER
else:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    IDENTIFIER = f"{RUN_PREFIX}_{timestamp}"

PROMPT_TEXT_PATH = CODE_ROOT / "02_parse_FMIS_titles" / "prompts" / f"prompt v{prompt_version}.md"

GEMINI_DIR = GEOCODING_DIR / "title_parsing_gemini_output"
LOG_DIR = GEOCODING_DIR / "title_parsing_gemini_logs"

OUTPUT_FILE_NAME = f"{IDENTIFIER}.csv"
RUN_DIR = GEMINI_DIR / IDENTIFIER
OUTPUT_PATH = GEMINI_DIR / OUTPUT_FILE_NAME
