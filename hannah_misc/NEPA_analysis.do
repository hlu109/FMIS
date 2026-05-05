/*==============================================================================
    This script explores and analyses the NEPA-related variables in FMIS. 
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

summarize nepa_class
summarize nepa_decision_date

exit

* get table of NEPA class of action before and after 1970 (there should be nothing before 1970)
preserve
keep if completion_year < 1970
tab nepa_class
restore
preserve
keep if completion_year >= 1970
tab nepa_class
restore

* get number of missing and non-missing dates before and after 1970 (should be all missing before 1970)
preserve
keep if completion_year < 1970
sum nepa_decision_date, detail
restore
preserve
keep if completion_year >= 1970
sum nepa_decision_date, detail
restore

* get list of unique values for nepa class of action
tab nepa_class


