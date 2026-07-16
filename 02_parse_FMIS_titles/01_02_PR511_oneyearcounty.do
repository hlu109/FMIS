/*==============================================================================
 	FMIS data processing 
    This script saves a subset of data restricted to counties with at most one year of PR-511 data. 
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

global geocoding_inputs_dir "$geocoding_dir/inputs"
if !direxists("$geocoding_inputs_dir") mkdir "$geocoding_inputs_dir"

* hardcoded path, should update
use "$project_root/Output/Finn/PR511_FMIS/one_year_counties.dta", clear

rename st state_fips
rename county countyid
gen long county_fips = real(string(state_fips, "%02.0f") + string(countyid, "%03.0f"))

keep county_fips
duplicates drop
tempfile pr511_counties
save `pr511_counties'

use "$geocoding_inputs_dir/FMIS_interstate_project_titles.dta", clear

* filter by PR-511 county data
* reconstruct number of counties 
* TODO: need to move this upstream in data cleaning pipeline 
replace county_fips = subinstr(county_fips, " ", "", .)
gen num_counties = wordcount(subinstr(county_fips, ";", " ", .))
quietly summarize num_counties
di "Max number of counties in a single FMIS project: " r(max)

gen long row = _n

* explode the semicolon-delimited county list into one row per county
* match if at least one of set of counties is in the PR-511 sample 
preserve
	keep row county_fips
	split county_fips, parse(";") gen(cty)
	drop county_fips
	reshape long cty, i(row) j(county_n)
	drop if missing(cty)
	destring cty, replace force
	drop if missing(cty)
	rename cty county_fips
    
	merge m:1 county_fips using `pr511_counties', keep(3) nogen
	keep row
	duplicates drop
	tempfile pr511_matched_rows
	save `pr511_matched_rows'
restore

merge 1:1 row using `pr511_matched_rows', keep(3) nogen
drop row num_counties

save "$geocoding_inputs_dir/FMIS_interstate_project_titles_oneyearPR511.dta", replace


