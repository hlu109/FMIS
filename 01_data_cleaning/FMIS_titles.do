/*==============================================================================
 	FMIS data processing 
    This script saves a file with only project titles and adjusted costs. 
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
* load FMIS data
use "$intermediate_data/project_level_FMIS.dta", clear

* filter to interstates 
keep if interstate_syscode == 1

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keepusing(cpi) nogen
gen total_cost_bills_adjusted = total_cost_mills / cpi / 1000
// rename year completion_year
sort year recipientid federal_project_number

* keep only project titles and adjusted costs
keep recipientid federal_project_number projecttitle state_fips countyid county_fips total_cost_bills_adjusted year
save "$data/Hannah sandbox/FMIS_interstate_titles_and_costs.dta", replace
