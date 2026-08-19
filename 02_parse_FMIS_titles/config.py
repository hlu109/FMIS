import os
import sys
import json
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
CONFIG_DIR = CODE_ROOT / "02_parse_FMIS_titles" / "configs"
PROMPTS_DIR = CODE_ROOT / "02_parse_FMIS_titles" / "prompts"

print(f"PROJECT_ROOT: {PROJECT_ROOT}")

# ------------------------------------------------------------------------------
# LOAD RUN CONFIG
# ------------------------------------------------------------------------------
config_fname = "VAL_fmis_pr511_1yr_ct_rt_interstate_newconstr.json"

CONFIG_PATH = CONFIG_DIR / config_fname

with open(CONFIG_PATH, "r", encoding="utf-8") as file:
    run_config = json.load(file)
print(f"Loaded run config: {CONFIG_PATH}")

# ------------------------------------------------------------------------------
# UNPACK CUSTOMIZABLE PARAMETERS
# ------------------------------------------------------------------------------
# required
GEMINI_MODEL_ID = run_config["gemini_model_id"]
prompt_version = run_config["prompt_version"]
run_name = run_config["run_name"]
INPUT_PATH = INTERMEDIATE_DATA_DIR / run_config["input_path"]

# optional (default None or as specified)
NOTE = run_config.get("note")
REUSE_OLD_RESULTS = run_config.get("reuse_old_results", False)
RESUME_RUN_IDENTIFIER = run_config.get("resume_run_identifier")
ROW_INDICES = run_config.get("row_indices")
SAMPLE_N = run_config.get("sample_n")
SAMPLE_STRATIFY_BY = run_config.get("sample_stratify_by")
RANDOM_SEED = run_config.get("random_seed", 42)

# SET FILE IDENTIFIERS
RUN_PREFIX = f"{run_name}_prompt_v{prompt_version}"

# SET SCHEMA
page_schema = Project

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

PROMPT_TEXT_PATH = PROMPTS_DIR / f"prompt v{prompt_version}.md"

GEMINI_DIR = GEOCODING_DIR / "title_parsing_gemini_output"
LOG_DIR = GEOCODING_DIR / "title_parsing_gemini_logs"

OUTPUT_FILE_NAME = f"{IDENTIFIER}.csv"
RUN_DIR = GEMINI_DIR / IDENTIFIER
OUTPUT_PATH = GEMINI_DIR / OUTPUT_FILE_NAME
