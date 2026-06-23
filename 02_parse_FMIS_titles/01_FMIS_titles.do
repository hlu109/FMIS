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
global geocoding_dir "$intermediate_data/geocoding"
if !direxists("$geocoding_dir") mkdir "$geocoding_dir"

* load FMIS data
use "$intermediate_data/project_level_FMIS.dta", clear

* filter to interstates 
keep if fp_ic == 1

* adjust for inflation 
rename completion_year year
merge m:1 year using "$intermediate_data/CPI_2025.dta", keep(match) keepusing(cpi) nogen
gen total_cost_bills_adjusted = total_cost_mills / cpi / 1000
rename year completion_year
sort completion_year recipientid federal_project_number

gen constauthyear = year(authconstdate)

* extract the route number from the federal project number
gen str3 route_fpn_str = substr(strtrim(federal_project_number), 1, 3)
gen str3 route_fpn = ustrregexra(route_fpn_str, "[A-Za-z]", "")
destring route_fpn, replace

* add state name as its own string variable (note we already have the county_fips and county_name variables as strings containing potentially multiple counties)
decode state_fips, gen(state_name)

* add variable to filter by pre/post NEPA 
gen post_1970_auth = constauthyear >= 1970

* add variable to filter by below/above median cost 
summarize total_cost_bills_adjusted, detail
gen below_median_cost = total_cost_bills_adjusted < r(p50)

* keep only project titles and some key variables
keep recipientid federal_project_number projecttitle projectdescription state_fips state_name county_fips county_name route_fpn total_cost_bills_adjusted completion_year constauthyear has_new_construction post_1970_auth below_median_cost
save "$geocoding_dir/FMIS_interstate_project_titles.dta", replace

* restrict to projects with new construction
keep if has_new_construction == 1

* recompute the median cost
summarize total_cost_bills_adjusted, detail
drop below_median_cost
gen below_median_cost = total_cost_bills_adjusted < r(p50)

keep recipientid federal_project_number projecttitle projectdescription state_fips state_name county_fips county_name route_fpn total_cost_bills_adjusted completion_year constauthyear post_1970_auth below_median_cost
save "$geocoding_dir/FMIS_interstate_newconstr_project_titles.dta", replace

