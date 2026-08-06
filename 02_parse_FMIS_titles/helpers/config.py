import os
import getpass
from pathlib import Path
from datetime import datetime

from .Project import Project


# Set File Paths -------------------------------------------
username = getpass.getuser()
print(f"Running as user: {username}")

if username == "hl2266": # username is the same between local machine and server, hence need further handling 
    if os.getcwd().startswith("C:"): # local machine 
        PROJECT_ROOT = Path("C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data")
    elif "pi_zdl3" in os.getcwd(): # Yale HPC 
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

# Set API Parameters 
GEMINI_MODEL_ID = "gemini-2.5-flash"
# GEMINI_MODEL_ID = "gemini-2.5-pro"
# GEMINI_MODEL_ID = "gemini-3.1-pro"
# GEMINI_MODEL_ID = "gemini-3.5-flash"

# SET GEMINI PROMPT 
prompt_version = 5

# SET FILE IDENTIFIERS 
RUN_PREFIX = f"interstate_oneyearPR511_v{prompt_version}"

# SET FILE PATHS 
INPUT_PATH = GEOCODING_DIR / "inputs" / "FMIS_interstate_project_titles_oneyearPR511.dta"

# SET SCHEMA
page_schema = Project

# SET SAMPLING PARAMETERS
ROW_INDICES = None 
# ROW_INDICES = [27, 28, 29, 30]          # manual override; if set, skip auto sample
# test on subset of projects coded as "other_landmark" from the 1000-project sample 
# ROW_INDICES = [4764,
# 9673, 17318, 9690, 19604, 10831, 17351, 18157, 10842, 15966, 15541, 13380, 1878, 1859, 15059, 19036, 4029, 5523, 8094, 9179, 8081, 11194, 9229, 5718, 15752, 9216, 14261, 9247, 16819, 5934, 12426, 1528, 20162, 19362, 18684, 10650, 14922]
# ROW_INDICES = [i - 1 for i in ROW_INDICES]
SAMPLE_N = None                # if set (and ROW_INDICES is None), sample this many rows
# SAMPLE_STRATIFY_BY = ["state_fips", "post_1970_auth", "below_median_cost"]
# SAMPLE_N = None # use full dataset
RANDOM_SEED = 42

# ------------------------------------------------------------------------------
# AUTO SET REMAINING FILE PATHS 
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
IDENTIFIER = f"{RUN_PREFIX}_{timestamp}"

PROMPT_TEXT_PATH = CODE_ROOT / "02_parse_FMIS_titles" / "prompts" / f"prompt v{prompt_version}.md"

GEMINI_DIR = GEOCODING_DIR / "title_parsing_gemini_output"
LOG_DIR = GEOCODING_DIR / "title_parsing_gemini_logs"

OUTPUT_FILE_NAME = f"{IDENTIFIER}.csv"
RUN_DIR = GEMINI_DIR / IDENTIFIER
OUTPUT_PATH = GEMINI_DIR / OUTPUT_FILE_NAME

