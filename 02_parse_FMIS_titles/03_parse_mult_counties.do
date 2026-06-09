/*==============================================================================
 	FMIS data processing 
    This script expands counties in case there are multiple counties per endpoint.
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
global gemini_dir "$geocoding_dir/title_parsing_gemini_output"

* load parsed title data 
local file_suffix "new_constr_v3_20260522_165917"

import delimited "$gemini_dir/fmis_interstate_parsed_titles_`file_suffix'.csv", clear

* import delimited may read sparse ref columns as numeric; coerce to string before assignment
foreach pattern in feature_name anchor_type {
	unab ref_vars : *`pattern'
	foreach v of local ref_vars {
		capture confirm numeric variable `v'
		if !_rc tostring `v', replace force
	}
}

* order counties so the first to appear goes in county_1 even if it's from anchor 3
foreach ep in a b {
    // populate first county 
	// init as string so later replace calls don't hit type mismatches across refs if the variable is all empty
	gen strL ep_`ep'_county_1 = ""
	replace ep_`ep'_county_1 = ep_`ep'_ref0_feature_name if ep_`ep'_ref0_anchor_type == "county"
	replace ep_`ep'_county_1 = ep_`ep'_ref1_feature_name if ep_`ep'_county_1 == "" & ep_`ep'_ref1_anchor_type == "county"
	replace ep_`ep'_county_1 = ep_`ep'_ref2_feature_name if ep_`ep'_county_1 == "" & ep_`ep'_ref2_anchor_type == "county"

    // populate second county 
	gen strL ep_`ep'_county_2 = ""
	replace ep_`ep'_county_2 = ep_`ep'_ref1_feature_name if ep_`ep'_ref0_anchor_type == "county" & ep_`ep'_ref1_anchor_type == "county"
	replace ep_`ep'_county_2 = ep_`ep'_ref2_feature_name if ep_`ep'_county_2 == "" & ep_`ep'_ref0_anchor_type == "county" & ep_`ep'_ref1_anchor_type != "county" & ep_`ep'_ref2_anchor_type == "county"
	replace ep_`ep'_county_2 = ep_`ep'_ref2_feature_name if ep_`ep'_county_2 == "" & ep_`ep'_ref0_anchor_type != "county" & ep_`ep'_ref1_anchor_type == "county" & ep_`ep'_ref2_anchor_type == "county"

    // populate third county 
	gen strL ep_`ep'_county_3 = ""
	replace ep_`ep'_county_3 = ep_`ep'_ref2_feature_name if ep_`ep'_ref0_anchor_type == "county" & ep_`ep'_ref1_anchor_type == "county" & ep_`ep'_ref2_anchor_type == "county"

	* count number of counties 
	gen byte ep_`ep'_n_counties = (ep_`ep'_ref0_anchor_type == "county") + ///
		(ep_`ep'_ref1_anchor_type == "county") + ///
		(ep_`ep'_ref2_anchor_type == "county")
}

save "$geocoding_dir/fmis_interstate_parsed_titles_mult_gemini_counties_`file_suffix'.dta", replace

tab ep_a_n_counties, mi 
tab ep_b_n_counties, mi 