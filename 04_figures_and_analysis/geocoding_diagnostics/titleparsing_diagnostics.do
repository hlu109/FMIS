/*==============================================================================
 	FMIS geocoding 
    This script generates descriptive statistics used to sanity check and diagnose any issues with the Gemini title-parsing algorithm. 
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
global geocoding_dir "$intermediate_data/geocoding"
if !direxists("$geocoding_dir") mkdir "$geocoding_dir"

* load latest sample of Gemini title-parsing output that we want to check 
import delimited "$geocoding_dir/title_parsing_gemini_output/otherlandmark_debug__new_constr_v4_20260623_160835.csv", clear

tab statewide 
tab various
tab multi 

misstable summarize main_route_num

tab route_fpn, mi

tab ep_a_ref1_anchor_type

* load a larger earlier example that contains Alaska and Hawaii 
import delimited "$geocoding_dir/fmis_interstate_parsed_titles_mult_fmis_counties_new_constr_v3_20260522_165917.csv", clear
