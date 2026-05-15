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

# Set File Paths -------------------------------------------
username = getpass.getuser()
if username == "hl2266":
    PROJECT_ROOT = Path("C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data")
elif username == "andersonkovesci":
    PROJECT_ROOT = Path("/Users/andersonkovesci/Dropbox/FHWA cost data")
else:
    raise ValueError("Update config with machine-specific paths.")

DATA_ROOT = PROJECT_ROOT / "Data"
RAW_DATA_DIR = DATA_ROOT / "Raw"
INTERMEDIATE_DATA_DIR = DATA_ROOT / "Intermediate"
GEOCODING_DIR = INTERMEDIATE_DATA_DIR / "geocoding"
CODE_ROOT = PROJECT_ROOT / "Code"

INPUT_PATH = GEOCODING_DIR / "FMIS_interstate_project_titles.dta"

# SET OUTPUT PATHS -------------------------------------------------------------
gemini_dir = GEOCODING_DIR / "title_parsing_gemini_output"
log_dir = GEOCODING_DIR / "title_parsing_gemini_logs"

# SET GEMINI PROMPT ------------------------------------------------------------
prompt_text_path = CODE_ROOT / "02_parse_FMIS_titles" / "prompt v1.md"

# Set Schema -----------------------------------
page_schema = Project

# Project filtering (optional) - if None, processes all projects
row_indices = None # TODO maybe replace row idxes with recipient id x fpn - but likely not needed 

# ------------------------------------------------------------------------------
# END OF SET PARAMETERS --------------------------------------------------------
# ------------------------------------------------------------------------------

timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
identifier = timestamp
OUTPUT_FILE_NAME = "fmis_interstate_parsed_titles_" + identifier + ".csv"

results_dir = gemini_dir / ("run_" + identifier)
temp_dir = results_dir / "temp"
