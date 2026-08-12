#!/bin/bash
#SBATCH --partition=day
#SBATCH --job-name=gemini_parse_titles_day
#SBATCH --output="/home/hl2266/project_pi_zdl3/shared/FMIS project/slurm_logs/gemini_parse_titles_day_%j.log"
#
#SBATCH --time=20:00:00
#SBATCH --mem=1G
#SBATCH --ntasks=1
#
#SBATCH --mail-type=FAIL,END
date
cd "/home/hl2266/project_pi_zdl3/shared/FMIS project/Code/FMIS_hannah"
source venv/bin/activate
module load Python

python 02_parse_FMIS_titles/02_main_parse_titles.py
