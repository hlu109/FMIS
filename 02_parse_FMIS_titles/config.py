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

# SET GEMINI PROMPT ------------------------------------------------------------
prompt_text_path = CODE_ROOT / "02_parse_FMIS_titles" / "prompt v4.md"

# SET FILE IDENTIFIERS --------------------------------------------------------
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
# identifier = "new_constr_v4_" + timestamp
RUN_PREFIX = "new_constr_v4"
identifier = f"{RUN_PREFIX}_{timestamp}"

# SET FILE PATHS -------------------------------------------------------------
INPUT_PATH = GEOCODING_DIR / "FMIS_interstate_newconstr_project_titles.dta"
gemini_dir = GEOCODING_DIR / "title_parsing_gemini_output"
log_dir = GEOCODING_DIR / "title_parsing_gemini_logs"

OUTPUT_FILE_NAME = f"{identifier}.csv"
run_dir = gemini_dir / identifier
OUTPUT_PATH = gemini_dir / OUTPUT_FILE_NAME


# Set Schema -----------------------------------
page_schema = Project

# Project filtering (optional)
row_indices = None 
# row_indices = [27, 28, 29, 30]          # manual override; if set, skip auto sample
# test on subset of projects coded as "other_landmark" from the 1000-project sample 
# row_indices = [4764,
# 9673, 17318, 9690, 19604, 10831, 17351, 18157, 10842, 15966, 15541, 13380, 1878, 1859, 15059, 19036, 4029, 5523, 8094, 9179, 8081, 11194, 9229, 5718, 15752, 9216, 14261, 9247, 16819, 5934, 12426, 1528, 20162, 19362, 18684, 10650, 14922]
# row_indices = [i - 1 for i in row_indices]
sample_n = 200                # if set (and row_indices is None), sample this many rows
sample_stratify_by = ["state_fips", "post_1970_auth", "below_median_cost"]
random_seed = 42
