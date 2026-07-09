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
    global code_root "$project_root/Code/FMIS_Hannah"
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
global postprocessing_dir "$intermediate_data/postprocessing"


* set latest sample of Gemini title-parsing output that we want to check 
global fname "interstate_new_constr_v5_20260709_160600"

* run postprocessing 
do "$code_root/02_parse_FMIS_titles/03_postprocessing.do"

// import delimited "$postprocessing_dir/interstate_new_constr_v5_20260709_135518_pp.csv", clear
// import delimited "$geocoding_dir/title_parsing_gemini_output/interstate_new_constr_v5_20260708_174821.csv", clear

// * load Alaska and Hawaii example
// import delimited "$geocoding_dir/title_parsing_gemini_output/interstate_new_constr_AK_HI_v5_20260709_113043.csv", clear

exit 
tab statewide 
tab various
tab multi 
drop if statewide == "True" | various == "True" | multi == "True"

* use the helper function extract_routes_regex
do "$code_root/01_data_cleaning/extract_route_regex.do"
extract_routes_regex, titlevar(project_title)


* compare route_fpn (metadata) vs main_route_num (extracted by Gemini)
gen byte route_fpn_matches_gemini = (route_fpn == main_route_num) if !mi(route_fpn) & !mi(main_route_num)

* compare route_fpn (metadata) vs regex
gen byte route_fpn_matches_regex_1 = (route_fpn == route_1_int) if !mi(route_1_int)
gen byte route_fpn_matches_regex_2 = (route_fpn == route_2_int) if !mi(route_2_int)
gen byte route_fpn_matches_regex_3 = (route_fpn == route_3_int) if !mi(route_3_int)
gen byte route_fpn_matches_regex = 0
replace route_fpn_matches_regex = 1 if route_fpn_matches_regex_1 == 1
replace route_fpn_matches_regex = 1 if route_fpn_matches_regex_2 == 1
replace route_fpn_matches_regex = 1 if route_fpn_matches_regex_3 == 1
replace route_fpn_matches_regex = . if mi(route_1_int) & mi(route_2_int) & mi(route_3_int)

* compare main_route_num (extracted by Gemini) vs regex
gen byte gemini_matches_regex_1 = (main_route_num == route_1_int) if !mi(main_route_num) & !mi(route_1_int)
gen byte gemini_matches_regex_2 = (main_route_num == route_2_int) if !mi(main_route_num) & !mi(route_2_int)
gen byte gemini_matches_regex_3 = (main_route_num == route_3_int) if !mi(main_route_num) & !mi(route_3_int)
gen byte gemini_matches_regex = 0
replace gemini_matches_regex = 1 if gemini_matches_regex_1 == 1
replace gemini_matches_regex = 1 if gemini_matches_regex_2 == 1
replace gemini_matches_regex = 1 if gemini_matches_regex_3 == 1
replace gemini_matches_regex = . if mi(route_1_int) & mi(route_2_int) & mi(route_3_int)

tab route_fpn_matches_gemini, mi
tab gemini_matches_regex, mi
tab route_fpn_matches_gemini gemini_matches_regex, mi
tab route_fpn_matches_regex, mi

* now specifically compare cases where main_route_num is missing but regex has identified a route in the title
gen byte gemini_miss_regex_hit = mi(main_route_num) & has_route_regex
tab gemini_miss_regex_hit



misstable summarize main_route_num

// tab route_fpn, mi

tab ep_a_ref1_anchor_type



tab main_route_num_match_status if route_fpn == main_route_num
tab main_route_num_match_status if route_fpn != main_route_num

