/*==============================================================================
 	One-off script to fix the missing state_name variable from the Gemini outputs for the 5k validation FMIS GIS sample. 
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
else if "`user'" == "fm557"{
    global project_root "C:/Users/fm557/YLS Dropbox/Finn Meffe/FHWA cost data"
    global output "$project_root/Output/Finn"
    global data "$project_root/Data"
	global raw_data "$data/Raw"
	global intermediate_data "$data/Intermediate"
}
* add your username and paths here as an else if condition
else {
	 display as error "Set your user"
}

* ==============================================================================

* load Gemini outputs
import delimited "$intermediate_data/geocoding/title_parsing_gemini_output/VAL_fmis_gis_5k_noninterstate_prompt_v6_20260812_123113.csv", clear

* add state name as its own string variable
* first relabel the fips codes since they are gone due to csv import
destring state_fips, replace
run "$intermediate_data/stata_labels/FMIS_labels.do"
label values state_fips state_fips_lbl
drop state_name
decode state_fips, gen(state_name)

order project_title state_name

* save
export delimited "$intermediate_data/geocoding/title_parsing_gemini_output/VAL_fmis_gis_5k_noninterstate_prompt_v6_20260812_123113_corrected.csv", replace
