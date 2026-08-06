/*==============================================================================
 	FMIS data processing 
    This script pulls lists of unique counties or county x route cells with unique chains within year or across all years.
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
global pr511_intermediate "$intermediate_data/PR_511"
if !direxists("$pr511_intermediate") mkdir "$pr511_intermediate"

global pr511_dir "$output/PR511"
if !direxists("$pr511_dir") mkdir "$pr511_dir"

* see how many counties have a unique PR-511 chain per calendar year 
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
drop if mi(open_year)
collapse (count) chain_count = chain_id, by(open_year st county)
tab chain_count

* plot bar chart by year 
preserve 
keep if chain_count == 1
collapse (count) county_count = chain_count, by(open_year)
keep if open_year >= 1940 & open_year <= 2000
graph twoway ///
    (bar county_count open_year), ///
    title("Number of Counties with a Unique PR-511 Chain per Calendar Year") ///
    xtitle("Opening Year") ///
    ytitle("Number of Counties") ///
    legend(off)
graph export "$pr511_dir/pr511_unique_chains_by_year_cty.png", replace width(1000)
restore

* county FIPS where there is never more than one PR-511 chain in any calendar year
collapse (max) max_chains = chain_count, by(st county)
tab max_chains
keep if max_chains == 1
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f"))
// sort county_fips
keep st county_fips
save "$pr511_intermediate/pr511_cty_max_one_chain_per_yr.dta", replace

* see how many county x route cells have a unique PR-511 chain per calendar year 
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
drop if mi(open_year)
collapse (count) chain_count = chain_id, by(open_year st county route)
tab chain_count

* plot bar chart by year 
preserve 
keep if chain_count == 1
collapse (count) cell_count = chain_count, by(open_year)
keep if open_year >= 1940 & open_year <= 2000
graph twoway ///
    (bar cell_count open_year), ///
    title("Number of County x Route Cells with a Unique PR-511 Chain per Calendar Year") ///
    xtitle("Opening Year") ///
    ytitle("Number of Cells") ///
    legend(off)
graph export "$pr511_dir/pr511_unique_chains_by_year_cty_rt.png", replace width(1000)
restore

* county x route cells where there is never more than one PR-511 chain in any calendar year
collapse (max) max_chains = chain_count, by(st county route)
tab max_chains
keep if max_chains == 1
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f"))
keep st county_fips route
save "$pr511_intermediate/pr511_cty_rt_max_one_chain_per_yr.dta", replace

* counties with only one distinct PR-511 chain_id across all years
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
bysort st county chain_id: keep if _n == 1
collapse (count) n_distinct = chain_id, by(st county)
keep if n_distinct == 1
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f"))
keep st county_fips
save "$pr511_intermediate/pr511_cty_single_chain_ever.dta", replace

* county x route cells with only one distinct PR-511 chain_id across all years
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
bysort st county route chain_id: keep if _n == 1
collapse (count) n_distinct = chain_id, by(st county route)
keep if n_distinct == 1
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f"))
keep st county_fips route
save "$pr511_intermediate/pr511_cty_rt_single_chain_ever.dta", replace



* counties with only one distinct PR-511 open_year across all years (can have multiple chains within that year)
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
gen one = 1
collapse (max) one, by(st county open_year)
collapse (count) n_years = open_year, by(st county)
keep if n_years == 1
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f"))
keep st county_fips
save "$pr511_intermediate/pr511_cty_single_openyr_ever.dta", replace


* county x route cells with only one distinct PR-511 open_year across all years (can have multiple chains within that year)
use "$pr511_intermediate/PR511_hubbardmazzeo_chained.dta", clear
gen one = 1
collapse (max) one, by(st county route open_year)
collapse (count) n_years = open_year, by(st county route)
keep if n_years == 1
gen long county_fips = real(string(st, "%02.0f") + string(county, "%03.0f"))
keep st county_fips route
save "$pr511_intermediate/pr511_cty_rt_single_openyr_ever.dta", replace


* ==============================================================================





