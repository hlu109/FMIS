/*==============================================================================
 	FMIS data processing 
    This script exports a list of unique program codes.
==============================================================================*/
* Set user
local user = c(username)
if "`user'" == "andersonkovesci"{
global output "/Users/andersonkovesci/Dropbox/FHWA cost data/Output/Andy"
global data "/Users/andersonkovesci/Dropbox/FHWA cost data/Data"
global raw_data "$data/Raw"
global intermediate_data "$data/Intermediate"
}
else if "`user'" == "hl2266"{
global project_root "C:/Users/hl2266/YLS Dropbox/Hannah Lu/shared/FHWA cost data"
global output "$project_root/Output/Hannah"
global data "$project_root/Data"
global raw_data "$data/Raw"
global intermediate_data "$data/Intermediate"
}
* add your username and paths here as an else if condition
else {
 display as error "Set your user"
}
* check that output folders exist and create them if not 
if !direxists("$output") mkdir "$output"
if !direxists("$intermediate_data") mkdir "$intermediate_data"

* ==============================================================================
use "$intermediate_data/receipt_level_FMIS_lite.dta", clear

contract detail_programcode, freq(discard)
drop discard
export delimited using "$intermediate_data/program_codes.csv", replace nolabel
